import 'package:flutter/material.dart';

import '../routing/models.dart';
import 'shelter_card_screen.dart';

class SituationCheckPage extends StatefulWidget {
  const SituationCheckPage({super.key});

  @override
  State<SituationCheckPage> createState() => _SituationCheckPageState();
}

class StatusCheckScreen extends SituationCheckPage {
  const StatusCheckScreen({super.key});
}

class _SituationOption {
  const _SituationOption(this.key, this.label);

  final String key;
  final String label;
}

class _SituationCheckPageState extends State<SituationCheckPage> {
  static const Color _backgroundColor = Color(0xFFE7FBF0);
  static const Color _textColor = Color(0xFF300808);
  static const Color _buttonColor = Color(0xFF300808);

  static const List<_SituationOption> _options = [
    _SituationOption('injury', 'けが人がいる'),
    _SituationOption('fire', '火災が発生している'),
    _SituationOption('collapse', '建物が倒壊している'),
    _SituationOption('tsunami', '津波のリスクがある（沿岸部）'),
  ];

  final List<bool> _selected = List<bool>.filled(_options.length, false);

  Set<String> _selectedSituation() {
    return {
      for (var index = 0; index < _options.length; index++)
        if (_selected[index]) _options[index].key,
    };
  }

  DisasterMode _disasterModeFor(Set<String> situation) {
    // 既存語彙: injury/fire/collapse/tsunami。
    // 将来の洪水・高潮・大雨キーも水害系として flood に寄せる。
    const floodKeys = {
      'tsunami',
      'flood',
      'storm_surge',
      'heavy_rain',
      'rain',
    };
    return situation.any(floodKeys.contains)
        ? DisasterMode.flood
        : DisasterMode.earthquake;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: _textColor,
        title: const Text('周囲の状況確認'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  '現在の周囲の状況をチェックしてください（複数選択可）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: _options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final option = _options[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _textColor, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: CheckboxListTile(
                        value: _selected[index],
                        activeColor: _buttonColor,
                        checkColor: _backgroundColor,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        title: Text(
                          option.label,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _selected[index] = value ?? false;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          height: 64,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _buttonColor,
              foregroundColor: _backgroundColor,
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              final situation = _selectedSituation();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShelterProposalPage(
                    situation: situation,
                    disasterMode: _disasterModeFor(situation),
                  ),
                ),
              );
            },
            child: const Text('避難所を検索する'),
          ),
        ),
      ),
    );
  }
}
