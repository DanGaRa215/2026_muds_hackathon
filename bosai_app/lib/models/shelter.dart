/// 避難所モデル（設計書 §4.2 のスキーマに対応）
class Shelter {
  final String shelterId;
  final String name;
  final double lat;
  final double lon;
  final double elevationM; // 海抜
  final double coastDistanceM; // 海岸からの距離
  final String types; // カンマ区切り: "earthquake,tsunami,fire"
  final int capacity;

  const Shelter({
    required this.shelterId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.coastDistanceM,
    required this.types,
    required this.capacity,
  });

  bool supports(String type) => types.split(',').contains(type);

  factory Shelter.fromMap(Map<String, dynamic> map) => Shelter(
        shelterId: map['shelter_id'] as String,
        name: map['name'] as String,
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        elevationM: (map['elevation_m'] as num).toDouble(),
        coastDistanceM: (map['coast_distance_m'] as num).toDouble(),
        types: map['types'] as String,
        capacity: map['capacity'] as int,
      );

  Map<String, dynamic> toMap() => {
        'shelter_id': shelterId,
        'name': name,
        'lat': lat,
        'lon': lon,
        'elevation_m': elevationM,
        'coast_distance_m': coastDistanceM,
        'types': types,
        'capacity': capacity,
      };
}
