import 'package:flutter/material.dart';

import '../utils/detection_editor.dart';
import '../widgets/diagnosis_result_card.dart';

/// v2.4 検出確認画面。アイコン・絵文字は使わない（v2.3 Part D 継承）。
class DetectionConfirmCard extends StatelessWidget {
  const DetectionConfirmCard({
    super.key,
    required this.editedDetection,
    required this.selectedFurnitureIndex,
    required this.onSelectedFurnitureIndexChanged,
    required this.onFurnitureClassChanged,
    required this.onWardrobeProfileChanged,
    required this.onBraceToggled,
    required this.onRetake,
    required this.onConfirm,
    required this.isSubmitting,
  });

  final Map<String, dynamic> editedDetection;
  final int selectedFurnitureIndex;
  final ValueChanged<int> onSelectedFurnitureIndexChanged;
  final ValueChanged<String?> onFurnitureClassChanged;
  final ValueChanged<String?> onWardrobeProfileChanged;
  final void Function(String braceClass, bool enabled) onBraceToggled;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;
  final bool isSubmitting;

  static const List<String> furnitureClasses = [
    'furniture_bookshelf',
    'furniture_wardrobe',
    'furniture_cupboard',
    'furniture_refrigerator',
    'furniture_tv',
    'furniture_microwave_stand',
    'furniture_desk',
    'furniture_other',
  ];

  @override
  Widget build(BuildContext context) {
    final furnitureList =
        (editedDetection['furniture'] as List<dynamic>).cast<Map<String, dynamic>>();
    final selectedItem = furnitureList[selectedFurnitureIndex];
    final furnitureClass = selectedItem['class'] as String;
    final confidence = (selectedItem['confidence'] as num?)?.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '写真から以下を検出しました。間違いがあれば修正してから判定してください。',
          style: TextStyle(height: 1.45),
        ),
        const SizedBox(height: 8),
        const Text(
          'この内容でリスクを判定します。よろしいですか？',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (furnitureList.length > 1) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text(
            '診断する家具を選んでください',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...List.generate(furnitureList.length, (index) {
            final item = furnitureList[index];
            return RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              title: Text(DetectionEditor.furnitureRadioLabel(item)),
              value: index,
              groupValue: selectedFurnitureIndex,
              onChanged: isSubmitting
                  ? null
                  : (value) {
                      if (value != null) onSelectedFurnitureIndexChanged(value);
                    },
            );
          }),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text('家具の種類', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: furnitureClass,
          decoration: InputDecoration(
            helperText: confidence == null
                ? null
                : '信頼度 ${confidence.toStringAsFixed(2)}（参考）',
          ),
          items: furnitureClasses
              .map(
                (cls) => DropdownMenuItem(
                  value: cls,
                  child: Text(furnitureLabel(cls)),
                ),
              )
              .toList(),
          onChanged: isSubmitting ? null : onFurnitureClassChanged,
        ),
        if (furnitureClass == 'furniture_wardrobe') ...[
          const SizedBox(height: 12),
          const Text('だんすの型', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: selectedItem['profile'] as String?,
            items: const [
              DropdownMenuItem(value: 'tall', child: Text('背の高い洋服だんす')),
              DropdownMenuItem(value: 'chest', child: Text('背の低い整理だんす')),
              DropdownMenuItem(value: null, child: Text('わからない')),
            ],
            onChanged: isSubmitting ? null : onWardrobeProfileChanged,
          ),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text(
          '固定具（写真で確認できたもの）',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...DetectionEditor.allBraceClasses.map((braceClass) {
          final enabled = DetectionEditor.isBraceEnabled(selectedItem, braceClass);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(braceLabel(braceClass)),
            value: enabled,
            onChanged: isSubmitting
                ? null
                : (value) => onBraceToggled(braceClass, value ?? false),
          );
        }),
        const SizedBox(height: 8),
        Text(
          '写真で確認できなかった固定具は、安全のためリスクの軽減に反映していません。',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isSubmitting ? null : onRetake,
                child: const Text('撮り直す'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: isSubmitting ? null : onConfirm,
                child: Text(isSubmitting ? '判定中…' : 'この内容で判定する'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
