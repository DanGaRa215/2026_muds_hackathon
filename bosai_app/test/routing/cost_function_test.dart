import 'package:bosai_app/routing/cost_function.dart';
import 'package:bosai_app/routing/graph.dart';
import 'package:bosai_app/routing/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 属性を1つだけ持つ2ノード1エッジのグラフを作る。
Graph _singleEdgeGraph({
  double lengthM = 100,
  double? waterDistM,
  double? elevationM,
  bool isBridge = false,
  bool isTunnel = false,
}) {
  return Graph.fromEdgeList(
    lats: [35.66, 35.661],
    lons: [139.85, 139.85],
    edges: [
      GraphEdgeInput(
        fromIndex: 0,
        toIndex: 1,
        lengthM: lengthM,
        waterDistM: waterDistM,
        elevationM: elevationM,
        isBridge: isBridge,
        isTunnel: isTunnel,
        dbId: 1,
      ),
    ],
  );
}

void main() {
  group('水域近接ペナルティの境界値(§8.2)', () {
    // (water_dist_m, earthquake期待値, flood期待値)
    const cases = [
      (49.9, 200.0, 600.0), // 強
      (50.0, 100.0, 300.0), // 弱(強と排他)
      (99.9, 100.0, 300.0), // 弱
      (100.0, 0.0, 0.0), // ペナルティなし
    ];

    for (final (waterDist, expectedEq, expectedFlood) in cases) {
      test('water_dist_m=$waterDist → eq:$expectedEq / flood:$expectedFlood',
          () {
        final graph =
            _singleEdgeGraph(waterDistM: waterDist, elevationM: 10);
        final eq = CostFunction(
            mode: DisasterMode.earthquake, profile: WeightProfile.balanced);
        final flood = CostFunction(
            mode: DisasterMode.flood, profile: WeightProfile.balanced);
        expect(eq.rawPenalty(graph, 0), expectedEq);
        expect(flood.rawPenalty(graph, 0), expectedFlood);
      });
    }
  });

  group('各重み項', () {
    test('橋: earthquake +600 / flood +300', () {
      final graph = _singleEdgeGraph(
          isBridge: true, waterDistM: 1000, elevationM: 10);
      expect(
        CostFunction(
                mode: DisasterMode.earthquake,
                profile: WeightProfile.balanced)
            .rawPenalty(graph, 0),
        600,
      );
      expect(
        CostFunction(
                mode: DisasterMode.flood, profile: WeightProfile.balanced)
            .rawPenalty(graph, 0),
        300,
      );
    });

    test('トンネル: earthquake +400 / floodは通行不可、フォールバック時+3000', () {
      final graph = _singleEdgeGraph(
          isTunnel: true, waterDistM: 1000, elevationM: 10);
      final eq = CostFunction(
          mode: DisasterMode.earthquake, profile: WeightProfile.balanced);
      expect(eq.allows(graph, 0), isTrue);
      expect(eq.rawPenalty(graph, 0), 400);

      final flood = CostFunction(
          mode: DisasterMode.flood, profile: WeightProfile.balanced);
      expect(flood.allows(graph, 0), isFalse, reason: 'ハード制約(§5.3)');

      final fallback = CostFunction(
          mode: DisasterMode.flood,
          profile: WeightProfile.balanced,
          tunnelFallback: true);
      expect(fallback.allows(graph, 0), isTrue);
      expect(fallback.rawPenalty(graph, 0), 3000);
    });

    test('低標高: max(0, 2.0-elev)×k、earthquakeはk=0', () {
      final graph = _singleEdgeGraph(waterDistM: 1000, elevationM: 0.5);
      expect(
        CostFunction(
                mode: DisasterMode.earthquake,
                profile: WeightProfile.balanced)
            .rawPenalty(graph, 0),
        0,
      );
      expect(
        CostFunction(
                mode: DisasterMode.flood, profile: WeightProfile.balanced)
            .rawPenalty(graph, 0),
        closeTo(1.5 * 150, 1e-9),
      );
      // 標高2.0以上はペナルティなし
      final high = _singleEdgeGraph(waterDistM: 1000, elevationM: 2.0);
      expect(
        CostFunction(
                mode: DisasterMode.flood, profile: WeightProfile.balanced)
            .rawPenalty(high, 0),
        0,
      );
    });

    test('NULL属性(water_dist_m/elevation_m)はペナルティなし扱い', () {
      final graph = _singleEdgeGraph(waterDistM: null, elevationM: null);
      expect(
        CostFunction(
                mode: DisasterMode.flood, profile: WeightProfile.balanced)
            .rawPenalty(graph, 0),
        0,
      );
    });
  });

  group('プロファイル係数(§5.1)', () {
    test('係数は距離に掛からずペナルティのみに掛かる', () {
      const length = 100.0;
      // 水域強(flood +600) の1エッジ
      final graph = _singleEdgeGraph(
          lengthM: length, waterDistM: 10, elevationM: 10);

      const rawPenalty = 600.0;
      const expectations = {
        WeightProfile.fastest: length + 0.5 * rawPenalty,
        WeightProfile.balanced: length + 1.0 * rawPenalty,
        WeightProfile.safest: length + 2.0 * rawPenalty,
      };
      expectations.forEach((profile, expected) {
        final costFn = CostFunction(mode: DisasterMode.flood, profile: profile);
        expect(costFn.cost(graph, 0), closeTo(expected, 1e-9),
            reason: '$profile: 距離$length はそのまま、ペナルティのみ係数倍');
      });
    });

    test('ペナルティ0のエッジではプロファイルによらずコスト=距離', () {
      final graph = _singleEdgeGraph(
          lengthM: 123.4, waterDistM: 1000, elevationM: 10);
      for (final profile in WeightProfile.values) {
        for (final mode in DisasterMode.values) {
          final costFn = CostFunction(mode: mode, profile: profile);
          expect(costFn.cost(graph, 0), closeTo(123.4, 1e-9));
        }
      }
    });
  });
}
