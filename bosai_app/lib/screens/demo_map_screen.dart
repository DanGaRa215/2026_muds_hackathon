import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../db/database_helper.dart';
import '../services/home_area_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRegisteredHomeAndMap();
  }

  Future<void> _loadRegisteredHomeAndMap() async {
    try {
      final homeData = await DatabaseHelper.instance.getRegisteredHome();
      String targetPmtilesPath = await _copyAssetToLocal(
        HomeAreaService.tokyo23PmtilesAsset,
      );

      if (homeData != null) {
        final lat = (homeData['lat'] as num).toDouble();
        final lon = (homeData['lon'] as num).toDouble();
        final pmtilesPath = homeData['pmtiles_path'].toString();

        setState(() {
          _mapCenter = LatLng(lat, lon);
          _currentAddress = homeData['address'] ?? "住所不明";
          _hasHomeInfo = true;
        });

        if (pmtilesPath.isNotEmpty) {
          targetPmtilesPath = pmtilesPath;
        }
      }

      final provider =
          await PmTilesVectorTileProvider.fromSource(targetPmtilesPath);

      if (mounted) {
        setState(() {
          _tileProvider = provider;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(_mapCenter, 14.5);
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

  Future<String> _copyAssetToLocal(String assetName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$assetName');
    if (!await file.exists() || file.lengthSync() == 0) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
    }
    return file.path;
  }

  vtr.Theme _buildDemoTheme() {
    final knownLayers = [
      'water',
      'building',
      'roads',
      'road',
      'landuse',
      'transportation',
      'waterway',
      'structure'
    ];

    final List<Map<String, dynamic>> styleLayers = [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': '#f2efe9'}
      },
    ];

    for (final layerName in knownLayers) {
      if (layerName.contains('water')) {
        styleLayers.add({
          'id': 'layer-$layerName',
          'type': 'fill',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'fill-color': '#ccdff0'}
        });
      } else if (layerName.contains('building') ||
          layerName.contains('structure')) {
        styleLayers.add({
          'id': 'layer-$layerName',
          'type': 'fill',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'fill-color': '#dedede', 'fill-outline-color': '#cccccc'}
        });
      } else if (layerName.contains('landuse')) {
        styleLayers.add({
          'id': 'layer-$layerName',
          'type': 'fill',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'fill-color': '#e1ebd5'}
        });
      } else {
        styleLayers.add({
          'id': 'layer-$layerName-line',
          'type': 'line',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'line-color': '#4a90d9', 'line-width': 1.8}
        });
      }
    }

    return vtr.ThemeReader().read({
      'version': 8,
      'sources': {
        'pmtiles': {'type': 'vector', 'url': 'pmtiles'}
      },
      'layers': styleLayers,
    });
  }

  @override
  Widget build(BuildContext context) {
    const mainColor = Color(0xFF1B5E20);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        title: const Text('オフラインマップ表示 (検証用デモ)',
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
                          initialZoom: 14.0,
                          minZoom: 10,
                          maxZoom: 17),
                      children: [
                        VectorTileLayer(
                          theme: _buildDemoTheme(),
                          tileProviders:
                              TileProviders({'pmtiles': _tileProvider!}),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _mapCenter,
                              width: 45,
                              height: 45,
                              child: const Icon(Icons.location_on,
                                  color: Colors.red, size: 45),
                            ),
                          ],
                        ),
                      ],
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
