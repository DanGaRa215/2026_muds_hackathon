import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;
import '../db/demo_database_helper.dart';

class DemoAddressGeocodingScreen extends StatefulWidget {
  const DemoAddressGeocodingScreen({Key? key}) : super(key: key);

  @override
  State<DemoAddressGeocodingScreen> createState() => _DemoAddressGeocodingScreenState();
}

class _DemoAddressGeocodingScreenState extends State<DemoAddressGeocodingScreen> {
  final TextEditingController _addressController = TextEditingController();
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  
  String _resultText = "ここに結果が表示されます";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // デモ画面を開いた瞬間に、デモ用のDBファイルを物理削除して完全初期化！
    _clearDemoDatabase();
  }

  Future<void> _clearDemoDatabase() async {
    await DemoAddressDatabaseHelper.instance.resetDemoDatabase();
    debugPrint("🎯 [Demo] デモ用DBファイルを初期化しました。");
  }

  // 住所から緯度経度を取得するメインロジック
  Future<void> _convertAddressToLatLon() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _resultText = "住所を入力してください");
      return;
    }

    setState(() {
      _isLoading = true;
      _resultText = "検索中...";
    });

    try {
      // geocodingパッケージの関数で住所を検索
      List<custom_geo.Location> locations = await _geocoding.locationFromAddress(address);

      if (locations.isNotEmpty) {
        final location = locations.first;
        setState(() {
          _resultText = '緯度: ${location.latitude}\n経度: ${location.longitude}';
        });
        
        // 🎯 修正②：引数名を pmtiles_path から pmtilesPath に変更
        await DemoAddressDatabaseHelper.instance.saveDemoHomeMapInfo(
          address: address,
          lat: location.latitude,
          lon: location.longitude,
          pmtilesPath: 'tokyo23_buffered.pmtiles', 
        );
      }
    } catch (e) {
      setState(() {
        _resultText = "見つかりませんでした。正しい住所か確認してください。\nエラー詳細: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自宅情報入力（デモ用）')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('平常時に自宅の住所を登録しておきましょう'),
            const SizedBox(height: 16),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '住所を入力 (例: 東京都江戸川区中央1-4-1)',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _convertAddressToLatLon,
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text('緯度・経度に変換'),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: Text(
                _resultText,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}