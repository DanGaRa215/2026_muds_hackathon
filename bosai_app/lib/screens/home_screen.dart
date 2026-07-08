import 'package:flutter/material.dart';

import 'eew_screen.dart';
import 'history_screen.dart';
import 'map_spike_screen.dart';
import 'furniture_diagnosis_ui_screen.dart';
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

  final List<Widget> _pages = const [
    _DailyDashboardPage(),
    _PlaceholderTabPage(
      title: '家具診断履歴',
      icon: Icons.history,
      description: '過去の診断結果をここに表示します。',
    ),
    _PlaceholderTabPage(
      title: '避難準備',
      icon: Icons.map_outlined,
      description: '避難計画や地図ダウンロード画面をここに接続します。',
    ),
    _PlaceholderTabPage(
      title: 'アプリ設定',
      icon: Icons.settings,
      description: '通知や表示設定をここで管理します。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
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
}

class _DailyDashboardPage extends StatelessWidget {
  const _DailyDashboardPage();

  static const Color _textColor = Color(0xFF300808);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // スクロール可能なメインコンテンツ領域
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '日常の防災メニュー',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                // 🎯 4つのボタンを同じサイズで2×2のグリッドに統一配置
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
                      onTap: () => _push(context, const FurnitureDiagnosisUiScreen()),
                    ),
                    _DailyMenuCardButton(
                      icon: Icons.map,
                      label: '避難準備（マップDL）',
                      onTap: () {},
                    ),
                    _DailyMenuCardButton(
                      icon: Icons.history,
                      label: '家具の診断履歴',
                      onTap: () => _push(context, const HistoryScreen()),
                    ),
                    _DailyMenuCardButton(
                      icon: Icons.home_work,
                      label: '自宅の住所登録',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AddressGeocodingScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // --- SPIKE: 検ッセージ後に削除 ---
                _MenuButton(
                  icon: Icons.map,
                  label: 'Map Spike (Dev)',
                  subtitle: 'PMTilesオフライン地図テスト',
                  onTap: () => _push(context, const MapSpikeScreen()),
                ),
                // --- END SPIKE ---
              ],
            ),
          ),
        ),
        
        // 🎯 フッター（ボトムナビ）の上に設置したデモボタンエリア
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: _textColor.withValues(alpha: 0.1), width: 1),
            ),
          ),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade800,
              side: BorderSide(color: Colors.red.shade800, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text(
              '審査用：EEWデモを起動する',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const EewScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyMenuCardButton extends StatelessWidget {
  const _DailyMenuCardButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
        elevation: 0,
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
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  static const Color _textColor = Color(0xFF300808);

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _textColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: _textColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                        style: const TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => page),
  );
}

class _PlaceholderTabPage extends StatelessWidget {
  const _PlaceholderTabPage({
    required this.title,
    required this.icon,
    required this.description,
  });

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
            Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}