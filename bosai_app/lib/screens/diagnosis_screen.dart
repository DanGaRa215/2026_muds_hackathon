import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../logic/diagnosis_engine.dart';
import '../models/diagnosis.dart';

/// 家具診断画面（設計書 §2.1）
/// 写真選択 → 補助入力（震度・固定状況）→ 判定 → 結果+履歴保存
class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  // モック実装。TFLite完成後は MockDiagnosisEngine() を差し替えるだけ。
  final DiagnosisEngine _engine = MockDiagnosisEngine();

  final _picker = ImagePicker();
  XFile? _image;
  String _intensity = '震度6強';
  final Map<String, bool> _fixations = {
    '突っ張り棒': false,
    'L字金具': false,
    '耐震マット': false,
    '固定なし': false,
  };
  bool _analyzing = false;
  DiagnosisResult? _result;

  Future<void> _pickImage() async {
    final img = await _picker.pickImage(source: ImageSource.gallery);
    if (img != null) setState(() => _image = img);
  }

  Future<void> _analyze() async {
    setState(() {
      _analyzing = true;
      _result = null;
    });
    final selected = _fixations.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    final result = await _engine.analyze(
      imagePath: _image?.path,
      intensity: _intensity,
      fixations: selected,
    );
    // 履歴保存
    await DatabaseHelper.instance.insertDiagnosis(Diagnosis(
      createdAt: DateTime.now().toIso8601String(),
      riskLevel: result.riskLevel,
      intensity: _intensity,
      fixations: selected.join(','),
      comment: result.comment,
    ));
    setState(() {
      _analyzing = false;
      _result = result;
    });
  }

  Color _riskColor(String level) => switch (level) {
        '危険' => Colors.red.shade700,
        '注意' => Colors.orange.shade700,
        _ => Colors.green.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家具診断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 写真選択
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library),
            label: Text(_image == null ? '家具の写真を選択' : '写真を選び直す'),
          ),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Image.file(File(_image!.path), height: 200),
            ),
          const SizedBox(height: 8),
          // 想定震度
          DropdownButtonFormField<String>(
            value: _intensity,
            decoration: const InputDecoration(labelText: '想定震度'),
            items: ['震度5弱', '震度5強', '震度6弱', '震度6強', '震度7']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _intensity = v!),
          ),
          const SizedBox(height: 8),
          // 固定状況
          const Text('固定状況（あてはまるものすべて）',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ..._fixations.keys.map(
            (key) => CheckboxListTile(
              value: _fixations[key],
              title: Text(key),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _fixations[key] = v ?? false),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _analyzing ? null : _analyze,
            child: _analyzing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('診断する', style: TextStyle(fontSize: 18)),
          ),
          // 結果表示
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              color: _riskColor(_result!.riskLevel).withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_result!.riskLevel,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: _riskColor(_result!.riskLevel))),
                        const SizedBox(width: 8),
                        // 非機能要件: 「参考値」ラベルを常時表示
                        const Chip(label: Text('※参考値')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_result!.comment,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    ..._result!.suggestions
                        .map((s) => Text('・$s')),
                    const Divider(),
                    const Text(
                      'この診断でわからないこと: 壁・天井の下地強度、家具内部の重量配分、設置面の摩擦',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
