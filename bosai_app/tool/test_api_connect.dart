import 'dart:io';

import 'package:bosai_app/services/diagnosis_api_client.dart';
import 'package:http_parser/http_parser.dart';

Future<void> main(List<String> args) async {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://furniture-diagnosis-api.onrender.com',
  );
  final appKey = Platform.environment['APP_KEY'] ??
      const String.fromEnvironment('APP_KEY');

  if (appKey.isEmpty) {
    stderr.writeln('APP_KEY が未設定です。');
    stderr.writeln('例: APP_KEY=xxx dart run tool/test_api_connect.dart');
    exit(1);
  }

  final imagePath = args.isNotEmpty ? args.first : '/tmp/diagnosis_test.jpg';
  final imageFile = File(imagePath);
  if (!await imageFile.exists()) {
    stderr.writeln('テスト画像が見つかりません: $imagePath');
    exit(1);
  }

  final bytes = await imageFile.readAsBytes();
  final client = DiagnosisApiClient(baseUrl, appKey);

  stdout.writeln('POST $baseUrl/diagnose (${bytes.length} bytes)...');

  try {
    final body = await client.diagnose(
      imageBytes: bytes,
      structure: 'wood',
      floorNo: 3,
      baseIsolated: false,
      filename: 'diagnosis.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
    stdout.writeln('status: ${body['status']}');
    stdout.writeln('body: $body');
  } on DiagnosisApiException catch (e) {
    stdout.writeln('DiagnosisApiException: ${e.statusCode} ${e.message}');
    exit(e.statusCode == 401 ? 2 : 1);
  }
}
