import 'package:flutter/material.dart';

import '../logic/shelter_recommender.dart';
import '../models/shelter.dart';

/// 現在地（デモ用の固定ダミー座標。本実装では geolocator で取得）
const _demoLat = 35.7434;
const _demoLon = 139.8472;

class ShelterProposalPage extends StatefulWidget {
  const ShelterProposalPage({super.key, required this.situation});

  final Set<String> situation;

  @override
  State<ShelterProposalPage> createState() => _ShelterProposalPageState();
}

class ShelterCardScreen extends ShelterProposalPage {
  const ShelterCardScreen({super.key, required super.situation});
}

class _ShelterProposalPageState extends State<ShelterProposalPage> {
  static const Color _backgroundColor = Color(0xFFE7FBF0);
  static const Color _textColor = Color(0xFF300808);

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
        child: Center(
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
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '第1候補：市川市立○○小学校（推奨度：高）',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        '現在地から 420m（徒歩約5分）',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '海抜: 12m',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
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
                          onPressed: () {},
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
                          onPressed: () {},
                          child: const Text('YES（ここへ避難する）'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 16)),
      ]),
    );
  }
}

/// オフラインナビ画面（簡易版）
/// 本実装: flutter_map(or maplibre_gl) + PMTiles + Dart自前A*（メンバーB/C）
class NaviScreen extends StatelessWidget {
  final Shelter shelter;
  const NaviScreen({super.key, required this.shelter});

  @override
  Widget build(BuildContext context) {
    final distance = ShelterRecommender.distanceM(
        _demoLat, _demoLon, shelter.lat, shelter.lon);
    return Scaffold(
      appBar: AppBar(
        title: const Text('避難ナビ'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, size: 96, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('オフライン地図をここに表示\n(flutter_map + PMTiles: 実装予定)',
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('目的地: ${shelter.name}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('残り 約${(distance / 1000).toStringAsFixed(1)}km',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
              onPressed: () async {
                // 到着確認 → 安否メモ（デモでは記録のみ表示）
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('到着を記録しました'),
                    content: const TextField(
                      decoration:
                          InputDecoration(hintText: '安否メモ（任意・デモ）'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
              child: const Text('到着した',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
