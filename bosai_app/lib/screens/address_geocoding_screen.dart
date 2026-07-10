import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../services/home_area_service.dart';
import '../routing_bootstrap.dart';

class AddressGeocodingScreen extends StatefulWidget {
  const AddressGeocodingScreen({super.key});

  @override
  State<AddressGeocodingScreen> createState() => _AddressGeocodingScreenState();
}

class _AddressGeocodingScreenState extends State<AddressGeocodingScreen> {
  final TextEditingController _zipController = TextEditingController(); // 郵便番号用
  final TextEditingController _addressController =
      TextEditingController(); // 住所用
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  final MapController _mapController = MapController();

  bool _isLoading = false;
  String _statusText = "郵便番号を入力して、住所を検索してください";

  // 初期位置（デフォルト：東京23区東部）
  LatLng _previewCenter = const LatLng(35.7069, 139.8687);
  bool _hasSearched = false;

  /// 📮 1. 郵便番号から住所を自動検索する処理（zipcloud API を使用）
  Future<void> _searchAddressByZip() async {
    final zipCode = _zipController.text.trim().replaceAll('-', ''); // ハイフンを除去
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
      final url = Uri.parse(
          'https://zipcloud.ibsnet.co.jp/api/search?zipcode=$zipCode');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          // 都道府県 + 市区町村 + 町域名 を結合
          final fullAddress =
              "${result['address1']}${result['address2']}${result['address3']}";

          _addressController.text = fullAddress;

          setState(() {
            _statusText = "📍 住所を検出しました！続けて地図へ反映します...";
          });

          // 自動で次のステップ（地図表示）へ進む
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

  /// 🗺️ 2. 確定した住所から経緯度を特定し、地図に表示する内部処理
  Future<void> _updateMapPreview(String address) async {
    try {
      List<custom_geo.Location> locations =
          await _geocoding.locationFromAddress(address);

      if (locations.isEmpty) {
        setState(() => _statusText = "住所の位置（座標）が特定できませんでした。");
        return;
      }

      final location = locations.first;
      final targetCenter = LatLng(location.latitude, location.longitude);

      // 地図のカメラを移動
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

  /// 🌍 識別キーの判定
  String? _getCityKey(String address) {
    return HomeAreaService.matchedTokyo23Ward(address);
  }

  /// 📥 3. 最後に地図（PMTiles）をダウンロード・同期する処理
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
      if (cityKey == null ||
          !HomeAreaService.isInTokyo23ApproxArea(_previewCenter)) {
        setState(() => _statusText = "東京23区の対象外です。登録は保存されません。");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("東京23区の対象外です")),
          );
        }
        return;
      }

      setState(() =>
          _statusText = "23区内のデータを検知しました。内蔵オフラインマップ（tokyo23_buffered）を同期中...");
      final savedPmtilesPath = await _copyAssetToLocal(
        HomeAreaService.tokyo23PmtilesAsset,
      );
      if (!mounted) return;

      // SQLiteに最終保存
      await DatabaseHelper.instance.saveHomeLocation(
        address: address,
        lat: _previewCenter.latitude,
        lon: _previewCenter.longitude,
        pmtilesPath: savedPmtilesPath,
      );
      if (!mounted) return;

      final precomputeMessage =
          await _precomputeAfterRegistration(_previewCenter);
      if (!mounted) return;

      setState(() {
        _statusText =
            "🎉 [$cityKey] のオフライン地図同期と自宅登録に成功しました！\n$precomputeMessage";
      });

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('同期・ダウンロード完了'),
          content: const Text(
              '対象エリアの地図ファイルを端末内に保存しました。\n\nこれで完全オフライン（圏外）になってもナビが利用可能です。\n\n'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText = "エラーが発生しました。\n詳細: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String> _precomputeAfterRegistration(LatLng home) async {
    final routeService = await RoutingBootstrap.routeService();
    final result = await HomeAreaService.precomputeIfRoutingAvailable(
      home: home,
      routeService: routeService,
      precomputeService: await RoutingBootstrap.precomputeService(),
    );
    return result.didRun
        ? '避難ルートを保存しました(オフラインで利用できます)。'
        : '経路データ未整備エリアのため、避難所提案と地図表示のみ利用できます。';
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
        title: const Text('自宅住所・マップ登録'),
        backgroundColor: subBackgroundColor,
        foregroundColor: mainColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 📮 ステップ1: 郵便番号入力フォーム
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      labelText: '郵便番号 (ハイフンなし)',
                      hintText: '1340001(7桁)',
                      prefixIcon:
                          const Icon(Icons.local_post_office, color: mainColor),
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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading ? null : _searchAddressByZip,
                      child: const Text('住所検索',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 📝 ステップ2: 下の住所表示フォーム（微調整できるように手動入力も可能）
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelText: '取得された住所 (番地などは追記してください)',
                prefixIcon: const Icon(Icons.home, color: mainColor),
              ),
              onChanged: (val) {
                if (val.isNotEmpty) _updateMapPreview(val);
              },
            ),
            const SizedBox(height: 16),

            // 📢 ステータス通知
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusText,
                style: const TextStyle(
                    fontSize: 13,
                    color: mainColor,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // 🗺️ ステップ3: 地図にその部分を表示
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
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'package:bosai_app',
                    ),
                    if (_hasSearched)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _previewCenter,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on,
                                color: Colors.red, size: 45),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 📥 ステップ4: 最後に地図をダウンロードするボタン
            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _hasSearched ? Colors.green[800] : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed:
                    (_isLoading || !_hasSearched) ? null : _downloadOfflineMap,
                icon: const Icon(Icons.download, size: 24),
                label: const Text('このエリアのオフライン地図をダウンロード',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
