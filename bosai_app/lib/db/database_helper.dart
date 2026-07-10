import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/diagnosis.dart';
import '../models/shelter.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _defaultAddress = '未登録住所';
  static const _defaultLat = 35.7434;
  static const _defaultLon = 139.8472;
  static const _defaultStructure = '木造';
  static const _defaultFloor = 1;
  static const _legacyHomeLocationSeparator = '||home=';

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'bosai_app.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE shelters(
            shelter_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            elevation_m REAL NOT NULL,
            coast_distance_m REAL NOT NULL,
            types TEXT NOT NULL,
            capacity INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE diagnoses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            intensity TEXT NOT NULL,
            fixations TEXT NOT NULL,
            comment TEXT NOT NULL,
            payload_json TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE home_info(
            id INTEGER PRIMARY KEY CHECK(id = 1),
            address TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            pmtiles_path TEXT NOT NULL,
            structure TEXT NOT NULL,
            floor INTEGER NOT NULL,
            home_registered INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _seedShelters(db);
        await _createPrecomputedRoutes(db);
        await _ensureHomeInfoColumns(db);
        await _repairHomeInfo(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createPrecomputedRoutes(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE diagnoses ADD COLUMN payload_json TEXT',
          );
        }
        await _ensureHomeInfoColumns(db);
        await _repairHomeInfo(db);
      },
      onOpen: (db) async {
        await _ensureHomeInfoColumns(db);
        await _repairHomeInfo(db);
      },
    );
  }

  /// v2: 事前計算した避難経路(仕様書② §7)
  Future<void> _createPrecomputedRoutes(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS precomputed_routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shelter_id TEXT NOT NULL,
        disaster_mode TEXT NOT NULL,     -- 'earthquake' | 'flood'
        weight_profile TEXT NOT NULL,    -- 'fastest' | 'balanced' | 'safest'
        distance_m REAL NOT NULL,
        penalty_m REAL NOT NULL,
        est_minutes REAL NOT NULL,
        safety_score REAL NOT NULL,
        used_fallback INTEGER NOT NULL DEFAULT 0,
        geometry TEXT NOT NULL,          -- [[lat,lon],...] JSON
        computed_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pre_mode_profile
        ON precomputed_routes(disaster_mode, weight_profile)
    ''');
  }

  /// home_info テーブルに不足カラムがあれば追加する（スキーマ修復）
  Future<void> _ensureHomeInfoColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(home_info)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();

    if (!columnNames.contains('address')) {
      await db.execute(
        "ALTER TABLE home_info ADD COLUMN address TEXT NOT NULL DEFAULT '$_defaultAddress'",
      );
    }
    if (!columnNames.contains('lat')) {
      await db.execute(
        'ALTER TABLE home_info ADD COLUMN lat REAL NOT NULL DEFAULT $_defaultLat',
      );
    }
    if (!columnNames.contains('lon')) {
      await db.execute(
        'ALTER TABLE home_info ADD COLUMN lon REAL NOT NULL DEFAULT $_defaultLon',
      );
    }
    if (!columnNames.contains('pmtiles_path')) {
      await db.execute(
        "ALTER TABLE home_info ADD COLUMN pmtiles_path TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!columnNames.contains('home_registered')) {
      await db.execute(
        'ALTER TABLE home_info ADD COLUMN home_registered INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _repairHomeInfo(Database db) async {
    final rows = await db.query('home_info', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      return;
    }

    final row = rows.first;
    final updates = <String, Object?>{};
    final rawStructure = row['structure'] as String? ?? _defaultStructure;
    final separatorIndex = rawStructure.indexOf(_legacyHomeLocationSeparator);

    if (separatorIndex >= 0) {
      final cleanStructure = rawStructure.substring(0, separatorIndex);
      updates['structure'] =
          cleanStructure.isEmpty ? _defaultStructure : cleanStructure;

      final values = rawStructure.substring(
        separatorIndex + _legacyHomeLocationSeparator.length,
      );
      final parts = values.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lon = double.tryParse(parts[1].trim());
        if (lat != null && lon != null) {
          updates['lat'] = lat;
          updates['lon'] = lon;
          updates['home_registered'] = 1;
        }
      }
    }

    final registered = (row['home_registered'] as num?)?.toInt() ?? 0;
    final address = row['address'] as String? ?? _defaultAddress;
    final lat = (updates['lat'] as double?) ??
        (row['lat'] as num?)?.toDouble() ??
        _defaultLat;
    final lon = (updates['lon'] as double?) ??
        (row['lon'] as num?)?.toDouble() ??
        _defaultLon;
    final hasLegacyLocation =
        address != _defaultAddress || lat != _defaultLat || lon != _defaultLon;
    if (registered == 0 && hasLegacyLocation) {
      updates['home_registered'] = 1;
    }

    if (updates.isNotEmpty) {
      await db.update('home_info', updates, where: 'id = 1');
    }
  }

  /// ダミー避難所データ（メンバーDの実DB＝国土数値情報ベースに差し替え予定）
  /// 座標・海抜・海岸距離はすべて仮の値。
  Future<void> _seedShelters(Database db) async {
    const shelters = [
      Shelter(
        shelterId: 'demo-0001',
        name: '第一小学校（ダミー）',
        lat: 35.750,
        lon: 139.848,
        elevationM: 3,
        coastDistanceM: 9000,
        types: 'earthquake,fire',
        capacity: 800,
      ),
    ];
    final batch = db.batch();
    for (final s in shelters) {
      batch.insert('shelters', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  // =====================================================================
  // 💡 修正・適合させたメソッド群
  // =====================================================================

  /// 自宅情報を取得する (getHomeInfo)
  Future<Map<String, dynamic>?> getHomeInfo() async {
    final db = await database;
    final rows = await db.query('home_info', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getRegisteredHome() async {
    final db = await database;
    final rows = await db.query(
      'home_info',
      where: 'id = 1 AND home_registered = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 避難所一覧を取得する (getShelters)
  /// 💡 Mapのリストから Shelter クラスのリストへ自動変換するように修正
  Future<List<Shelter>> getShelters() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('shelters');
    return maps.map(Shelter.fromMap).toList();
  }

  /// 家具診断の結果を保存する (insertDiagnosis)
  /// 💡 引数で Diagnosis オブジェクトを直接受け取り、内部で .toMap() するように修正
  Future<int> insertDiagnosis(Diagnosis diagnosis) async {
    final db = await database;
    return await db.insert(
      'diagnoses',
      diagnosis.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Diagnosis>> getDiagnoses() async {
    final db = await database;
    final rows = await db.query('diagnoses', orderBy: 'id DESC');
    return rows.map(Diagnosis.fromMap).toList();
  }

  Future<Diagnosis?> getDiagnosisById(int id) async {
    final db = await database;
    final rows = await db.query(
      'diagnoses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Diagnosis.fromMap(rows.first);
  }

  Future<void> _ensureHomeInfoRow(Database db) async {
    await db.insert(
      'home_info',
      {
        'id': 1,
        'address': _defaultAddress,
        'lat': _defaultLat,
        'lon': _defaultLon,
        'pmtiles_path': '',
        'structure': _defaultStructure,
        'floor': _defaultFloor,
        'home_registered': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> saveHomeProfile({
    required String structure,
    required int floor,
  }) async {
    final db = await database;
    await _ensureHomeInfoRow(db);
    await db.update(
      'home_info',
      {
        'structure': structure,
        'floor': floor,
      },
      where: 'id = 1',
    );
  }

  Future<void> saveHomeLocation({
    required double lat,
    required double lon,
    String? address,
    String? pmtilesPath,
  }) async {
    final db = await database;
    await _ensureHomeInfoRow(db);

    final updates = <String, Object?>{
      'lat': lat,
      'lon': lon,
      'home_registered': 1,
    };
    if (address != null) {
      updates['address'] = address;
    }
    if (pmtilesPath != null) {
      updates['pmtiles_path'] = pmtilesPath;
    }

    await db.update('home_info', updates, where: 'id = 1');
    await clearPrecomputedRoutes();
  }

  Future<void> clearPrecomputedRoutes() async {
    final db = await database;
    await db.delete('precomputed_routes');
  }
}
