import 'package:flutter/material.dart';

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
  static const Color _warningBorderColor = Color(0xFFC62828);
  static const Color _warningBackgroundColor = Color(0xFFFDECEC);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.98,
            children: const [
              _DailyMenuCardButton(
                icon: Icons.camera_alt,
                label: 'AI家具安全診断',
              ),
              _DailyMenuCardButton(
                icon: Icons.map,
                label: '避難準備（マップDL）',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _warningBackgroundColor,
              border: Border.all(color: _warningBorderColor, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '🚨 ハッカソン審査・デモ用',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _warningBorderColor,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text('緊急地震速報（EEW）を擬似発火'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyMenuCardButton extends StatelessWidget {
  const _DailyMenuCardButton({
    required this.icon,
    required this.label,
  });

  static const Color _textColor = Color(0xFF300808);

  final IconData icon;
  final String label;

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
      onPressed: () {},
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44),
          const SizedBox(height: 14),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
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
