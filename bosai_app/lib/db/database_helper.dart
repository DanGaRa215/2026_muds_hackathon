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
      version: 1,
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
      },
      onOpen: (db) async {
        await _seedShelters(db);
      },
    );
  }

  /// 江戸川区デモ用避難所データ（メンバーD作成）
  /// 津波リスクや高台避難のロジック検証に特化した5件
  Future<void> _seedShelters(Database db) async {
    const shelters = [
      Shelter(
        shelterId: '13113-0001',
        name: '葛西臨海公園（広域避難場所）',
        lat: 35.6420, lon: 139.8620,
        elevationM: 3.0, coastDistanceM: 546.0,
        // 海に近いため津波フラグなし（ロジックで除外される想定）
        types: 'earthquake,fire', capacity: 10000,
      ),
      Shelter(
        shelterId: '13113-0002',
        name: '江戸川区立葛西第三中学校',
        lat: 35.6600, lon: 139.8700,
        elevationM: -1.0, coastDistanceM: 2663.0,
        // 海抜ゼロメートル地帯。津波時のスコアが低くなる想定
        types: 'earthquake,fire', capacity: 800,
      ),
      Shelter(
        shelterId: '13113-0003',
        name: '江戸川区役所',
        lat: 35.7067, lon: 139.8672,
        elevationM: -1.5, coastDistanceM: 7724.0,
        // 内陸寄りだが海抜は低い
        types: 'earthquake,fire', capacity: 1200,
      ),
      Shelter(
        shelterId: '13113-0004',
        name: 'タワーホール船堀（津波避難ビル）',
        lat: 35.6839, lon: 139.8643,
        elevationM: 15.0, coastDistanceM: 5174.0,
        // 垂直避難の正解ルート（本命）
        types: 'earthquake,tsunami,fire', capacity: 3000,
      ),
      Shelter(
        shelterId: '12203-0001',
        name: '市川市立国府台小学校（推奨・高台避難所）',
        lat: 35.7420, lon: 139.9000,
        elevationM: 22.0, coastDistanceM: 12180.0,
        // 区外の台地。「最寄りの高台へ」の切り札
        types: 'earthquake,tsunami,fire', capacity: 1500,
      ),
    ];
    
    await db.delete('shelters');
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