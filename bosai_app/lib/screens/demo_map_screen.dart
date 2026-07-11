import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../db/database_helper.dart';
import '../map/offline_map_tiles.dart';
import '../map/offline_map_visuals.dart';
import '../map/shelter_overlay_layers.dart';
import '../services/shelter_candidate_service.dart';

class DemoMapScreen extends StatefulWidget {
  const DemoMapScreen({super.key});

  @override
  State<DemoMapScreen> createState() => _DemoMapScreenState();
}

class _DemoMapScreenState extends State<DemoMapScreen> {
  final MapController _mapController = MapController();
  LatLng _mapCenter = const LatLng(35.7069, 139.8683);

  PmTilesVectorTileProvider? _tileProvider;
  bool _isLoading = true;
  String? _errorMessage;
  String _currentAddress = "未登録";
  bool _hasHomeInfo = false;
  ShelterCandidates? _candidates;
  int _selectedShelterIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadRegisteredHomeAndMap();
  }

  Future<void> _loadRegisteredHomeAndMap() async {
    try {
      final homeData = await DatabaseHelper.instance.getRegisteredHome();
      String? pmtilesPath;
      _candidates = null;
      _selectedShelterIndex = 0;

      Future<ShelterCandidates?>? candidatesFuture;
      if (homeData != null) {
        final lat = (homeData['lat'] as num).toDouble();
        final lon = (homeData['lon'] as num).toDouble();
        pmtilesPath = homeData['pmtiles_path'].toString();

        setState(() {
          _mapCenter = LatLng(lat, lon);
          _currentAddress = homeData['address'] ?? "住所不明";
          _hasHomeInfo = true;
        });

        // 避難所候補取得はタイル読込と並列実行（失敗時は tryLoad が null を返し
        // 地図表示は継続する）
        candidatesFuture =
            ShelterCandidateService.tryLoad(origin: LatLng(lat, lon));
      }

      final provider = await loadOfflineMapTileProvider(
        preferredPath: pmtilesPath,
      );
      _candidates = await candidatesFuture;

      if (mounted) {
        setState(() {
          _tileProvider = provider;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(_mapCenter, offlineMapInitialZoom);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? theme.colorScheme.surface : const Color(0xFFE7FBF0);
    final fgColor = isDark ? theme.colorScheme.onSurface : const Color(0xFF300808);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        title: const Text('東京23区オフラインマップ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadRegisteredHomeAndMap();
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('エラー: $_errorMessage'))
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                          initialCenter: _mapCenter,
                          initialZoom: offlineMapInitialZoom,
                          cameraConstraint: _hasHomeInfo
                              ? CameraConstraint.containCenter(
                                  bounds: boundsForHomeRadius(_mapCenter),
                                )
                              : const CameraConstraint.unconstrained(),
                          minZoom: 10,
                          maxZoom: 17),
                      children: [
                        buildOfflineBaseMapLayer(_tileProvider!),
                        if (_hasHomeInfo) buildHomeRadiusLayer(_mapCenter),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _mapCenter,
                              width: 45,
                              height: 45,
                              child: const Icon(Icons.location_on,
                                  color: Color(0xFF1976D2), size: 45),
                            ),
                          ],
                        ),
                        if (_hasHomeInfo &&
                            _candidates != null &&
                            _candidates!.shelters.isNotEmpty)
                          ...buildShelterOverlayLayers(
                            candidates: _candidates!,
                            selectedIndex: _selectedShelterIndex,
                            onSelect: (i) =>
                                setState(() => _selectedShelterIndex = i),
                          ),
                      ],
                    ),
                    if (_hasHomeInfo &&
                        _candidates != null &&
                        _candidates!.shelters.isNotEmpty)
                      buildShelterOverlayChip(
                        candidates: _candidates!,
                        selectedIndex: _selectedShelterIndex,
                      ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(
                                _hasHomeInfo
                                    ? Icons.verified
                                    : Icons.info_outline,
                                color:
                                    _hasHomeInfo ? Colors.green : Colors.amber),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      _hasHomeInfo
                                          ? '🏡 登録済みの自宅位置を表示中'
                                          : '⚠️ 自宅登録がありません',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  Text('登録住所: $_currentAddress',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black54),
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
