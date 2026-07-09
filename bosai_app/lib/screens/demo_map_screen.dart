import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../db/demo_database_helper.dart';

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
      final homeData = await DemoDatabaseHelper.instance.getHomeMapInfo();
      String targetPmtilesPath = '';

      if (homeData != null && homeData['pmtiles_path'].toString().isNotEmpty) {
        final double lat = homeData['lat'];
        final double lon = homeData['lon'];
        
        setState(() {
          _mapCenter = LatLng(lat, lon);
          _currentAddress = homeData['address'] ?? "住所不明";
          _hasHomeInfo = true;
        });
        
        targetPmtilesPath = homeData['pmtiles_path'];
      } else {
        targetPmtilesPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
      }

      final provider = await PmTilesVectorTileProvider.fromSource(targetPmtilesPath);

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
      final data = await DefaultAssetBundle.of(context).load('assets/$assetName');
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    return file.path;
  }

  vtr.Theme _buildDemoTheme() {
    return vtr.ThemeReader().read({
      'version': 8,
      'sources': {'pmtiles': {'type': 'vector', 'url': 'pmtiles'}},
      'layers': [
        {'id': 'background', 'type': 'background', 'paint': {'background-color': '#f5f4f0'}},
        {'id': 'roads', 'type': 'line', 'source': 'pmtiles', 'source-layer': '*', 'paint': {'line-color': '#4a90d9', 'line-width': 1.8}}
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    const mainColor = Color(0xFF1B5E20);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: mainColor,
        foregroundColor: Colors.white,
        title: const Text('オフラインマップ表示 (検証用デモ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      options: MapOptions(initialCenter: _mapCenter, initialZoom: 14.0, minZoom: 10, maxZoom: 17),
                      children: [
                        VectorTileLayer(
                          theme: _buildDemoTheme(),
                          tileProviders: TileProviders({'pmtiles': _tileProvider!}),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _mapCenter,
                              width: 45,
                              height: 45,
                              child: const Icon(Icons.location_on, color: Colors.red, size: 45),
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
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(_hasHomeInfo ? Icons.verified : Icons.info_outline, color: _hasHomeInfo ? Colors.green : Colors.amber),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_hasHomeInfo ? '🏡 デモ用DBから位置情報を取得中' : '⚠️ デモ用DBに登録がありません', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text('登録住所: $_currentAddress', style: const TextStyle(fontSize: 11, color: Colors.black54), overflow: TextOverflow.ellipsis),
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