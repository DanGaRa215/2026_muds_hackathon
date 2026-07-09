import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class EewManager {
  // シングルトン化（アプリ全体で1つのインスタンスを使い回す）
  static final EewManager _instance = EewManager._internal();
  factory EewManager() => _instance;
  EewManager._internal();

  static const String _productionUrl = 'wss://api.p2pquake.net/v2/ws';
  static const String _sandboxUrl = 'wss://api-realtime-sandbox.p2pquake.net/v2/ws';

  WebSocketChannel? _channel;
  bool _isConnecting = false;
  int _reconnectDelaySeconds = 1;
  bool _shouldReconnect = true;
  
  final Set<String> _processedIds = {};
  final String targetPrefecture = "東京都";
  final int minScaleThreshold = 10; // 震度1以上

  // 【デバッグ用】UIに接続状態やログを伝えるためのストリーム
  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  final StreamController<bool> _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  bool get isConnected => _channel != null && !_isConnecting;

  /// ログを記録してUIに送信
  /// ログを記録してUIとターミナルの両方に送信
  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    
    // 💡 ターミナル上で絶対に見逃さないように、目立つプレフィックスをつけて print 出力！
    print('🟢 [EEW_LOG] $logMessage');
    
    // UI側のデバッグ画面にも送る
    _logController.add(logMessage);
  }

  /// WebSocket接続を開始
  void connect({bool useSandbox = true}) {
    if (_isConnecting || _channel != null) return;
    _isConnecting = true;
    _shouldReconnect = true;
    _statusController.add(false);

    final url = useSandbox ? _sandboxUrl : _productionUrl;
    _addLog('🔌 接続開始: $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnecting = false;
      _statusController.add(true);
      _addLog('✅ 接続に成功しました');
      
      _channel!.stream.listen(
        (message) {
          _resetReconnectDelay();
          _handleMessage(message.toString());
        },
        onError: (error) {
          _addLog('❌ エラー発生: $error');
          _statusController.add(false);
          if (_shouldReconnect) _scheduleReconnect(useSandbox);
        },
        onDone: () {
          _addLog('🔌 接続が終了しました (OnDone)');
          _statusController.add(false);
          if (_shouldReconnect) _scheduleReconnect(useSandbox);
        },
      );
    } catch (e) {
      _addLog('❌ 接続例外: $e');
      _isConnecting = false;
      _statusController.add(false);
      if (_shouldReconnect) _scheduleReconnect(useSandbox);
    }
  }

  /// 接続を手動で切断
  void disconnect() {
    _shouldReconnect = false;
    _channel?.sink.close();
    _channel = null;
    _isConnecting = false;
    _statusController.add(false);
    _addLog('🛑 手動で切断しました');
  }

  void _scheduleReconnect(bool useSandbox) {
    if (!_shouldReconnect) return;
    _channel = null;
    _statusController.add(false);

    _addLog('⏳ $_reconnectDelaySeconds 秒後に自動再接続を試みます...');
    Timer(Duration(seconds: _reconnectDelaySeconds), () {
      if (_shouldReconnect) {
        _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 60);
        connect(useSandbox: useSandbox);
      }
    });
  }

  void _resetReconnectDelay() {
    _reconnectDelaySeconds = 1;
  }

  /// メッセージのパースと処理
  void _handleMessage(String rawJson) {
    try {
      final data = jsonDecode(rawJson);
      if (data is! Map<String, dynamic>) return;

      final String? id = data['id'];
      final int code = data['code'] ?? 0;
      final String time = data['time'] ?? '不明';

      _addLog('📥 データ受信 [Code: $code / ID: $id]');

      if (id != null) {
        if (_processedIds.contains(id)) {
          _addLog('⚠️ 重複判定: ID $id は既に処理済みの為スキップ');
          return;
        }
        _processedIds.add(id);
        if (_processedIds.length > 100) _processedIds.remove(_processedIds.first);
      }

      switch (code) {
        case 556:
          _addLog('🚨 処理対象: 緊急地震速報（警報）');
          _processCode556(data);
          break;
        case 551:
          _addLog('⚠️ 処理対象: 地震情報（各地の震度）');
          _processCode551(data);
          break;
        case 552:
          _addLog('🌊 処理対象: 津波予報');
          _processCode552(data);
          break;
        default:
          _addLog('ℹ️ 処理対象外のCode ($code) のためロジックをスキップします');
          break;
      }
    } catch (e) {
      _addLog('❌ JSONパース失敗: $e\nデータ: $rawJson');
    }
  }

  void _processCode556(Map<String, dynamic> data) {
    final List<dynamic> areas = data['areas'] ?? [];
    _addLog('   - 解析中: エリア件数 ${areas.length}件');
    
    bool shouldNotify = false;
    String matchedAreaName = "";

    for (var area in areas) {
      final String pref = area['pref'] ?? '';
      final int scaleTo = area['scaleTo'] ?? 0;

      _addLog('     └ エリア: $pref (予想最大震度コード: $scaleTo)');

      if (pref.contains(targetPrefecture) && scaleTo >= minScaleThreshold) {
        shouldNotify = true;
        matchedAreaName = area['name'] ?? pref;
        break;
      }
    }

    if (shouldNotify) {
      _addLog('🔥 条件合致！通知を発火します [設定対象: $targetPrefecture]');
      _triggerLocalNotification(
        title: '🚨【緊急地震速報】身を守ってください！',
        body: '$matchedAreaName 方向に強い揺れ。安全な場所へ非難してください。',
      );
    } else {
      _addLog('⏭️ フィルター条件（地域が $targetPrefecture かつ震度4以上）を満たさないため通知をスキップしました');
    }
  }

  void _processCode551(Map<String, dynamic> data) {
    final List<dynamic> points = data['points'] ?? [];
    _addLog('   - 解析中: 震度観測点件数 ${points.length}件');
    
    bool shouldNotify = false;
    int maxScale = 0;

    for (var point in points) {
      final String pref = point['pref'] ?? '';
      final int scale = point['scale'] ?? 0;

      if (pref.contains(targetPrefecture) && scale >= minScaleThreshold) {
        shouldNotify = true;
        if (scale > maxScale) maxScale = scale;
      }
    }

    final String domesticTsunami = data['domesticTsunami'] ?? 'None';
    if (domesticTsunami != 'None') {
      _addLog('🌊 津波の可能性情報あり ($domesticTsunami) -> スコーリングシステムへ連携');
    }

    if (shouldNotify) {
      _addLog('🔥 条件合致！震度速報通知を発火します');
      _triggerLocalNotification(
        title: '⚠️ 地震情報（各地の震度）',
        body: '$targetPrefecture内で最大震度 ${_getScaleName(maxScale)} の地震が発生しました。',
      );
    } else {
      _addLog('⏭️ フィルター条件（地域が $targetPrefecture 内で震度4以上）を満たさないため通知をスキップ');
    }
  }

  void _processCode552(Map<String, dynamic> data) {
    _addLog('🔥 津波予報を受信。無条件で通知を発火します');
    _triggerLocalNotification(
      title: '🌊【津波予報】海岸から離れてください',
      body: '津波予報が更新されました。安全な高台へ移動してください。',
    );
  }

  void _triggerLocalNotification({required String title, required String body}) {
    _addLog('🔔 【ローカル通知システム起動】\nタイトル: $title\n本文: $body');
    // TODO: flutter_local_notificationsの実際のプラグイン呼び出し
  }

  String _getScaleName(int code) {
    switch (code) {
      case 10: return '1'; case 20: return '2'; case 30: return '3'; case 40: return '4';
      case 45: return '5弱'; case 50: return '5強'; case 55: return '6弱'; case 60: return '6強'; case 70: return '7';
      default: return '不明';
    }
  }

  /// 【デバッグ用】仮の緊急地震速報(Code 556)データを無理やり流し込む
  void injectMockEewAlarm() {
    _addLog('🚀 [デモ用] モックEEWデータ(Code 556: 東京都/震度5弱想定) を注入します');
    const mockJson = '''
    {
      "id": "mock_eew_debug_2026",
      "code": 556,
      "time": "2026/07/08 18:00:00",
      "areas": [
        {
          "pref": "東京都",
          "name": "東京２３区",
          "scaleFrom": 40,
          "scaleTo": 45
        }
      ]
    }
    ''';
    _handleMessage(mockJson);
  }
}