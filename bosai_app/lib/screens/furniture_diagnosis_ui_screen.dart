import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/diagnosis.dart';
import '../services/diagnosis_api_client.dart';

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
        'message': '通信に失敗しました。ネットワークを確認してもう一度お試しください。',
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
    final tvRiskType = (_baseIsolated || _floorNo >= 8) ? 'slide' : 'topple';
    final tvRiskLevel = (_baseIsolated || _floorNo >= 8) ? 'low' : 'mid';

    return {
      'status': 'ok',
      'results': [
        {
          'furniture': {
            'class': 'furniture_bookshelf',
            'confidence': 0.91,
            'bbox': [0.12, 0.08, 0.30, 0.78],
            'profile': null,
          },
          'braces': [
            {
              'class': 'brace_l_bracket',
              'confidence': 0.78,
              'install_quality': 'correct',
              'bbox': [0.18, 0.09, 0.05, 0.04],
            },
          ],
          'risk': {
            'level': 'high',
            'type': 'topple',
            'base_level': 'high',
            'modifiers': [
              {'factor': 'fix_l_bracket_correct', 'shift': -1},
            ],
          },
          'warnings': ['recheck_after_quakes'],
          'reference_only': true,
          'suggestions': [
            {
              'text': 'L字金具の設置を推奨。実調査で転倒率33.5%→8.9%（約1/4）',
              'source': 'TFD-H',
            },
          ],
        },
        {
          'furniture': {
            'class': 'furniture_tv',
            'confidence': 0.85,
            'bbox': null,
            'profile': null,
          },
          'braces': [
            {
              'class': 'brace_mat',
              'confidence': 0.7,
              'install_quality': 'correct',
              'bbox': null,
            },
          ],
          'risk': {
            'level': tvRiskLevel,
            'type': tvRiskType,
            'base_level': 'high',
            'modifiers': [],
          },
          'warnings': [if (tvRiskType == 'slide') 'slide_on_high_floor' else 'recheck_after_quakes'],
          'reference_only': true,
          'suggestions': [
            {
              'text': '耐震マットは単独よりL字金具との併用が有効です。',
              'source': 'TFD-H',
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
    final results = payload['results'] as List<dynamic>;
    if (results.isEmpty) return;

    final first = results.first as Map<String, dynamic>;
    final risk = first['risk'] as Map<String, dynamic>;
    final suggestions = (first['suggestions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final comment = suggestions.isNotEmpty
        ? suggestions.first['text'] as String
        : '${_furnitureLabel(first['furniture']['class'] as String)}の診断結果を保存しました';

    await DatabaseHelper.instance.insertDiagnosis(
      Diagnosis(
        createdAt: DateTime.now().toIso8601String(),
        riskLevel: _historyRiskLabel(risk['level'] as String),
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

  String _furnitureLabel(String key) => switch (key) {
        'furniture_bookshelf' => '本棚',
        'furniture_wardrobe' => 'タンス',
        'furniture_cupboard' => '食器棚',
        'furniture_refrigerator' => '冷蔵庫',
        'furniture_tv' => 'テレビ（テレビ台含む）',
        'furniture_microwave_stand' => '電子レンジ台',
        'furniture_desk' => '机',
        'furniture_other' => 'その他の家具（判定対象外）',
        _ => key,
      };

  String _braceLabel(String key) => switch (key) {
        'brace_tension_rod' => '突っ張り棒',
        'brace_l_bracket' => 'L字金具',
        'brace_mat' => '耐震マット',
        'brace_belt' => 'ベルト・チェーン',
        'brace_stopper' => 'ストッパー・転倒防止板',
        _ => key,
      };

  String _qualityLabel(String key) => switch (key) {
        'correct' => '適切に設置',
        'loose' => '緩み・傾きあり（注意）',
        'wrong_position' => '取付位置が不適切（要見直し）',
        'unverified' => '写真では確認できず',
        _ => key,
      };

  String _warningLabel(String key) => switch (key) {
        'recheck_after_quakes' => '繰り返しの揺れで固定具は緩みます。震度4程度の地震の後は点検を。',
        'mat_ineffective_on_heavy' => '耐震マット単独は重い家具では効果が確認されていません。L字金具等の追加を推奨。',
        'slide_on_high_floor' => '高層階では家具が「移動」するリスクがあります。キャスターは固定を。',
        _ => key,
      };

  String _riskLevelLabel(String level) => switch (level) {
        'high' => '高',
        'mid' => '中',
        'low' => '低',
        _ => level,
      };

  String _historyRiskLabel(String level) => switch (level) {
        'high' => '危険',
        'mid' => '注意',
        'low' => 'おおむね安全',
        _ => '注意',
      };

  String _riskTypeLabel(String type) => switch (type) {
        'topple' => '転倒リスク',
        'slide' => '移動リスク',
        _ => type,
      };

  IconData _riskTypeIcon(String type) => switch (type) {
        'topple' => Icons.trending_up,
        'slide' => Icons.swap_horiz,
        _ => Icons.info_outline,
      };

  Color _riskColor(String level) => switch (level) {
        'high' => Colors.red.shade700,
        'mid' => Colors.orange.shade700,
        'low' => Colors.green.shade700,
        _ => Colors.grey.shade700,
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
        actions: [
          IconButton(
            tooltip: 'ホームへ戻る',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: '診断結果',
          subtitle: 'results は高リスク順に並んでいる前提です。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final result in results) ...[
                _ResultCard(
                  result: result,
                  furnitureLabel: _furnitureLabel,
                  braceLabel: _braceLabel,
                  qualityLabel: _qualityLabel,
                  warningLabel: _warningLabel,
                  riskLevelLabel: _riskLevelLabel,
                  riskTypeLabel: _riskTypeLabel,
                  riskTypeIcon: _riskTypeIcon,
                  riskColor: _riskColor,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _UnknownsCard(unknowns: unknowns),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('戻る'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          icon: const Icon(Icons.home_outlined),
          label: const Text('ホームへ戻る'),
        ),
      ],
    );
  }

  Widget _buildRetakeOrErrorCard(Map<String, dynamic> payload) {
    final status = payload['status'] as String;
    final color = switch (status) {
      'api_error' => Colors.red,
      _ => Colors.orange,
    };

    final title = switch (status) {
      'api_error' => 'APIエラー',
      _ => '再撮影が必要です',
    };

    final reason = payload['reason'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.refresh, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            (payload['message'] as String?) ?? _retakeMessageForReason(reason),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _isLoading ? null : _runDiagnosis,
                child: const Text('再試行'),
              ),
              OutlinedButton(
                onPressed: () => _pickImage(ImageSource.gallery),
                child: const Text('画像を選び直す'),
              ),
            ],
          ),
        ],
      ),
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

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.furnitureLabel,
    required this.braceLabel,
    required this.qualityLabel,
    required this.warningLabel,
    required this.riskLevelLabel,
    required this.riskTypeLabel,
    required this.riskTypeIcon,
    required this.riskColor,
  });

  final Map<String, dynamic> result;
  final String Function(String) furnitureLabel;
  final String Function(String) braceLabel;
  final String Function(String) qualityLabel;
  final String Function(String) warningLabel;
  final String Function(String) riskLevelLabel;
  final String Function(String) riskTypeLabel;
  final IconData Function(String) riskTypeIcon;
  final Color Function(String) riskColor;

  @override
  Widget build(BuildContext context) {
    final furniture = result['furniture'] as Map<String, dynamic>;
    final braces =
        (result['braces'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final risk = result['risk'] as Map<String, dynamic>;
    final warnings = (result['warnings'] as List<dynamic>? ?? []).cast<String>();
    final suggestions =
        (result['suggestions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final referenceOnly = result['reference_only'] as bool? ?? false;
    final bbox = furniture['bbox'];

    final level = risk['level'] as String;
    final color = riskColor(level);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      furnitureLabel(furniture['class'] as String),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '信頼度 ${(furniture['confidence'] as num).toDouble().toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              if (referenceOnly)
                const Chip(
                  label: Text('参考値'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RiskBadge(
                color: color,
                  icon: Icons.change_history,
                label: riskLevelLabel(level),
              ),
              _RiskBadge(
                color: Colors.black87,
                icon: riskTypeIcon(risk['type'] as String),
                label: riskTypeLabel(risk['type'] as String),
              ),
                if (bbox is List)
                  const _RiskBadge(
                  color: Colors.blueGrey,
                  icon: Icons.crop_free,
                  label: 'bboxあり',
                ),
            ],
          ),
          if (braces.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('固定具', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final brace in braces)
                  _SmallChip(
                    label: braceLabel(brace['class'] as String),
                    subLabel: qualityLabel(brace['install_quality'] as String),
                  ),
              ],
            ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('警告', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(warningLabel(warning))),
                  ],
                ),
              ),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('提案', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...suggestions.map(
              (suggestion) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(suggestion['text'] as String),
                          if ((suggestion['source'] as String?)?.isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                suggestion['source'] as String,
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (result['risk'] is Map<String, dynamic>) ...[
            const SizedBox(height: 8),
            Text(
              '対策前は ${risk['base_level'] as String} でした',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.52), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.subLabel});

  final String label;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subLabel, style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.58))),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _UnknownsCard extends StatelessWidget {
  const _UnknownsCard({required this.unknowns});

  final List<String> unknowns;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'この診断でわからないこと',
      subtitle: '参考値であることを必ず明示します。',
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          title: const Text('折りたたんで表示'),
          children: [
            ...unknowns.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.help_outline, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
