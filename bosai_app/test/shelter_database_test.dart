import 'dart:io';

import 'package:bosai_app/db/shelter_database.dart';
import 'package:bosai_app/routing/models.dart';
import 'package:bosai_app/services/home_area_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = File('assets/shelters.db').absolute.path;

  test('GSI shelters.db can be opened and queried', () async {
    final db = await ShelterDatabase.open(databasePath: dbPath);

    expect(await db.countAll(), 2179);
    expect(await db.countEarthquake(), 632);

    final edogawa = await db.queryByCityCode('13123', limit: 5);
    expect(edogawa, isNotEmpty);
    expect(edogawa.first.cityCode, '13123');
  });

  test('queryNearest returns disaster-aware nearest shelters', () async {
    final db = await ShelterDatabase.open(databasePath: dbPath);

    const home = LatLng(35.6466, 139.6532); // 世田谷区付近
    final result = await db.queryNearest(
      lat: home.latitude,
      lon: home.longitude,
      mode: DisasterMode.flood,
    );

    expect(result.usedDisasterTypeFallback, isFalse);
    expect(result.shelters, hasLength(5));
    for (final shelter in result.shelters) {
      expect(shelter.tFlood == 1 || shelter.tStormSurge == 1, isTrue);
    }

    final distances = result.shelters
        .map((s) => HomeAreaService.distanceM(home, LatLng(s.lat, s.lon)))
        .toList();
    for (var i = 1; i < distances.length; i++) {
      expect(distances[i], greaterThanOrEqualTo(distances[i - 1]));
    }
  });

  test('queryNearest falls back when disaster type data is missing nearby',
      () async {
    final db = await ShelterDatabase.open(databasePath: dbPath);

    const home = LatLng(35.7068, 139.8683); // 江戸川区付近
    final result = await db.queryNearest(
      lat: home.latitude,
      lon: home.longitude,
      mode: DisasterMode.flood,
    );

    expect(result.usedDisasterTypeFallback, isTrue);
    expect(result.shelters, hasLength(5));
  });

  test('queryNearest can return nearest shelters without disaster type filter',
      () async {
    final db = await ShelterDatabase.open(databasePath: dbPath);

    const home = LatLng(35.6062, 139.7349); // 大井町駅付近
    final result = await db.queryNearest(
      lat: home.latitude,
      lon: home.longitude,
      mode: DisasterMode.earthquake,
      preferDisasterType: false,
    );

    expect(result.usedDisasterTypeFallback, isFalse);
    expect(result.shelters, hasLength(5));
    expect(result.shelters.first.name, '立会小学校');

    final distances = result.shelters
        .map((s) => HomeAreaService.distanceM(home, LatLng(s.lat, s.lon)))
        .toList();
    for (var i = 1; i < distances.length; i++) {
      expect(distances[i], greaterThanOrEqualTo(distances[i - 1]));
    }
  });
}
