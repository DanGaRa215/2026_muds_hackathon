import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as custom_geo;

class AddressGeocodingScreen extends StatefulWidget {
  const AddressGeocodingScreen({Key? key}) : super(key: key);

  @override
  State<AddressGeocodingScreen> createState() => _AddressGeocodingScreenState();
}

class _AddressGeocodingScreenState extends State<AddressGeocodingScreen> {
  final TextEditingController _addressController = TextEditingController();
  final custom_geo.Geocoding _geocoding = custom_geo.Geocoding();
  
  String _resultText = "ここに結果が表示されます";
  bool _isLoading = false;

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
        // 通常は複数候補が返るが、一番可能性が高い最初の候補(first)を使用する
        final location = locations.first;
        setState(() {
          _resultText = '緯度: ${location.latitude}\n経度: ${location.longitude}';
        });
        
        // 【メンバーC・Dへの連携メモ】
        // ここで取得した location.latitude と location.longitude を
        // DatabaseHelperの home_info 等に保存すれば、
        // 災害発生時（オフライン時）の現在地や出発地点として利用できます！
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