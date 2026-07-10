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

  /// POST /detect — Vision検出のみ。タイムアウト30秒 [DESIGN v2.4]
  Future<Map<String, dynamic>> detect({
    required List<int> imageBytes,
    required String filename,
    required MediaType contentType,
  }) async {
    if (imageBytes.length > maxImageBytes) {
      throw DiagnosisApiException(413, '画像サイズは5MB以内にしてください。');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/detect'),
    )
      ..headers['X-App-Key'] = appKey
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: filename,
          contentType: contentType,
        ),
      );

    // Vision LLM の推論時間を含む。モデル評価の REQUEST_TIMEOUT=30.0 と揃える [DESIGN v2.4]
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    return _parseResponse(streamed);
  }

  /// POST /diagnose — 編集済み detection JSON。タイムアウト15秒 [DESIGN]
  Future<Map<String, dynamic>> diagnoseFromDetection({
    required Map<String, dynamic> detection,
    required String structure,
    required int floorNo,
    required bool baseIsolated,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/diagnose'),
    )
      ..headers['X-App-Key'] = appKey
      ..fields['structure'] = structure
      ..fields['floor_no'] = floorNo.toString()
      ..fields['base_isolated'] = baseIsolated.toString()
      ..fields['detection'] = jsonEncode(detection);

    // ルールエンジンのみで数msのため既定値を維持 [DESIGN]
    final streamed = await request.send().timeout(const Duration(seconds: 15));
    return _parseResponse(streamed);
  }

  /// 画像入力の後方互換経路（回帰テスト・旧クライアント用）。
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
    return _parseResponse(streamed);
  }

  Future<Map<String, dynamic>> _parseResponse(http.StreamedResponse streamed) async {
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
    final apiMessage = body['message'] ?? body['detail'];
    if (apiMessage is String && apiMessage.isNotEmpty) {
      return apiMessage;
    }

    return switch (statusCode) {
      400 => '送信内容が不正です。もう一度お試しください。',
      401 => 'アプリキーが一致しません。接続設定を確認してください。',
      413 => '画像サイズは5MB以内にしてください。',
      429 => 'リクエストが多すぎます。しばらく待ってから再試行してください。',
      _ => '診断APIの呼び出しに失敗しました（$statusCode）。',
    };
  }
}
