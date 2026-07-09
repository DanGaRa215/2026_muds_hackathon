import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/diagnosis.dart';
import '../models/shelter.dart';

/// SQLite（sqflite）ラッパー。v1のGRDB相当。
/// テーブル: shelters / diagnoses / home_info
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
      Shelter(
        shelterId: 'demo-0002',
        name: '中央中学校（ダミー）',
        lat: 35.744, lon: 139.855,
        elevationM: 8, coastDistanceM: 10500,
        types: 'earthquake,tsunami', capacity: 1200,
      ),
      Shelter(
        shelterId: 'demo-0003',
        name: '緑地公園・広域避難場所（ダミー）',
        lat: 35.756, lon: 139.840,
        elevationM: 4, coastDistanceM: 9500,
        types: 'earthquake,fire', capacity: 5000,
      ),
      Shelter(
        shelterId: 'demo-0004',
        name: '東高校（ダミー）',
        lat: 35.738, lon: 139.842,
        elevationM: 12, coastDistanceM: 11000,
        types: 'earthquake,tsunami,fire', capacity: 1500,
      ),
      Shelter(
        shelterId: 'demo-0005',
        name: '区民センター（ダミー）',
        lat: 35.747, lon: 139.836,
        elevationM: 3, coastDistanceM: 9200,
        types: 'earthquake', capacity: 400,
      ),
    ];
    final batch = db.batch();
    for (final s in shelters) {
      batch.insert('shelters', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  // ---- shelters ----
  Future<List<Shelter>> getShelters() async {
    final db = await database;
    final rows = await db.query('shelters');
    return rows.map(Shelter.fromMap).toList();
  }

  // ---- diagnoses ----
  Future<int> insertDiagnosis(Diagnosis d) async {
    final db = await database;
    return db.insert('diagnoses', d.toMap());
  }

  Future<List<Diagnosis>> getDiagnoses() async {
    final db = await database;
    final rows = await db.query('diagnoses', orderBy: 'id DESC');
    return rows.map(Diagnosis.fromMap).toList();
  }

  // ---- home_info ----
  Future<void> saveHomeInfo({required String structure, required int floor}) async {
    final db = await database;
    await db.insert(
      'home_info',
      {'id': 1, 'structure': structure, 'floor': floor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getHomeInfo() async {
    final db = await database;
    final rows = await db.query('home_info', where: 'id = 1');
    return rows.isEmpty ? null : rows.first;
  }
}
