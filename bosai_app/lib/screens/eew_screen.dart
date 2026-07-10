import 'dart:async';

import 'package:flutter/material.dart';

import 'status_check_screen.dart';

/// 身を守る画面（設計書 §3【発生時】の先頭）
///
/// 本番フロー: 気象庁API(WebSocket)受信 → flutter_local_notifications で
/// カスタムサウンド通知 →「通知タップで起動」→ 本画面。
/// デモではホームのボタンから直接起動する。
class EewScreen extends StatefulWidget {
  const EewScreen({super.key});

  @override
  State<EewScreen> createState() => _EewScreenState();
}

class _EewScreenState extends State<EewScreen> {
  static const _countdownSec = 10;
  int _remaining = _countdownSec;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SituationCheckPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade800,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.warning_amber, color: Colors.white, size: 96),
              const SizedBox(height: 24),
              const Text(
                '緊急地震速報（デモ）',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '強い揺れに警戒\n身を守ってください',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
              const SizedBox(height: 32),
              Text(
                '$_remaining',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade800,
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: _goNext,
                child: const Text('揺れが収まった',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
