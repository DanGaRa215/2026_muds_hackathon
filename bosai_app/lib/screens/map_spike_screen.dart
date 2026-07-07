import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// PMTiles オフライン地図表示のスパイク検証画面。
/// 既存画面に影響を与えない独立ファイル。検証後に削除 or NaviScreen へ統合。
class MapSpikeScreen extends StatefulWidget {
  const MapSpikeScreen({super.key});

  @override
  State<MapSpikeScreen> createState() => _MapSpikeScreenState();
}

class _MapSpikeScreenState extends State<MapSpikeScreen> {
  // 江戸川区中心付近
  static const _defaultCenter = LatLng(35.7069, 139.8683);
  static const _defaultZoom = 14.0;

  PmTilesVectorTileProvider? _tileProvider;
  LatLng? _currentPosition;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      // PMTiles を assets からローカルストレージへコピー
      final localPath = await _copyAssetToLocal('demo_area.pmtiles');

      // タイルプロバイダ作成
      final provider = await PmTilesVectorTileProvider.fromSource(localPath);

      // 現在地取得（失敗しても地図は表示する）
      LatLng? position;
      try {
        position = await _getCurrentLocation();
      } catch (e) {
        debugPrint('Location unavailable: $e');
      }

      if (mounted) {
        setState(() {
          _tileProvider = provider;
          _currentPosition = position;
          _isLoading = false;
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

  /// Flutter assets はランダムアクセス不可のため、
  /// PMTiles をローカルファイルにコピーして使う。
  Future<String> _copyAssetToLocal(String assetName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$assetName');

    if (!file.existsSync()) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    return file.path;
  }

  /// roads レイヤーのみのシンプルテーマ。
  /// glyphs / sprite を参照しないためネットワーク不要。
  vtr.Theme _buildRoadsTheme() {
    return vtr.ThemeReader().read({
      'version': 8,
      'sources': {
        'pmtiles': {
          'type': 'vector',
          'url': 'pmtiles',
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {
            'background-color': '#e8e8e8',
          },
        },
        {
          'id': 'roads-line',
          'type': 'line',
          'source': 'pmtiles',
          'source-layer': 'roads',
          'paint': {
            'line-color': '#4a90d9',
            'line-width': 2.0,
          },
        },
      ],
    });
  }

  Future<LatLng?> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return LatLng(position.latitude, position.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE7FBF0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE7FBF0),
        foregroundColor: const Color(0xFF300808),
        title: const Text('Map Spike (PMTiles)'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('PMTilesを読み込み中...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error: $_errorMessage',
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final theme = _buildRoadsTheme();

    return FlutterMap(
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: _defaultZoom,
        minZoom: 10,
        maxZoom: 16,
      ),
      children: [
        VectorTileLayer(
          theme: theme,
          tileProviders: TileProviders({
            'pmtiles': _tileProvider!,
          }),
        ),
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _currentPosition!,
                width: 20,
                height: 20,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
