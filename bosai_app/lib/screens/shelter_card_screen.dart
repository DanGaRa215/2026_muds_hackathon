import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../map/offline_map_tiles.dart';
import '../map/offline_map_visuals.dart';
import '../map/shelter_overlay_layers.dart';
import '../routing/models.dart';
import '../routing/route_service.dart';
import '../services/home_area_service.dart';
import '../services/shelter_candidate_service.dart';
import 'navi_screen.dart';

typedef _ProposalData = ({
  ShelterCandidates candidates,
  PmTilesVectorTileProvider? tileProvider,
});

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
  static const _floodGuidance = '大規模水害時は、時間に余裕がある場合は浸水しない地域への広域避難、'
      '余裕がない場合は近くの建物の3階以上への避難(垂直避難)が基本です。'
      'この経路は参考情報です';
  late final Future<_ProposalData> _sheltersFuture;
  var _candidateIndex = 0;

  @override
  void initState() {
    super.initState();
    _sheltersFuture = _loadProposalData();
  }

  Future<_ProposalData> _loadProposalData() async {
    final candidates = await ShelterCandidateService.load(
      origin: widget.originOverride,
      mode: widget.disasterMode,
      situation: widget.situation,
    );
    if (candidates.needsHomeRegistration) {
      return (candidates: candidates, tileProvider: null);
    }
    // originOverride 時は pmtilesPath が null → 同梱PMTilesへフォールバック解決
    final tileProvider = await _loadTileProvider(candidates.pmtilesPath);
    return (candidates: candidates, tileProvider: tileProvider);
  }

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
        child: FutureBuilder<_ProposalData>(
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

            final data = snapshot.data ??
                (candidates: const ShelterCandidates(), tileProvider: null);
            final candidates = data.candidates;
            if (candidates.needsHomeRegistration) {
              return _buildNeedsHomeRegistrationState();
            }
            if (candidates.shelters.isEmpty) {
              return _buildEmptyState();
            }

            final shelters = candidates.shelters;
            final shelter = shelters[_candidateIndex % shelters.length];
            return _buildShelterCandidate(context, shelter, data);
          },
        ),
      ),
    );
  }

  Widget _buildShelterCandidate(
    BuildContext context,
    ShelterInfo shelter,
    _ProposalData data,
  ) {
    final candidates = data.candidates;
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
                child: _buildCandidateMap(data, shelter),
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
    _ProposalData data,
    ShelterInfo selectedShelter,
  ) {
    final candidates = data.candidates;
    final homeLocation = candidates.homeLocation;
    final tileProvider = data.tileProvider;
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
          ...buildShelterOverlayLayers(
            candidates: candidates,
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onSelect: (index) {
              if (_candidateIndex != index) {
                setState(() => _candidateIndex = index);
              }
            },
          ),
          MarkerLayer(
            markers: [_buildHomeMarker(homeLocation)],
          ),
          if (selectedIndex >= 0)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Align(
                alignment: Alignment.topLeft,
                child: buildSelectedShelterLabel(
                  index: selectedIndex,
                  shelter: selectedShelter,
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
