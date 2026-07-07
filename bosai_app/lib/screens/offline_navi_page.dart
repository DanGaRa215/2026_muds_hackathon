import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OfflineNaviPage extends StatefulWidget {
  final double homeLatitude;
  final double homeLongitude;
  final String homeAddress;
  final String pmtilesFilePath;

  const OfflineNaviPage({
    super.key,
    required this.homeLatitude,
    required this.homeLongitude,
    required this.homeAddress,
    required this.pmtilesFilePath,
  });

  @override
  State<OfflineNaviPage> createState() => _OfflineNaviPageState();
}

class _OfflineNaviPageState extends State<OfflineNaviPage> {
  @override
  Widget build(BuildContext context) {
    const mainColor = Color(0xFF300808);
    final homeCenter = LatLng(widget.homeLatitude, widget.homeLongitude);

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      body: SafeArea(
        child: Column(
          children: [
            // 上部ヘッダー部分
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: mainColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: mainColor, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '登録住所: ${widget.homeAddress}\n(ローカルキャッシュ地図モード)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: mainColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // 地図表示部分
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: homeCenter,
                      initialZoom: 14.5,
                      maxZoom: 18,
                      minZoom: 1,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.bosai_app',
                        // 🎯 核心：どのバージョンでも絶対に存在する標準プロバイダーに変更
                        tileProvider: NetworkTileProvider(),
                        tileBuilder: (context, tileWidget, tile) {
                          return Image(
                            image: CachedNetworkImageProvider(
                              'https://tile.openstreetmap.org/${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y}.png',
                            ),
                          );
                        },
                      ),
                      
                      // 自宅位置のピン
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: homeCenter,
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
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}