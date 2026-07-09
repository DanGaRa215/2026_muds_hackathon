import 'package:flutter/material.dart';
import 'dart:async'; // 💡 デバッグ用のタイマーのために追加

import 'db/database_helper.dart';
import 'db/shelter_database.dart';
import 'screens/home_screen.dart';
import 'services/eew_manager.dart'; // 💡 EEWマネージャーを読み込む

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // DB初期化
  await DatabaseHelper.instance.database;
  await ShelterDatabase.instance;

  // 📡 【デバッグ】アプリ起動と同時に、バックグラウンドでWebSocketに接続する
  EewManager().connect(useSandbox: true);

  // 🚀 【デバッグ】ターミナル検証用：アプリ起動の5秒後に自動でモックデータを注入する
  // （※ターミナル上でログを確認するための仕掛けです。本番ではこのTimer処理は削除します）
  Timer(const Duration(seconds: 5), () {
    print('🟢 [EEW_LOG] ⏰ タイマー発動：モックデータを注入します');
    EewManager().injectMockEewAlarm();
  });
  
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
      // 💡 画面は本番用の HomeScreen に戻します！
      home: const HomeScreen(),
    );
  }
}