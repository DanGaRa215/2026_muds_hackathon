import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../db/database_helper.dart';
import '../models/shelter.dart';
import '../routing_bootstrap.dart';
import 'home_register_screen.dart';

/// 避難準備画面（設計書 §3【平常時】[避難準備]）
/// 自宅情報の登録・避難所リスト確認・マップDL（プレースホルダ）
class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key});

  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  static const _homeLocationSeparator = '||home=';

  String _structure = '木造';
  int _floor = 1;
  bool _saved = false;
  LatLng? _homeLocation;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final info = await DatabaseHelper.instance.getHomeInfo();
    if (info != null && mounted) {
      final rawStructure = info['structure'] as String;
      setState(() {
        _structure = _parseStructure(rawStructure);
        _homeLocation = _parseHomeLocation(rawStructure);
        _floor = info['floor'] as int;
        _saved = true;
      });
    }
  }

  Future<void> _save() async {
    await _saveHomeInfo(showSnackBar: true);
  }

  Future<void> _saveHomeInfo({required bool showSnackBar}) async {
    await DatabaseHelper.instance.saveHomeInfo(
      structure: _encodeStructure(_structure, _homeLocation),
      floor: _floor,
    );
    if (mounted) {
      setState(() => _saved = true);
      if (showSnackBar) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('自宅情報を保存しました')));
      }
    }
  }

  String _encodeStructure(String structure, LatLng? homeLocation) {
    if (homeLocation == null) {
      return structure;
    }
    return '$structure$_homeLocationSeparator'
        '${homeLocation.latitude.toStringAsFixed(7)},'
        '${homeLocation.longitude.toStringAsFixed(7)}';
  }

  String _parseStructure(String rawStructure) {
    final separatorIndex = rawStructure.indexOf(_homeLocationSeparator);
    if (separatorIndex < 0) {
      return rawStructure;
    }
    final structure = rawStructure.substring(0, separatorIndex);
    return structure.isEmpty ? '木造' : structure;
  }

  LatLng? _parseHomeLocation(String rawStructure) {
    final separatorIndex = rawStructure.indexOf(_homeLocationSeparator);
    if (separatorIndex < 0) {
      return null;
    }

    final values =
        rawStructure.substring(separatorIndex + _homeLocationSeparator.length);
    final parts = values.split(',');
    if (parts.length != 2) {
      return null;
    }

    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) {
      return null;
    }
    return LatLng(lat, lon);
  }

  Future<void> _openHomeRegisterScreen() async {
    final selectedHome = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const HomeRegisterScreen()),
    );
    if (selectedHome == null || !mounted) {
      return;
    }

    setState(() => _homeLocation = selectedHome);
    await _saveHomeInfo(showSnackBar: false);
    if (!mounted) return;

    await _runPrecomputeWithRetry(selectedHome);
  }

  Future<void> _runPrecomputeWithRetry(LatLng homeLocation) async {
    var shouldRetry = true;
    while (shouldRetry && mounted) {
      shouldRetry = false;
      try {
        await _precomputeWithProgress(homeLocation);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('避難ルートを保存しました(オフラインで利用できます)'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        shouldRetry = await _showPrecomputeError(e);
      }
    }
  }

  Future<void> _precomputeWithProgress(LatLng homeLocation) async {
    var progress = 0.0;
    StateSetter? updateDialog;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          updateDialog = setDialogState;
          return AlertDialog(
            title: const Text('避難ルートを保存中'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 12),
                Text('${(progress * 100).round()}%'),
              ],
            ),
          );
        },
      ),
    );

    try {
      final precomputeService = await RoutingBootstrap.precomputeService();
      await precomputeService.precomputeAll(
        home: homeLocation,
        onProgress: (value) {
          progress = value.clamp(0.0, 1.0);
          updateDialog?.call(() {});
        },
      );
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await dialogFuture;
      rethrow;
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
  }

  Future<bool> _showPrecomputeError(Object error) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('避難ルートの保存に失敗しました'),
        content: Text(error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('閉じる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('再試行'),
          ),
        ],
      ),
    );
    return retry ?? false;
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_location_alt),
            label: Text(_homeLocation == null ? '地図をタップして自宅を登録' : '自宅位置を再登録する'),
            onPressed: _openHomeRegisterScreen,
          ),
          if (_homeLocation != null) ...[
            const SizedBox(height: 8),
            Text(
              '自宅位置: ${_homeLocation!.latitude.toStringAsFixed(5)}, '
              '${_homeLocation!.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
          const Divider(height: 32),
          // --- オフラインマップ（プレースホルダ） ---
          const Text('オフラインマップ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('生活圏マップをダウンロード'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PMTiles同梱・DL機能は実装予定（メンバーC/D担当）')),
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
