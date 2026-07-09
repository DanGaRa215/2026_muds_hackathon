import 'dart:typed_data';

/// Graph 構築用のエッジ入力。from/to は内部ノードindex。
class GraphEdgeInput {
  final int fromIndex;
  final int toIndex;
  final double lengthM;
  final double? waterDistM;
  final double? elevationM;
  final bool isBridge;
  final bool isTunnel;

  /// routing.db の edges.id。テスト用グラフでは任意の値でよい。
  final int dbId;

  const GraphEdgeInput({
    required this.fromIndex,
    required this.toIndex,
    required this.lengthM,
    this.waterDistM,
    this.elevationM,
    this.isBridge = false,
    this.isTunnel = false,
    this.dbId = -1,
  });
}

/// インメモリグラフ。フラットTypedData構造のみで構成し、
/// そのまま isolate へ送れる(探索中にSQLiteを叩かない)。
/// 無向エッジはCSR隣接リスト上で両方向に展開する。
class Graph {
  static const int bridgeBit = 1; // flags bit0
  static const int tunnelBit = 2; // flags bit1

  /// water_dist_m が NULL のときの番兵(水域なし扱い=ペナルティ0)
  static const double noWaterDist = double.infinity;

  /// elevation_m が NULL のときの番兵(十分高い扱い=ペナルティ0)
  static const double noElevation = 9999.0;

  final int nodeCount;
  final int edgeCount;

  // ノード属性
  final Float64List lat;
  final Float64List lon;

  // CSR隣接リスト(無向を両方向展開、長さ 2*edgeCount)
  final Int32List adjOffsets; // 長さ nodeCount+1
  final Int32List adjTargets;
  final Int32List adjEdgeIds; // エッジ内部index

  // エッジ属性(内部index順)
  final Int32List edgeFromNode;
  final Int32List edgeToNode;
  final Int32List edgeDbIds;
  final Float64List lengthM;
  final Float64List waterDistM;
  final Float64List elevationM;
  final Uint8List flags;

  Graph._({
    required this.nodeCount,
    required this.edgeCount,
    required this.lat,
    required this.lon,
    required this.adjOffsets,
    required this.adjTargets,
    required this.adjEdgeIds,
    required this.edgeFromNode,
    required this.edgeToNode,
    required this.edgeDbIds,
    required this.lengthM,
    required this.waterDistM,
    required this.elevationM,
    required this.flags,
  });

  /// ノード座標とエッジリストから構築する(sqflite非依存。テストでも使用)。
  factory Graph.fromEdgeList({
    required List<double> lats,
    required List<double> lons,
    required List<GraphEdgeInput> edges,
  }) {
    assert(lats.length == lons.length);
    final n = lats.length;
    final m = edges.length;

    final latArr = Float64List.fromList(lats);
    final lonArr = Float64List.fromList(lons);

    final edgeFrom = Int32List(m);
    final edgeTo = Int32List(m);
    final edgeDb = Int32List(m);
    final lenArr = Float64List(m);
    final waterArr = Float64List(m);
    final elevArr = Float64List(m);
    final flagArr = Uint8List(m);

    for (var i = 0; i < m; i++) {
      final e = edges[i];
      edgeFrom[i] = e.fromIndex;
      edgeTo[i] = e.toIndex;
      edgeDb[i] = e.dbId;
      lenArr[i] = e.lengthM;
      waterArr[i] = e.waterDistM ?? noWaterDist;
      elevArr[i] = e.elevationM ?? noElevation;
      flagArr[i] =
          (e.isBridge ? bridgeBit : 0) | (e.isTunnel ? tunnelBit : 0);
    }

    // CSR構築: 次数カウント → オフセット → 充填
    final degree = Int32List(n);
    for (var i = 0; i < m; i++) {
      degree[edgeFrom[i]]++;
      degree[edgeTo[i]]++;
    }
    final offsets = Int32List(n + 1);
    for (var v = 0; v < n; v++) {
      offsets[v + 1] = offsets[v] + degree[v];
    }
    final targets = Int32List(2 * m);
    final adjEdges = Int32List(2 * m);
    final cursor = Int32List.fromList(offsets.sublist(0, n));
    for (var i = 0; i < m; i++) {
      final u = edgeFrom[i];
      final v = edgeTo[i];
      targets[cursor[u]] = v;
      adjEdges[cursor[u]] = i;
      cursor[u]++;
      targets[cursor[v]] = u;
      adjEdges[cursor[v]] = i;
      cursor[v]++;
    }

    return Graph._(
      nodeCount: n,
      edgeCount: m,
      lat: latArr,
      lon: lonArr,
      adjOffsets: offsets,
      adjTargets: targets,
      adjEdgeIds: adjEdges,
      edgeFromNode: edgeFrom,
      edgeToNode: edgeTo,
      edgeDbIds: edgeDb,
      lengthM: lenArr,
      waterDistM: waterArr,
      elevationM: elevArr,
      flags: flagArr,
    );
  }

  bool isBridge(int edgeIndex) => (flags[edgeIndex] & bridgeBit) != 0;

  bool isTunnel(int edgeIndex) => (flags[edgeIndex] & tunnelBit) != 0;
}
