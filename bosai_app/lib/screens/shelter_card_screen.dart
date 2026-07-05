import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../logic/shelter_recommender.dart';
import '../models/shelter.dart';

/// 現在地（デモ用の固定ダミー座標。本実装では geolocator で取得）
const _demoLat = 35.7434;
const _demoLon = 139.8472;

/// 避難所カード画面（設計書 §3: 1件表示 → YES/NO → 最大5件ループ）
class ShelterCardScreen extends StatefulWidget {
  final Set<String> situation;
  const ShelterCardScreen({super.key, required this.situation});

  @override
  State<ShelterCardScreen> createState() => _ShelterCardScreenState();
}

class _ShelterCardScreenState extends State<ShelterCardScreen> {
  List<Shelter>? _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shelters = await DatabaseHelper.instance.getShelters();
    // ※推薦ロジックはダミー。メンバーBのスコア関数に差し替え予定。
    final recommended = ShelterRecommender.recommend(
      shelters: shelters,
      situation: widget.situation,
      currentLat: _demoLat,
      currentLon: _demoLon,
    );
    setState(() => _candidates = recommended);
  }

  void _no() {
    if (_index + 1 >= _candidates!.length) {
      // 全候補NO → 最終指示（設計書のエッジケース）
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FinalInstructionScreen()),
      );
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    if (candidates == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final shelter = candidates[_index];
    final distance = ShelterRecommender.distanceM(
        _demoLat, _demoLon, shelter.lat, shelter.lon);

    return Scaffold(
      appBar: AppBar(
        title: Text('避難所候補 ${_index + 1}/${candidates.length}'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shelter.name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _InfoRow(
                        icon: Icons.directions_walk,
                        text:
                            '約${(distance / 1000).toStringAsFixed(1)}km・徒歩${ShelterRecommender.walkMinutes(distance)}分'),
                    _InfoRow(
                        icon: Icons.terrain,
                        text: '海抜 ${shelter.elevationM.toStringAsFixed(0)}m'),
                    _InfoRow(
                        icon: Icons.waves,
                        text:
                            '海岸から ${(shelter.coastDistanceM / 1000).toStringAsFixed(1)}km'),
                    _InfoRow(
                        icon: Icons.groups, text: '定員 約${shelter.capacity}人'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Text('この避難所へ向かいますか？',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                minimumSize: const Size.fromHeight(64),
              ),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => NaviScreen(shelter: shelter)),
              ),
              child: const Text('YES（ここへ避難する）',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _no,
              child: const Text('NO（次の候補を見る）',
                  style: TextStyle(fontSize: 18)),
            ),
          ],
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
