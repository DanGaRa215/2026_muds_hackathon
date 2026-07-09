import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../routing_bootstrap.dart';

class HomeRegisterScreen extends StatefulWidget {
  const HomeRegisterScreen({super.key});

  @override
  State<HomeRegisterScreen> createState() => _HomeRegisterScreenState();
}

class _HomeRegisterScreenState extends State<HomeRegisterScreen> {
  static const _initialCenter = LatLng(35.7068, 139.8683);
  static const _initialZoom = 14.0;

  PmTilesVectorTileProvider? _tileProvider;
  LatLng? _selectedHome;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isCheckingArea = false;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      final localPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
      final provider = await PmTilesVectorTileProvider.fromSource(localPath);

      if (mounted) {
        setState(() {
          _tileProvider = provider;
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

  Future<void> _confirmSelectedHome() async {
    final selectedHome = _selectedHome;
    if (selectedHome == null || _isCheckingArea) {
      return;
    }

    setState(() => _isCheckingArea = true);
    try {
      final routeService = await RoutingBootstrap.routeService();
      final isInArea = routeService.isInRoutingArea(selectedHome);
      if (!mounted) return;

      if (!isInArea) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('対応エリア外です')),
        );
        return;
      }

      Navigator.of(context).pop(selectedHome);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('確認に失敗しました'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingArea = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自宅位置を登録')),
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
            Text('地図を読み込み中...'),
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

    final selectedHome = _selectedHome;
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: _initialZoom,
            minZoom: 10,
            maxZoom: 16,
            onTap: (_, point) => setState(() => _selectedHome = point),
          ),
          children: [
            VectorTileLayer(
              theme: _buildRoadsTheme(),
              tileProviders: TileProviders({
                'pmtiles': _tileProvider!,
              }),
            ),
            if (selectedHome != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: selectedHome,
                    width: 48,
                    height: 48,
                    child: const Icon(
                      Icons.home,
                      color: Colors.red,
                      size: 44,
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 16,
                    color: Color(0x33000000),
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      selectedHome == null
                          ? '地図をタップして自宅位置を選択'
                          : '選択位置: ${selectedHome.latitude.toStringAsFixed(5)}, '
                              '${selectedHome.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: selectedHome == null || _isCheckingArea
                          ? null
                          : _confirmSelectedHome,
                      icon: _isCheckingArea
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('ここを自宅にする'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
