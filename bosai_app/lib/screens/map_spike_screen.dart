import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

// 🎯 修正点①：DBから登録情報を引っ張ってくるためにインポート
import '../db/database_helper.dart';
import '../map/offline_map_tiles.dart';
import '../map/offline_map_visuals.dart';
import '../map/shelter_overlay_layers.dart';
import '../services/shelter_candidate_service.dart';

class MapSpikeScreen extends StatefulWidget {
  const MapSpikeScreen({super.key});

  @override
  State<MapSpikeScreen> createState() => _MapSpikeScreenState();
}

class _MapSpikeScreenState extends State<MapSpikeScreen> {
  // デフォルト位置（万が一DBが空だった場合のフォールバック用：東京23区東部）
  static const _defaultCenter = LatLng(35.7069, 139.8683);

  PmTilesVectorTileProvider? _tileProvider;
  LatLng _mapCenter = _defaultCenter; // 🎯 マップの中心位置（DBから取得する自宅の座標）
  String? _errorMessage;
  bool _isLoading = true;
  ShelterCandidates? _candidates;
  int _selectedShelterIndex = 0;

  @override
  void initState() {
    super.initState();
    _initMapFromDatabase();
  }

  // 🎯 核心修正②：DBから最新の登録住所（緯度経度・PMTilesパス）をロードするロジック
  Future<void> _initMapFromDatabase() async {
    try {
      // SQLiteから保存されている自宅情報を取得
      final homeInfo = await DatabaseHelper.instance.getRegisteredHome();

      LatLng targetLatLng = _defaultCenter;

      if (homeInfo != null) {
        // DBにデータがある場合は、登録された「正確な緯度経度」と「PMTilesのパス」を使用
        final targetPath = homeInfo['pmtiles_path'].toString();
        targetLatLng = LatLng(
          (homeInfo['lat'] as num).toDouble(),
          (homeInfo['lon'] as num).toDouble(),
        );

        // タイルプロバイダ作成と避難所候補取得は独立なので並列実行する
        // （候補側は tryLoad が例外を握るため、失敗しても地図表示は継続）
        final providerFuture = loadOfflineMapTileProvider(
          preferredPath: targetPath,
        );
        final candidatesFuture =
            ShelterCandidateService.tryLoad(origin: targetLatLng);
        final provider = await providerFuture;
        final candidates = await candidatesFuture;

        if (mounted) {
          setState(() {
            _tileProvider = provider;
            _mapCenter = targetLatLng; // 🎯 カメラ初期位置をDBに保存した自宅の場所にセット！
            _candidates = candidates;
            _selectedShelterIndex = 0;
            _isLoading = false;
          });
        }
      } else {
        // 万が一まだ登録画面で一度も登録していなければ、例外を出して登録を促す
        throw Exception("自宅情報が登録されていません。「自宅情報・マップ取得」画面から先に登録を行ってください。");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll("Exception:", "");
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE7FBF0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE7FBF0),
        foregroundColor: const Color(0xFF300808),
        title: const Text('Map Spike (PMTiles)'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('DBからオフライン地図データを読み込み中...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: const TextStyle(
                color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final candidates = _candidates;
    final hasShelters = candidates != null && candidates.shelters.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _mapCenter, // 🎯 DBから取得した自宅位置が中心になります
            initialZoom: offlineMapInitialZoom, // 自宅周辺がハッキリ見えるように少しズームアップ
            cameraConstraint: CameraConstraint.containCenter(
              bounds: boundsForHomeRadius(_mapCenter),
            ),
            minZoom: 10,
            maxZoom: 16,
          ),
          children: [
            buildOfflineBaseMapLayer(_tileProvider!),
            buildHomeRadiusLayer(_mapCenter),

            // 🎯 核心修正③：DBから読み込んだ「自宅の場所（_mapCenter）」に青い大きなピンを刺す
            MarkerLayer(
              markers: [
                Marker(
                  point: _mapCenter,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on, // 自宅を示す青いピンマーク（EEW画面の自宅色と統一）
                    color: Color(0xFF1976D2),
                    size: 45,
                  ),
                ),
              ],
            ),
            if (hasShelters)
              ...buildShelterOverlayLayers(
                candidates: candidates,
                selectedIndex: _selectedShelterIndex,
                onSelect: (i) => setState(() => _selectedShelterIndex = i),
              ),
          ],
        ),
        if (hasShelters)
          buildShelterOverlayChip(
            candidates: candidates,
            selectedIndex: _selectedShelterIndex,
          ),
      ],
    );
  }
}
