import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:latlong2/latlong.dart';

import 'astar.dart';
import 'cost_function.dart';
import 'graph.dart';
import 'models.dart';
import 'routing_db.dart';
import 'snap.dart';

abstract interface class RouteSearchClient {
  bool isInRoutingArea(LatLng from);

  Future<List<RouteResult>> findRoutesToAll({
    required LatLng from,
    required DisasterMode mode,
    required WeightProfile profile,
  });
}

/// 探索本体(isolate内)の出力。geometry のDB引きはメインisolateで行うため、
/// エッジ列とコストのみを返す(§6.3)。
class PathOutcome {
  final int goalNode;
  final List<int> edgeIndexes;
  final List<bool> reversedFlags;
  final double distanceM;
  final double penaltyM;
  final bool usedFallback;

  const PathOutcome({
    required this.goalNode,
    required this.edgeIndexes,
    required this.reversedFlags,
    required this.distanceM,
    required this.penaltyM,
    required this.usedFallback,
  });
}

/// 1対1探索の本体(純ロジック。sqflite非依存でテスト可能)。
/// 単一ゴールなので直線距離ヒューリスティックのA*。
/// floodモードで到達不能の場合のみ、トンネルを+3000mソフトペナルティに
/// 緩めたフォールバック探索を1回だけ行い usedFallback を立てる(§5.3)。
PathOutcome? searchSingleGoal(
  Graph graph,
  int start,
  int goal,
  DisasterMode mode,
  WeightProfile profile,
) {
  double heuristic(int node) => haversineM(
      graph.lat[node], graph.lon[node], graph.lat[goal], graph.lon[goal]);

  PathOutcome? run({required bool fallback}) {
    final costFn =
        CostFunction(mode: mode, profile: profile, tunnelFallback: fallback);
    final result = aStarSearch(
      graph: graph,
      costFn: costFn,
      start: start,
      goals: {goal},
      heuristic: heuristic,
    );
    final path = extractPath(graph, result, start, goal);
    if (path == null) return null;
    return PathOutcome(
      goalNode: goal,
      edgeIndexes: path.edgeIndexes,
      reversedFlags: path.reversedFlags,
      distanceM: path.distanceM,
      penaltyM: path.penaltyM,
      usedFallback: fallback,
    );
  }

  final normal = run(fallback: false);
  if (normal != null) return normal;
  if (mode != DisasterMode.flood) return null;
  return run(fallback: true);
}

/// 1始点→複数ゴールの一括探索の本体(h=0のDijkstra)。
/// floodモードで到達不能だったゴールに対してのみ、フォールバック探索を
/// 1回だけ追加で行う。
Map<int, PathOutcome> searchMultiGoal(
  Graph graph,
  int start,
  Set<int> goals,
  DisasterMode mode,
  WeightProfile profile,
) {
  final outcomes = <int, PathOutcome>{};

  Set<int> runInto({
    required Set<int> targets,
    required bool fallback,
  }) {
    final costFn =
        CostFunction(mode: mode, profile: profile, tunnelFallback: fallback);
    final result = aStarSearch(
      graph: graph,
      costFn: costFn,
      start: start,
      goals: targets,
      heuristic: null, // 複数ゴールは必ず h=0(§6.1)
    );
    final unreached = <int>{};
    for (final goal in targets) {
      final path = extractPath(graph, result, start, goal);
      if (path == null) {
        unreached.add(goal);
        continue;
      }
      outcomes[goal] = PathOutcome(
        goalNode: goal,
        edgeIndexes: path.edgeIndexes,
        reversedFlags: path.reversedFlags,
        distanceM: path.distanceM,
        penaltyM: path.penaltyM,
        usedFallback: fallback,
      );
    }
    return unreached;
  }

  final unreached = runInto(targets: goals, fallback: false);
  if (unreached.isNotEmpty && mode == DisasterMode.flood) {
    runInto(targets: unreached, fallback: true);
  }
  return outcomes;
}

/// 経路探索の公開窓口(§3)。仕様書③がこの型に依存する。
class RouteService implements RouteSearchClient {
  final RoutingDatabase _rdb;

  RouteService._(this._rdb);

  /// routing.db ロード込みの初期化。
  static Future<RouteService> create() async {
    return RouteService._(await RoutingDatabase.open());
  }

  /// テスト用: 展開済みDBファイルを直接指定して初期化する。
  static Future<RouteService> createFromPath(String databasePath) async {
    return RouteService._(
        await RoutingDatabase.open(databasePath: databasePath));
  }

  int? _snapStart(LatLng from) =>
      nearestNodeIndex(_rdb.graph, from.latitude, from.longitude);

  @override
  bool isInRoutingArea(LatLng from) => _snapStart(from) != null;

  /// 1対1のリアルタイム探索(直線距離ヒューリスティックのA*)。
  /// 出発地がグラフ範囲外(最近傍ノードまで300m超)または避難所不明・
  /// 到達不能のとき null。
  Future<RouteResult?> findRoute({
    required LatLng from,
    required String shelterId,
    required DisasterMode mode,
    required WeightProfile profile,
  }) async {
    final shelterIndex =
        _rdb.shelters.indexWhere((s) => s.shelterId == shelterId);
    if (shelterIndex < 0) {
      developer.log('避難所が見つからない: $shelterId', name: 'routing', level: 900);
      return null;
    }
    final goal = _rdb.shelterNodeIndexes[shelterIndex];
    if (goal < 0) return null;

    final graph = _rdb.graph;
    final start = _snapStart(from);
    if (start == null) {
      developer.log('出発地がグラフ範囲外: $from', name: 'routing', level: 900);
      return null;
    }

    final outcome = await Isolate.run(
        () => searchSingleGoal(graph, start, goal, mode, profile));
    if (outcome == null) return null;
    return _buildResult(_rdb.shelters[shelterIndex], mode, profile, outcome);
  }

  /// 1始点→複数避難所の一括探索(h=0のDijkstra)。事前計算が使う。
  /// 到達不能(フォールバックも失敗)の避難所は結果から除かれる。
  @override
  Future<List<RouteResult>> findRoutesToAll({
    required LatLng from,
    required DisasterMode mode,
    required WeightProfile profile,
  }) async {
    final graph = _rdb.graph;
    final start = _snapStart(from);
    if (start == null) {
      developer.log('出発地がグラフ範囲外: $from', name: 'routing', level: 900);
      return [];
    }

    final shelters = sheltersFor(mode);
    // 同一ノードに複数避難所がスナップされる場合があるため node → 避難所リスト
    final sheltersByNode = <int, List<ShelterInfo>>{};
    for (final s in shelters) {
      final index = _rdb.shelters.indexOf(s);
      final node = _rdb.shelterNodeIndexes[index];
      if (node < 0) continue;
      sheltersByNode.putIfAbsent(node, () => []).add(s);
    }
    final goals = sheltersByNode.keys.toSet();
    if (goals.isEmpty) return [];

    final outcomes = await Isolate.run(
        () => searchMultiGoal(graph, start, goals, mode, profile));

    final skipped = goals.length - outcomes.length;
    if (skipped > 0) {
      developer.log('到達不能でスキップしたゴール: $skipped件 (mode=$mode)',
          name: 'routing', level: 900);
    }

    final results = <RouteResult>[];
    for (final entry in outcomes.entries) {
      for (final shelter in sheltersByNode[entry.key]!) {
        results.add(await _buildResult(shelter, mode, profile, entry.value));
      }
    }
    return results;
  }

  /// モードに対応した避難所一覧(shelters.types に基づく §5.2)。
  /// フィルタ結果が0件の場合はデータ不備の保険として全件を返し警告を出す。
  List<ShelterInfo> sheltersFor(DisasterMode mode) {
    final wanted = mode == DisasterMode.earthquake
        ? const {'earthquake', 'fire'}
        : const {'flood', 'surge'};
    final filtered =
        _rdb.shelters.where((s) => s.typeList.any(wanted.contains)).toList();
    if (filtered.isEmpty) {
      developer.log(
        'sheltersFor($mode): typesフィルタが0件。データ不備の可能性があるため全件を返す',
        name: 'routing',
        level: 900,
      );
      return List.of(_rdb.shelters);
    }
    return filtered;
  }

  Future<RouteResult> _buildResult(
    ShelterInfo shelter,
    DisasterMode mode,
    WeightProfile profile,
    PathOutcome outcome,
  ) async {
    final geometry = await _rdb.loadPathGeometry(
      outcome.edgeIndexes,
      outcome.reversedFlags,
      startPoint: shelter.latLng,
    );
    return RouteResult.fromCosts(
      shelterId: shelter.shelterId,
      mode: mode,
      profile: profile,
      distanceM: outcome.distanceM,
      penaltyM: outcome.penaltyM,
      geometry: geometry,
      usedFallback: outcome.usedFallback,
    );
  }
}
