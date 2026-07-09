import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'graph.dart';
import 'models.dart';

/// DBに保存されたgeometryを、実際にエッジを通過した向きへ揃える。
/// routing.db の geometry は from_node→to_node 順とは限らないため、端点座標を
/// グラフノード座標と比較して向きを判定する。
List<List<double>> orientEdgeGeometryForTraversal(
  Graph graph,
  int edgeIndex,
  bool reversedTraversal,
  List<List<double>> points,
) {
  if (points.length < 2) return List<List<double>>.from(points);

  final expectedStart = reversedTraversal
      ? graph.edgeToNode[edgeIndex]
      : graph.edgeFromNode[edgeIndex];
  final expectedEnd = reversedTraversal
      ? graph.edgeFromNode[edgeIndex]
      : graph.edgeToNode[edgeIndex];
  final first = points.first;
  final last = points.last;

  final keepScore = _pointNodeDistance2(graph, first, expectedStart) +
      _pointNodeDistance2(graph, last, expectedEnd);
  final reverseScore = _pointNodeDistance2(graph, first, expectedEnd) +
      _pointNodeDistance2(graph, last, expectedStart);

  if (reverseScore < keepScore) {
    return points.reversed.toList();
  }
  return List<List<double>>.from(points);
}

double _pointNodeDistance2(Graph graph, List<double> point, int nodeIndex) {
  final dLat = point[0] - graph.lat[nodeIndex];
  final dLon = point[1] - graph.lon[nodeIndex];
  return dLat * dLat + dLon * dLon;
}

/// routing.db の展開・読み込みと、探索後の geometry 取得を担う。
/// グラフ本体は起動時に全件読み込み、探索中はSQLiteを一切叩かない(§4.2)。
class RoutingDatabase {
  static const String assetName = 'routing.db';
  static const String _assetRevision = '20260710_gsi_edogawa_types_v2';

  final Database db;
  final Graph graph;
  final List<ShelterInfo> shelters;

  /// shelters と同順の、各避難所 nearest_node の内部ノードindex。
  /// グラフに存在しないノードを指す場合は -1。
  final List<int> shelterNodeIndexes;

  RoutingDatabase._({
    required this.db,
    required this.graph,
    required this.shelters,
    required this.shelterNodeIndexes,
  });

  /// assets/routing.db をドキュメントディレクトリへコピー(初回のみ)して開き、
  /// nodes/edges/shelters を読み込んでインメモリグラフを構築する。
  /// [databasePath] を指定するとassetコピーを行わずそのファイルを開く(テスト用)。
  static Future<RoutingDatabase> open({String? databasePath}) async {
    final path = databasePath ?? await _ensureLocalCopy();
    final db = await openDatabase(path, readOnly: true);

    final nodeRows = await db.rawQuery('SELECT id, lat, lon FROM nodes');
    final edgeRows = await db.rawQuery(
        'SELECT id, from_node, to_node, length_m, is_bridge, is_tunnel, '
        'water_dist_m, elevation_m FROM edges');
    final shelterRows = await db.query('shelters');

    // フラット配列への展開はCPU負荷があるため isolate で行う(§6.3)。
    // sqflite の結果行(List<Map>)はそのまま送れる。
    final built = await Isolate.run(() => _buildGraph(nodeRows, edgeRows));
    final graph = built.graph;
    final nodeIndexById = built.nodeIndexById;

    final shelters = shelterRows.map(ShelterInfo.fromMap).toList();
    final shelterNodeIndexes = <int>[];
    for (final s in shelters) {
      final index = nodeIndexById[s.nearestNode];
      if (index == null) {
        developer.log(
          '避難所 ${s.shelterId} の nearest_node ${s.nearestNode} がグラフに存在しない',
          name: 'routing',
          level: 900,
        );
      }
      shelterNodeIndexes.add(index ?? -1);
    }

    return RoutingDatabase._(
      db: db,
      graph: graph,
      shelters: shelters,
      shelterNodeIndexes: shelterNodeIndexes,
    );
  }

  /// assets/routing.db をローカルへ展開する。
  /// routing.db は生成済みassetなので、リビジョンが変わった場合は再コピーする。
  static Future<String> _ensureLocalCopy() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, assetName));
    final revisionFile = File(p.join(dir.path, '$assetName.revision'));

    final currentRevision = await revisionFile.exists()
        ? (await revisionFile.readAsString()).trim()
        : null;
    if (!await file.exists() || currentRevision != _assetRevision) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await revisionFile.writeAsString(_assetRevision, flush: true);
    }
    return file.path;
  }

  static ({Graph graph, Map<int, int> nodeIndexById}) _buildGraph(
    List<Map<String, Object?>> nodeRows,
    List<Map<String, Object?>> edgeRows,
  ) {
    final n = nodeRows.length;
    final lats = List<double>.filled(n, 0);
    final lons = List<double>.filled(n, 0);
    final nodeIndexById = <int, int>{};
    for (var i = 0; i < n; i++) {
      final row = nodeRows[i];
      nodeIndexById[(row['id'] as num).toInt()] = i;
      lats[i] = (row['lat'] as num).toDouble();
      lons[i] = (row['lon'] as num).toDouble();
    }

    final edges = <GraphEdgeInput>[];
    for (final row in edgeRows) {
      final from = nodeIndexById[(row['from_node'] as num).toInt()];
      final to = nodeIndexById[(row['to_node'] as num).toInt()];
      if (from == null || to == null) continue; // 端点欠損は捨てる
      edges.add(GraphEdgeInput(
        fromIndex: from,
        toIndex: to,
        lengthM: (row['length_m'] as num).toDouble(),
        waterDistM: (row['water_dist_m'] as num?)?.toDouble(),
        elevationM: (row['elevation_m'] as num?)?.toDouble(),
        isBridge: ((row['is_bridge'] as num?)?.toInt() ?? 0) != 0,
        isTunnel: ((row['is_tunnel'] as num?)?.toInt() ?? 0) != 0,
        dbId: (row['id'] as num).toInt(),
      ));
    }

    return (
      graph: Graph.fromEdgeList(lats: lats, lons: lons, edges: edges),
      nodeIndexById: nodeIndexById,
    );
  }

  /// 経路のエッジ列(内部index)から描画用座標列を構築する。
  /// geometry は探索でメモリに載せないため、ここで該当エッジのみDBから引く(§4.2)。
  /// メインisolate側でのみ呼ぶこと(§6.3)。
  Future<List<LatLng>> loadPathGeometry(
    List<int> edgeIndexes,
    List<bool> reversedFlags, {
    required LatLng startPoint,
  }) async {
    if (edgeIndexes.isEmpty) return [startPoint];

    final dbIds = [for (final e in edgeIndexes) graph.edgeDbIds[e]];
    final geometryById = <int, List<List<double>>>{};
    // SQLiteのバインド変数上限(999)を避けてチャンク分割
    const chunkSize = 500;
    for (var i = 0; i < dbIds.length; i += chunkSize) {
      final chunk = dbIds.sublist(
          i, i + chunkSize > dbIds.length ? dbIds.length : i + chunkSize);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id, geometry FROM edges WHERE id IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        final decoded = jsonDecode(row['geometry'] as String) as List;
        geometryById[(row['id'] as num).toInt()] = [
          for (final point in decoded)
            [
              ((point as List)[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ]
        ];
      }
    }

    final result = <LatLng>[];
    for (var i = 0; i < edgeIndexes.length; i++) {
      final rawPoints = geometryById[dbIds[i]];
      if (rawPoints == null || rawPoints.isEmpty) continue;
      final points = orientEdgeGeometryForTraversal(
        graph,
        edgeIndexes[i],
        reversedFlags[i],
        rawPoints,
      );
      for (final point in points) {
        // 連結部の重複座標をスキップ
        if (result.isNotEmpty &&
            (result.last.latitude - point[0]).abs() < 1e-9 &&
            (result.last.longitude - point[1]).abs() < 1e-9) {
          continue;
        }
        result.add(LatLng(point[0], point[1]));
      }
    }
    return result;
  }
}
