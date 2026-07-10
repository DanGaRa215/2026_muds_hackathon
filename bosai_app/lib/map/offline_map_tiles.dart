import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../services/home_area_service.dart';

Future<PmTilesVectorTileProvider> loadOfflineMapTileProvider({
  String? preferredPath,
}) async {
  final path = await resolveOfflineMapPath(preferredPath: preferredPath);
  return PmTilesVectorTileProvider.fromSource(path);
}

Future<String> resolveOfflineMapPath({String? preferredPath}) async {
  final path = preferredPath?.trim();
  if (path != null && path.isNotEmpty) {
    try {
      final file = File(path);
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
    } on FileSystemException {
      // 保存済みパスが読めない場合は同梱PMTilesにフォールバックする。
    }
  }

  return copyBundledOfflineMapToLocal();
}

Future<String> copyBundledOfflineMapToLocal() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/${HomeAreaService.tokyo23PmtilesAsset}');
  if (!await file.exists() || await file.length() == 0) {
    final data = await rootBundle.load(
      'assets/${HomeAreaService.tokyo23PmtilesAsset}',
    );
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return file.path;
}
