import 'package:flutter/material.dart';

import '../routing/models.dart';
import '../routing_bootstrap.dart';
import 'navi_screen.dart';

class ShelterProposalPage extends StatefulWidget {
  const ShelterProposalPage({
    super.key,
    required this.situation,
    this.disasterMode = DisasterMode.earthquake,
  });

  final Set<String> situation;
  final DisasterMode disasterMode;

  @override
  State<ShelterProposalPage> createState() => _ShelterProposalPageState();
}

class ShelterCardScreen extends ShelterProposalPage {
  const ShelterCardScreen({
    super.key,
    required super.situation,
    super.disasterMode,
  });
}

class _ShelterProposalPageState extends State<ShelterProposalPage> {
  static const Color _backgroundColor = Color(0xFFE7FBF0);
  static const Color _textColor = Color(0xFF300808);
  static const _floodGuidance = '大規模水害時は、時間に余裕がある場合は浸水しない地域への広域避難、'
      '余裕がない場合は近くの建物の3階以上への避難(垂直避難)が基本です。'
      'この経路は参考情報です';
  late final Future<List<ShelterInfo>> _sheltersFuture;
  var _candidateIndex = 0;

  @override
  void initState() {
    super.initState();
    _sheltersFuture = RoutingBootstrap.routeService().then(
      (service) => service.sheltersFor(widget.disasterMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: _textColor,
        title: const Text('おすすめの避難所'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: FutureBuilder<List<ShelterInfo>>(
          future: _sheltersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '避難所候補の読み込みに失敗しました\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }

            final shelters = snapshot.data ?? const <ShelterInfo>[];
            if (shelters.isEmpty) {
              return const Center(child: Text('避難所候補が見つかりません'));
            }

            final shelter = shelters[_candidateIndex % shelters.length];
            return _buildShelterCandidate(context, shelter, shelters.length);
          },
        ),
      ),
    );
  }

  Widget _buildShelterCandidate(
    BuildContext context,
    ShelterInfo shelter,
    int shelterCount,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _textColor, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '第${_candidateIndex + 1}候補：${shelter.name}',
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '海抜: ${shelter.elevationM.toStringAsFixed(0)}m',
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '収容人数: ${shelter.capacity}人',
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (widget.disasterMode == DisasterMode.flood) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    _floodGuidance,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 64,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textColor,
                        side: const BorderSide(color: _textColor, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        if (_candidateIndex + 1 >= shelterCount) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FinalInstructionScreen(),
                            ),
                          );
                          return;
                        }
                        setState(() => _candidateIndex++);
                      },
                      child: const Text('NO（他の候補を見る）'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 64,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _textColor,
                        foregroundColor: _backgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NaviScreen(
                              shelter: shelter,
                              mode: widget.disasterMode,
                            ),
                          ),
                        );
                      },
                      child: const Text('YES（ここへ避難する）'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 全候補NO時の最終指示（設計書のエッジケース）
class FinalInstructionScreen extends StatelessWidget {
  const FinalInstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange.shade800,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.terrain, color: Colors.white, size: 96),
              const SizedBox(height: 24),
              const Text(
                '周囲で最も高い場所へ\n避難してください',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '高台・頑丈な建物の上層階など',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 32),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange.shade800,
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('ホームへ戻る',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
