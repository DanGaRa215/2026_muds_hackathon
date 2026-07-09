import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/diagnosis.dart';
import '../models/shelter.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'bosai_app.db');
    return openDatabase(
      path,
      version: 2,
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
            comment TEXT NOT NULL
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
            floor INTEGER NOT NULL
          )
        ''');
        await _seedShelters(db);
        await _createPrecomputedRoutes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createPrecomputedRoutes(db);
        }
        await _ensureHomeInfoColumns(db);
      },
      onOpen: (db) async {
        await _ensureHomeInfoColumns(db);
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
      await db.execute('ALTER TABLE home_info ADD COLUMN address TEXT NOT NULL DEFAULT "未登録住所"');
    }
    if (!columnNames.contains('lat')) {
      await db.execute('ALTER TABLE home_info ADD COLUMN lat REAL NOT NULL DEFAULT 35.7434');
    }
    if (!columnNames.contains('lon')) {
      await db.execute('ALTER TABLE home_info ADD COLUMN lon REAL NOT NULL DEFAULT 139.8472');
    }
    if (!columnNames.contains('pmtiles_path')) {
      await db.execute('ALTER TABLE home_info ADD COLUMN pmtiles_path TEXT NOT NULL DEFAULT ""');
    }
  }

  /// ダミー避難所データ（メンバーDの実DB＝国土数値情報ベースに差し替え予定）
  /// 座標・海抜・海岸距離はすべて仮の値。
  Future<void> _seedShelters(Database db) async {
    const shelters = [
      Shelter(
        shelterId: 'demo-0001',
        name: '第一小学校（ダミー）',
        lat: 35.750, lon: 139.848,
        elevationM: 3, coastDistanceM: 9000,
        types: 'earthquake,fire', capacity: 800,
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

  // =====================================================================
  // 既存のメソッド
  // =====================================================================

  Future<List<Diagnosis>> getDiagnoses() async {
    final db = await database;
    final rows = await db.query('diagnoses', orderBy: 'id DESC');
    return rows.map(Diagnosis.fromMap).toList();
  }

  Future<void> saveHomeInfo({
    required String structure,
    required int floor,
    String address = '未登録住所',
    double lat = 35.7434,
    double lon = 139.8472,
    String pmtilesPath = '',
  }) async {
    final db = await database;
    await db.insert(
      'home_info',
      {
        'id': 1,
        'address': address,
        'lat': lat,
        'lon': lon,
        'pmtiles_path': pmtilesPath,
        'structure': structure,
        'floor': floor,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 🎯 復活：自宅登録画面から位置情報とPMTilesパスを保存する用
  Future<void> saveHomeMapInfo({
    required String address,
    required double lat,
    required double lon,
    required String pmtilesPath,
    String structure = '木造',
    int floor = 1,
  }) async {
    await saveHomeInfo(
      structure: structure,
      floor: floor,
      address: address,
      lat: lat,
      lon: lon,
      pmtilesPath: pmtilesPath,
    );
  }

  Future<Map<String, dynamic>?> getHomeMapInfo() async {
    final db = await database;
    final rows = await db.query('home_info', where: 'id = 1');
    return rows.isEmpty ? null : rows.first;
  }
}