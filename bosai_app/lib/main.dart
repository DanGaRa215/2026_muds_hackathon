import 'package:flutter/material.dart';

import 'db/database_helper.dart';
import 'screens/home_screen.dart'; // ← ここにセミコロン(;)を追加しました

// ※ボタンのコードはここには置けないため、削除しています

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // DB初期化（初回起動時にダミー避難所データを投入）
  await DatabaseHelper.instance.database;
  runApp(const BosaiApp());
}

class BosaiApp extends StatelessWidget {
  const BosaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '総合防災アプリ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      // アプリ起動時の最初の画面として HomeScreen を開く
      home: const HomeScreen(),
    );
  }
}