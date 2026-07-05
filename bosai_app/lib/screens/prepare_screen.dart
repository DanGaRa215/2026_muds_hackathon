import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/shelter.dart';

/// 避難準備画面（設計書 §3【平常時】[避難準備]）
/// 自宅情報の登録・避難所リスト確認・マップDL（プレースホルダ）
class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key});

  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  String _structure = '木造';
  int _floor = 1;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final info = await DatabaseHelper.instance.getHomeInfo();
    if (info != null && mounted) {
      setState(() {
        _structure = info['structure'] as String;
        _floor = info['floor'] as int;
        _saved = true;
      });
    }
  }

  Future<void> _save() async {
    await DatabaseHelper.instance
        .saveHomeInfo(structure: _structure, floor: _floor);
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('自宅情報を保存しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('避難準備')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- 自宅情報 ---
          Text('自宅情報${_saved ? "（登録済み）" : ""}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _structure,
            decoration: const InputDecoration(labelText: '建物構造'),
            items: ['木造', '鉄骨造', 'RC造（鉄筋コンクリート）']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _structure = v!),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _floor,
            decoration: const InputDecoration(labelText: '居住階数'),
            items: List.generate(15, (i) => i + 1)
                .map((v) => DropdownMenuItem(value: v, child: Text('$v階')))
                .toList(),
            onChanged: (v) => setState(() => _floor = v!),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _save,
            child: const Text('保存する'),
          ),
          const Divider(height: 32),
          // --- オフラインマップ（プレースホルダ） ---
          const Text('オフラインマップ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('生活圏マップをダウンロード'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('PMTiles同梱・DL機能は実装予定（メンバーC/D担当）')),
            ),
          ),
          const Divider(height: 32),
          // --- 避難所リスト ---
          const Text('周辺の避難所（ダミーデータ）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          FutureBuilder<List<Shelter>>(
            future: DatabaseHelper.instance.getShelters(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: snapshot.data!
                    .map((s) => ListTile(
                          leading: const Icon(Icons.home_work),
                          title: Text(s.name),
                          subtitle: Text(
                              '海抜${s.elevationM.toStringAsFixed(0)}m / 対応: ${s.types}'),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
