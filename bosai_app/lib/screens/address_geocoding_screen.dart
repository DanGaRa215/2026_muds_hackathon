import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';

class AddressGeocodingScreen extends StatefulWidget {
  const AddressGeocodingScreen({Key? key}) : super(key: key);

  @override
  State<AddressGeocodingScreen> createState() => _AddressGeocodingScreenState();
}

class _AddressGeocodingScreenState extends State<AddressGeocodingScreen> {
  final TextEditingController _addressController = TextEditingController();
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  final MapController _mapController = MapController();
  
  bool _isLoading = false;
  String _statusText = "住所を入力して検索してください";
  
  // 初期位置（江戸川区周辺）
  LatLng _previewCenter = const LatLng(35.7069, 139.8687); 
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
  }

  // 🌍 住所から識別キー（サーバーのファイル名）を判定
  String _getCityKey(String address) {
    final tokyo23Wards = ["江戸川", "葛飾", "江東", "墨田", "足立", "荒川", "港区", "新宿", "品川", "目黒", "大田", "世田谷", "渋谷", "中野", "杉並", "練馬", "台東", "文京", "千代田", "中央区", "豊島", "北区", "板橋"];
    for (var ward in tokyo23Wards) {
      if (address.contains(ward)) return "demo_area"; 
    }
    
    if (address.contains("浦安")) return "urayasu";
    if (address.contains("市川")) return "ichikawa";
    return "demo_area"; 
  }

  // 📥 住所をオンライン特定し、裏でオフライン用PMTilesを同期ダウンロードする処理
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

      // 🎯 修正点①：オンラインマップのカメラを、検索した住所のドンピシャへ滑らかに移動
      _mapController.move(targetCenter, 15.0);

      String savedPmtilesPath = '';

      if (cityKey == "demo_area") {
        setState(() => _statusText = "23区内のデータを検知しました。内蔵オフラインマップ（tokyo23_buffered）を同期中...");
        final localPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
        savedPmtilesPath = localPath;
        
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
        savedPmtilesPath = localPath;
      }

      // SQLiteに「正確な緯度経度」と「オフラインPMTilesパス」を完全保存
      await DatabaseHelper.instance.saveHomeMapInfo(
        address: address,
        lat: targetCenter.latitude,
        lon: targetCenter.longitude,
        pmtilesPath: savedPmtilesPath,
      );

      setState(() {
        _previewCenter = targetCenter;
        _hasSearched = true;
        _statusText = "🎉 [$cityKey.pmtiles] のダウンロード＆自宅登録に成功しました！";
      });

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('設定＆ダウンロード完了 🚀'),
          content: Text('対象エリアのオフライン地図ファイル（$cityKey.pmtiles）を端末内に同期しました。\n\nこれで完全オフライン状態（圏外）になっても、この地域の災害ナビが100%作動します！'),
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
                labelText: '住所を入力 (例: 東京都江戸川区中央)',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '🗺️ 自宅登録マッププレビュー (通常のオンラインマップでサクサク動きます)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: mainColor),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _previewCenter,
                          initialZoom: 14.0,
                          maxZoom: 18,
                          minZoom: 1,
                        ),
                        children: [
                          // 🎯 修正点②：プレビューを100%滑らかに表示できる標準オンラインレイヤーに差し替え
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'package:bosai_app',
                          ),
                          if (_hasSearched)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _previewCenter,
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