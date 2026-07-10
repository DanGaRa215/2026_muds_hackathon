import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

// 🎯 修正点①：DBから登録情報を引っ張ってくるためにインポート
import '../db/database_helper.dart';
import '../services/home_area_service.dart';

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
        var targetPath = homeInfo['pmtiles_path'].toString();
        targetLatLng = LatLng(
          (homeInfo['lat'] as num).toDouble(),
          (homeInfo['lon'] as num).toDouble(),
        );
        if (targetPath.isEmpty) {
          targetPath =
              await _copyAssetToLocal(HomeAreaService.tokyo23PmtilesAsset);
        }

        final file = File(targetPath);
        if (!await file.exists()) {
          throw Exception("保存されたオフライン地図ファイルが見つかりません。再ダウンロードが必要です。");
        }

        // タイルプロバイダを作成
        final provider = await PmTilesVectorTileProvider.fromSource(targetPath);

        if (mounted) {
          setState(() {
            _tileProvider = provider;
            _mapCenter = targetLatLng; // 🎯 カメラ初期位置をDBに保存した自宅の場所にセット！
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

  Future<String> _copyAssetToLocal(String assetName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$assetName');
    if (!await file.exists() || file.lengthSync() == 0) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  // レイヤー名を網羅してすり抜けを防ぐTheme定義
  vtr.Theme _buildOfflineMapTheme() {
    final knownLayers = [
      'water',
      'building',
      'roads',
      'road',
      'landuse',
      'transportation',
      'waterway',
      'structure'
    ];

    final List<Map<String, dynamic>> styleLayers = [
      {
        'id': 'background',
        'type': 'background',
        'paint': {
          'background-color': '#f2efe9',
        },
      }
    ];

    for (final layerName in knownLayers) {
      if (layerName.contains('water')) {
        styleLayers.add({
          'id': 'layer-$layerName',
          'type': 'fill',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'fill-color': '#ccdff0'}
        });
      } else if (layerName.contains('building') ||
          layerName.contains('structure')) {
        styleLayers.add({
          'id': 'layer-$layerName',
          'type': 'fill',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'fill-color': '#dedede', 'fill-outline-color': '#cccccc'}
        });
      } else if (layerName.contains('landuse')) {
        styleLayers.add({
          'id': 'layer-$layerName',
          'type': 'fill',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'fill-color': '#e1ebd5'}
        });
      } else {
        styleLayers.add({
          'id': 'layer-$layerName-line',
          'type': 'line',
          'source': 'pmtiles',
          'source-layer': layerName,
          'paint': {'line-color': '#4a90d9', 'line-width': 1.8}
        });
      }
    }

    return vtr.ThemeReader().read({
      'version': 8,
      'sources': {
        'pmtiles': {
          'type': 'vector',
          'url': 'pmtiles',
        },
      },
      'layers': styleLayers,
    });
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

    return FlutterMap(
      options: MapOptions(
        initialCenter: _mapCenter, // 🎯 DBから取得した自宅位置が中心になります
        initialZoom: 15.0, // 自宅周辺がハッキリ見えるように少しズームアップ
        minZoom: 10,
        maxZoom: 16,
      ),
      children: [
        VectorTileLayer(
          theme: _buildOfflineMapTheme(),
          tileProviders: TileProviders({
            'pmtiles': _tileProvider!,
          }),
        ),

        // 🎯 核心修正③：DBから読み込んだ「自宅の場所（_mapCenter）」に赤い大きなピンを刺す
        MarkerLayer(
          markers: [
            Marker(
              point: _mapCenter,
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_on, // 災害時に目立つ赤いピンマーク
                color: Colors.red,
                size: 45,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
