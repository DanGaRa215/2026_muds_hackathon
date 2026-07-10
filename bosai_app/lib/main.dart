import 'package:flutter/material.dart';
import 'dart:async';

import 'app_theme.dart';
import 'db/database_helper.dart';
import 'db/shelter_database.dart';
import 'screens/home_screen.dart';
import 'services/eew_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseHelper.instance.database;
  await ShelterDatabase.instance;

  EewManager().connect(useSandbox: true);

  Timer(const Duration(seconds: 5), () {
    debugPrint('🟢 [EEW_LOG] ⏰ タイマー発動：モックデータを注入します');
    EewManager().injectMockEewAlarm();
  });

  runApp(const BosaiApp());
}

class BosaiApp extends StatelessWidget {
  const BosaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 🎯 ValueListenableBuilderで包むことで、Notifierが変更された瞬間に全画面が再描画されます
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeNotifier,
      builder: (_, currentMode, __) {
        return MaterialApp(
          title: '総合防災アプリ',
          debugShowCheckedModeBanner: false,
          
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
          ),
          
          themeMode: currentMode, // 👈 状態に応じてライト/ダークが全画面一斉に切り替わる
          home: const HomeScreen(),
        );
      },
    );
  }
}