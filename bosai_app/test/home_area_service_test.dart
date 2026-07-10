import 'package:bosai_app/routing/models.dart';
import 'package:bosai_app/services/home_area_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('nearestSheltersByStraightLine sorts by distance from home and limits',
      () {
    const home = LatLng(35.6062, 139.7349); // 大井町駅付近
    const shelters = [
      ShelterInfo(
        shelterId: 'far',
        name: '遠い避難所',
        lat: 35.6909,
        lon: 139.7003,
        elevationM: 0,
        coastDistanceM: 0,
        types: 'earthquake',
        capacity: 0,
        nearestNode: 1,
      ),
      ShelterInfo(
        shelterId: 'near',
        name: '近い避難所',
        lat: 35.6070,
        lon: 139.7350,
        elevationM: 0,
        coastDistanceM: 0,
        types: 'earthquake',
        capacity: 0,
        nearestNode: 2,
      ),
      ShelterInfo(
        shelterId: 'middle',
        name: '中間の避難所',
        lat: 35.6200,
        lon: 139.7350,
        elevationM: 0,
        coastDistanceM: 0,
        types: 'earthquake',
        capacity: 0,
        nearestNode: 3,
      ),
    ];

    final sorted = HomeAreaService.nearestSheltersByStraightLine(
      home: home,
      shelters: shelters,
      limit: 2,
    );

    expect(sorted.map((s) => s.shelterId), ['near', 'middle']);
  });

  test('capacityLabel treats zero and negative values as unknown', () {
    expect(HomeAreaService.capacityLabel(-1), '不明');
    expect(HomeAreaService.capacityLabel(0), '不明');
    expect(HomeAreaService.capacityLabel(120), '120人');
  });
}
