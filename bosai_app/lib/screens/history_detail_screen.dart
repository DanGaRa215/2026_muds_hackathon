import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/diagnosis.dart';
import '../widgets/diagnosis_result_panel.dart';

/// 診断履歴1件の詳細表示。
class HistoryDetailScreen extends StatelessWidget {
  const HistoryDetailScreen({super.key, required this.diagnosis});

  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final date = diagnosis.createdAt.split('T').first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('診断詳細'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                date,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (diagnosis.payloadJson != null)
            _buildPayloadDetail(context)
          else
            _buildLegacyDetail(context),
        ],
      ),
    );
  }

  Widget _buildPayloadDetail(BuildContext context) {
    try {
      final payload =
          jsonDecode(diagnosis.payloadJson!) as Map<String, dynamic>;
      if (payload['status'] != 'ok') {
        return _buildLegacyDetail(context);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiagnosisResultPanel(payload: payload),
          const SizedBox(height: 12),
          Text(
            'これはあくまでAIの提案です。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    } catch (_) {
      return _buildLegacyDetail(context);
    }
  }

  Widget _buildLegacyDetail(BuildContext context) {
    final color = switch (diagnosis.riskLevel) {
      '危険' => Colors.red,
      '注意' => Colors.orange,
      _ => Colors.green,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    switch (diagnosis.riskLevel) {
                      '危険' => Icons.error,
                      '注意' => Icons.warning_amber,
                      _ => Icons.check_circle,
                    },
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    diagnosis.riskLevel,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('想定震度: ${diagnosis.intensity}'),
              const SizedBox(height: 6),
              Text(
                '建物構造: ${diagnosis.fixations.isEmpty ? "未記録" : diagnosis.fixations}',
              ),
              const SizedBox(height: 12),
              Text(
                diagnosis.comment,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '詳細データは保存されていません。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
