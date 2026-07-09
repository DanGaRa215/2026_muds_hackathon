import 'dart:async'; // 💡 修正点1: Timer を使うためにこのインポートを追加しました
import 'package:flutter/material.dart';
import '../services/eew_manager.dart';

class EewDebugScreen extends StatefulWidget {
  const EewDebugScreen({super.key});

  @override
  State<EewDebugScreen> createState() => _EewDebugScreenState();
}

class _EewDebugScreenState extends State<EewDebugScreen> {
  final EewManager _eewManager = EewManager();
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    // 初期状態の同期
    _isConnected = _eewManager.isConnected;

    // ログストリームの監視
    _eewManager.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
        });
        // ログが追加されたら一番下まで自動スクロール
        Timer(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // 接続状態ストリームの監視
    _eewManager.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _isConnected = status;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EEWリアルタイム受信 接続テスト'),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'ログをクリア',
            onPressed: () => setState(() => _logs.clear()),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📡 ステータス表示セクション
            Card(
              color: _isConnected ? Colors.green.shade50 : Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.gpp_good : Icons.cloud_off,
                      color: _isConnected ? Colors.green : Colors.red,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isConnected ? 'WebSocket 接続中 (リアルタイム監視中)' : 'WebSocket 切断状態',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            '通知設定フィルター: ${_eewManager.targetPrefecture} / 震度4以上',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 🛠️ 制御・テスト用アクションボタン
            const Text('【テスト・デモ用制御パネル】', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('接続(テスト環境)'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100),
                    onPressed: _isConnected ? null : () => _eewManager.connect(useSandbox: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('手動切断'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
                    onPressed: !_isConnected ? null : () => _eewManager.disconnect(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 本番・機内モード想定のモック注入ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bolt, color: Colors.white),
                label: const Text('デモ用モック緊急地震速報を注入する', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _eewManager.injectMockEewAlarm(),
              ),
            ),
            const SizedBox(height: 16),

            // 📥 リアルタイムコンソールログ
            const Text('【受信データ・解析リアルタイムログ】', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _logs.isEmpty
                    ? const Center(
                        child: Text(
                          'ログはありません。\n上のボタンで接続するか、データを注入してください。',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                          textAlign: TextAlign.center, // 💡 修正点2: Center から TextAlign.center に修正しました
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              _logs[index],
                              style: const TextStyle(
                                color: Colors.lightGreenAccent,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}