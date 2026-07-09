import 'dart:io';

import 'package:bosai_app/db/database_helper.dart';
import 'package:bosai_app/routing/models.dart';
import 'package:bosai_app/routing/precompute_service.dart';
import 'package:bosai_app/routing/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _OutOfRangeRouteClient implements RouteSearchClient {
  bool findRoutesCalled = false;

  @override
  bool isInRoutingArea(LatLng from) => false;

  @override
  Future<List<RouteResult>> findRoutesToAll({
    required LatLng from,
    required DisasterMode mode,
    required WeightProfile profile,
  }) async {
    findRoutesCalled = true;
    return const [];
  }
}

class _EmptyRouteClient implements RouteSearchClient {
  int findRoutesCallCount = 0;

  @override
  bool isInRoutingArea(LatLng from) => true;

  @override
  Future<List<RouteResult>> findRoutesToAll({
    required LatLng from,
    required DisasterMode mode,
    required WeightProfile profile,
  }) async {
    findRoutesCallCount++;
    return const [];
  }
}

/// 実データ疎通テスト(§8.3)。
/// routing.db が無い環境ではskip。また flutter test のホスト実行環境では
/// sqflite のプラットフォーム実装が無いため、DBが開けない場合もskipする
/// (仕様§6の「新規依存の追加は不可」により sqflite_common_ffi を導入できない)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自宅座標がグラフ範囲外なら探索・保存に進まず失敗する', () async {
    final client = _OutOfRangeRouteClient();
    final precompute = PrecomputeService(client);

    await expectLater(
      precompute.precomputeAll(home: const LatLng(0, 0)),
      throwsA(isA<StateError>()),
    );
    expect(client.findRoutesCalled, isFalse);
  });

  test('到達可能な経路が0件なら保存に進まず失敗する', () async {
    final client = _EmptyRouteClient();
    final precompute = PrecomputeService(client);

    await expectLater(
      precompute.precomputeAll(home: const LatLng(35.6647, 139.8586)),
      throwsA(isA<StateError>()),
    );
    expect(client.findRoutesCallCount, 6);
  });

  test(
    '西葛西付近を自宅として precomputeAll が完走し期待行数が入る',
    () async {
      final dbFile = File('assets/routing.db');
      if (!dbFile.existsSync()) {
        markTestSkipped('assets/routing.db が無いためskip');
        return;
      }

      final RouteService service;
      try {
        service = await RouteService.createFromPath(dbFile.path);
      } catch (e) {
        markTestSkipped('この環境ではsqfliteが利用できないためskip: $e');
        return;
      }

      const home = LatLng(35.6647, 139.8586); // 西葛西付近
      final progressValues = <double>[];
      final precompute = PrecomputeService(service);
      final stopwatch = Stopwatch()..start();
      await precompute.precomputeAll(
        home: home,
        onProgress: progressValues.add,
      );
      stopwatch.stop();
      // ignore: avoid_print
      print('precomputeAll: ${stopwatch.elapsedMilliseconds}ms');

      // 進捗はモード2×プロファイル3=6回、最後は1.0
      expect(progressValues.length, 6);
      expect(progressValues.last, 1.0);

      // 期待行数 = Σ(モード×プロファイルごとの到達可能避難所数)
      var expectedRows = 0;
      for (final mode in DisasterMode.values) {
        for (final profile in WeightProfile.values) {
          final routes = await service.findRoutesToAll(
              from: home, mode: mode, profile: profile);
          expectedRows += routes.length;
        }
      }
      expect(expectedRows, greaterThan(0));

      final db = await DatabaseHelper.instance.database;
      final count =
          (await db.rawQuery('SELECT COUNT(*) AS c FROM precomputed_routes'))
              .first['c'] as int;
      expect(count, expectedRows);

      // loadPrecomputed の疎通
      final loaded = await precompute.loadPrecomputed(
        mode: DisasterMode.earthquake,
        profile: WeightProfile.balanced,
      );
      expect(loaded, isNotEmpty);
      expect(loaded.first.geometry, isNotEmpty);
      expect(loaded.first.estMinutes, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
