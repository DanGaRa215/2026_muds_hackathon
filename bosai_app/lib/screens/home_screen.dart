import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/location_service.dart';
import 'eew_current_location_screen.dart';
import 'eew_screen.dart';
import 'history_screen.dart';
import 'map_spike_screen.dart';
import 'furniture_diagnosis_ui_screen.dart';
import 'package:bosai_app/db/database_helper.dart';
import 'package:bosai_app/screens/demo_map_screen.dart';
import 'package:bosai_app/screens/address_geocoding_screen.dart';
import 'package:bosai_app/screens/demo_address_geocoding_screen.dart';
import 'package:bosai_app/main.dart'; // 💡 appThemeNotifier を参照するためにインポート

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  List<Widget> _getPages() {
    return [
      const _DailyDashboardPage(isDemoMode: false),
      const _PlaceholderTabPage(
        title: '家具診断履歴',
        icon: Icons.history,
        description: '過去の診断結果をここに表示します。',
      ),
      const _PlaceholderTabPage(
        title: '避難準備',
        icon: Icons.map_outlined,
        description: '避難計画や地図ダウンロード画面をここに接続します。',
      ),
      _AppSettingsTabPage(onNavigateToDemo: () {
        _push(
            context,
            const Scaffold(
              body: SafeArea(child: _DailyDashboardPage(isDemoMode: true)),
            ));
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 💡 テーマから現在のカラー情報を動的に取得
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // ダークモード時は暗めの背景、ライトモード時はこれまでの薄緑を適用
    final currentBgColor = isDark ? theme.colorScheme.background : const Color(0xFFE7FBF0);
    final currentTextColor = isDark ? theme.colorScheme.onBackground : const Color(0xFF300808);

    return Scaffold(
      backgroundColor: currentBgColor,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _getPages(),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: isDark ? theme.colorScheme.primary : currentTextColor,
        unselectedItemColor: (isDark ? theme.colorScheme.onSurface : currentTextColor).withValues(alpha: 0.6),
        backgroundColor: theme.colorScheme.surface, // 白固定からテーマ連動に変更
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: '家具診断履歴',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: '避難準備',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'アプリ設定',
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _DailyDashboardPage extends StatefulWidget {
  final bool isDemoMode;

  const _DailyDashboardPage({this.isDemoMode = false});

  @override
  State<_DailyDashboardPage> createState() => _DailyDashboardPageState();
}

class _DailyDashboardPageState extends State<_DailyDashboardPage> {
  late Future<bool> _hasRegisteredHomeFuture;

  @override
  void initState() {
    super.initState();
    _hasRegisteredHomeFuture = _hasRegisteredHome();
    if (widget.isDemoMode) {
      // デモ起動時に位置情報権限を先に済ませておく
      // （EEW発火時に権限ダイアログでブロックしないため）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LocationService.ensurePermission();
      });
    }
  }

  Future<bool> _hasRegisteredHome() async {
    return await DatabaseHelper.instance.getRegisteredHome() != null;
  }

  Future<void> _openAddressRegistration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => widget.isDemoMode
            ? const DemoAddressGeocodingScreen()
            : const AddressGeocodingScreen(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _hasRegisteredHomeFuture = _hasRegisteredHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 💡 修正：固定値を取り除き、テーマ連動カラーに変更
    final currentBgColor = isDark ? theme.colorScheme.background : const Color(0xFFE7FBF0);
    final currentTextColor = isDark ? theme.colorScheme.onBackground : const Color(0xFF300808);

    return Scaffold(
      backgroundColor: currentBgColor, // 👈 ⭕ 修正：明るい色の固定を解除
      appBar: widget.isDemoMode
          ? AppBar(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              title: const Text('東京23区デモ画面',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              centerTitle: true,
              elevation: 0,
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isDemoMode ? '日常の防災メニュー（デモ）' : '日常の防災メニュー',
                    style: TextStyle(
                        color: currentTextColor, // 👈 ⭕ 修正：ダークモード対応のテキスト色に連動
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.98,
                    children: [
                      _DailyMenuCardButton(
                        icon: Icons.camera_alt,
                        label: 'AI家具安全診断',
                        onTap: () =>
                            _push(context, const FurnitureDiagnosisUiScreen()),
                      ),
                      _DailyMenuCardButton(
                        icon: Icons.map,
                        label: '避難準備（マップDL）',
                        onTap: () {
                          if (widget.isDemoMode) {
                            _push(context, const DemoMapScreen());
                          } else {
                            _push(context, const MapSpikeScreen());
                          }
                        },
                      ),
                      _DailyMenuCardButton(
                        icon: Icons.history,
                        label: '家具の診断履歴',
                        onTap: () => _push(context, const HistoryScreen()),
                      ),
                      FutureBuilder<bool>(
                        future: _hasRegisteredHomeFuture,
                        builder: (context, snapshot) {
                          final hasRegisteredHome = snapshot.data ?? false;
                          return _DailyMenuCardButton(
                            icon: Icons.home_work,
                            label: hasRegisteredHome ? '自宅住所の変更' : '自宅の住所登録',
                            onTap: _openAddressRegistration,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (widget.isDemoMode) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.warning_amber_rounded, size: 24),
                      label: const Text('デモ実行：緊急地震速報（EEW）を発災',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => const EewScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.my_location, size: 24),
                      label: const Text('デモ実行：EEWを発災（現在地から避難）',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) =>
                                const EewCurrentLocationScreen()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSettingsTabPage extends StatelessWidget {
  final VoidCallback onNavigateToDemo;

  const _AppSettingsTabPage({required this.onNavigateToDemo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentTextColor = isDark ? theme.colorScheme.onBackground : const Color(0xFF300808);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'アプリ設定',
            style: TextStyle(
                color: currentTextColor, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // 🌙 🎯 追加：ダークモード手動切り替えスイッチ
          SwitchListTile(
            title: const Text('ダークモード', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(isDark ? 'ON (夜間モード適用中)' : 'OFF (標準モード適用中)'),
            value: isDark,
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: theme.colorScheme.primary),
            onChanged: (bool value) {
              appThemeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
            },
          ),
          const SizedBox(height: 16),

          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400, width: 1),
            ),
            leading: Icon(Icons.developer_mode, color: currentTextColor),
            title: const Text('東京23区デモモードを起動',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: onNavigateToDemo,
          ),
        ],
      ),
    );
  }
}

class _DailyMenuCardButton extends StatelessWidget {
  const _DailyMenuCardButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentTextColor = isDark ? theme.colorScheme.onBackground : const Color(0xFF300808);

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.surface, // 自動で白かグレー反転
        foregroundColor: currentTextColor,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? theme.colorScheme.outline : currentTextColor, width: 2),
        ),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: isDark ? theme.colorScheme.primary : currentTextColor),
          const SizedBox(height: 14),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: currentTextColor)),
        ],
      ),
    );
  }
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

class _PlaceholderTabPage extends StatelessWidget {
  const _PlaceholderTabPage(
      {required this.title, required this.icon, required this.description});

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentTextColor = isDark ? theme.colorScheme.onBackground : const Color(0xFF300808);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: currentTextColor),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    color: currentTextColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description,
                textAlign: TextAlign.center,
                style: TextStyle(color: currentTextColor, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}