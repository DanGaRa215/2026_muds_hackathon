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
      },
    );
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

  // 🎯 復活：家具診断履歴を取得するための大事なメソッド
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

  // 自宅登録画面から呼び出される位置情報保存用メソッド
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