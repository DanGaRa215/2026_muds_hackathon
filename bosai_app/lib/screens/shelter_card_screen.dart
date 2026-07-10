import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../db/database_helper.dart';
import '../db/shelter_database.dart';
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
  });

  final Set<String> situation;
  final DisasterMode disasterMode;

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
    final registeredHome = await DatabaseHelper.instance.getRegisteredHome();
    if (registeredHome == null) {
      return const _ShelterCandidates(needsHomeRegistration: true);
    }

    final homeLocation = LatLng(
      (registeredHome['lat'] as num).toDouble(),
      (registeredHome['lon'] as num).toDouble(),
    );
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
      final shelters = routeRanked.isEmpty ? straightCandidates : routeRanked;
      return _ShelterCandidates(
        shelters: shelters.take(_displayCandidateLimit).toList(),
        homeLocation: homeLocation,
        routesByShelterId: routesByShelterId,
      );
    }

    final shelterDb = await ShelterDatabase.instance;
    final nearest = await shelterDb.queryNearest(
      lat: homeLocation.latitude,
      lon: homeLocation.longitude,
      mode: widget.disasterMode,
      limit: _displayCandidateLimit,
      preferDisasterType: false,
    );
    return _ShelterCandidates(
      shelters: nearest.shelters.map(HomeAreaService.toShelterInfo).toList(),
      homeLocation: homeLocation,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: _textColor,
        title: const Text('近い避難所候補'),
        automaticallyImplyLeading: false,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                        side: const BorderSide(color: _textColor, width: 2),
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
                              builder: (_) => const FinalInstructionScreen(),
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
    this.needsHomeRegistration = false,
  });

  final List<ShelterInfo> shelters;
  final LatLng? homeLocation;
  final Map<String, RouteResult> routesByShelterId;
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
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange.shade800,
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('ホームへ戻る',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
