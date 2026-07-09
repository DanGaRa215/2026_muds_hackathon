import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'package:bosai_app/db/demo_database_helper.dart';
import 'package:bosai_app/screens/demo_address_geocoding_screen.dart';

/// 🛠️ ハッカソン審査・デモ専用の地図画面（江戸川区特化）
class DemoMapScreen extends StatefulWidget {
  const DemoMapScreen({super.key});

  @override
  State<DemoMapScreen> createState() => _DemoMapScreenState();
}

class _DemoMapScreenState extends State<DemoMapScreen> {
  static const _defaultCenter = LatLng(35.7069, 139.8683);

  PmTilesVectorTileProvider? _tileProvider;
  LatLng _mapCenter = _defaultCenter;
  bool _isLoading = true;
  String? _errorMessage;
  
  // デモ住所が登録されているかを管理するフラグ
  bool _isAddressRegistered = false;

  @override
  void initState() {
    super.initState();
    _loadDemoEnvironment();
  }

  Future<void> _loadDemoEnvironment() async {
    try {
      final demoInfo = await DemoAddressDatabaseHelper.instance.getDemoHomeMapInfo();

      String targetPath = '';
      LatLng targetLatLng = _defaultCenter;
      bool registered = false;

      if (demoInfo != null) {
        // デモDBにデータが存在する場合
        targetPath = demoInfo['pmtiles_path'];
        targetLatLng = LatLng(demoInfo['lat'], demoInfo['lon']);
        registered = true;
      } else {
        // デモDBが空の場合（未登録時）はデフォルトのアセットを読み込む
        targetPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
      }

      final file = File(targetPath);
      if (!await file.exists()) {
        targetPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
      }

      final provider = await PmTilesVectorTileProvider.fromSource(targetPath);

      if (mounted) {
        setState(() {
          _tileProvider = provider;
          _mapCenter = targetLatLng;
          _isAddressRegistered = registered; // フラグを更新
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
              : Stack(
                  children: [
                    // 地図本体
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: _mapCenter,
                        initialZoom: 14.0,
                        minZoom: 11,
                        maxZoom: 16,
                      ),
                      children: [
                        VectorTileLayer(
                          theme: _buildDemoTheme(),
                          tileProviders: TileProviders({'pmtiles': _tileProvider!}),
                        ),
                        MarkerLayer(
                          markers: [
                            // 登録されている時だけピンを表示（未登録時は表示しない）
                            if (_isAddressRegistered)
                              Marker(
                                point: _mapCenter,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                              ),
                          ],
                        ),
                      ],
                    ),

                    // 住所未登録の時だけ、地図の上に警告アナウンスをオーバーレイ表示
                    if (!_isAddressRegistered)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Card(
                          color: Colors.red.shade50,
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  // 🎯 修正2：const を外して遷移させる
                                  builder: (_) => const DemoAddressGeocodingScreen(),
                                ),
                              ).then((_) => _loadDemoEnvironment()); // 戻ってきた時に地図をリロード
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade800, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '住所登録ができていません。\nここをタップして自宅の登録を行ってください。',
                                      style: TextStyle(
                                        color: Colors.red.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: Colors.red.shade800, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}