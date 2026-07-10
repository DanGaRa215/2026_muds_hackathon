import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/diagnosis.dart';
import 'history_detail_screen.dart';

/// 診断履歴一覧（設計書 §3【平常時】[備えチェック]）
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, this.diagnosesFuture});

  /// テスト注入用。本番では null のまま DB から読み込む。
  final Future<List<Diagnosis>>? diagnosesFuture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('診断履歴')),
      body: FutureBuilder<List<Diagnosis>>(
        future: diagnosesFuture ?? DatabaseHelper.instance.getDiagnoses(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('まだ診断履歴がありません'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = items[i];
              final date = d.createdAt.split('T').first;
              final summary = d.comment.length > 48
                  ? '${d.comment.substring(0, 48)}…'
                  : d.comment;
              return ListTile(
                leading: Icon(
                  switch (d.riskLevel) {
                    '危険' => Icons.error,
                    '注意' => Icons.warning_amber,
                    _ => Icons.check_circle,
                  },
                  color: switch (d.riskLevel) {
                    '危険' => Colors.red,
                    '注意' => Colors.orange,
                    _ => Colors.green,
                  },
                ),
                title: Text('${d.riskLevel}（$date）'),
                subtitle: Text(
                  '想定: ${d.intensity} / 構造: ${d.fixations.isEmpty ? "未記録" : d.fixations}\n$summary\nタップで詳細',
                ),
                isThreeLine: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HistoryDetailScreen(diagnosis: d),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
