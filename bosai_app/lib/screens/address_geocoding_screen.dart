import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../db/database_helper.dart';

class AddressGeocodingScreen extends StatefulWidget {
  const AddressGeocodingScreen({Key? key}) : super(key: key);

  @override
  State<AddressGeocodingScreen> createState() => _AddressGeocodingScreenState();
}

class _AddressGeocodingScreenState extends State<AddressGeocodingScreen> {
  final TextEditingController _addressController = TextEditingController();
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  PmTilesVectorTileProvider? _tileProvider;
  
  bool _isLoading = false;
  String _statusText = "住所を入力して検索してください";
  
  LatLng? _previewCenter;       // 特定された自宅の座標
  String? _downloadedLocalPath; // DLしたPMTilesのスマホ内パス（23区外用）
  bool _isUsingAssetMap = false; // 23区内（demo_area）のデータを使うかどうかのフラグ

  // 🌍 住所文字列から「23区内（アセット）」か「区外（DL）」かを判定
  String _getCityKey(String address) {
    final tokyo23Wards = ["江戸川", "葛飾", "江東", "墨田", "足立", "荒川", "港区", "新宿", "品川", "目黒", "大田", "世田谷", "渋谷", "中野", "杉並", "練馬", "台東", "文京", "千代田", "中央区", "豊島", "北区", "板橋"];
    for (var ward in tokyo23Wards) {
      if (address.contains(ward)) return "demo_area"; 
    }
    
    if (address.contains("浦安")) return "urayasu";
    if (address.contains("市川")) return "ichikawa";
    return "demo_area"; 
  }

  Future<void> _searchAndDownloadOfflineMap() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("住所を入力してください")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = "住所の座標を特定中...";
      _previewCenter = null;
      _downloadedLocalPath = null;
      _isUsingAssetMap = false;
        _tileProvider = null;
    });

    try {
      List<custom_geo.Location> locations = await _geocoding.locationFromAddress(address);

      if (locations.isEmpty) {
        setState(() => _statusText = "指定された住所が見つかりませんでした。");
        return;
      }

      final location = locations.first;
      final targetCenter = LatLng(location.latitude, location.longitude);
      final cityKey = _getCityKey(address);

      if (cityKey == "demo_area") {
        setState(() => _statusText = "23区内のデータを検知しました。内蔵マップを展開します...");

        final localPath = await _copyAssetToLocal('demo_area.pmtiles');
        final provider = await PmTilesVectorTileProvider.fromSource(localPath);
        
        await DatabaseHelper.instance.saveHomeMapInfo(
          address: address,
          lat: targetCenter.latitude,
          lon: targetCenter.longitude,
          pmtilesPath: localPath,
        );

        setState(() {
          _previewCenter = targetCenter;
          _isUsingAssetMap = true;
          _tileProvider = provider;
          _statusText = "🎉 23区内（demo_area）のオフラインマップを同期しました！";
        });
        
      } else {
        setState(() => _statusText = "周辺のオフラインマップデータをダウンロード中...\n(サーバーから ${cityKey}.pmtiles を取得しています)");

        final directory = await getApplicationDocumentsDirectory();
        final localPath = '${directory.path}/$cityKey.pmtiles';
        final file = File(localPath);

        if (!await file.exists()) {
          final serverUrl = 'https://your-team-pages.github.io/maps/$cityKey.pmtiles';
          final response = await http.get(Uri.parse(serverUrl));

          if (response.statusCode == 200) {
            await file.writeAsBytes(response.bodyBytes);
          } else {
            throw Exception("地図サーバーからのダウンロードに失敗しました (Status: ${response.statusCode})");
          }
        }

        final provider = await PmTilesVectorTileProvider.fromSource(localPath);

        await DatabaseHelper.instance.saveHomeMapInfo(
          address: address,
          lat: targetCenter.latitude,
          lon: targetCenter.longitude,
          pmtilesPath: localPath,
        );

        setState(() {
          _previewCenter = targetCenter;
          _downloadedLocalPath = localPath;
          _tileProvider = provider;
          _statusText = "🎉 周辺エリア（$cityKey）のオフラインマップをダウンロードしました！";
        });
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('オフライン地図同期完了 🚀'),
          content: Text(cityKey == "demo_area" 
              ? '内蔵されている23区マップ（demo_area）との紐付けが完了しました！'
              : '対象エリア（$cityKey）のPMTilesファイルをサーバーから端末内に完全保存しました。\n\nこれで完全オフラインでも災害ナビゲーションが動作します！'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );

    } catch (e) {
      setState(() {
        _statusText = "エラーが発生しました。\n詳細: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String> _copyAssetToLocal(String assetName) async {
    final directory = await getApplicationDocumentsDirectory();
    final localPath = '${directory.path}/$assetName';
    final file = File(localPath);

    if (!await file.exists()) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    return localPath;
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

  @override
  Widget build(BuildContext context) {
    const mainColor = Color(0xFF300808);
    const subBackgroundColor = Color(0xFFE7FBF0);

    return Scaffold(
      backgroundColor: subBackgroundColor,
      appBar: AppBar(
        title: const Text('自宅情報・マップ取得'),
        backgroundColor: subBackgroundColor,
        foregroundColor: mainColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '平常時に自宅周辺のPMTilesマップを登録しておき、災害時（完全圏外）に備えましょう。',
              style: TextStyle(color: mainColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelText: '住所を入力 (例: 千葉県浦安市日の出)',
                prefixIcon: const Icon(Icons.map, color: mainColor),
              ),
            ),
            const SizedBox(height: 12),
            
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: mainColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isLoading ? null : _searchAndDownloadOfflineMap,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_lock),
                label: const Text('位置特定 ＆ オフライン地図を同期', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusText,
                style: const TextStyle(fontSize: 14, color: mainColor, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: _previewCenter == null
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: mainColor.withOpacity(0.2)),
                      ),
                      child: const Center(
                        child: Text(
                          'データを同期すると、\nここに完全オフライン表示のPMTilesマップが出現します。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '🗺️ 保存されたPMTilesの描画プレビュー (完全オフライン対応)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: mainColor),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: _previewCenter!,
                                initialZoom: 14.0,
                                maxZoom: 18,
                                minZoom: 1,
                              ),
                              children: [
                                VectorTileLayer(
                                  theme: _buildRoadsTheme(),
                                  tileProviders: TileProviders({
                                    'pmtiles': _tileProvider!,
                                  }),
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _previewCenter!,
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.location_on, color: Colors.red, size: 45),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}