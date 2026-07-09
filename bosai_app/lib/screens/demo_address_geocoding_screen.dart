import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../db/demo_database_helper.dart';
import 'demo_map_screen.dart';

/// 🛠️ ハッカソン審査・デモ専用の自宅住所・マップ登録画面
class DemoAddressGeocodingScreen extends StatefulWidget {
  const DemoAddressGeocodingScreen({Key? key}) : super(key: key);

  @override
  State<DemoAddressGeocodingScreen> createState() => _DemoAddressGeocodingScreenState();
}

class _DemoAddressGeocodingScreenState extends State<DemoAddressGeocodingScreen> {
  final TextEditingController _zipController = TextEditingController(); 
  final TextEditingController _addressController = TextEditingController(); 
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  final MapController _mapController = MapController();
  
  bool _isLoading = false;
  String _statusText = "【デモ画面】郵便番号を入力して、住所を検索してください";
  
  LatLng _previewCenter = const LatLng(35.7069, 139.8687); 
  bool _hasSearched = false;

  Future<void> _searchAddressByZip() async {
    final zipCode = _zipController.text.trim().replaceAll('-', ''); 
    if (zipCode.isEmpty || zipCode.length != 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("正しい郵便番号（7桁）を入力してください")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = "📮 郵便番号から住所を検索中...";
    });

    try {
      final url = Uri.parse('https://zipcloud.ibsnet.co.jp/api/search?zipcode=$zipCode');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          final fullAddress = "${result['address1']}${result['address2']}${result['address3']}";
          
          _addressController.text = fullAddress;
          
          setState(() {
            _statusText = "📍 住所を検出しました！続けて地図へ反映します...";
          });

          await _updateMapPreview(fullAddress);
        } else {
          setState(() => _statusText = "該当する住所が見つかりませんでした。");
        }
      } else {
        throw Exception("郵便番号サーバーへの接続に失敗しました");
      }
    } catch (e) {
      setState(() => _statusText = "エラーが発生しました: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateMapPreview(String address) async {
    try {
      List<custom_geo.Location> locations = await _geocoding.locationFromAddress(address);

      if (locations.isEmpty) {
        setState(() => _statusText = "住所の位置（座標）が特定できませんでした。");
        return;
      }

      final location = locations.first;
      final targetCenter = LatLng(location.latitude, location.longitude);

      _mapController.move(targetCenter, 15.0);

      setState(() {
        _previewCenter = targetCenter;
        _hasSearched = true;
        _statusText = "🗺️ 地図にプレビューを表示しました！\n問題なければ下のボタンから地図を同期してください。";
      });
    } catch (e) {
      setState(() => _statusText = "地図の反映に失敗しました。手動で微調整してください。\n詳細: $e");
    }
  }

  String _getCityKey(String address) {
    final tokyo23Wards = ["江戸川", "葛飾", "江東", "墨田", "足立", "荒川", "港区", "新宿", "品川", "目黒", "大田", "世田谷", "渋谷", "中野", "杉並", "練馬", "台東", "文京", "千代田", "中央区", "豊島", "北区", "板橋"];
    for (var ward in tokyo23Wards) {
      if (address.contains(ward)) return "demo_area"; 
    }
    return "demo_area"; 
  }

  Future<void> _downloadOfflineMap() async {
    final address = _addressController.text.trim();
    if (address.isEmpty || !_hasSearched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("先に郵便番号から位置を確定させてください")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusText = "💾 オフライン地図データを同期中...";
    });

    try {
      final cityKey = _getCityKey(address);
      String savedPmtilesPath = '';

      if (cityKey == "demo_area") {
        setState(() => _statusText = "23区内のデータを検知しました。内蔵オフラインマップ（tokyo23_buffered）を同期中...");
        final localPath = await _copyAssetToLocal('tokyo23_buffered.pmtiles');
        savedPmtilesPath = localPath;
      } else {
        setState(() => _statusText = "周辺のオフラインマップデータをダウンロード中...\n(サーバーから $cityKey.pmtiles を取得しています)");

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

      // 🎯 最新のDemoDatabaseHelperに情報を格納
      await DemoDatabaseHelper.instance.saveHomeMapInfo(
        address: address,
        lat: _previewCenter.latitude,
        lon: _previewCenter.longitude,
        pmtilesPath: savedPmtilesPath,
        structure: '木造',
        floor: 1,
      );

      setState(() {
        _statusText = "🎉 [$cityKey.pmtiles] のダウンロード＆【デモDB】自宅登録に成功しました！";
      });

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('【デモ】同期・ダウンロード完了'),
          content: const Text('対象エリア of 地図ファイルを検証用領域に保存しました。\n\n「OK」を押すと、デモ用マップ表示画面へ移動します。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DemoMapScreen()),
                );
              },
              child: const Text('OK (マップを確認)'),
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
    const mainColor = Color(0xFF1B5E20);
    const subBackgroundColor = Color(0xFFE8F5E9);

    return Scaffold(
      backgroundColor: subBackgroundColor,
      appBar: AppBar(
        title: const Text('自宅住所・マップ登録 (検証用デモ)'),
        backgroundColor: subBackgroundColor,
        foregroundColor: mainColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _zipController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      labelText: '郵便番号 (ハイフンなし)',
                      hintText: '1340001(7桁)',
                      prefixIcon: const Icon(Icons.local_post_office, color: mainColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: mainColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _searchAddressByZip,
                      child: const Text('住所検索', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelText: '取得された住所 (番地などは追記してください)',
                prefixIcon: const Icon(Icons.home, color: mainColor),
              ),
              onChanged: (val) {
                if (val.isNotEmpty) _updateMapPreview(val);
              },
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
                style: const TextStyle(fontSize: 13, color: mainColor, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

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
            const SizedBox(height: 16),

            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasSearched ? Colors.green[700] : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_isLoading || !_hasSearched) ? null : _downloadOfflineMap,
                icon: const Icon(Icons.verified_user, size: 24),
                label: const Text('デモ用DB領域に地図を保存する', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}