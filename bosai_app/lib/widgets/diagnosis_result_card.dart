import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String furnitureLabel(String key) => switch (key) {
      'furniture_bookshelf' => '本棚',
      'furniture_wardrobe' => 'タンス',
      'furniture_cupboard' => '食器棚',
      'furniture_refrigerator' => '冷蔵庫',
      'furniture_tv' => 'テレビ（テレビ台含む）',
      'furniture_microwave_stand' => '電子レンジ台',
      'furniture_desk' => '机',
      'furniture_other' => 'その他の家具（判定対象外）',
      _ => key,
    };

String braceLabel(String key) => switch (key) {
      'brace_tension_rod' => '突っ張り棒',
      'brace_l_bracket' => 'L字金具',
      'brace_mat' => '耐震マット',
      'brace_belt' => 'ベルト・チェーン',
      'brace_stopper' => 'ストッパー・転倒防止板',
      _ => key,
    };

String qualityLabel(String key) => switch (key) {
      'correct' => '適切に設置',
      'loose' => '緩み・傾きあり（注意）',
      'wrong_position' => '取付位置が不適切（要見直し）',
      'unverified' => '写真では確認できず',
      _ => key,
    };

String? warningLabel(String key) => switch (key) {
      'recheck_after_quakes' =>
        '繰り返しの揺れで固定具は緩みます。震度4程度の地震の後は点検を。',
      'mat_ineffective_on_heavy' =>
        '耐震マット単独は重い家具では効果が確認されていません。L字金具等の追加を推奨。',
      'slide_on_high_floor' =>
        '高層階では家具が「移動」するリスクがあります。キャスターは固定を。',
      _ => null,
    };

String riskLevelLabel(String level) => switch (level) {
      'high' => '高',
      'mid' => '中',
      'low' => '低',
      _ => level,
    };

/// API レスポンスから UI 表示用の代表結果を選ぶ（v2.3）。
Map<String, dynamic>? selectPrimaryResult(Map<String, dynamic> payload) {
  final results =
      (payload['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  if (results.isEmpty) return null;
  final index = payload['primary_index'] as int? ?? 0;
  if (index < 0 || index >= results.length) return results.first;
  return results[index];
}

/// `sources` 欠落時のフォールバック辞書（v2.3）。
const List<Map<String, dynamic>> fallbackSources = [
  {
    'id': 'NILIM',
    'title': '国土技術政策総合研究所「什器の転倒・滑動・落下」評価法',
    'summary': '家具の種類ごとに、倒れ始める揺れの強さ（ガル）を実験から求めたデータです。',
  },
  {
    'id': 'JMA',
    'title': '気象庁 震度と加速度の換算',
    'summary': '想定した震度を、床の揺れの強さ（ガル）に変換する際に使っています。',
  },
  {
    'id': 'TFD-H',
    'title': '東京消防庁「熊本地震における家具等の転倒等の実態調査」戸建編',
    'summary':
        'L字金具で転倒率が33.5%から8.9%に低下（n=79）。耐震マット単独は39.7%（n=56）で効果が確認されていません。',
  },
  {
    'id': 'TFD-M',
    'title': '東京消防庁「熊本地震における家具等の転倒等の実態調査」マンション編',
    'summary':
        '異なる種類の固定具を2点以上併用した住戸では転倒が確認されていません（n=8のため参考値）。',
  },
];

Color riskColor(String level) => switch (level) {
      'high' => const Color(0xFFB71C1C),
      'mid' => const Color(0xFFE65100),
      'low' => const Color(0xFF558B2F),
      _ => Colors.grey.shade700,
    };

/// v2.2 API の `display` ブロックを主表示とする診断結果カード。
class DiagnosisResultCard extends StatefulWidget {
  const DiagnosisResultCard({super.key, required this.result});

  final Map<String, dynamic> result;

  @override
  State<DiagnosisResultCard> createState() => _DiagnosisResultCardState();
}

class _DiagnosisResultCardState extends State<DiagnosisResultCard> {
  bool _reasonExpanded = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final furniture = result['furniture'] as Map<String, dynamic>;
    final braces =
        (result['braces'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final risk = result['risk'] as Map<String, dynamic>?;
    final display = result['display'] as Map<String, dynamic>?;
    final warnings = (result['warnings'] as List<dynamic>? ?? []).cast<String>();
    final suggestions =
        (result['suggestions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final outOfScope = result['out_of_scope'] as bool? ?? false;
    final isOutOfScope = outOfScope || risk == null;

    final badge = display?['badge'] as Map<String, dynamic>?;
    final level = badge?['level'] as String? ??
        risk?['level'] as String? ??
        (isOutOfScope ? 'low' : 'mid');
    final color = isOutOfScope ? Colors.grey.shade600 : riskColor(level);

    final headline = display?['headline'] as String? ??
        _fallbackHeadline(risk, isOutOfScope);
    final title = display?['title'] as String? ??
        furnitureLabel(furniture['class'] as String);
    final summary = display?['summary'] as String?;
    final reasonChain = _reasonChain(display, risk, isOutOfScope);

    final warningTexts = warnings
        .map(warningLabel)
        .whereType<String>()
        .where((text) => text.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CudBadge(
                color: color,
                label: badge?['label'] as String? ??
                    (isOutOfScope ? '—' : riskLevelLabel(level)),
                shape: badge?['shape'] as String? ??
                    (isOutOfScope ? 'circle' : _defaultShape(level)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Chip(
                label: Text('参考値'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
          if (summary != null && summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              summary,
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
          ],
          if (braces.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text('固定具', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final brace in braces)
                  _SmallChip(
                    label: braceLabel(brace['class'] as String),
                    subLabel: qualityLabel(brace['install_quality'] as String),
                  ),
              ],
            ),
          ],
          if (reasonChain.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _reasonExpanded = !_reasonExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _reasonExpanded ? '▼ なぜこの判定？' : '▶ なぜこの判定？',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (_reasonExpanded) ...[
              const SizedBox(height: 6),
              ...reasonChain.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
              ),
            ],
          ],
          if (warningTexts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...warningTexts.map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '注意：$text',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...suggestions.map(
              (suggestion) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(suggestion['text'] as String),
                    if ((suggestion['source'] as String?)?.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          suggestion['source'] as String,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (kDebugMode && risk != null) ...[
            const SizedBox(height: 8),
            Text(
              'debug: level=${risk['level']}, type=${risk['type']}',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fallbackHeadline(Map<String, dynamic>? risk, bool isOutOfScope) {
    if (isOutOfScope) return '判定対象外';
    final type = risk?['type'] as String? ?? 'topple';
    final level = risk?['level'] as String? ?? 'mid';
    final riskWord = type == 'slide' ? '移動' : '転倒';
    return '$riskWordリスク：${riskLevelLabel(level)}';
  }

  List<String> _reasonChain(
    Map<String, dynamic>? display,
    Map<String, dynamic>? risk,
    bool isOutOfScope,
  ) {
    if (isOutOfScope) return const [];
    final fromDisplay =
        (display?['reason_chain'] as List<dynamic>? ?? []).cast<String>();
    if (fromDisplay.isNotEmpty) return fromDisplay;

    final modifiers =
        (risk?['modifiers'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return modifiers
        .map((m) => m['label'] as String?)
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .toList();
  }

  String _defaultShape(String level) => switch (level) {
        'high' => 'triangle',
        'mid' => 'diamond',
        _ => 'circle',
      };
}

class _CudBadge extends StatelessWidget {
  const _CudBadge({
    required this.color,
    required this.label,
    required this.shape,
  });

  final Color color;
  final String label;
  final String shape;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShapeIcon(color: color, shape: shape),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ShapeIcon extends StatelessWidget {
  const _ShapeIcon({required this.color, required this.shape});

  final Color color;
  final String shape;

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    return switch (shape) {
      'triangle' => Icon(Icons.change_history, color: color, size: size),
      'diamond' => Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      _ => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
    };
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.subLabel});

  final String label;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            subLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画面末尾に1回だけ表示する unknowns 折りたたみ。
class DiagnosisUnknownsCard extends StatelessWidget {
  const DiagnosisUnknownsCard({super.key, required this.unknowns});

  final List<String> unknowns;

  @override
  Widget build(BuildContext context) {
    if (unknowns.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ExpansionTile(
        title: const Text('この診断でわからないこと'),
        children: unknowns
            .map(
              (item) => ListTile(
                dense: true,
                title: Text(item),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// 画面末尾に1回だけ表示する sources 折りたたみ（v2.3）。
class DiagnosisSourcesCard extends StatelessWidget {
  const DiagnosisSourcesCard({super.key, required this.sources});

  final List<Map<String, dynamic>> sources;

  @override
  Widget build(BuildContext context) {
    final items = sources.isNotEmpty ? sources : fallbackSources;
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ExpansionTile(
        title: const Text('参考にした調査・基準値'),
        children: items
            .map(
              (source) => ListTile(
                dense: true,
                title: Text(
                  source['title'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(source['summary'] as String? ?? ''),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// retake / api_error 時の再試行カード。
class DiagnosisRetakeCard extends StatelessWidget {
  const DiagnosisRetakeCard({
    super.key,
    required this.payload,
    required this.onRetry,
    required this.onPickImage,
    required this.isLoading,
  });

  final Map<String, dynamic> payload;
  final VoidCallback onRetry;
  final VoidCallback onPickImage;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final status = payload['status'] as String;
    final isApiError = status == 'api_error';
    final color = isApiError ? Colors.red : Colors.orange;
    final reason = payload['reason'] as String?;
    final message = (payload['message'] as String?) ??
        switch (reason) {
          'no_furniture' => '家具全体が写るように撮影してください。',
          'nothing_detected' => '検出できませんでした。明るい場所で全体を撮影してください。',
          'brace_only' => '固定具だけが写っています。家具全体が写るように撮り直してください。',
          _ => '家具全体が写るように撮り直してください。',
        };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isApiError ? '通信エラー' : '再撮影が必要です',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 15)),
          if (isApiError) ...[
            const SizedBox(height: 8),
            Text(
              '避難機能には影響ありません。',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: isLoading ? null : onRetry,
                child: Text(isApiError ? '再試行' : '再撮影'),
              ),
              OutlinedButton(
                onPressed: onPickImage,
                child: const Text('画像を選び直す'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
