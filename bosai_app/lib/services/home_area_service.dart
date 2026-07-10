import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/gsi_shelter.dart';
import '../routing/models.dart';
import '../routing/precompute_service.dart';
import '../routing/route_service.dart';

class HomeAreaService {
  HomeAreaService._();

  static const minTokyo23Lat = 35.50;
  static const maxTokyo23Lat = 35.83;
  static const minTokyo23Lon = 139.55;
  static const maxTokyo23Lon = 139.93;
  static const tokyo23PmtilesAsset = 'tokyo23_buffered.pmtiles';

  static const _tokyo23Wards = [
    '千代田区',
    '中央区',
    '港区',
    '新宿区',
    '文京区',
    '台東区',
    '墨田区',
    '江東区',
    '品川区',
    '目黒区',
    '大田区',
    '世田谷区',
    '渋谷区',
    '中野区',
    '杉並区',
    '豊島区',
    '北区',
    '荒川区',
    '板橋区',
    '練馬区',
    '足立区',
    '葛飾区',
    '江戸川区',
  ];

  static bool isInTokyo23ApproxArea(LatLng point) {
    return point.latitude >= minTokyo23Lat &&
        point.latitude <= maxTokyo23Lat &&
        point.longitude >= minTokyo23Lon &&
        point.longitude <= maxTokyo23Lon;
  }

  static String? matchedTokyo23Ward(String address) {
    final normalized = address.replaceAll(RegExp(r'\s+'), '');
    for (final ward in _tokyo23Wards) {
      if (normalized.contains(ward)) {
        return ward;
      }
    }
    return null;
  }

  static bool isTokyo23Address(String address, LatLng point) {
    return matchedTokyo23Ward(address) != null && isInTokyo23ApproxArea(point);
  }

  static Future<HomePrecomputeResult> precomputeIfRoutingAvailable({
    required LatLng home,
    required RouteService routeService,
    required PrecomputeService precomputeService,
    void Function(double progress)? onProgress,
  }) async {
    if (!routeService.isInRoutingArea(home)) {
      return const HomePrecomputeResult.skipped();
    }

    await precomputeService.precomputeAll(
      home: home,
      onProgress: onProgress,
    );
    return const HomePrecomputeResult.completed();
  }

  static ShelterInfo toShelterInfo(GsiShelter shelter) {
    return ShelterInfo(
      shelterId: shelter.shelterId,
      name: shelter.name,
      lat: shelter.lat,
      lon: shelter.lon,
      elevationM: shelter.elevationM ?? double.nan,
      coastDistanceM: shelter.coastDistanceM ?? double.nan,
      types: _typesForGsiShelter(shelter).join(','),
      capacity: shelter.capacity ?? -1,
      nearestNode: -1,
    );
  }

  static List<ShelterInfo> nearestSheltersByStraightLine({
    required LatLng home,
    required Iterable<ShelterInfo> shelters,
    int limit = 5,
  }) {
    final sorted = shelters.toList()
      ..sort((a, b) {
        final distanceA = distanceM(home, a.latLng);
        final distanceB = distanceM(home, b.latLng);
        return distanceA.compareTo(distanceB);
      });
    if (sorted.length <= limit) return sorted;
    return sorted.take(limit).toList();
  }

  static List<String> _typesForGsiShelter(GsiShelter shelter) {
    final types = <String>[];
    if (shelter.tEarthquake == 1) types.add('earthquake');
    if (shelter.tFire == 1) types.add('fire');
    if (shelter.tFlood == 1) types.add('flood');
    if (shelter.tStormSurge == 1) types.add('surge');
    if (shelter.tTsunami == 1) types.add('tsunami');
    if (shelter.tLandslide == 1) types.add('landslide');
    if (shelter.tInlandFlood == 1) types.add('inland_flood');
    return types;
  }

  static double distanceM(LatLng a, LatLng b) {
    const earthRadiusM = 6371000.0;
    const degToRad = math.pi / 180;
    final dLat = (b.latitude - a.latitude) * degToRad;
    final dLon = (b.longitude - a.longitude) * degToRad;
    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);
    final h = sinLat * sinLat +
        math.cos(a.latitude * degToRad) *
            math.cos(b.latitude * degToRad) *
            sinLon *
            sinLon;
    return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static String direction8(LatLng from, LatLng to) {
    const degToRad = math.pi / 180;
    const radToDeg = 180 / math.pi;
    final lat1 = from.latitude * degToRad;
    final lat2 = to.latitude * degToRad;
    final dLon = (to.longitude - from.longitude) * degToRad;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = (math.atan2(y, x) * radToDeg + 360) % 360;
    const directions = ['北', '北東', '東', '南東', '南', '南西', '西', '北西'];
    final index = ((bearing + 22.5) / 45).floor() % directions.length;
    return directions[index];
  }

  static String distanceLabel(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
    return '${meters.round()}m';
  }

  static String elevationLabel(double elevationM) {
    return elevationM.isNaN ? '不明' : '${elevationM.toStringAsFixed(0)}m';
  }

  static String capacityLabel(int capacity) {
    return capacity <= 0 ? '不明' : '$capacity人';
  }
}

class HomePrecomputeResult {
  const HomePrecomputeResult._({required this.didRun});

  const HomePrecomputeResult.completed() : this._(didRun: true);

  const HomePrecomputeResult.skipped() : this._(didRun: false);

  final bool didRun;
}
