import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../db/database_helper.dart';
import '../db/shelter_database.dart';
import '../logic/coastal_logic.dart';
import '../routing/models.dart';
import '../routing_bootstrap.dart';
import 'home_area_service.dart';

/// 避難所候補の読み込み結果。
/// EEW後の避難所提案画面と避難準備マップ画面で共有する。
class ShelterCandidates {
  const ShelterCandidates({
    this.shelters = const <ShelterInfo>[],
    this.homeLocation,
    this.routesByShelterId = const <String, RouteResult>{},
    this.pmtilesPath,
    this.needsHomeRegistration = false,
  });

  final List<ShelterInfo> shelters;
  final LatLng? homeLocation;
  final Map<String, RouteResult> routesByShelterId;

  /// 登録自宅を起点にした場合の home_info の pmtiles_path。
  /// origin 指定時は null（呼び出し側が同梱PMTilesにフォールバック）。
  final String? pmtilesPath;
  final bool needsHomeRegistration;

  RouteResult? routeFor(ShelterInfo shelter) =>
      routesByShelterId[shelter.shelterId];
}

/// 近い避難所候補の取得（直線距離で絞り込み→経路探索→ランキング）。
class ShelterCandidateService {
  ShelterCandidateService._();

  static const displayCandidateLimit = 5;
  static const routeSortCandidateLimit = 20;

  /// [load] の例外を握る版。避難準備マップ画面用
  /// （候補取得に失敗しても地図表示は継続させたいので null を返すだけ）。
  static Future<ShelterCandidates?> tryLoad({
    LatLng? origin,
    DisasterMode mode = DisasterMode.earthquake,
    Set<String> situation = const <String>{},
  }) async {
    try {
      return await load(origin: origin, mode: mode, situation: situation);
    } catch (e) {
      debugPrint('避難所候補の取得に失敗: $e');
      return null;
    }
  }

  /// [origin] が null の場合は登録済み自宅を起点にする
  /// （未登録なら needsHomeRegistration: true を返す）。
  static Future<ShelterCandidates> load({
    LatLng? origin,
    DisasterMode mode = DisasterMode.earthquake,
    Set<String> situation = const <String>{},
  }) async {
    final routeService = await RoutingBootstrap.routeService();

    final LatLng homeLocation;
    String? pmtilesPath;
    if (origin != null) {
      homeLocation = origin;
    } else {
      final registeredHome = await DatabaseHelper.instance.getRegisteredHome();
      if (registeredHome == null) {
        return const ShelterCandidates(needsHomeRegistration: true);
      }
      homeLocation = LatLng(
        (registeredHome['lat'] as num).toDouble(),
        (registeredHome['lon'] as num).toDouble(),
      );
      pmtilesPath = registeredHome['pmtiles_path']?.toString();
    }

    final needsSurgeRanking =
        situation.contains('surge') || situation.contains('tsunami');

    if (routeService.isInRoutingArea(homeLocation)) {
      final straightCandidates = HomeAreaService.nearestSheltersByStraightLine(
        home: homeLocation,
        shelters: routeService.allShelters,
        limit: routeSortCandidateLimit,
      );
      final routes = await routeService.findRoutesToShelters(
        from: homeLocation,
        shelters: straightCandidates,
        mode: mode,
        profile: WeightProfile.safest,
      );
      final routesByShelterId = {
        for (final route in routes) route.shelterId: route,
      };
      final routeRanked = [
        for (final shelter in straightCandidates)
          if (routesByShelterId.containsKey(shelter.shelterId)) shelter,
      ]..sort(
          (a, b) {
            final aRoute = routesByShelterId[a.shelterId]!;
            final bRoute = routesByShelterId[b.shelterId]!;
            final fallbackOrder = (aRoute.usedFallback ? 1 : 0)
                .compareTo(bRoute.usedFallback ? 1 : 0);
            if (fallbackOrder != 0) return fallbackOrder;
            final penaltyOrder = aRoute.penaltyM.compareTo(bRoute.penaltyM);
            if (penaltyOrder != 0) return penaltyOrder;
            return aRoute.distanceM.compareTo(bRoute.distanceM);
          },
        );
      var shelters = routeRanked.isEmpty ? straightCandidates : routeRanked;
      if (needsSurgeRanking) {
        shelters = rankSheltersForSurge(
          shelters: shelters,
          origin: homeLocation,
          routesByShelterId: routesByShelterId,
        );
      }
      return ShelterCandidates(
        shelters: shelters.take(displayCandidateLimit).toList(),
        homeLocation: homeLocation,
        routesByShelterId: routesByShelterId,
        pmtilesPath: pmtilesPath,
      );
    }

    final shelterDb = await ShelterDatabase.instance;
    final fallbackQueryLimit =
        needsSurgeRanking ? routeSortCandidateLimit : displayCandidateLimit;
    final nearest = await shelterDb.queryNearest(
      lat: homeLocation.latitude,
      lon: homeLocation.longitude,
      mode: mode,
      limit: fallbackQueryLimit,
      preferDisasterType: false,
    );
    var fallbackShelters =
        nearest.shelters.map(HomeAreaService.toShelterInfo).toList();
    if (needsSurgeRanking) {
      fallbackShelters = rankSheltersForSurge(
        shelters: fallbackShelters,
        origin: homeLocation,
      );
    }
    return ShelterCandidates(
      shelters: fallbackShelters.take(displayCandidateLimit).toList(),
      homeLocation: homeLocation,
      pmtilesPath: pmtilesPath,
    );
  }
}
