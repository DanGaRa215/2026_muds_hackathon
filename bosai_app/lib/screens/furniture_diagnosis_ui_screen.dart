import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/diagnosis.dart';
import '../services/diagnosis_api_client.dart';
import '../widgets/diagnosis_result_card.dart';

enum _DemoMode {
  auto,
  ok,
  retakeNoFurniture,
  retakeNothingDetected,
  retakeBraceOnly,
  apiError,
}

class FurnitureDiagnosisUiScreen extends StatefulWidget {
  const FurnitureDiagnosisUiScreen({super.key});

  @override
  State<FurnitureDiagnosisUiScreen> createState() => _FurnitureDiagnosisUiScreenState();
}

class _FurnitureDiagnosisUiScreenState extends State<FurnitureDiagnosisUiScreen> {
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _appKey = String.fromEnvironment('APP_KEY');

  final ImagePicker _picker = ImagePicker();

  XFile? _image;
  bool _isLoading = false;
  Map<String, dynamic>? _payload;
  String? _statusMessage;

  static const String _fixedShindo = 's6weak';

  String _structure = 'wood';
  int _floorNo = 3;
  bool _baseIsolated = false;
  _DemoMode _demoMode = _DemoMode.auto;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image != null && mounted) {
        setState(() {
          _image = image;
          _payload = null;
          _statusMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '画像の選択に失敗しました: $e';
        });
      }
    }
  }

  bool get _hasApiConfig => _apiBaseUrl.isNotEmpty && _appKey.isNotEmpty;

  Future<void> _runDiagnosis() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _payload = null;
    });

    Map<String, dynamic> payload;

    try {
      if (_demoMode != _DemoMode.auto) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        payload = _buildPayload();
      } else if (_hasApiConfig) {
        payload = await _diagnoseWithApi();
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        payload = _buildPayload();
      }
    } on DiagnosisApiException catch (e) {
      payload = {
        'status': 'api_error',
        'code': e.statusCode,
        'message': e.message,
      };
    } catch (e) {
      payload = {
        'status': 'api_error',
        'message': '通信環境の良い場所で再試行してください。避難機能には影響ありません。',
      };
    }

    if (mounted) {
      setState(() {
        _payload = payload;
        _isLoading = false;
        _statusMessage = _statusMessageFor(payload);
      });
    }

    if (payload['status'] == 'ok') {
      await _saveHistory(payload);
    }
  }

  Future<Map<String, dynamic>> _diagnoseWithApi() async {
    if (_image == null) {
      return _buildRetakePayload(
        reason: 'no_furniture',
        message: '先に画像を選んでから診断してください。',
      );
    }

    try {
      final imageBytes = await _image!.readAsBytes();
      final imageMeta = _imageMetaFor(_image!);
      final client = DiagnosisApiClient(_apiBaseUrl, _appKey);

      return client.diagnose(
        imageBytes: imageBytes,
        structure: _structure,
        floorNo: _floorNo,
        baseIsolated: _baseIsolated,
        filename: imageMeta.filename,
        contentType: imageMeta.contentType,
      );
    } on DiagnosisApiException {
      rethrow;
    } catch (e) {
      throw DiagnosisApiException(
        0,
        '画像の読み込みまたは通信に失敗しました: $e',
      );
    }
  }

  ({String filename, MediaType contentType}) _imageMetaFor(XFile image) {
    final path = image.path.toLowerCase();
    final mimeType = image.mimeType?.toLowerCase();

    if (path.endsWith('.png') || mimeType == 'image/png') {
      return (
        filename: 'diagnosis.png',
        contentType: MediaType('image', 'png'),
      );
    }

    return (
      filename: 'diagnosis.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
  }

  Map<String, dynamic> _buildPayload() {
    switch (_demoMode) {
      case _DemoMode.ok:
        return _buildOkPayload();
      case _DemoMode.retakeNoFurniture:
        return _buildRetakePayload(
          reason: 'no_furniture',
          message: '家具全体が写るように撮影してください。',
        );
      case _DemoMode.retakeNothingDetected:
        return _buildRetakePayload(
          reason: 'nothing_detected',
          message: '検出できませんでした。明るい場所で全体を撮影してください。',
        );
      case _DemoMode.retakeBraceOnly:
        return _buildRetakePayload(
          reason: 'brace_only',
          message: '固定具だけが写っています。家具全体が写るように撮り直してください。',
        );
      case _DemoMode.apiError:
        return {
          'status': 'api_error',
          'code': 502,
          'message': 'Vision応答不正です。もう一度お試しください。',
        };
      case _DemoMode.auto:
        if (_image == null) {
          return _buildRetakePayload(
            reason: 'no_furniture',
            message: '家具全体が写るように撮影してください。',
          );
        }
        return _buildOkPayload();
    }
  }

  Map<String, dynamic> _buildOkPayload() {
    return {
      'status': 'ok',
      'primary_index': 0,
      'input': {
        'shindo': 's6weak',
        'soil': 'normal',
        'structure': _structure,
        'floor_no': _floorNo,
        'base_isolated': _baseIsolated,
      },
      'results': [
        {
          'furniture': {
            'class': 'furniture_cupboard',
            'confidence': 0.92,
            'bbox': [0.1, 0.05, 0.4, 0.8],
            'profile': null,
          },
          'braces': [],
          'risk': {
            'level': 'mid',
            'type': 'topple',
            'base_level': 'mid',
            'modifiers': [
              {
                'factor': 'track_physics',
                'shift': 0,
                'label':
                    '想定震度6弱のとき、床の揺れの強さは約200ガル（1ガル＝1cm/s²、気象庁換算）です。'
                    '食器棚が倒れ始める目安は約232ガル（国総研データ）。'
                    'まだ届いていませんが、安全側の余裕を見た基準値162.4ガル'
                    'を超えているため「中」と判定しました。',
              },
            ],
          },
          'display': {
            'title': '食器棚',
            'headline': '転倒リスク：中',
            'summary': '揺れの条件によっては、食器棚が倒れる可能性があります。',
            'reason_chain': [
              '想定震度6弱のとき、床の揺れの強さは約200ガル（1ガル＝1cm/s²、気象庁換算）です。'
                  '食器棚が倒れ始める目安は約232ガル（国総研データ）。'
                  'まだ届いていませんが、安全側の余裕を見た基準値162.4ガル'
                  'を超えているため「中」と判定しました。',
            ],
            'badge': {'level': 'mid', 'label': '中', 'shape': 'diamond'},
          },
          'warnings': ['recheck_after_quakes'],
          'reference_only': true,
          'suggestions': [
            {
              'action': 'add_l_bracket',
              'text': 'L字金具の設置を推奨。実調査では転倒率33.5%→8.9%（約1/4）に下がっています。',
              'source': 'TFD-H',
              'priority': 40,
            },
            {
              'action': 'stud_note',
              'text': '石膏ボードへの直接ビス止めは効きません。下地（間柱）を探して固定してください。',
              'source': 'DESIGN',
              'priority': 5,
            },
          ],
        },
      ],
      'unknowns': [
        '収納物の重さ・重心',
        '壁・天井の下地強度',
        '床材の滑りやすさ',
        '固定具の劣化・締め付け',
        '実際の揺れの周期・継続時間',
      ],
      'sources': [
        {
          'id': 'NILIM',
          'title': '国土技術政策総合研究所「什器の転倒・滑動・落下」評価法',
          'summary': '家具の種類ごとに、倒れ始める揺れの強さ（ガル）を実験から求めたデータです。',
        },
        {
          'id': 'JMA',
          'title': '気象庁 震度と加速度の換算',
          'summary': '想定した震度を、床の揺れの強さ（ガル）に変換する際に使っています。',
        },
        {
          'id': 'TFD-H',
          'title': '東京消防庁「熊本地震における家具等の転倒等の実態調査」戸建編',
          'summary':
              'L字金具で転倒率が33.5%から8.9%に低下（n=79）。耐震マット単独は39.7%（n=56）で効果が確認されていません。',
        },
      ],
    };
  }

  Map<String, dynamic> _buildRetakePayload({
    required String reason,
    required String message,
  }) {
    return {
      'status': 'retake',
      'reason': reason,
      'message': message,
      'unknowns': [
        '収納物の重さ・重心',
        '壁・天井の下地強度',
        '床材の滑りやすさ',
        '固定具の劣化・締め付け',
        '実際の揺れの周期・継続時間',
      ],
    };
  }

  Future<void> _saveHistory(Map<String, dynamic> payload) async {
    final primary = selectPrimaryResult(payload);
    if (primary == null) return;

    final risk = primary['risk'] as Map<String, dynamic>?;
    final display = primary['display'] as Map<String, dynamic>?;
    final suggestions = (primary['suggestions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final comment = suggestions.isNotEmpty
        ? suggestions.first['text'] as String
        : (display?['summary'] as String?) ??
            '${furnitureLabel(primary['furniture']['class'] as String)}の診断結果を保存しました';

    final level = risk?['level'] as String? ?? 'mid';

    await DatabaseHelper.instance.insertDiagnosis(
      Diagnosis(
        createdAt: DateTime.now().toIso8601String(),
        riskLevel: _historyRiskLabel(level),
        intensity: _shindoLabel(_fixedShindo),
        fixations: _structureLabel(_structure),
        comment: comment,
      ),
    );
  }

  String _statusMessageFor(Map<String, dynamic> payload) {
    switch (payload['status'] as String) {
      case 'ok':
        return '診断が完了しました。';
      case 'retake':
        return (payload['message'] as String?) ??
            _retakeMessageForReason(payload['reason'] as String?);
      case 'api_error':
        return (payload['message'] as String?) ?? 'もう一度お試しください。';
      default:
        return '結果を取得しました。';
    }
  }

  String _historyRiskLabel(String level) => switch (level) {
        'high' => '危険',
        'mid' => '注意',
        'low' => 'おおむね安全',
        _ => '注意',
      };

  String _shindoLabel(String value) => switch (value) {
        's5weak' => '震度5弱',
        's5strong' => '震度5強',
        's6weak' => '震度6弱',
        's6strong' => '震度6強',
        's7' => '震度7',
        _ => value,
      };

  String _structureLabel(String value) => switch (value) {
        'wood' => '木造',
        'rc' => 'RC',
        'steel' => '鉄骨',
        _ => value,
      };

  String _statusLabel(String status) => switch (status) {
        'ok' => '成功',
        'retake' => '再撮影',
        'api_error' => 'エラー',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final payload = _payload;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E8),
      appBar: AppBar(
        title: const Text('AI家具安全診断'),
        backgroundColor: const Color(0xFFF5F0E8),
        foregroundColor: const Color(0xFF300808),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroCard(),
              const SizedBox(height: 12),
              _buildImageSection(),
              const SizedBox(height: 12),
              _buildInputSection(),
              const SizedBox(height: 12),
              _buildDemoModeSection(),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _runDiagnosis,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(_isLoading ? '判定中（最大2分）...' : '診断する'),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                _buildStatusBanner(_statusMessage!, payload),
              ],
              if (payload != null) ...[
                const SizedBox(height: 12),
                _buildResultArea(payload),
              ],
              const SizedBox(height: 12),
              _buildEnvNote(),
              const SizedBox(height: 12),
              const Text(
                'これはあくまでAIの提案です。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A463C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _connectionPillLabel() {
    if (!_hasApiConfig) return 'デモJSON';
    if (_isLoading) return 'API通信中...';
    return switch (_payload?['status'] as String?) {
      'ok' => 'API診断成功',
      'retake' => 'API応答あり',
      'api_error' => 'APIエラー',
      _ => 'API設定済み',
    };
  }

  Widget _buildHeroCard() {
    final usingDemo = !_hasApiConfig;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2A39), Color(0xFF5C2D24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '家具1点ごとにリスクを可視化',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '画像・補助入力・状態分岐をまとめたUIです。判定根拠はバックエンドに寄せ、UIは結果の描画に専念します。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _Pill(label: '参考値表示'),
              _Pill(label: usingDemo ? 'デモJSON' : _connectionPillLabel()),
              _Pill(label: '状態: ${_statusLabel(_payload?['status'] as String? ?? '待機')}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return _SectionCard(
      title: '撮影 / 画像',
      subtitle: 'カメラ撮影またはギャラリー選択で画像を追加します。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('カメラで撮る'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('ギャラリーから選ぶ'),
              ),
            ],
          ),
          if (_image != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(_image!.path),
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: const Text('ここに選択した画像が表示されます'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return _SectionCard(
      title: '補助入力',
      subtitle: '建物情報はUIで補助的に入力します。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _structure,
            decoration: const InputDecoration(labelText: '建物構造'),
            items: const [
              DropdownMenuItem(value: 'wood', child: Text('木造')),
              DropdownMenuItem(value: 'rc', child: Text('RC')),
              DropdownMenuItem(value: 'steel', child: Text('鉄骨')),
            ],
            onChanged: (value) => setState(() => _structure = value ?? _structure),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _floorNo,
            decoration: const InputDecoration(labelText: '階数'),
            items: List.generate(
              20,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('${index + 1}階'),
              ),
            ),
            onChanged: (value) => setState(() => _floorNo = value ?? _floorNo),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _baseIsolated,
            title: const Text('免震'),
            subtitle: const Text('高層階では移動リスクの表示に反映します。'),
            onChanged: (value) => setState(() => _baseIsolated = value),
          ),
          const SizedBox(height: 8),
          Text(
            '表示値: ${_structureLabel(_structure)} / $_floorNo階 / 免震${_baseIsolated ? 'あり' : 'なし'}',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.62)),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoModeSection() {
    return _SectionCard(
      title: 'デモ結果モード',
      subtitle: 'Day1の先行開発用に、状態分岐をUI単体で確認できます。',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in {
            _DemoMode.auto: '自動',
            _DemoMode.ok: '成功',
            _DemoMode.retakeNoFurniture: '再撮影: 家具なし',
            _DemoMode.retakeNothingDetected: '再撮影: 未検出',
            _DemoMode.retakeBraceOnly: '再撮影: 固定具のみ',
            _DemoMode.apiError: 'APIエラー',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _demoMode == entry.key,
              onSelected: (_) => setState(() => _demoMode = entry.key),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String message, Map<String, dynamic>? payload) {
    final status = payload?['status'] as String? ?? 'unknown';
    final color = switch (status) {
      'ok' => Colors.green,
      'retake' => Colors.orange,
      'api_error' => Colors.red,
      _ => Colors.blueGrey,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status == 'ok'
                ? Icons.check_circle_outline
                : status == 'retake'
                    ? Icons.photo_camera_outlined
                    : Icons.cloud_off_outlined,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArea(Map<String, dynamic> payload) {
    final status = payload['status'] as String;

    if (status != 'ok') {
      return _SectionCard(
        title: '状態分岐',
        subtitle: 'status と reason に応じた再撮影/エラー表示です。',
        child: _buildRetakeOrErrorCard(payload),
      );
    }

    final results =
        (payload['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final unknowns = (payload['unknowns'] as List<dynamic>? ?? []).cast<String>();
    final sources =
        (payload['sources'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final primary = selectPrimaryResult(payload);
    final otherCount = results.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '診断結果',
          subtitle: '最もリスクの高い家具を1件表示しています。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primary != null) DiagnosisResultCard(result: primary),
              if (otherCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '他に $otherCount件の家具を検出しました（最もリスクの高いものを表示しています）',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.62),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        DiagnosisUnknownsCard(unknowns: unknowns),
        const SizedBox(height: 12),
        DiagnosisSourcesCard(sources: sources),
      ],
    );
  }

  Widget _buildRetakeOrErrorCard(Map<String, dynamic> payload) {
    return DiagnosisRetakeCard(
      payload: payload,
      isLoading: _isLoading,
      onRetry: _runDiagnosis,
      onPickImage: () => _pickImage(ImageSource.gallery),
    );
  }

  String _retakeMessageForReason(String? reason) => switch (reason) {
        'no_furniture' => '家具全体が写るように撮影してください。',
        'nothing_detected' => '検出できませんでした。明るい場所で全体を撮影してください。',
        'brace_only' => '固定具だけが写っています。家具全体が写るように撮り直してください。',
        _ => '家具全体が写るように撮り直してください。',
      };

  Widget _buildEnvNote() {
    final usingDemo = !_hasApiConfig;
    return Text(
      usingDemo
          ? '開発時は --dart-define=API_BASE_URL=... --dart-define=APP_KEY=... で接続情報を注入できます。'
          : '接続情報は dart-define から読み取っています。',
      style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 12),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: Colors.black.withValues(alpha: 0.62)),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
