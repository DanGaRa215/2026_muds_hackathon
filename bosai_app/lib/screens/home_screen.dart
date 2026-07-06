import 'package:flutter/material.dart';

import 'diagnosis_screen.dart';
import 'eew_screen.dart';
import 'history_screen.dart';
import 'prepare_screen.dart';
import 'package:bosai_app/screens/address_geocoding_screen.dart';

/// ホーム画面: 4ボタンのみ（設計書 §3【平常時】）
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('総合防災アプリ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuButton(
              icon: Icons.camera_alt,
              label: '家具診断',
              subtitle: '写真から転倒リスクをAI判定',
              onTap: () => _push(context, const DiagnosisScreen()),
            ),
            _MenuButton(
              icon: Icons.map,
              label: '避難準備',
              subtitle: '自宅情報の登録・避難所リスト確認',
              onTap: () => _push(context, const PrepareScreen()),
            ),
            _MenuButton(
              icon: Icons.history,
              label: '診断履歴',
              subtitle: '過去の家具診断を確認',
              onTap: () => _push(context, const HistoryScreen()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddressGeocodingScreen()),
                );
              },
              child: const Text('自宅の住所を登録する'),
            ),
            const Spacer(),
            // 本番では気象庁API(WebSocket)受信 → flutter_local_notifications
            // の通知タップでEEW画面を起動する。デモでは直接起動。
            _MenuButton(
              icon: Icons.warning_amber,
              label: 'EEWデモ起動',
              subtitle: '発生時フローのシミュレーション',
              color: Colors.red.shade700,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const EewScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(72), // 非常時UI原則: 大きなタップ領域
          alignment: Alignment.centerLeft,
        ),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
