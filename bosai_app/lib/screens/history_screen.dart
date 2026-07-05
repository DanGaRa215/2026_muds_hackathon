import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/diagnosis.dart';

/// 診断履歴一覧（設計書 §3【平常時】[備えチェック]）
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('診断履歴')),
      body: FutureBuilder<List<Diagnosis>>(
        future: DatabaseHelper.instance.getDiagnoses(),
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
                    '想定: ${d.intensity} / 固定: ${d.fixations.isEmpty ? "なし" : d.fixations}\n${d.comment}'),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
