import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// 現在地取得ユーティリティ。
///
/// デモモードでは画面起動時に [ensurePermission] を先行実行して
/// OSの権限ダイアログを済ませておき、EEW発火時の取得を待たせない。
/// （本番想定ではインストール/オンボーディング時に権限取得する）
class LocationService {
  LocationService._();

  /// 位置情報サービスと権限を確認し、未許可なら要求する。
  /// 利用可能なら true。
  static Future<bool> ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    } catch (e) {
      debugPrint('LocationService.ensurePermission failed: $e');
      return false;
    }
  }

  /// 現在地を取得する。権限なし・タイムアウト・例外時は null。
  /// timeLimit はEEWカウントダウン(10秒)内に必ず結果を返すための上限。
  static Future<LatLng?> getCurrentLatLng({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await ensurePermission()) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on TimeoutException {
      debugPrint('LocationService: 現在地取得がタイムアウトしました');
      return null;
    } catch (e) {
      debugPrint('LocationService.getCurrentLatLng failed: $e');
      return null;
    }
  }
}
