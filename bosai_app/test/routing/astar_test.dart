import 'package:bosai_app/routing/astar.dart';
import 'package:bosai_app/routing/cost_function.dart';
import 'package:bosai_app/routing/graph.dart';
import 'package:bosai_app/routing/models.dart';
import 'package:bosai_app/routing/route_service.dart';
import 'package:bosai_app/routing/routing_db.dart';
import 'package:bosai_app/routing/snap.dart';
import 'package:flutter_test/flutter_test.dart';

/// 3x3格子グラフ(9ノード + 補助1ノードで10ノード規模)。
/// ノードindex = row * 3 + col。エッジ長は端点間のhaversine距離
/// (直線距離ヒューリスティックのadmissibilityを保つため)。
///
///   6 - 7 - 8
///   |   |   |
///   3 - 4 - 5
///   |   |   |
///   0 - 1 - 2
class _GridSpec {
  final List<double> lats = [];
  final List<double> lons = [];
  final List<GraphEdgeInput> edges = [];

  /// エッジ(from,to)のリスト上の位置。属性の上書きに使う。
  final Map<String, int> edgePos = {};

  _GridSpec() {
    const baseLat = 35.66;
    const baseLon = 139.85;
    const step = 0.001; // 約111m(緯度方向)
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        lats.add(baseLat + row * step);
        lons.add(baseLon + col * step);
      }
    }
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final v = row * 3 + col;
        if (col < 2) _addEdge(v, v + 1); // 東西
        if (row < 2) _addEdge(v, v + 3); // 南北
      }
    }
  }

  void _addEdge(int from, int to) {
    edgePos['$from-$to'] = edges.length;
    edges.add(GraphEdgeInput(
      fromIndex: from,
      toIndex: to,
      lengthM: haversineM(lats[from], lons[from], lats[to], lons[to]),
      waterDistM: 1000, // ペナルティなし
      elevationM: 10,
      dbId: edges.length + 1,
    ));
  }

  /// 指定エッジの属性を差し替える。
  void override(
    int from,
    int to, {
    double? waterDistM,
    double? elevationM,
    bool? isBridge,
    bool? isTunnel,
  }) {
    final pos = edgePos['$from-$to'] ?? edgePos['$to-$from']!;
    final e = edges[pos];
    edges[pos] = GraphEdgeInput(
      fromIndex: e.fromIndex,
      toIndex: e.toIndex,
      lengthM: e.lengthM,
      waterDistM: waterDistM ?? e.waterDistM,
      elevationM: elevationM ?? e.elevationM,
      isBridge: isBridge ?? e.isBridge,
      isTunnel: isTunnel ?? e.isTunnel,
      dbId: e.dbId,
    );
  }

  Graph build() => Graph.fromEdgeList(lats: lats, lons: lons, edges: edges);

  double edgeLength(int from, int to) =>
      edges[edgePos['$from-$to'] ?? edgePos['$to-$from']!].lengthM;
}

void main() {
  group('A*格子グラフ正当性(§8.1)', () {
    test('1. ペナルティ全0のとき既知の最短経路距離と一致する', () {
      final spec = _GridSpec();
      final graph = spec.build();
      final costFn = CostFunction(
          mode: DisasterMode.earthquake, profile: WeightProfile.balanced);

      final result =
          aStarSearch(graph: graph, costFn: costFn, start: 0, goals: {8});
      final path = extractPath(graph, result, 0, 8);

      expect(path, isNotNull);
      // 0→8 は縦2 + 横2 の4エッジ(格子の性質上どの単調経路も同距離)
      final expected = 2 * spec.edgeLength(0, 3) + 2 * spec.edgeLength(0, 1);
      expect(path!.distanceM, closeTo(expected, 0.01));
      expect(path.totalCost, closeTo(expected, 0.01)); // ペナルティ0
      expect(path.edgeIndexes.length, 4);
    });

    test('2. water_dist_mが小さいエッジをfloodモードで回避する', () {
      final spec = _GridSpec();
      // 0→1(東)を水域至近にする。0→8 は北回り(0→3→...)で完全回避できる
      spec.override(0, 1, waterDistM: 10);
      final graph = spec.build();
      final costFn = CostFunction(
          mode: DisasterMode.flood, profile: WeightProfile.balanced);

      final result =
          aStarSearch(graph: graph, costFn: costFn, start: 0, goals: {8});
      final path = extractPath(graph, result, 0, 8);

      expect(path, isNotNull);
      final wetEdge = spec.edgePos['0-1']!;
      expect(path!.edgeIndexes, isNot(contains(wetEdge)),
          reason: '水域至近エッジを回避すること');
      expect(path.penaltyM, closeTo(0, 0.01), reason: '回避経路はペナルティ0');
      // 距離は最短のまま(等距離の代替経路がある)
      final expected = 2 * spec.edgeLength(0, 3) + 2 * spec.edgeLength(0, 1);
      expect(path.distanceM, closeTo(expected, 0.01));
    });

    test('3. h=0(Dijkstra)と直線距離hのA*が同一コストの経路を返す', () {
      final spec = _GridSpec();
      // ペナルティも混ぜて非自明にする
      spec.override(3, 4, isBridge: true);
      spec.override(1, 4, waterDistM: 70);
      final graph = spec.build();
      final costFn = CostFunction(
          mode: DisasterMode.earthquake, profile: WeightProfile.balanced);

      final dijkstra = aStarSearch(
          graph: graph, costFn: costFn, start: 0, goals: {8}, heuristic: null);
      final astar = aStarSearch(
        graph: graph,
        costFn: costFn,
        start: 0,
        goals: {8},
        heuristic: (n) =>
            haversineM(graph.lat[n], graph.lon[n], graph.lat[8], graph.lon[8]),
      );

      final pathD = extractPath(graph, dijkstra, 0, 8);
      final pathA = extractPath(graph, astar, 0, 8);
      expect(pathD, isNotNull);
      expect(pathA, isNotNull);
      expect(pathA!.totalCost, closeTo(pathD!.totalCost, 1e-9));
    });

    test('4. 複数ゴール探索の各経路コストが個別Dijkstraと一致する', () {
      final spec = _GridSpec();
      spec.override(0, 1, waterDistM: 40);
      spec.override(4, 7, isBridge: true);
      final graph = spec.build();
      final costFn = CostFunction(
          mode: DisasterMode.earthquake, profile: WeightProfile.balanced);
      final goals = {2, 6, 8};

      final multi =
          aStarSearch(graph: graph, costFn: costFn, start: 0, goals: goals);
      expect(multi.settledGoals, goals, reason: '全ゴールが確定されること');

      for (final goal in goals) {
        final single =
            aStarSearch(graph: graph, costFn: costFn, start: 0, goals: {goal});
        final pathMulti = extractPath(graph, multi, 0, goal);
        final pathSingle = extractPath(graph, single, 0, goal);
        expect(pathMulti, isNotNull);
        expect(pathSingle, isNotNull);
        expect(pathMulti!.totalCost, closeTo(pathSingle!.totalCost, 1e-9),
            reason: 'goal=$goal のコストが個別Dijkstraと一致すること');
      }
    });

    test('5. floodでトンネルが唯一の経路のとき通常探索は失敗しフォールバックで返る', () {
      // 一直線 0-1-2(トンネル区間 1-2 が唯一のゴール到達路)
      final lats = [35.66, 35.661, 35.662];
      final lons = [139.85, 139.85, 139.85];
      final edges = [
        GraphEdgeInput(
          fromIndex: 0,
          toIndex: 1,
          lengthM: haversineM(lats[0], lons[0], lats[1], lons[1]),
          waterDistM: 1000,
          elevationM: 10,
          dbId: 1,
        ),
        GraphEdgeInput(
          fromIndex: 1,
          toIndex: 2,
          lengthM: haversineM(lats[1], lons[1], lats[2], lons[2]),
          waterDistM: 1000,
          elevationM: 10,
          isTunnel: true,
          dbId: 2,
        ),
      ];
      final graph = Graph.fromEdgeList(lats: lats, lons: lons, edges: edges);

      // 通常探索(ハード制約): 到達不能
      final normal = aStarSearch(
        graph: graph,
        costFn: CostFunction(
            mode: DisasterMode.flood, profile: WeightProfile.balanced),
        start: 0,
        goals: {2},
      );
      expect(extractPath(graph, normal, 0, 2), isNull);

      // 探索本体のフォールバック込み実装: usedFallback=true の経路が返る
      final outcome = searchSingleGoal(
          graph, 0, 2, DisasterMode.flood, WeightProfile.balanced);
      expect(outcome, isNotNull);
      expect(outcome!.usedFallback, isTrue);
      expect(outcome.edgeIndexes.length, 2);
      // トンネルのソフトペナルティ +3000 が乗っていること
      expect(
          outcome.penaltyM, closeTo(RoutingWeights.tunnelFloodFallback, 0.01));

      // 複数ゴール版も同様にフォールバックする
      final multiOutcomes = searchMultiGoal(
          graph, 0, {2}, DisasterMode.flood, WeightProfile.balanced);
      expect(multiOutcomes[2], isNotNull);
      expect(multiOutcomes[2]!.usedFallback, isTrue);
    });
  });

  group('geometry復元', () {
    test('DB上のgeometry向きが逆でも通行方向に正規化する', () {
      final graph = Graph.fromEdgeList(
        lats: [35.0, 35.001],
        lons: [139.0, 139.0],
        edges: [
          const GraphEdgeInput(
            fromIndex: 0,
            toIndex: 1,
            lengthM: 100,
            waterDistM: 1000,
            elevationM: 10,
            dbId: 1,
          ),
        ],
      );
      final rawReverse = [
        [35.001, 139.0],
        [35.0, 139.0],
      ];

      final forward = orientEdgeGeometryForTraversal(
        graph,
        0,
        false,
        rawReverse,
      );
      expect(
        forward,
        equals([
          [35.0, 139.0],
          [35.001, 139.0],
        ]),
      );

      final backward = orientEdgeGeometryForTraversal(
        graph,
        0,
        true,
        rawReverse,
      );
      expect(backward, equals(rawReverse));
    });
  });
}
