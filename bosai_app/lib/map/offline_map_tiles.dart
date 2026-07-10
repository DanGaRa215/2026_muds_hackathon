import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../services/home_area_service.dart';

Future<String>? _bundledOfflineMapCopyFuture;

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
  final inFlight = _bundledOfflineMapCopyFuture;
  if (inFlight != null) {
    return inFlight;
  }

  final copyFuture = _copyBundledOfflineMapToLocal();
  _bundledOfflineMapCopyFuture = copyFuture;
  try {
    return await copyFuture;
  } finally {
    if (identical(_bundledOfflineMapCopyFuture, copyFuture)) {
      _bundledOfflineMapCopyFuture = null;
    }
  }
}

Future<String> _copyBundledOfflineMapToLocal() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/${HomeAreaService.tokyo23PmtilesAsset}');
  if (!await file.exists() || await file.length() == 0) {
    final tmpFile = File('${file.path}.tmp');
    final data = await rootBundle.load(
      'assets/${HomeAreaService.tokyo23PmtilesAsset}',
    );
    await tmpFile.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }
  return file.path;
}
