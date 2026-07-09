import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// 🛠️ ハッカソン審査・デモ専用の地図画面（江戸川区特化）
/// 他のメンバーが避難所データやUIのカスタマイズを行う場合は、このファイルを修正してください。
class DemoMapScreen extends StatefulWidget {
  const DemoMapScreen({super.key});

  @override
  State<DemoMapScreen> createState() => _DemoMapScreenState();
}

class _DemoMapScreenState extends State<DemoMapScreen> {
  // デモの初期位置：江戸川区周辺
  static const _edogawaCenter = LatLng(35.7069, 139.8683);

  PmTilesVectorTileProvider? _tileProvider;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDemoPmtiles();
  }

  Future<void> _loadDemoPmtiles() async {
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

    if (!await file.exists() || file.lengthSync() == 0) {
      final data = await DefaultAssetBundle.of(context).load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  // デモ専用の地図指示書（Theme）
  vtr.Theme _buildDemoTheme() {
    return vtr.ThemeReader().read({
      'version': 8,
      'sources': {'pmtiles': {'type': 'vector', 'url': 'pmtiles'}},
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#f5f4f0'}
        },
        {
          'id': 'roads',
          'type': 'line',
          'source': 'pmtiles',
          'source-layer': '*', 
          'paint': {'line-color': '#4a90d9', 'line-width': 1.8}
        }
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.amber.shade700,
        foregroundColor: Colors.white,
        title: const Text('オフラインマップ（デモ）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('エラー: $_errorMessage'))
              : FlutterMap(
                  options: const MapOptions(
                    initialCenter: _edogawaCenter,
                    initialZoom: 14.0,
                    minZoom: 11,
                    maxZoom: 16,
                  ),
                  children: [
                    VectorTileLayer(
                      theme: _buildDemoTheme(),
                      tileProviders: TileProviders({'pmtiles': _tileProvider!}),
                    ),
                    
                    // 🎯 【メンバー追加用エリア】：江戸川区の避難所ピンなどはここに配列として追加していきます
                    MarkerLayer(
                      markers: [
                        const Marker(
                          point: _edogawaCenter,
                          width: 40,
                          height: 40,
                          child: Icon(Icons.location_on, color: Colors.red, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}