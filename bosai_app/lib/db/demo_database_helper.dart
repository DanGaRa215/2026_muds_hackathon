import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/shelter.dart';

/// 🛠️ ハッカソン審査・デモ専用の独立データベースヘルパー
/// 本番用のDBとは完全に隔離された「demo_bosai_app.db」を生成・管理します。
/// デモ画面の起動時にファイルごと物理削除されるため、毎回真っさらな状態からデモが可能です。
class DemoAddressDatabaseHelper {
  DemoAddressDatabaseHelper._();
  static final DemoAddressDatabaseHelper instance = DemoAddressDatabaseHelper._();

  static Database? _demoDb;

  Future<Database> get database async {
    _demoDb ??= await _openDemoDatabase();
    return _demoDb!;
  }

  /// 📥 デモ専用のDBファイルをオープン
  Future<Database> _openDemoDatabase() async {
    final path = join(await getDatabasesPath(), 'demo_bosai_app.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // デモの住所登録に必要な最小限のテーブルのみを定義
        await db.execute('''
          CREATE TABLE demo_home_info (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            address TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            pmtiles_path TEXT NOT NULL
          )
        ''');
        
        // 必要に応じてデモ用の避難所テーブルなどもここに最小限持たせられます
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
        await _seedDemoShelters(db);
      },
    );
  }

  /// 🚨 デモ用DBファイルを物理的に丸ごと消去するリセット関数
  /// デモ画面の起動時（initStateなど）にこれを1発叩くだけで、完全初期化されます。
  Future<void> resetDemoDatabase() async {
    if (_demoDb != null) {
      await _demoDb!.close();
      _demoDb = null;
    }
    
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'demo_bosai_app.db');
    final file = File(path);
    
    if (await file.exists()) {
      await file.delete();
      print("🎯 [Demo DB] デモ専用DBファイルを物理削除し、完全リセットしました。");
    }
  }

  /// 💾 デモ用の位置・マップ情報を保存
  Future<void> saveDemoHomeMapInfo({
    required String address,
    required double lat,
    required double lon,
    required String pmtilesPath,
  }) async {
    final db = await database;
    await db.insert(
      'demo_home_info',
      {
        'id': 1,
        'address': address,
        'lat': lat,
        'lon': lon,
        'pmtiles_path': pmtilesPath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 🔍 デモ用の登録情報を取得
  Future<Map<String, dynamic>?> getDemoHomeMapInfo() async {
    final db = await database;
    final rows = await db.query('demo_home_info', where: 'id = 1');
    return rows.isEmpty ? null : rows.first;
  }

  /// 江戸川区デモ用の簡易ダミー避難所データ
  Future<void> _seedDemoShelters(Database db) async {
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
    ];
    final batch = db.batch();
    for (final s in shelters) {
      batch.insert('shelters', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}