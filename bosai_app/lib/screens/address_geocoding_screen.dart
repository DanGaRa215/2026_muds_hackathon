import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../db/database_helper.dart';

class AddressGeocodingScreen extends StatefulWidget {
  const AddressGeocodingScreen({Key? key}) : super(key: key);

  @override
  State<AddressGeocodingScreen> createState() => _AddressGeocodingScreenState();
}

class _AddressGeocodingScreenState extends State<AddressGeocodingScreen> {
  final TextEditingController _addressController = TextEditingController();
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  
  bool _isLoading = false;
  LatLng? _previewCenter; // 特定された自宅位置の座標（地図プレビュー用）
  String? _errorMessage;

  // 住所から緯度経度を特定し、プレビュー地図を出すロジック
  Future<void> _searchAddressAndPreview() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("住所を入力してください")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _previewCenter = null;
    });

    try {
      List<custom_geo.Location> locations = await _geocoding.locationFromAddress(address);

      if (locations.isNotEmpty) {
        final location = locations.first;
        setState(() {
          _previewCenter = LatLng(location.latitude, location.longitude);
        });
      } else {
        setState(() {
          _errorMessage = "指定された住所が見つかりませんでした。";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "住所の特定に失敗しました。正しい住所か確認してください。";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 確定された位置情報をSQLiteに保存して完了するロジック
  Future<void> _saveAndDownloadMap() async {
    if (_previewCenter == null) return;

    setState(() => _isLoading = true);

    try {
      // 🗄️ 裏側で住所、緯度経度をSQLiteへ一発保存！
      await DatabaseHelper.instance.saveHomeMapInfo(
        address: _addressController.text.trim(),
        lat: _previewCenter!.latitude,
        lon: _previewCenter!.longitude,
        pmtilesPath: '', // キャッシュ方式のため空文字でOK
      );

      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('自宅登録・地図DL完了 🎉'),
          content: const Text('自宅周辺の地図データのバックアップが完了しました！\nこれで災害による通信遮断時でも、オフラインでナビゲーションが利用可能です。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // ダイアログを閉じる
                Navigator.pop(context); // ホーム画面に戻る
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("データの保存に失敗しました: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const mainColor = Color(0xFF300808);
    const subBackgroundColor = Color(0xFFE7FBF0);

    return Scaffold(
      backgroundColor: subBackgroundColor,
      appBar: AppBar(
        title: const Text('自宅情報入力'),
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
              '平常時に自宅の住所を登録し、オフラインマップを準備しておきましょう。',
              style: TextStyle(color: mainColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelText: '住所を入力 (例: 東京都江戸川区東小岩)',
                prefixIcon: const Icon(Icons.home, color: mainColor),
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
                onPressed: _isLoading ? null : _searchAddressAndPreview,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('住所を検索して地図を確認', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: _previewCenter == null
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: mainColor.withValues(alpha: 0.2)),
                      ),
                      child: const Center(
                        child: Text(
                          '住所入力を入力し、\n上のボタンを押すとここに地図が表示されます。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '🗺️ 自宅の位置が合っているか確認してください：',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: mainColor),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: _previewCenter!,
                                initialZoom: 15.0,
                                maxZoom: 18,
                                minZoom: 1,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.muds.bosaiapp.dev',
                                  tileBuilder: (context, tileWidget, tile) {
                                    return Image(
                                      image: CachedNetworkImageProvider(
                                        'https://tile.openstreetmap.org/${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y}.png',
                                      ),
                                    );
                                  },
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _previewCenter!,
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                            onPressed: _isLoading ? null : _saveAndDownloadMap,
                            icon: const Icon(Icons.cloud_download),
                            label: const Text(
                              'この住所を登録',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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