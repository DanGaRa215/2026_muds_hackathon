import 'package:bosai_app/utils/detection_editor.dart';
import 'package:bosai_app/widgets/detection_confirm_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sampleDetection() {
  return {
    'furniture': [
      {
        'class': 'furniture_cupboard',
        'confidence': 0.92,
        'bbox': null,
        'profile': null,
        'braces': [
          {
            'class': 'brace_l_bracket',
            'confidence': 0.78,
            'install_quality': 'correct',
            'bbox': null,
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

Widget _wrapConfirmCard(DetectionConfirmCard card) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: card),
    ),
  );
}

DetectionConfirmCard _buildCard({
  void Function(int index)? onSelect,
  void Function(String? value)? onClass,
  void Function(String? value)? onProfile,
  void Function(String brace, bool enabled)? onBrace,
  VoidCallback? onRetake,
  VoidCallback? onConfirm,
}) {
  return DetectionConfirmCard(
    editedDetection: DetectionEditor.deepCopy(_sampleDetection()),
    selectedFurnitureIndex: 0,
    isSubmitting: false,
    onSelectedFurnitureIndexChanged: onSelect ?? (_) {},
    onFurnitureClassChanged: onClass ?? (_) {},
    onWardrobeProfileChanged: onProfile ?? (_) {},
    onBraceToggled: onBrace ?? (_, __) {},
    onRetake: onRetake ?? () {},
    onConfirm: onConfirm ?? () {},
  );
}

void main() {
  test('固定具ONで unverified が追加される', () {
    final edited = DetectionEditor.deepCopy(_sampleDetection());
    final item = DetectionEditor.selectedFurnitureItem(edited, 0);
    DetectionEditor.setBraceEnabled(item, 'brace_mat', true);

    final braces = item['braces'] as List<dynamic>;
    final mat = braces.cast<Map<String, dynamic>>().firstWhere(
          (b) => b['class'] == 'brace_mat',
        );
    expect(mat['install_quality'], 'unverified');
    expect(mat['confidence'], 1.0);
  });

  test('固定具OFFで braces から除去される', () {
    final edited = DetectionEditor.deepCopy(_sampleDetection());
    final item = DetectionEditor.selectedFurnitureItem(edited, 0);
    DetectionEditor.setBraceEnabled(item, 'brace_l_bracket', false);

    final braces = (item['braces'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(braces.any((b) => b['class'] == 'brace_l_bracket'), isFalse);
  });

  test('Vision検出の correct は維持される', () {
    final edited = DetectionEditor.deepCopy(_sampleDetection());
    final item = DetectionEditor.selectedFurnitureItem(edited, 0);
    final braces = (item['braces'] as List<dynamic>).cast<Map<String, dynamic>>();
    final bracket = braces.firstWhere((b) => b['class'] == 'brace_l_bracket');
    expect(bracket['install_quality'], 'correct');
  });

  test('選択家具1件だけが submission になる', () {
    final edited = DetectionEditor.deepCopy(_sampleDetection());
    final submission = DetectionEditor.buildSubmissionDetection(edited, 1);
    expect(submission['furniture'], hasLength(1));
    expect(
      (submission['furniture'] as List).first['class'],
      'furniture_bookshelf',
    );
  });

  test('deepCopy は元 detection を変更しない', () {
    final original = _sampleDetection();
    final edited = DetectionEditor.deepCopy(original);
    final item = DetectionEditor.selectedFurnitureItem(edited, 0);
    DetectionEditor.setBraceEnabled(item, 'brace_mat', true);

    final originalBraces =
        (original['furniture'] as List).first['braces'] as List<dynamic>;
    expect(originalBraces, hasLength(1));
  });

  testWidgets('確認画面に結果カード用ヘッドラインがまだ出ない', (tester) async {
    await tester.pumpWidget(_wrapConfirmCard(_buildCard()));

    expect(find.textContaining('転倒リスク'), findsNothing);
    expect(find.text('この内容で判定する'), findsOneWidget);
  });

  testWidgets('家具2件でラジオが表示される', (tester) async {
    await tester.pumpWidget(_wrapConfirmCard(_buildCard()));

    expect(find.text('診断する家具を選んでください'), findsOneWidget);
    expect(find.byType(RadioListTile<int>), findsNWidgets(2));
  });

  testWidgets('確認画面に絵文字がない', (tester) async {
    await tester.pumpWidget(_wrapConfirmCard(_buildCard()));

    expect(find.textContaining('💡'), findsNothing);
    expect(find.textContaining('⚠'), findsNothing);
    expect(find.textContaining('🔧'), findsNothing);
  });

  testWidgets('未確認固定具の注記が表示される', (tester) async {
    await tester.pumpWidget(_wrapConfirmCard(_buildCard()));

    expect(
      find.textContaining('写真で確認できなかった固定具は'),
      findsOneWidget,
    );
  });
}
