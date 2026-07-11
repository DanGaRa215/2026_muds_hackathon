import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../routing/models.dart';
import '../services/home_area_service.dart';
import '../services/shelter_candidate_service.dart';

const Color _labelTextColor = Color(0xFF300808);

/// 避難ルートのポリライン（白フチ＋オレンジ）。
/// route が null か geometry が2点未満なら null。
PolylineLayer? buildRoutePolylineLayer(RouteResult? route) {
  if (route == null || route.geometry.length < 2) {
    return null;
  }
  return PolylineLayer(
    polylines: [
      Polyline(
        points: route.geometry,
        color: Colors.white,
        strokeWidth: 9,
      ),
      Polyline(
        points: route.geometry,
        color: const Color(0xFFFF6D00),
        strokeWidth: 7,
      ),
    ],
  );
}

/// 番号付きの避難所候補ピン。タップで選択切り替え。
Marker buildShelterCandidateMarker({
  required ShelterInfo shelter,
  required int index,
  required bool isSelected,
  required VoidCallback onTap,
}) {
  return Marker(
    point: shelter.latLng,
    width: 46,
    height: 46,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(
            Icons.location_on,
            color:
                isSelected ? const Color(0xFFE53935) : const Color(0xFF6D3D3D),
            size: isSelected ? 40 : 36,
          ),
          Positioned(
            top: isSelected ? 8 : 7,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: Colors.white,
                fontSize: isSelected ? 12 : 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 避難所候補ピンをまとめた MarkerLayer。
MarkerLayer buildShelterCandidateMarkerLayer({
  required List<ShelterInfo> shelters,
  required int selectedIndex,
  required ValueChanged<int> onSelect,
}) {
  return MarkerLayer(
    markers: [
      for (var i = 0; i < shelters.length; i++)
        buildShelterCandidateMarker(
          shelter: shelters[i],
          index: i,
          isSelected: i == selectedIndex,
          onTap: () => onSelect(i),
        ),
    ],
  );
}

/// 選択中候補へのルート＋全候補ピンのレイヤー一式
/// （FlutterMap の children に spread して使う）。
List<Widget> buildShelterOverlayLayers({
  required ShelterCandidates candidates,
  required int selectedIndex,
  required ValueChanged<int> onSelect,
}) {
  final shelters = candidates.shelters;
  if (shelters.isEmpty) {
    return const <Widget>[];
  }
  final index = selectedIndex % shelters.length;
  final polyline = buildRoutePolylineLayer(candidates.routeFor(shelters[index]));
  return [
    if (polyline != null) polyline,
    buildShelterCandidateMarkerLayer(
      shelters: shelters,
      selectedIndex: index,
      onSelect: onSelect,
    ),
  ];
}

/// 避難準備マップ画面用の下部パネル（Stack 内に置く Positioned）。
/// 選択中候補の番号・名前・経路距離・徒歩分数を大きめに表示する。
Widget buildShelterOverlayChip({
  required ShelterCandidates candidates,
  required int selectedIndex,
}) {
  final shelters = candidates.shelters;
  final index = selectedIndex % shelters.length;
  final shelter = shelters[index];
  final route = candidates.routeFor(shelter);
  final home = candidates.homeLocation;

  final String? detail;
  if (route != null) {
    detail = '経路 ${HomeAreaService.distanceLabel(route.distanceM)} ・ '
        '徒歩 ${route.estMinutes.ceil()}分';
  } else if (home != null) {
    detail = '直線 ${HomeAreaService.distanceLabel(HomeAreaService.distanceM(home, shelter.latLng))} ・ '
        '方位 ${HomeAreaService.direction8(home, shelter.latLng)}';
  } else {
    detail = null;
  }

  return Positioned(
    left: 12,
    right: 12,
    bottom: 12,
    child: Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(blurRadius: 12, color: Color(0x33000000)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第${index + 1}候補',
            style: const TextStyle(
              color: Color(0xFF6D3D3D),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            shelter.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _labelTextColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: const TextStyle(
                color: _labelTextColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 「第N候補 名前」の白ピルラベル。
/// route / home を渡すと距離情報の行を追加表示する。
Widget buildSelectedShelterLabel({
  required int index,
  required ShelterInfo shelter,
  RouteResult? route,
  LatLng? home,
}) {
  final String? detail;
  if (route != null) {
    detail = '経路 ${HomeAreaService.distanceLabel(route.distanceM)} / '
        '徒歩 ${route.estMinutes.ceil()}分';
  } else if (home != null) {
    detail = '直線 ${HomeAreaService.distanceLabel(HomeAreaService.distanceM(home, shelter.latLng))}・'
        '${HomeAreaService.direction8(home, shelter.latLng)}';
  } else {
    detail = null;
  }
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      boxShadow: const [
        BoxShadow(blurRadius: 8, color: Color(0x33000000)),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第${index + 1}候補 ${shelter.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _labelTextColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (detail != null)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _labelTextColor,
                fontSize: 11,
              ),
            ),
        ],
      ),
    ),
  );
}
