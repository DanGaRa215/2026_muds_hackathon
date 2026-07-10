import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../db/database_helper.dart';
import '../logic/coastal_logic.dart';
import '../map/offline_map_tiles.dart';
import '../routing/models.dart';
import '../routing/route_service.dart';
import '../routing_bootstrap.dart';
import '../services/home_area_service.dart';
import '../services/location_service.dart';
import 'shelter_card_screen.dart';

/// 身を守る画面（現在地ベースの第2デモ）
///
/// 既存の EewScreen（自宅登録前提）と並列に存在する。
/// カウントダウン中に現在地取得・オフライン地図コピー(mapDL)・
/// 経路エンジン起動を並行して進め、沿岸部なら高潮/津波モードで
/// 避難所提案へ遷移する。
class EewCurrentLocationScreen extends StatefulWidget {
  const EewCurrentLocationScreen({super.key});

  @override
  State<EewCurrentLocationScreen> createState() =>
      _EewCurrentLocationScreenState();
}

class _EewLocationResult {
  const _EewLocationResult({
    this.position,
    this.coastal = false,
    this.inTokyo23 = false,
  });

  final LatLng? position;
  final bool coastal;
  final bool inTokyo23;

  bool get usable => position != null && inTokyo23;
}

class _EewCurrentLocationScreenState extends State<EewCurrentLocationScreen> {
  static const _countdownSec = 10;
  static const _mapCopyTimeout = Duration(seconds: 8);
  int _remaining = _countdownSec;
  Timer? _timer;

  late final Future<_EewLocationResult> _prepareFuture;
  String _statusText = '現在地を取得中…';
  bool _isNavigating = false;
  String? _blockedMessage;

  @override
  void initState() {
    super.initState();
    _prepareFuture = _prepare();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        _goNext();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 現在地取得・mapDL・経路エンジン起動を並行実行する。
  Future<_EewLocationResult> _prepare() async {
    final positionFuture = LocationService.getCurrentLatLng();
    final Future<String?> mapCopyFuture = copyBundledOfflineMapToLocal()
        .then<String?>((path) => path)
        .timeout(_mapCopyTimeout)
        .catchError((Object e, StackTrace st) {
      debugPrint('オフライン地図の準備に失敗: $e');
      return null;
    });
    final Future<RouteService?> routeServiceFuture =
        RoutingBootstrap.routeService()
            .then<RouteService?>((service) => service)
            .catchError((Object e, StackTrace st) {
      debugPrint('経路エンジンの準備に失敗: $e');
      return null;
    });

    final position = await positionFuture;
    await mapCopyFuture;

    if (position == null) {
      _updateStatus('位置情報を取得できませんでした');
      return const _EewLocationResult();
    }
    if (!HomeAreaService.isInTokyo23ApproxArea(position)) {
      _updateStatus('現在地は対象エリア（東京23区）外です');
      return _EewLocationResult(position: position);
    }

    var coastal = false;
    final routeService = await routeServiceFuture;
    if (routeService != null) {
      coastal = isCoastalPoint(
        point: position,
        shelters: routeService.allShelters,
      );
    }

    _updateStatus(coastal ? '現在地を取得しました（沿岸部：高潮・津波モード）' : '現在地を取得しました（内陸部）');
    return _EewLocationResult(
      position: position,
      coastal: coastal,
      inTokyo23: true,
    );
  }

  void _updateStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
  }

  Future<void> _goNext() async {
    if (!mounted || _isNavigating) return;
    setState(() => _isNavigating = true);
    _timer?.cancel();

    final result = await _prepareFuture;
    if (!mounted) return;

    if (result.usable) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShelterProposalPage(
            situation:
                result.coastal ? const {'surge', 'tsunami'} : const <String>{},
            disasterMode:
                result.coastal ? DisasterMode.flood : DisasterMode.earthquake,
            originOverride: result.position,
          ),
        ),
      );
      setState(() => _isNavigating = false);
      return;
    }

    // フォールバック: 登録済み自宅があれば既存フローで提案する
    final registeredHome = await DatabaseHelper.instance.getRegisteredHome();
    if (!mounted) return;
    if (registeredHome != null) {
      final reason = result.position == null
          ? '位置情報を取得できなかったため自宅基準で提案します'
          : '現在地は対象エリア外のため自宅基準で提案します';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ShelterProposalPage(situation: <String>{}),
        ),
      );
      setState(() => _isNavigating = false);
      return;
    }

    setState(() {
      _isNavigating = false;
      _blockedMessage = result.position == null
          ? '位置情報を取得できませんでした。\n端末設定で位置情報を許可してください。'
          : '現在地は対象エリア（東京23区）外です。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade800,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _blockedMessage != null
              ? _buildBlockedState()
              : _buildCountdownState(),
        ),
      ),
    );
  }

  Widget _buildCountdownState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.warning_amber, color: Colors.white, size: 96),
        const SizedBox(height: 24),
        const Text(
          '緊急地震速報（デモ・現在地）',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          '強い揺れに警戒\n身を守ってください',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
        const SizedBox(height: 32),
        _isNavigating
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Text(
                '$_remaining',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold),
              ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.my_location, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.red.shade800,
            minimumSize: const Size.fromHeight(64),
          ),
          onPressed: _isNavigating ? null : _goNext,
          child: const Text('揺れが収まった',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildBlockedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.location_off, color: Colors.white, size: 96),
        const SizedBox(height: 24),
        Text(
          _blockedMessage!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22),
        ),
        const SizedBox(height: 32),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.red.shade800,
            minimumSize: const Size.fromHeight(64),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('ホームへ戻る',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
