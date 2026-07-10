import 'package:flutter/material.dart';

import 'diagnosis_result_card.dart';

/// 診断成功時（status == ok）の結果表示パネル。
/// 診断画面と履歴詳細画面で共用する。
class DiagnosisResultPanel extends StatelessWidget {
  const DiagnosisResultPanel({super.key, required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final results =
        (payload['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final unknowns = (payload['unknowns'] as List<dynamic>? ?? []).cast<String>();
    final sources =
        (payload['sources'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final primary = selectPrimaryResult(payload);
    final otherCount = results.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DiagnosisSectionCard(
          title: '診断結果',
          subtitle: '最もリスクの高い家具を1件表示しています。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primary != null) DiagnosisResultCard(result: primary),
              if (otherCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '他に $otherCount件の家具を検出しました（最もリスクの高いものを表示しています）',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.62),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        DiagnosisUnknownsCard(unknowns: unknowns),
        const SizedBox(height: 12),
        DiagnosisSourcesCard(sources: sources),
      ],
    );
  }
}

class _DiagnosisSectionCard extends StatelessWidget {
  const _DiagnosisSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.62)),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
