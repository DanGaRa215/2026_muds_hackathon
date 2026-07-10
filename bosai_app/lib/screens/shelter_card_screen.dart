import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../db/database_helper.dart';
import '../db/shelter_database.dart';
import '../logic/coastal_logic.dart';
import '../map/offline_map_tiles.dart';
import '../map/offline_map_visuals.dart';
import '../routing/models.dart';
import '../routing/route_service.dart';
import '../routing_bootstrap.dart';
import '../services/home_area_service.dart';
import 'navi_screen.dart';

class ShelterProposalPage extends StatefulWidget {
  const ShelterProposalPage({
    super.key,
    required this.situation,
    this.disasterMode = DisasterMode.earthquake,
    this.originOverride,
  });

  final Set<String> situation;
  final DisasterMode disasterMode;

  /// 非nullの場合、登録済み自宅の代わりにこの座標を起点とする
  /// （現在地ベースのEEWデモ用。DBの home_info は読まない/書かない）。
  final LatLng? originOverride;

  @override
  State<ShelterProposalPage> createState() => _ShelterProposalPageState();
}

class ShelterCardScreen extends ShelterProposalPage {
  const ShelterCardScreen({
    super.key,
    required super.situation,
    super.disasterMode,
  });
}

class _ShelterProposalPageState extends State<ShelterProposalPage> {
  static const Color _backgroundColor = Color(0xFFE7FBF0);
  static const Color _textColor = Color(0xFF300808);
  static const _displayCandidateLimit = 5;
  static const _routeSortCandidateLimit = 20;
  static const _floodGuidance = '大規模水害時は、時間に余裕がある場合は浸水しない地域への広域避難、'
      '余裕がない場合は近くの建物の3階以上への避難(垂直避難)が基本です。'
      'この経路は参考情報です';
  late final Future<_ShelterCandidates> _sheltersFuture;
  var _candidateIndex = 0;

  @override
  void initState() {
    super.initState();
    _sheltersFuture = _loadShelterCandidates();
  }

  Future<_ShelterCandidates> _loadShelterCandidates() async {
    final routeService = await RoutingBootstrap.routeService();

    final LatLng homeLocation;
    final PmTilesVectorTileProvider? tileProvider;
    final override = widget.originOverride;
    if (override != null) {
      homeLocation = override;
      // 同梱PMTilesへのフォールバック解決（現在地デモが事前コピー済み）
      tileProvider = await _loadTileProvider(null);
    } else {
      final registeredHome = await DatabaseHelper.instance.getRegisteredHome();
      if (registeredHome == null) {
        return const _ShelterCandidates(needsHomeRegistration: true);
      }
      homeLocation = LatLng(
        (registeredHome['lat'] as num).toDouble(),
        (registeredHome['lon'] as num).toDouble(),
      );
      tileProvider = await _loadTileProvider(
        registeredHome['pmtiles_path']?.toString(),
      );
    }
    if (routeService.isInRoutingArea(homeLocation)) {
      final straightCandidates = HomeAreaService.nearestSheltersByStraightLine(
        home: homeLocation,
        shelters: routeService.allShelters,
        limit: _routeSortCandidateLimit,
      );
      final routes = await routeService.findRoutesToShelters(
        from: homeLocation,
        shelters: straightCandidates,
        mode: widget.disasterMode,
        profile: WeightProfile.balanced,
      );
      final routesByShelterId = {
        for (final route in routes) route.shelterId: route,
      };
      final routeRanked = [
        for (final shelter in straightCandidates)
          if (routesByShelterId.containsKey(shelter.shelterId)) shelter,
      ]..sort(
          (a, b) => routesByShelterId[a.shelterId]!
              .distanceM
              .compareTo(routesByShelterId[b.shelterId]!.distanceM),
        );
      var shelters = routeRanked.isEmpty ? straightCandidates : routeRanked;
      if (_needsSurgeRanking) {
        shelters = rankSheltersForSurge(
          shelters: shelters,
          origin: homeLocation,
          routesByShelterId: routesByShelterId,
        );
      }
      return _ShelterCandidates(
        shelters: shelters.take(_displayCandidateLimit).toList(),
        homeLocation: homeLocation,
        routesByShelterId: routesByShelterId,
        tileProvider: tileProvider,
      );
    }

    final shelterDb = await ShelterDatabase.instance;
    final fallbackQueryLimit =
        _needsSurgeRanking ? _routeSortCandidateLimit : _displayCandidateLimit;
    final nearest = await shelterDb.queryNearest(
      lat: homeLocation.latitude,
      lon: homeLocation.longitude,
      mode: widget.disasterMode,
      limit: fallbackQueryLimit,
      preferDisasterType: false,
    );
    var fallbackShelters =
        nearest.shelters.map(HomeAreaService.toShelterInfo).toList();
    if (_needsSurgeRanking) {
      fallbackShelters = rankSheltersForSurge(
        shelters: fallbackShelters,
        origin: homeLocation,
      );
    }
    return _ShelterCandidates(
      shelters: fallbackShelters.take(_displayCandidateLimit).toList(),
      homeLocation: homeLocation,
      tileProvider: tileProvider,
    );
  }

  /// 高潮/津波の状況タグがある時のみリランクを適用する
  /// （既存デモは situation が空なので挙動不変）。
  bool get _needsSurgeRanking =>
      widget.situation.contains('surge') ||
      widget.situation.contains('tsunami');

  Future<PmTilesVectorTileProvider?> _loadTileProvider(
      String? pmtilesPath) async {
    try {
      return loadOfflineMapTileProvider(preferredPath: pmtilesPath);
    } catch (e) {
      debugPrint('Shelter proposal map unavailable: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: _textColor,
        title: const Text('近い避難所候補'),
        leading: IconButton(
          tooltip: '戻る',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: 'ホームへ戻る',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_ShelterCandidates>(
          future: _sheltersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '避難所候補の読み込みに失敗しました\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }

            final candidates = snapshot.data ?? const _ShelterCandidates();
            if (candidates.needsHomeRegistration) {
              return _buildNeedsHomeRegistrationState();
            }
            if (candidates.shelters.isEmpty) {
              return _buildEmptyState();
            }

            final shelters = candidates.shelters;
            final shelter = shelters[_candidateIndex % shelters.length];
            return _buildShelterCandidate(context, shelter, candidates);
          },
        ),
      ),
    );
  }

  Widget _buildShelterCandidate(
    BuildContext context,
    ShelterInfo shelter,
    _ShelterCandidates candidates,
  ) {
    final shelterCount = candidates.shelters.length;
    final homeLocation = candidates.homeLocation;
    final route = candidates.routeFor(shelter);
    final straightDistanceM = homeLocation == null
        ? null
        : HomeAreaService.distanceM(homeLocation, shelter.latLng);
    final supportsCurrentMode =
        shelterSupportsMode(shelter, widget.disasterMode);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapHeight =
            (constraints.maxHeight * 0.34).clamp(196.0, 280.0).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: mapHeight,
                child: _buildCandidateMap(candidates, shelter),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _textColor, width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '第${_candidateIndex + 1}候補：${shelter.name}',
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildTypeLabels(shelter),
                          if (!supportsCurrentMode) ...[
                            const SizedBox(height: 12),
                            _buildModeNotice(shelter),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            '海抜: ${HomeAreaService.elevationLabel(shelter.elevationM)}',
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '収容人数: ${HomeAreaService.capacityLabel(shelter.capacity)}',
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (route != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              '経路距離: ${HomeAreaService.distanceLabel(route.distanceM)} / '
                              '徒歩: ${route.estMinutes.ceil()}分',
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ] else if (straightDistanceM != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              '直線距離: ${HomeAreaService.distanceLabel(straightDistanceM)} / '
                              '方位: ${HomeAreaService.direction8(homeLocation!, shelter.latLng)}',
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (widget.disasterMode == DisasterMode.flood) ...[
                      _buildFloodGuidance(),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 64,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textColor,
                                side: const BorderSide(
                                  color: _textColor,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                if (_candidateIndex + 1 >= shelterCount) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const FinalInstructionScreen(),
                                    ),
                                  );
                                  return;
                                }
                                setState(() => _candidateIndex++);
                              },
                              child: const Text('NO（他の候補を見る）'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 64,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _textColor,
                                foregroundColor: _backgroundColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => NaviScreen(
                                      shelter: shelter,
                                      mode: widget.disasterMode,
                                      initialRoute: route,
                                      originOverride: widget.originOverride,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('YES（ここへ避難する）'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCandidateMap(
    _ShelterCandidates candidates,
    ShelterInfo selectedShelter,
  ) {
    final homeLocation = candidates.homeLocation;
    final tileProvider = candidates.tileProvider;
    if (homeLocation == null) {
      return const SizedBox.shrink();
    }
    if (tileProvider == null) {
      return _buildMapUnavailable();
    }

    final selectedIndex = candidates.shelters.indexWhere(
      (candidate) => candidate.shelterId == selectedShelter.shelterId,
    );
    final route = candidates.routeFor(selectedShelter);
    final fitPoints = <LatLng>[
      homeLocation,
      for (final shelter in candidates.shelters) shelter.latLng,
      selectedShelter.latLng,
      if (route != null) ...route.geometry,
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFE8E8E8),
        border: Border.all(color: const Color(0x33300808)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FlutterMap(
        key: ValueKey('shelter-proposal-map-${selectedShelter.shelterId}'),
        options: MapOptions(
          initialCenter: homeLocation,
          initialZoom: 15,
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(fitPoints),
            padding: const EdgeInsets.all(36),
            maxZoom: 16,
          ),
          minZoom: 10,
          maxZoom: 16,
        ),
        children: [
          buildOfflineBaseMapLayer(tileProvider),
          buildHomeRadiusLayer(homeLocation),
          if (route != null && route.geometry.length >= 2)
            PolylineLayer(
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
            ),
          MarkerLayer(
            markers: [
              _buildHomeMarker(homeLocation),
              for (var i = 0; i < candidates.shelters.length; i++)
                _buildShelterMarker(
                  candidates.shelters[i],
                  i,
                  i == selectedIndex,
                ),
            ],
          ),
          if (selectedIndex >= 0)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildSelectedShelterMapLabel(
                  selectedIndex,
                  selectedShelter,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapUnavailable() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x33300808)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: _textColor, size: 40),
            SizedBox(height: 8),
            Text(
              '地図を読み込めませんでした',
              style: TextStyle(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildHomeMarker(LatLng homeLocation) {
    return Marker(
      point: homeLocation,
      width: 30,
      height: 30,
      child: Container(
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(blurRadius: 8, color: Color(0x33000000)),
          ],
        ),
        child: const Icon(
          Icons.my_location,
          color: Color(0xFF1976D2),
          size: 20,
        ),
      ),
    );
  }

  Marker _buildShelterMarker(
    ShelterInfo shelter,
    int index,
    bool isSelected,
  ) {
    return Marker(
      point: shelter.latLng,
      width: 46,
      height: 46,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_candidateIndex != index) {
            setState(() => _candidateIndex = index);
          }
        },
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(
              Icons.location_on,
              color: isSelected
                  ? const Color(0xFFE53935)
                  : const Color(0xFF6D3D3D),
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

  Widget _buildSelectedShelterMapLabel(
    int selectedIndex,
    ShelterInfo shelter,
  ) {
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
        child: Text(
          '第${selectedIndex + 1}候補 ${shelter.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildNeedsHomeRegistrationState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '自宅住所を登録してください',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '登録した位置から近い避難所候補を表示します',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textColor, fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _textColor,
                foregroundColor: _backgroundColor,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text(
                'ホームへ戻る',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '避難所候補が見つかりません',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.disasterMode == DisasterMode.flood) ...[
              const SizedBox(height: 16),
              _buildFloodGuidance(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFloodGuidance() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          _floodGuidance,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildModeNotice(ShelterInfo shelter) {
    final text = shelter.typeList.isEmpty
        ? '災害種別の指定が未整備です。近さ優先の候補です'
        : '現在の災害種別としては指定されていません。近さ優先の候補です';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: const TextStyle(
            color: _textColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeLabels(ShelterInfo shelter) {
    final labels = _typeLabels(shelter);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          DecoratedBox(
            decoration: BoxDecoration(
              color: label == '災害種別未整備'
                  ? const Color(0xFFFFF4E5)
                  : const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                label,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<String> _typeLabels(ShelterInfo shelter) {
    if (shelter.typeList.isEmpty) {
      return const ['災害種別未整備'];
    }
    const labels = {
      'earthquake': '地震',
      'fire': '火災',
      'flood': '洪水',
      'surge': '高潮',
      'tsunami': '津波',
      'landslide': '土砂',
      'inland_flood': '内水',
    };
    return [
      for (final type in shelter.typeList) labels[type] ?? type,
    ];
  }
}

class _ShelterCandidates {
  const _ShelterCandidates({
    this.shelters = const <ShelterInfo>[],
    this.homeLocation,
    this.routesByShelterId = const <String, RouteResult>{},
    this.tileProvider,
    this.needsHomeRegistration = false,
  });

  final List<ShelterInfo> shelters;
  final LatLng? homeLocation;
  final Map<String, RouteResult> routesByShelterId;
  final PmTilesVectorTileProvider? tileProvider;
  final bool needsHomeRegistration;

  RouteResult? routeFor(ShelterInfo shelter) =>
      routesByShelterId[shelter.shelterId];
}

/// 全候補NO時の最終指示（設計書のエッジケース）
class FinalInstructionScreen extends StatelessWidget {
  const FinalInstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange.shade800,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.terrain, color: Colors.white, size: 96),
              const SizedBox(height: 24),
              const Text(
                '周囲で最も高い場所へ\n避難してください',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '高台・頑丈な建物の上層階など',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 2),
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text(
                  '戻る',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange.shade800,
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                icon: const Icon(Icons.home_outlined),
                label: const Text(
                  'ホームへ戻る',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
