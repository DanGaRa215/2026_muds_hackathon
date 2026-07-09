import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/gsi_shelter.dart';

/// 国土地理院ベースの避難所 DB（assets/shelters.db）へのアクセス。
///
/// ## データ由来
/// - 指定緊急避難場所 / 指定避難所（https://hinanmap.gsi.go.jp/）
/// - 東京23区（city_code 13101-13123）を収録
///
/// ## 名寄せロジック（2026-07 ビルド時点の判断根拠）
/// CSV→DB 変換パイプラインはリポジトリには残さないが、統合判断は以下の通り。
///
/// 1. **台帳番号（共通ID の連番）は名寄せキーに使わない**
///    指定緊急避難場所と指定避難所で台帳番号が一致するとは限らないため。
///
/// 2. **第1キー**: `(city_code, 正規化施設名, lat/lon 小数第4位)`
///    - 正規化: NFKC → 空白除去 → 括弧書き除去 → 小文字化
///    - 座標グリッド: 約11m 単位
///
/// 3. **第2キー（フォールバック）**: 同一 city_code 内で
///    正規化施設名が一致し、直線距離 < 150m なら同一施設
///
/// 4. **is_open_space [DESIGN]**: 元 CSV に屋外フラグは無い。
///    施設名に「公園 / 広場 / グラウンド / 運動場 / 緑地 / 河川敷」を含み
///    かつ is_shelter == 0 のとき 1（推定値）。
///
/// 5. **elevation_m / coast_distance_m / capacity**:
///    元データに無い場合は NULL（後続 enrich で埋める）。
///
/// ## 既存 DB との関係
/// - [DatabaseHelper] の bosai_app.db … 診断履歴・自宅情報・簡易 shelters（デモ1件）
/// - RoutingDatabase の routing.db … 経路グラフ + nearest_node 付き shelters（江戸川等）
/// - 本 DB … 発生時フローの状況チェック向け GSI スナップショット（読み取り専用）
class ShelterDatabase {
  ShelterDatabase._(this._db);

  static const String assetName = 'shelters.db';

  static ShelterDatabase? _instance;
  final Database _db;

  static Future<ShelterDatabase> get instance async {
    _instance ??= await open();
    return _instance!;
  }

  /// assets/shelters.db をドキュメントディレクトリへコピー（初回のみ）して開く。
  /// [databasePath] を指定すると asset コピーを行わずそのファイルを開く（テスト用）。
  static Future<ShelterDatabase> open({String? databasePath}) async {
    final path = databasePath ?? await _ensureLocalCopy();
    final db = await openDatabase(path, readOnly: true);
    return ShelterDatabase._(db);
  }

  static Future<String> _ensureLocalCopy() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, assetName));
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  Future<int> countAll() async {
    final row = await _db.rawQuery('SELECT COUNT(*) AS c FROM shelters');
    return (row.first['c'] as num).toInt();
  }

  Future<int> countEarthquake() async {
    final row = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM shelters WHERE t_earthquake = 1',
    );
    return (row.first['c'] as num).toInt();
  }

  Future<List<GsiShelter>> queryByCityCode(
    String cityCode, {
    int limit = 5,
  }) async {
    final rows = await _db.query(
      'shelters',
      where: 'city_code = ?',
      whereArgs: [cityCode],
      orderBy: 'name',
      limit: limit,
    );
    return rows.map(GsiShelter.fromMap).toList();
  }

  Future<List<GsiShelter>> queryAll() async {
    final rows = await _db.query('shelters', orderBy: 'city_code, name');
    return rows.map(GsiShelter.fromMap).toList();
  }
}
