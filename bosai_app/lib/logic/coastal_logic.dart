import 'package:latlong2/latlong.dart';

import '../routing/models.dart';
import '../services/home_area_service.dart';

/// 沿岸判定に使う海岸距離の閾値（メートル）。
/// 東京湾岸の高潮・津波浸水想定域（江東・中央・港・品川・大田・江戸川の
/// 湾岸部）をカバーしつつ内陸区を除外する目安。
const kCoastalThresholdM = 2000.0;

/// 高潮/津波リランクの距離係数。
const kSurgeDistanceWeight = 0.5;

/// 高潮/津波リランクの海抜係数。
const kSurgeElevationWeight = 500.0;

/// 高潮/津波リランクの海岸距離係数。
const kSurgeCoastDistanceWeight = 0.2;

/// 高潮/津波リランク時に surge/tsunami 非対応の避難所へ課すペナルティ。
const kSurgeUnsupportedPenalty = 100000.0;

/// 沿岸判定に参照する近傍避難所の数。
const _nearbyShelterSample = 3;

/// [point] が沿岸部かどうかを近傍避難所の海岸距離から近似判定する。
///
/// ユーザー位置自体の海岸距離データは持たないため、直近
/// [_nearbyShelterSample] 件の避難所の coastDistanceM の最小値を代理値と
/// する（23区内は避難所が高密度なので誤差は数百m程度）。
/// データが無い/全て NaN の場合は false（安全側 = 通常の地震モード）。
bool isCoastalPoint({
  required LatLng point,
  required Iterable<ShelterInfo> shelters,
  double thresholdM = kCoastalThresholdM,
}) {
  final nearest = HomeAreaService.nearestSheltersByStraightLine(
    home: point,
    shelters: shelters,
    limit: _nearbyShelterSample,
  );
  double? minCoastDistance;
  for (final shelter in nearest) {
    final d = shelter.coastDistanceM;
    if (d.isNaN) continue;
    if (minCoastDistance == null || d < minCoastDistance) {
      minCoastDistance = d;
    }
  }
  if (minCoastDistance == null) return false;
  return minCoastDistance < thresholdM;
}

/// 高潮/津波向けの避難所リランク。
///
/// score = [kSurgeDistanceWeight]*距離 − [kSurgeElevationWeight]*海抜
///   − [kSurgeCoastDistanceWeight]*海岸距離（昇順=良い）。
/// surge/tsunami どちらにも非対応の避難所は大幅減点。
/// 距離はルート距離（あれば）を優先し、無ければ直線距離。
/// 係数は ShelterRecommender の津波スコアリングと共有する。
List<ShelterInfo> rankSheltersForSurge({
  required List<ShelterInfo> shelters,
  required LatLng origin,
  Map<String, RouteResult> routesByShelterId = const {},
}) {
  double score(ShelterInfo s) {
    final route = routesByShelterId[s.shelterId];
    final d = route?.distanceM ?? HomeAreaService.distanceM(origin, s.latLng);
    final elevation = s.elevationM.isNaN ? 0.0 : s.elevationM;
    final coastDistance = s.coastDistanceM.isNaN ? 0.0 : s.coastDistanceM;
    var sc = kSurgeDistanceWeight * d -
        kSurgeElevationWeight * elevation -
        kSurgeCoastDistanceWeight * coastDistance;
    final types = s.typeList;
    if (!types.contains('surge') && !types.contains('tsunami')) {
      sc += kSurgeUnsupportedPenalty;
    }
    return sc;
  }

  final ranked = [...shelters]..sort((a, b) => score(a).compareTo(score(b)));
  return ranked;
}
