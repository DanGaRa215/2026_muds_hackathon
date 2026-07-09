/// 国土地理院ベースの避難所レコード（assets/shelters.db 用）。
///
/// [Shelter]（bosai_app.db）や [ShelterInfo]（routing.db）とは別スキーマ。
class GsiShelter {
  final String shelterId;
  final String name;
  final String? address;
  final String cityCode;
  final String cityName;
  final double lat;
  final double lon;
  final int isEmergencySite;
  final int isShelter;
  final int tFlood;
  final int tLandslide;
  final int tStormSurge;
  final int tEarthquake;
  final int tTsunami;
  final int tFire;
  final int tInlandFlood;
  final int tVolcano;
  final int isOpenSpace;
  final int? capacity;
  final double? elevationM;
  final double? coastDistanceM;
  final String? sourceNote;
  final String? updatedAt;

  const GsiShelter({
    required this.shelterId,
    required this.name,
    required this.address,
    required this.cityCode,
    required this.cityName,
    required this.lat,
    required this.lon,
    required this.isEmergencySite,
    required this.isShelter,
    required this.tFlood,
    required this.tLandslide,
    required this.tStormSurge,
    required this.tEarthquake,
    required this.tTsunami,
    required this.tFire,
    required this.tInlandFlood,
    required this.tVolcano,
    required this.isOpenSpace,
    required this.capacity,
    required this.elevationM,
    required this.coastDistanceM,
    required this.sourceNote,
    required this.updatedAt,
  });

  factory GsiShelter.fromMap(Map<String, Object?> map) {
    return GsiShelter(
      shelterId: map['shelter_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      cityCode: map['city_code'] as String,
      cityName: map['city_name'] as String,
      lat: (map['lat'] as num).toDouble(),
      lon: (map['lon'] as num).toDouble(),
      isEmergencySite: (map['is_emergency_site'] as num).toInt(),
      isShelter: (map['is_shelter'] as num).toInt(),
      tFlood: (map['t_flood'] as num?)?.toInt() ?? 0,
      tLandslide: (map['t_landslide'] as num?)?.toInt() ?? 0,
      tStormSurge: (map['t_storm_surge'] as num?)?.toInt() ?? 0,
      tEarthquake: (map['t_earthquake'] as num?)?.toInt() ?? 0,
      tTsunami: (map['t_tsunami'] as num?)?.toInt() ?? 0,
      tFire: (map['t_fire'] as num?)?.toInt() ?? 0,
      tInlandFlood: (map['t_inland_flood'] as num?)?.toInt() ?? 0,
      tVolcano: (map['t_volcano'] as num?)?.toInt() ?? 0,
      isOpenSpace: (map['is_open_space'] as num?)?.toInt() ?? 0,
      capacity: (map['capacity'] as num?)?.toInt(),
      elevationM: (map['elevation_m'] as num?)?.toDouble(),
      coastDistanceM: (map['coast_distance_m'] as num?)?.toDouble(),
      sourceNote: map['source_note'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
