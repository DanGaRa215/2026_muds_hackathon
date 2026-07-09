import 'dart:convert';
import 'dart:developer' as developer;

import 'package:latlong2/latlong.dart';

import '../db/database_helper.dart';
import 'models.dart';
import 'route_service.dart';

/// 自宅からの避難経路の事前計算と precomputed_routes への永続化(§7)。
class PrecomputeService {
  final RouteSearchClient _routeService;
  final DatabaseHelper _dbHelper;

  PrecomputeService(this._routeService, {DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// 自宅登録時に呼ぶ。全モード×全プロファイルを計算しDB保存。
  /// onProgress は 0.0〜1.0。
  Future<void> precomputeAll({
    required LatLng home,
    void Function(double progress)? onProgress,
  }) async {
    const modes = DisasterMode.values;
    const profiles = WeightProfile.values;
    final totalCombos = modes.length * profiles.length;

    if (!_routeService.isInRoutingArea(home)) {
      developer.log('precomputeAll: 自宅座標がグラフ範囲外: $home',
          name: 'routing', level: 900);
      throw StateError('自宅座標がルーティング範囲外です');
    }

    final results = <RouteResult>[];
    var done = 0;
    for (final mode in modes) {
      for (final profile in profiles) {
        final routes = await _routeService.findRoutesToAll(
          from: home,
          mode: mode,
          profile: profile,
        );
        results.addAll(routes);
        done++;
        onProgress?.call(done / totalCombos);
      }
    }

    if (results.isEmpty) {
      developer.log('precomputeAll: 到達可能な経路が0件のため保存を中止する',
          name: 'routing', level: 900);
      throw StateError('事前計算できた経路が0件です');
    }

    developer.log('precomputeAll: ${results.length}件を保存する', name: 'routing');

    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    // 既存行を全削除してから単一トランザクションで一括insert(§7)
    await db.transaction((txn) async {
      await txn.delete('precomputed_routes');
      final batch = txn.batch();
      for (final r in results) {
        batch.insert('precomputed_routes', {
          'shelter_id': r.shelterId,
          'disaster_mode': r.mode.name,
          'weight_profile': r.profile.name,
          'distance_m': r.distanceM,
          'penalty_m': r.penaltyM,
          'est_minutes': r.estMinutes,
          'safety_score': r.safetyScore,
          'used_fallback': r.usedFallback ? 1 : 0,
          'geometry': jsonEncode([
            for (final p in r.geometry) [p.latitude, p.longitude]
          ]),
          'computed_at': now,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<RouteResult>> loadPrecomputed({
    required DisasterMode mode,
    required WeightProfile profile,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'precomputed_routes',
      where: 'disaster_mode = ? AND weight_profile = ?',
      whereArgs: [mode.name, profile.name],
    );
    return rows.map((row) {
      final decoded = jsonDecode(row['geometry'] as String) as List;
      return RouteResult(
        shelterId: row['shelter_id'] as String,
        mode: mode,
        profile: profile,
        distanceM: (row['distance_m'] as num).toDouble(),
        penaltyM: (row['penalty_m'] as num).toDouble(),
        estMinutes: (row['est_minutes'] as num).toDouble(),
        safetyScore: (row['safety_score'] as num).toDouble(),
        usedFallback: ((row['used_fallback'] as num?)?.toInt() ?? 0) != 0,
        geometry: [
          for (final point in decoded)
            LatLng(
              ((point as List)[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            )
        ],
      );
    }).toList();
  }
}
