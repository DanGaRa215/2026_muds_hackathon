import 'dart:typed_data';

import 'cost_function.dart';
import 'graph.dart';

/// A*探索の結果。cameFrom 系配列から経路を復元する。
class SearchResult {
  /// 各ノードへの確定コスト。未到達は double.infinity
  final Float64List gCost;

  /// 各ノードへ入ってきたエッジの内部index。始点・未到達は -1
  final Int32List cameFromEdge;

  /// 各ノードの先行ノードindex。始点・未到達は -1
  final Int32List cameFromNode;

  /// settled(キューから確定)されたゴールノードの集合
  final Set<int> settledGoals;

  const SearchResult({
    required this.gCost,
    required this.cameFromEdge,
    required this.cameFromNode,
    required this.settledGoals,
  });
}

/// 標準的なA*。heuristic が null のとき h=0 で動作する(=Dijkstra)。
///
/// 複数ゴール対応: ゴールノードが settled されるたびに記録し、
/// 全ゴール確定またはキュー枯渇で終了する(最初の1件では終了しない)。
/// 複数ゴール時は heuristic を必ず null にすること(assertで防御)。
SearchResult aStarSearch({
  required Graph graph,
  required CostFunction costFn,
  required int start,
  required Set<int> goals,
  double Function(int nodeIndex)? heuristic,
}) {
  assert(heuristic == null || goals.length <= 1,
      '複数ゴール探索では heuristic を null にすること(§6.1)');

  final n = graph.nodeCount;
  final gCost = Float64List(n)..fillRange(0, n, double.infinity);
  final cameFromEdge = Int32List(n)..fillRange(0, n, -1);
  final cameFromNode = Int32List(n)..fillRange(0, n, -1);
  final settled = Uint8List(n);
  final settledGoals = <int>{};

  final heap = _BinaryHeap();
  gCost[start] = 0;
  heap.push(heuristic?.call(start) ?? 0, start);

  while (heap.isNotEmpty) {
    final node = heap.pop();
    if (settled[node] != 0) continue; // 遅延削除された古いエントリ
    settled[node] = 1;

    if (goals.contains(node)) {
      settledGoals.add(node);
      if (settledGoals.length == goals.length) break;
    }

    final begin = graph.adjOffsets[node];
    final end = graph.adjOffsets[node + 1];
    for (var i = begin; i < end; i++) {
      final edge = graph.adjEdgeIds[i];
      if (!costFn.allows(graph, edge)) continue;
      final target = graph.adjTargets[i];
      if (settled[target] != 0) continue;
      final newCost = gCost[node] + costFn.cost(graph, edge);
      if (newCost < gCost[target]) {
        gCost[target] = newCost;
        cameFromEdge[target] = edge;
        cameFromNode[target] = node;
        heap.push(newCost + (heuristic?.call(target) ?? 0), target);
      }
    }
  }

  return SearchResult(
    gCost: gCost,
    cameFromEdge: cameFromEdge,
    cameFromNode: cameFromNode,
    settledGoals: settledGoals,
  );
}

/// 復元された経路。エッジ列と、各エッジを逆向きに通ったかのフラグ。
class ExtractedPath {
  /// 通過エッジの内部index(始点→ゴール順)
  final List<int> edgeIndexes;

  /// 各エッジについて、DB上の from→to と逆向きに通った場合 true
  final List<bool> reversedFlags;

  /// 実距離合計(ペナルティ含まず)
  final double distanceM;

  /// 総コスト(実距離 + プロファイル係数適用後ペナルティ)
  final double totalCost;

  const ExtractedPath({
    required this.edgeIndexes,
    required this.reversedFlags,
    required this.distanceM,
    required this.totalCost,
  });

  /// 総コスト − 実距離 = 係数適用後ペナルティ合計
  double get penaltyM {
    final p = totalCost - distanceM;
    return p < 0 ? 0 : p; // 浮動小数の丸めで僅かに負になるのを防ぐ
  }
}

/// SearchResult から goal までの経路を復元する。未到達なら null。
ExtractedPath? extractPath(
  Graph graph,
  SearchResult result,
  int start,
  int goal,
) {
  if (result.gCost[goal].isInfinite) return null;

  final edgeIndexes = <int>[];
  final reversedFlags = <bool>[];
  var distance = 0.0;
  var node = goal;
  while (node != start) {
    final edge = result.cameFromEdge[node];
    final prev = result.cameFromNode[node];
    if (edge < 0 || prev < 0) return null; // 復元不能(理論上到達しない)
    edgeIndexes.add(edge);
    // DB上 from→to のエッジを prev→node と通った。向きが逆なら反転フラグ。
    reversedFlags.add(graph.edgeFromNode[edge] != prev);
    distance += graph.lengthM[edge];
    node = prev;
  }

  return ExtractedPath(
    edgeIndexes: edgeIndexes.reversed.toList(),
    reversedFlags: reversedFlags.reversed.toList(),
    distanceM: distance,
    totalCost: result.gCost[goal],
  );
}

/// (優先度, ノード) の最小ヒープ。遅延削除方式(settled側でスキップ)。
class _BinaryHeap {
  final List<double> _priority = [];
  final List<int> _node = [];

  bool get isNotEmpty => _node.isNotEmpty;

  void push(double priority, int node) {
    _priority.add(priority);
    _node.add(node);
    var i = _node.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_priority[parent] <= _priority[i]) break;
      _swap(parent, i);
      i = parent;
    }
  }

  /// 最小優先度のノードを取り出す。空のとき呼んではならない。
  int pop() {
    final top = _node[0];
    final lastIndex = _node.length - 1;
    _priority[0] = _priority[lastIndex];
    _node[0] = _node[lastIndex];
    _priority.removeLast();
    _node.removeLast();
    var i = 0;
    final n = _node.length;
    while (true) {
      final left = 2 * i + 1;
      if (left >= n) break;
      final right = left + 1;
      var smallest = left;
      if (right < n && _priority[right] < _priority[left]) smallest = right;
      if (_priority[i] <= _priority[smallest]) break;
      _swap(i, smallest);
      i = smallest;
    }
    return top;
  }

  void _swap(int a, int b) {
    final p = _priority[a];
    _priority[a] = _priority[b];
    _priority[b] = p;
    final v = _node[a];
    _node[a] = _node[b];
    _node[b] = v;
  }
}
