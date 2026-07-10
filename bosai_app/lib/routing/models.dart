import 'package:latlong2/latlong.dart';

/// 災害モード。東京23区の低地・沿岸部を含む避難計画を踏まえ、
/// 津波は独立モードとせず flood(洪水・高潮)に包含する。
enum DisasterMode { earthquake, flood }

/// 経路探索の重みプロファイル。ペナルティにのみ係数が掛かる。
enum WeightProfile { fastest, balanced, safest }

/// 経路探索結果。仕様書③(UI層)がこの型に依存するため変更禁止。
class RouteResult {
  final String shelterId;
  final DisasterMode mode;
  final WeightProfile profile;

  /// 実距離合計(ペナルティ含まず)
  final double distanceM;

  /// ペナルティ合計(m換算、プロファイル係数適用後)
  final double penaltyM;

  /// distanceM / 66.7 (徒歩4km/h)
  final double estMinutes;

  /// 100 * distanceM / (distanceM + penaltyM)。100が最安全
  final double safetyScore;

  /// 描画用座標列
  final List<LatLng> geometry;

  /// ハード制約を緩めて算出した場合 true
  final bool usedFallback;

  const RouteResult({
    required this.shelterId,
    required this.mode,
    required this.profile,
    required this.distanceM,
    required this.penaltyM,
    required this.estMinutes,
    required this.safetyScore,
    required this.geometry,
    required this.usedFallback,
  });

  /// distanceM / penaltyM から派生値(estMinutes, safetyScore)を計算して生成する。
  factory RouteResult.fromCosts({
    required String shelterId,
    required DisasterMode mode,
    required WeightProfile profile,
    required double distanceM,
    required double penaltyM,
    required List<LatLng> geometry,
    required bool usedFallback,
  }) {
    final total = distanceM + penaltyM;
    return RouteResult(
      shelterId: shelterId,
      mode: mode,
      profile: profile,
      distanceM: distanceM,
      penaltyM: penaltyM,
      estMinutes: distanceM / 66.7,
      safetyScore: total <= 0 ? 100.0 : 100.0 * distanceM / total,
      geometry: geometry,
      usedFallback: usedFallback,
    );
  }
}

/// 1対1探索のリクエスト。
class RouteRequest {
  final LatLng from;
  final String shelterId;
  final DisasterMode mode;
  final WeightProfile profile;

  const RouteRequest({
    required this.from,
    required this.shelterId,
    required this.mode,
    required this.profile,
  });
}

/// routing.db の shelters 行のモデル。
/// 既存 models/shelter.dart(bosai_app.db用)とは別クラス。
class ShelterInfo {
  final String shelterId;
  final String name;
  final double lat;
  final double lon;
  final double elevationM;
  final double coastDistanceM;

  /// 対応災害種別CSV(例: 'earthquake,fire')
  final String types;
  final int capacity;

  /// 最寄りグラフノードのOSM node id
  final int nearestNode;

  const ShelterInfo({
    required this.shelterId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.coastDistanceM,
    required this.types,
    required this.capacity,
    required this.nearestNode,
  });

  factory ShelterInfo.fromMap(Map<String, Object?> map) {
    return ShelterInfo(
      shelterId: map['shelter_id'] as String,
      name: map['name'] as String,
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      elevationM: (map['elevation_m'] as num).toDouble(),
      coastDistanceM: (map['coast_distance_m'] as num).toDouble(),
      types: map['types'] as String,
      capacity: (map['capacity'] as num).toInt(),
      nearestNode: (map['nearest_node'] as num).toInt(),
    );
  }

  List<String> get typeList =>
      types.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  LatLng get latLng => LatLng(lat, lon);
}
