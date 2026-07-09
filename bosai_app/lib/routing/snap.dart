import 'dart:math' as math;

import 'graph.dart';

/// スナップ許容距離。これを超えると「グラフ範囲外」として null を返す(§6.2)。
const double snapMaxDistanceM = 300;

const double _earthRadiusM = 6371000;

/// 大円距離(haversine)。メートル。
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const degToRad = math.pi / 180;
  final dLat = (lat2 - lat1) * degToRad;
  final dLon = (lon2 - lon1) * degToRad;
  final sinLat = math.sin(dLat / 2);
  final sinLon = math.sin(dLon / 2);
  final a = sinLat * sinLat +
      math.cos(lat1 * degToRad) * math.cos(lat2 * degToRad) * sinLon * sinLon;
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// 与えられた座標の最近傍ノードindexを全ノード線形走査で返す。
/// 最近傍が maxDistanceM を超える場合はグラフ範囲外として null。
/// (数万ノードの線形走査は数ms以内。ハッカソン範囲ではインデックス不要)
int? nearestNodeIndex(
  Graph graph,
  double lat,
  double lon, {
  double maxDistanceM = snapMaxDistanceM,
}) {
  var bestIndex = -1;
  var bestDist = double.infinity;
  for (var i = 0; i < graph.nodeCount; i++) {
    final d = haversineM(lat, lon, graph.lat[i], graph.lon[i]);
    if (d < bestDist) {
      bestDist = d;
      bestIndex = i;
    }
  }
  if (bestIndex < 0 || bestDist > maxDistanceM) return null;
  return bestIndex;
}
