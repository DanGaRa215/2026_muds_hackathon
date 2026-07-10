import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/diagnosis.dart';
import '../services/diagnosis_api_client.dart';
import '../utils/detection_editor.dart';
import '../widgets/detection_confirm_card.dart';
import '../widgets/diagnosis_result_card.dart';

enum _DiagnosisPhase {
  idle,
  detecting,
  confirmDetection,
  diagnosing,
  result,
  retake,
  apiError,
}

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
  _DiagnosisPhase _phase = _DiagnosisPhase.idle;
  Map<String, dynamic>? _detection;
  Map<String, dynamic>? _editedDetection;
  int _selectedFurnitureIndex = 0;
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
          _resetFlowState();
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

  bool get _isLoading =>
      _phase == _DiagnosisPhase.detecting || _phase == _DiagnosisPhase.diagnosing;

  void _resetFlowState() {
    _phase = _DiagnosisPhase.idle;
    _detection = null;
    _editedDetection = null;
    _selectedFurnitureIndex = 0;
    _payload = null;
    _statusMessage = null;
  }

  Future<void> _runDiagnosis() async {
    if (_image == null && _demoMode == _DemoMode.auto) {
      setState(() {
        _phase = _DiagnosisPhase.retake;
        _payload = _buildRetakePayload(
          reason: 'no_furniture',
          message: '家具全体が写るように撮影してください。',
        );
        _statusMessage = _statusMessageFor(_payload!);
      });
      return;
    }

    setState(() {
      _phase = _DiagnosisPhase.detecting;
      _statusMessage = null;
      _payload = null;
      _detection = null;
      _editedDetection = null;
    });

    try {
      if (_demoMode != _DemoMode.auto) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (_demoMode == _DemoMode.apiError) {
          _setApiError('Vision応答不正です。もう一度お試しください。', 502);
          return;
        }
        final detectResult = _buildDetectPayload();
        _applyDetectResult(detectResult);
        return;
      }

      if (_hasApiConfig) {
        final detectResult = await _detectWithApi();
        _applyDetectResult(detectResult);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 800));
      _applyDetectResult(_buildDetectionPayload());
    } on DiagnosisApiException catch (e) {
      _setApiError(e.message, e.statusCode);
    } catch (_) {
      _setApiError('通信環境の良い場所で再試行してください。避難機能には影響ありません。', 0);
    }
  }

  void _applyDetectResult(Map<String, dynamic> detectResult) {
    if (!mounted) return;

    if (detectResult['status'] == 'retake') {
      setState(() {
        _phase = _DiagnosisPhase.retake;
        _payload = detectResult;
        _statusMessage = _statusMessageFor(detectResult);
      });
      return;
    }

    final detection = detectResult['detection'] as Map<String, dynamic>;
    final edited = DetectionEditor.deepCopy(detection);
    final furniture = edited['furniture'] as List<dynamic>;

    setState(() {
      _phase = _DiagnosisPhase.confirmDetection;
      _detection = detection;
      _editedDetection = edited;
      _selectedFurnitureIndex = DetectionEditor.initialSelectedIndex(furniture);
      _statusMessage = null;
      _payload = null;
    });
  }

  void _setApiError(String message, int code) {
    if (!mounted) return;
    setState(() {
      _phase = _DiagnosisPhase.apiError;
      _payload = {
        'status': 'api_error',
        'code': code,
        'message': message,
      };
      _statusMessage = message;
    });
  }

  Future<void> _confirmAndDiagnose() async {
    if (_editedDetection == null) return;

    setState(() => _phase = _DiagnosisPhase.diagnosing);

    final submission = DetectionEditor.buildSubmissionDetection(
      _editedDetection!,
      _selectedFurnitureIndex,
    );

    try {
      Map<String, dynamic> payload;
      if (_hasApiConfig && _demoMode == _DemoMode.auto) {
        final client = DiagnosisApiClient(_apiBaseUrl, _appKey);
        payload = await client.diagnoseFromDetection(
          detection: submission,
          structure: _structure,
          floorNo: _floorNo,
          baseIsolated: _baseIsolated,
        );
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        // デモでは編集内容を結果に反映しない固定JSONを返す（審査員デモ用）
        payload = _buildOkPayload();
      }

      if (!mounted) return;
      setState(() {
        _phase = _DiagnosisPhase.result;
        _payload = payload;
        _statusMessage = _statusMessageFor(payload);
      });

      if (payload['status'] == 'ok') {
        await _saveHistory(payload);
      }
    } on DiagnosisApiException catch (e) {
      _setApiError(e.message, e.statusCode);
    } catch (_) {
      _setApiError('通信環境の良い場所で再試行してください。避難機能には影響ありません。', 0);
    }
  }

  Future<Map<String, dynamic>> _detectWithApi() async {
    final imageBytes = await _image!.readAsBytes();
    final imageMeta = _imageMetaFor(_image!);
    final client = DiagnosisApiClient(_apiBaseUrl, _appKey);
    return client.detect(
      imageBytes: imageBytes,
      filename: imageMeta.filename,
      contentType: imageMeta.contentType,
    );
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

  Map<String, dynamic> _buildDetectPayload() {
    switch (_demoMode) {
      case _DemoMode.ok:
        return {'status': 'ok', 'detection': _buildDetectionPayload()};
      case _DemoMode.retakeNoFurniture:
        return {'status': 'retake', 'reason': 'no_furniture'};
      case _DemoMode.retakeNothingDetected:
        return {'status': 'retake', 'reason': 'nothing_detected'};
      case _DemoMode.retakeBraceOnly:
        return {'status': 'retake', 'reason': 'brace_only'};
      case _DemoMode.apiError:
        return {'status': 'retake', 'reason': 'nothing_detected'};
      case _DemoMode.auto:
        return {'status': 'ok', 'detection': _buildDetectionPayload()};
    }
  }

  Map<String, dynamic> _buildDetectionPayload() {
    return {
      'furniture': [
        {
          'class': 'furniture_cupboard',
          'confidence': 0.92,
          'bbox': [0.1, 0.05, 0.4, 0.8],
          'profile': null,
          'braces': [
            {
              'class': 'brace_l_bracket',
              'confidence': 0.78,
              'install_quality': 'correct',
              'bbox': [0.18, 0.09, 0.05, 0.04],
            },
          ],
        },
        {
          'class': 'furniture_bookshelf',
          'confidence': 0.61,
          'bbox': null,
          'profile': null,
          'braces': [],
        },
      ],
      'image_issues': [],
    };
  }

  Map<String, dynamic> _buildPayload() {
    return _buildOkPayload();
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

  String _primaryActionLabel() => switch (_phase) {
        _DiagnosisPhase.detecting => '写真を解析しています…',
        _DiagnosisPhase.diagnosing => 'リスクを計算しています…',
        _ => '診断する',
      };

  String _phaseLabel() => switch (_phase) {
        _DiagnosisPhase.idle => '待機',
        _DiagnosisPhase.detecting => '解析中',
        _DiagnosisPhase.confirmDetection => '確認',
        _DiagnosisPhase.diagnosing => '判定中',
        _DiagnosisPhase.result => '結果',
        _DiagnosisPhase.retake => '再撮影',
        _DiagnosisPhase.apiError => 'エラー',
      };

  bool get _showPrimaryButton =>
      _phase == _DiagnosisPhase.idle ||
      _phase == _DiagnosisPhase.detecting ||
      _phase == _DiagnosisPhase.diagnosing ||
      _phase == _DiagnosisPhase.result ||
      _phase == _DiagnosisPhase.retake ||
      _phase == _DiagnosisPhase.apiError;

  @override
  Widget build(BuildContext context) {
    // 💡 テーマ設定（ライト/ダーク）を動的にキャッチ
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 🎨 モードに応じてカラーパレットを切り替え
    final currentBgColor = isDark ? theme.colorScheme.background : const Color(0xFFF5F0E8);
    final currentTextColor = isDark ? theme.colorScheme.onBackground : const Color(0xFF300808);

    final payload = _payload;

    return Scaffold(
      backgroundColor: currentBgColor,
      appBar: AppBar(
        title: const Text('AI家具安全診断'),
        backgroundColor: currentBgColor,
        foregroundColor: currentTextColor,
        elevation: 0,
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
              if (_showPrimaryButton) ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? theme.colorScheme.primary : const Color(0xFF300808),
                    foregroundColor:
                        isDark ? theme.colorScheme.onPrimary : Colors.white,
                  ),
                  onPressed: _isLoading ? null : _runDiagnosis,
                  child: Text(_primaryActionLabel()),
                ),
              ],
              if (_phase == _DiagnosisPhase.confirmDetection &&
                  _editedDetection != null) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: '検出結果の確認',
                  subtitle: '修正後にリスク判定へ進みます。',
                  child: DetectionConfirmCard(
                    editedDetection: _editedDetection!,
                    selectedFurnitureIndex: _selectedFurnitureIndex,
                    isSubmitting: _isLoading,
                    onSelectedFurnitureIndexChanged: (index) {
                      setState(() => _selectedFurnitureIndex = index);
                    },
                    onFurnitureClassChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        final item = DetectionEditor.selectedFurnitureItem(
                          _editedDetection!,
                          _selectedFurnitureIndex,
                        );
                        item['class'] = value;
                      });
                    },
                    onWardrobeProfileChanged: (value) {
                      setState(() {
                        final item = DetectionEditor.selectedFurnitureItem(
                          _editedDetection!,
                          _selectedFurnitureIndex,
                        );
                        item['profile'] = value;
                      });
                    },
                    onBraceToggled: (braceClass, enabled) {
                      setState(() {
                        final item = DetectionEditor.selectedFurnitureItem(
                          _editedDetection!,
                          _selectedFurnitureIndex,
                        );
                        DetectionEditor.setBraceEnabled(item, braceClass, enabled);
                      });
                    },
                    onRetake: () {
                      setState(_resetFlowState);
                      _pickImage(ImageSource.gallery);
                    },
                    onConfirm: _confirmAndDiagnose,
                  ),
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                _buildStatusBanner(_statusMessage!, payload),
              ],
              if (_payload != null &&
                  (_phase == _DiagnosisPhase.result ||
                      _phase == _DiagnosisPhase.retake ||
                      _phase == _DiagnosisPhase.apiError)) ...[
                const SizedBox(height: 12),
                _buildResultArea(payload),
              ],
              const SizedBox(height: 12),
              _buildEnvNote(),
              const SizedBox(height: 12),
              Text(
                'これはあくまでAIの提案です。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? theme.colorScheme.onBackground.withOpacity(0.7) : const Color(0xFF5A463C),
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
              color: Colors.white.withOpacity(0.88),
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
              _Pill(label: '状態: ${_phaseLabel()}'),
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08)),
              ),
              child: const Text('ここに選択した画像が表示されます'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    final theme = Theme.of(context);
    return _SectionCard(
      title: '補助入力',
      subtitle: '建物情報はUIで補助的に入力します。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _structure,
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
            value: _floorNo,
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
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.62)),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.28)),
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
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('戻る'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('ホームへ戻る'),
        ),
      ],
    );
  }

  Widget _buildRetakeOrErrorCard(Map<String, dynamic> payload) {
    return DiagnosisRetakeCard(
      payload: payload,
      isLoading: _isLoading,
      onRetry: () {
        setState(_resetFlowState);
        _runDiagnosis();
      },
      onPickImage: () {
        setState(_resetFlowState);
        _pickImage(ImageSource.gallery);
      },
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
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55), fontSize: 12),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, // 白固定からテーマのサーフェス色へ
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.62)),
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
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}