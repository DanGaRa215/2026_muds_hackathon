import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/diagnosis.dart';
import '../models/shelter.dart';

/// 🎯 デモ・検証専用の隔離されたSQLiteヘルパー
/// ファイル名を『demo_database_helper.db』に変更し、本番のテーブル構造・バージョンと完全同期しました。
class DemoDatabaseHelper {
  DemoDatabaseHelper._();
  static final DemoDatabaseHelper instance = DemoDatabaseHelper._();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // 💡 ファイル名を指定の通り完全に統一
    final path = join(await getDatabasesPath(), 'demo_database_helper.db');
    return openDatabase(
      path,
      version: 2, // 本番のバージョン「2」と一致
      onCreate: (db, version) async {
        // 1. shelters テーブルの作成
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

        // 2. diagnoses テーブルの作成
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

        // 3. home_info テーブルの作成
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

        // 4. 初期デモデータの投入
        await _seedDemoShelters(db);

        // 5. 事前計算経路テーブルとインデックスの作成
        await _createPrecomputedRoutes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createPrecomputedRoutes(db);
        }
      },
    );
  }

  /// v2の事前計算した避難経路テーブルの作成
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

  /// デモ用のダミー初期データ投入
  Future<void> _seedDemoShelters(Database db) async {
    const shelters = [
      Shelter(
        shelterId: 'demo-0001',
        name: '第一小学校（デモ用）',
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
  // メソッド群（本番の仕様と完全同期・省略なし）
  // =====================================================================

  /// 自宅情報を取得する (getHomeInfo)
  Future<Map<String, dynamic>?> getHomeInfo() async {
    final db = await database;
    final rows = await db.query('home_info', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// 避難所一覧を取得する (getShelters)
  Future<List<Shelter>> getShelters() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('shelters');
    return maps.map(Shelter.fromMap).toList();
  }

  /// 家具診断の結果を保存する (insertDiagnosis)
  Future<int> insertDiagnosis(Diagnosis diagnosis) async {
    final db = await database;
    return await db.insert(
      'diagnoses', 
      diagnosis.toMap(), 
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 家具診断履歴を取得する (getDiagnoses)
  Future<List<Diagnosis>> getDiagnoses() async {
    final db = await database;
    final rows = await db.query('diagnoses', orderBy: 'id DESC');
    return rows.map(Diagnosis.fromMap).toList();
  }

  /// 自宅情報を保存するベースメソッド (saveHomeInfo)
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

  /// 自宅登録画面から位置情報とPMTilesパスを保存する用 (saveHomeMapInfo)
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

  /// マップ情報付きの自宅情報を取得する (getHomeMapInfo)
  Future<Map<String, dynamic>?> getHomeMapInfo() async {
    final db = await database;
    final rows = await db.query('home_info', where: 'id = 1');
    return rows.isEmpty ? null : rows.first;
  }
}