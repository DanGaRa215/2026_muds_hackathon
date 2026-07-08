import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class DiagnosisApiException implements Exception {
  DiagnosisApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'DiagnosisApiException($statusCode): $message';
}

class DiagnosisApiClient {
  DiagnosisApiClient(this.baseUrl, this.appKey);

  final String baseUrl;
  final String appKey;

  static const int maxImageBytes = 5 * 1024 * 1024;

  Future<Map<String, dynamic>> diagnose({
    required List<int> imageBytes,
    required String structure,
    required int floorNo,
    required bool baseIsolated,
    required String filename,
    required MediaType contentType,
  }) async {
    if (imageBytes.length > maxImageBytes) {
      throw DiagnosisApiException(413, '画像サイズは5MB以内にしてください。');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/diagnose'),
    )
      ..headers['X-App-Key'] = appKey
      ..fields['structure'] = structure
      ..fields['floor_no'] = floorNo.toString()
      ..fields['base_isolated'] = baseIsolated.toString()
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: filename,
          contentType: contentType,
        ),
      );

    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);

    Map<String, dynamic> body;
    final rawBody = response.body.trim();
    if (rawBody.isEmpty) {
      throw DiagnosisApiException(
        response.statusCode,
        'サーバーから空の応答が返りました（${response.statusCode}）。',
      );
    }

    try {
      body = jsonDecode(rawBody) as Map<String, dynamic>;
    } catch (_) {
      throw DiagnosisApiException(
        response.statusCode,
        'サーバー応答の解析に失敗しました（${response.statusCode}）。',
      );
    }

    if (response.statusCode == 200 || response.statusCode == 502) {
      return body;
    }

    throw DiagnosisApiException(
      response.statusCode,
      _messageForStatusCode(response.statusCode, body),
    );
  }

  String _messageForStatusCode(int statusCode, Map<String, dynamic> body) {
    final apiMessage = body['message'];
    if (apiMessage is String && apiMessage.isNotEmpty) {
      return apiMessage;
    }

    return switch (statusCode) {
      401 => 'アプリキーが一致しません。接続設定を確認してください。',
      413 => '画像サイズは5MB以内にしてください。',
      429 => 'リクエストが多すぎます。しばらく待ってから再試行してください。',
      _ => '診断APIの呼び出しに失敗しました（$statusCode）。',
    };
  }
}
