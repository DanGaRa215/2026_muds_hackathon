import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:bosai_app/logic/coastal_logic.dart';
import 'package:bosai_app/routing/models.dart';

ShelterInfo _shelter({
  required String id,
  required double lat,
  required double lon,
  double elevationM = 0,
  double coastDistanceM = 0,
  String types = 'earthquake',
}) {
  return ShelterInfo(
    shelterId: id,
    name: id,
    lat: lat,
    lon: lon,
    elevationM: elevationM,
    coastDistanceM: coastDistanceM,
    types: types,
    capacity: 100,
    nearestNode: -1,
  );
}

void main() {
  // 豊洲付近を「現在地」に見立てる
  const origin = LatLng(35.6547, 139.7964);

  group('isCoastalPoint', () {
    test('近傍避難所の海岸距離が閾値未満なら沿岸と判定する', () {
      final shelters = [
        _shelter(id: 'a', lat: 35.655, lon: 139.797, coastDistanceM: 500),
        _shelter(id: 'b', lat: 35.656, lon: 139.798, coastDistanceM: 3000),
      ];
      expect(isCoastalPoint(point: origin, shelters: shelters), isTrue);
    });

    test('近傍避難所が全て閾値以上なら内陸と判定する', () {
      final shelters = [
        _shelter(id: 'a', lat: 35.655, lon: 139.797, coastDistanceM: 5000),
        _shelter(id: 'b', lat: 35.656, lon: 139.798, coastDistanceM: 9000),
      ];
      expect(isCoastalPoint(point: origin, shelters: shelters), isFalse);
    });

    test('遠方の沿岸避難所は近傍3件に入らず判定に影響しない', () {
      final shelters = [
        _shelter(id: 'n1', lat: 35.655, lon: 139.797, coastDistanceM: 8000),
        _shelter(id: 'n2', lat: 35.656, lon: 139.798, coastDistanceM: 8000),
        _shelter(id: 'n3', lat: 35.654, lon: 139.795, coastDistanceM: 8000),
        // 現在地から大きく離れた沿岸避難所
        _shelter(id: 'far', lat: 35.50, lon: 139.90, coastDistanceM: 100),
      ];
      expect(isCoastalPoint(point: origin, shelters: shelters), isFalse);
    });

    test('coastDistanceM が全て NaN なら安全側で false', () {
      final shelters = [
        _shelter(
            id: 'a', lat: 35.655, lon: 139.797, coastDistanceM: double.nan),
      ];
      expect(isCoastalPoint(point: origin, shelters: shelters), isFalse);
    });

    test('避難所が空なら false', () {
      expect(isCoastalPoint(point: origin, shelters: const []), isFalse);
    });
  });

  group('rankSheltersForSurge', () {
    test('高海抜・海岸から遠い避難所が近距離の低地より優先される', () {
      // near: 目の前だが海抜0m・海岸0m / high: 1km先だが海抜10m・海岸2km
      final near = _shelter(
        id: 'near',
        lat: 35.655,
        lon: 139.797,
        elevationM: 0,
        coastDistanceM: 0,
        types: 'surge',
      );
      final high = _shelter(
        id: 'high',
        lat: 35.663,
        lon: 139.800,
        elevationM: 10,
        coastDistanceM: 2000,
        types: 'surge',
      );
      final ranked =
          rankSheltersForSurge(shelters: [near, high], origin: origin);
      expect(ranked.first.shelterId, 'high');
    });

    test('surge/tsunami 非対応の避難所は後回しになる', () {
      final supported = _shelter(
        id: 'supported',
        lat: 35.663,
        lon: 139.800,
        elevationM: 5,
        coastDistanceM: 1000,
        types: 'surge,tsunami',
      );
      final unsupported = _shelter(
        id: 'unsupported',
        lat: 35.655,
        lon: 139.797,
        elevationM: 5,
        coastDistanceM: 1000,
        types: 'earthquake,fire',
      );
      final ranked = rankSheltersForSurge(
          shelters: [unsupported, supported], origin: origin);
      expect(ranked.first.shelterId, 'supported');
    });

    test('ルート距離があれば直線距離より優先して使う', () {
      final a = _shelter(
        id: 'a',
        lat: 35.655,
        lon: 139.797,
        types: 'surge',
      );
      final b = _shelter(
        id: 'b',
        lat: 35.656,
        lon: 139.798,
        types: 'surge',
      );
      // a は直線では近いが、ルートでは大回り
      final routes = {
        'a': RouteResult.fromCosts(
          shelterId: 'a',
          mode: DisasterMode.flood,
          profile: WeightProfile.balanced,
          distanceM: 10000,
          penaltyM: 0,
          geometry: const [],
          usedFallback: false,
        ),
        'b': RouteResult.fromCosts(
          shelterId: 'b',
          mode: DisasterMode.flood,
          profile: WeightProfile.balanced,
          distanceM: 500,
          penaltyM: 0,
          geometry: const [],
          usedFallback: false,
        ),
      };
      final ranked = rankSheltersForSurge(
        shelters: [a, b],
        origin: origin,
        routesByShelterId: routes,
      );
      expect(ranked.first.shelterId, 'b');
    });
  });
}
