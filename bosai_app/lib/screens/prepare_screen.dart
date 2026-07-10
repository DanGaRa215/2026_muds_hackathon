import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../db/database_helper.dart';
import '../models/shelter.dart';
import '../routing/precompute_service.dart';
import '../routing_bootstrap.dart';
import '../services/home_area_service.dart';
import 'home_register_screen.dart';

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
  LatLng? _homeLocation;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final info = await DatabaseHelper.instance.getHomeInfo();
    final registeredHome = await DatabaseHelper.instance.getRegisteredHome();
    if (info != null && mounted) {
      setState(() {
        _structure = info['structure'] as String;
        _homeLocation = registeredHome == null
            ? null
            : LatLng(
                (registeredHome['lat'] as num).toDouble(),
                (registeredHome['lon'] as num).toDouble(),
              );
        _floor = info['floor'] as int;
        _saved = true;
      });
    }
  }

  Future<void> _save() async {
    await _saveHomeProfile(showSnackBar: true);
  }

  Future<void> _saveHomeProfile({required bool showSnackBar}) async {
    await DatabaseHelper.instance.saveHomeProfile(
      structure: _structure,
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

  Future<void> _openHomeRegisterScreen() async {
    final selectedHome = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const HomeRegisterScreen()),
    );
    if (selectedHome == null || !mounted) {
      return;
    }

    setState(() => _homeLocation = selectedHome);
    await DatabaseHelper.instance.saveHomeProfile(
      structure: _structure,
      floor: _floor,
    );
    await DatabaseHelper.instance.saveHomeLocation(
      lat: selectedHome.latitude,
      lon: selectedHome.longitude,
    );
    if (!mounted) return;

    await _runPrecomputeWithRetry(selectedHome);
  }

  Future<void> _runPrecomputeWithRetry(LatLng homeLocation) async {
    final routeService = await RoutingBootstrap.routeService();
    if (!routeService.isInRoutingArea(homeLocation)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('経路データ未整備エリアです。避難所提案と地図表示は利用できます。'),
        ),
      );
      return;
    }

    var shouldRetry = true;
    while (shouldRetry && mounted) {
      shouldRetry = false;
      try {
        await _precomputeWithProgress(
          homeLocation,
          PrecomputeService(routeService),
        );
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

  Future<void> _precomputeWithProgress(
    LatLng homeLocation,
    PrecomputeService precomputeService,
  ) async {
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
      final routeService = await RoutingBootstrap.routeService();
      await HomeAreaService.precomputeIfRoutingAvailable(
        home: homeLocation,
        routeService: routeService,
        precomputeService: precomputeService,
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
            key: ValueKey('structure-$_structure'),
            initialValue: _structure,
            decoration: const InputDecoration(labelText: '建物構造'),
            items: ['木造', '鉄骨造', 'RC造（鉄筋コンクリート）']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _structure = v!),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey('floor-$_floor'),
            initialValue: _floor,
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
