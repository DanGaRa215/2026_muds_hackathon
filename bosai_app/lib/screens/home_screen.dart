import 'package:flutter/material.dart';

import 'eew_screen.dart';
import 'history_screen.dart';
import 'map_spike_screen.dart';
import 'furniture_diagnosis_ui_screen.dart';
import 'package:bosai_app/screens/demo_map_screen.dart';
import 'package:bosai_app/screens/address_geocoding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _backgroundColor = Color(0xFFE7FBF0);
  static const Color _textColor = Color(0xFF300808);

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
      // アプリ設定タブから HomeScreen の Context を利用してデモ画面へ遷移させる
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
    return Scaffold(
      backgroundColor: _backgroundColor,
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
        selectedItemColor: _textColor,
        unselectedItemColor: _textColor.withValues(alpha: 0.7),
        backgroundColor: Colors.white,
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

class _DailyDashboardPage extends StatelessWidget {
  final bool isDemoMode;

  const _DailyDashboardPage({this.isDemoMode = false});

  static const Color _textColor = Color(0xFF300808);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE7FBF0),
      appBar: isDemoMode
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
                    isDemoMode ? '日常の防災メニュー（デモ）' : '日常の防災メニュー',
                    style: const TextStyle(
                        color: _textColor,
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
                          if (isDemoMode) {
                            // デモモード時は新設した専用マップ画面へジャンプ
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
                      _DailyMenuCardButton(
                        icon: Icons.home_work,
                        label: '自宅の住所登録',
                        onTap: () =>
                            _push(context, const AddressGeocodingScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (isDemoMode)
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

  static const Color _textColor = Color(0xFF300808);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'アプリ設定',
            style: TextStyle(
                color: _textColor, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // 東京23区デモ起動用のシンプルなListTileボタン
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade400, width: 1),
            ),
            leading: const Icon(Icons.developer_mode, color: _textColor),
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
  static const Color _textColor = Color(0xFF300808);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _textColor, width: 2),
        ),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44),
          const SizedBox(height: 14),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textColor)),
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
  static const Color _textColor = Color(0xFF300808);
  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _textColor),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: _textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textColor, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
