import 'package:flutter/material.dart';

import 'shelter_card_screen.dart';

/// 状況確認画面（設計書 §3: チェックボックス×4のみ・1画面完結）
class StatusCheckScreen extends StatefulWidget {
  const StatusCheckScreen({super.key});

  @override
  State<StatusCheckScreen> createState() => _StatusCheckScreenState();
}

class _StatusCheckScreenState extends State<StatusCheckScreen> {
  // key: injury / fire / collapse / tsunami
  final Map<String, bool> _checks = {
    'injury': false,
    'fire': false,
    'collapse': false,
    'tsunami': false,
  };

  static const _labels = {
    'injury': 'けがをしている',
    'fire': '周囲で火災が発生している',
    'collapse': '建物倒壊の危険がある',
    'tsunami': '津波の危険がある（沿岸部）',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('状況確認'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'あてはまるものをチェックしてください',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._checks.keys.map(
              (key) => CheckboxListTile(
                value: _checks[key],
                title: Text(_labels[key]!,
                    style: const TextStyle(fontSize: 18)),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => _checks[key] = v ?? false),
              ),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
              onPressed: () {
                final situation = _checks.entries
                    .where((e) => e.value)
                    .map((e) => e.key)
                    .toSet();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ShelterCardScreen(situation: situation),
                  ),
                );
              },
              child: const Text('確認して避難所を探す',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
