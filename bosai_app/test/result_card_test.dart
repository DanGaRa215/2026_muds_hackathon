import 'package:bosai_app/widgets/diagnosis_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _resultWithDisplay({
  bool referenceOnly = true,
}) {
  return {
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
      'level': 'mid',
      'type': 'topple',
      'base_level': 'high',
      'modifiers': [
        {
          'factor': 'track_physics',
          'shift': 0,
          'label': '想定震度6弱の床応答200galが、本棚の転倒限界174galを上回っています',
        },
      ],
    },
    'display': {
      'title': '本棚',
      'headline': '転倒リスク：中',
      'summary': '揺れの条件によっては、本棚が倒れる可能性があります。',
      'reason_chain': [
        '想定震度6弱の床応答200galが、本棚の転倒限界174galを上回っています',
      ],
      'badge': {'level': 'mid', 'label': '中', 'shape': 'diamond'},
    },
    'warnings': ['recheck_after_quakes'],
    'suggestions': [
      {
        'action': 'add_second_brace',
        'text': '異種の固定具を併用すると、さらに大幅に低減できます（参考値）。',
        'source': 'TFD-M',
        'priority': 30,
      },
    ],
    'reference_only': referenceOnly,
  };
}

Map<String, dynamic> _legacyResultWithoutDisplay() {
  return {
    'furniture': {
      'class': 'furniture_bookshelf',
      'confidence': 0.91,
      'bbox': null,
      'profile': null,
    },
    'braces': [],
    'risk': {
      'level': 'mid',
      'type': 'topple',
      'base_level': 'high',
      'modifiers': [],
    },
    'warnings': [],
    'suggestions': [],
    'reference_only': false,
  };
}

Map<String, dynamic> _outOfScopeResult() {
  return {
    'furniture': {
      'class': 'furniture_other',
      'confidence': 0.75,
      'bbox': null,
      'profile': null,
    },
    'braces': [],
    'risk': null,
    'out_of_scope': true,
    'display': {
      'title': 'その他の家具（判定対象外）',
      'headline': '判定対象外',
      'summary': 'この家具は判定に必要な基準値がないため、リスクを算出していません。',
      'reason_chain': [],
      'badge': {'level': 'low', 'label': '対象外', 'shape': 'circle'},
    },
    'warnings': [],
    'suggestions': [
      {
        'action': 'out_of_scope_note',
        'text': 'この家具は判定対象外です。背の高い家具は上部を壁に固定してください。',
        'source': 'DESIGN',
        'priority': 15,
      },
    ],
    'reference_only': true,
  };
}

void main() {
  testWidgets('display があれば headline / summary が表示される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _resultWithDisplay()),
        ),
      ),
    );

    expect(find.text('転倒リスク：中'), findsOneWidget);
    expect(find.textContaining('倒れる可能性'), findsOneWidget);
  });

  testWidgets('bbox があってもテキスト bbox が画面に現れない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _resultWithDisplay()),
        ),
      ),
    );

    expect(find.textContaining('bbox'), findsNothing);
  });

  testWidgets('risk == null（furniture_other）でクラッシュしない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _outOfScopeResult()),
        ),
      ),
    );

    expect(find.text('判定対象外'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display 欠落時でも辞書フォールバックでカードが描画される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _legacyResultWithoutDisplay()),
        ),
      ),
    );

    expect(find.text('本棚'), findsOneWidget);
    expect(find.textContaining('倒れる可能性'), findsNothing);
  });

  testWidgets('reference_only の値に関わらず参考値ラベルが表示される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _resultWithDisplay(referenceOnly: false)),
        ),
      ),
    );

    expect(find.text('参考値'), findsOneWidget);
  });

  testWidgets('suggestions text と source タグが表示される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _resultWithDisplay()),
        ),
      ),
    );

    expect(find.textContaining('異種の固定具を併用'), findsOneWidget);
    expect(find.text('TFD-M'), findsOneWidget);
  });

  testWidgets('retake no_furniture で再撮影案内とボタンが出る', (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisRetakeCard(
            payload: const {
              'status': 'retake',
              'reason': 'no_furniture',
              'message': '家具全体が写るように撮影してください。',
            },
            isLoading: false,
            onRetry: () => retried = true,
            onPickImage: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('家具全体が写るように撮影してください'), findsOneWidget);
    await tester.tap(find.text('再撮影'));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('unknowns が画面内に1回だけ現れる', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiagnosisUnknownsCard(
            unknowns: ['収納物の重さ・重心', '壁・天井の下地強度'],
          ),
        ),
      ),
    );

    expect(find.text('この診断でわからないこと'), findsOneWidget);
  });

  testWidgets('results が3件でもカードは1枚だけ描画される', (tester) async {
    final payload = {
      'primary_index': 0,
      'results': [
        _resultWithDisplay(),
        _resultWithDisplay(),
        _resultWithDisplay(),
      ],
    };
    final primary = selectPrimaryResult(payload)!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: primary),
        ),
      ),
    );

    expect(find.byType(DiagnosisResultCard), findsOneWidget);
    expect(find.text('転倒リスク：中'), findsOneWidget);
  });

  testWidgets('複数検出時の補足テキストが1行だけ出る', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text(
            '他に 2件の家具を検出しました（最もリスクの高いものを表示しています）',
          ),
        ),
      ),
    );

    expect(
      find.textContaining('他に 2件の家具を検出しました'),
      findsOneWidget,
    );
  });

  testWidgets('primary_index 欠落時に先頭結果へフォールバックする', (tester) async {
    final payload = {
      'results': [
        {
          ..._resultWithDisplay(),
          'display': {
            'title': '先頭家具',
            'headline': '転倒リスク：中',
            'summary': '先頭の家具です。',
            'reason_chain': [],
            'badge': {'level': 'mid', 'label': '中', 'shape': 'diamond'},
          },
        },
        _resultWithDisplay(),
      ],
    };

    final primary = selectPrimaryResult(payload)!;
    expect(primary['display']['title'], '先頭家具');
  });

  testWidgets('参考にした調査・基準値セクションが表示される', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisSourcesCard(
            sources: [
              {
                'id': 'NILIM',
                'title': '国土技術政策総合研究所「什器の転倒・滑動・落下」評価法',
                'summary': '家具の種類ごとに、倒れ始める揺れの強さ（ガル）を実験から求めたデータです。',
              },
            ],
          ),
        ),
      ),
    );

    expect(find.text('参考にした調査・基準値'), findsOneWidget);
  });

  testWidgets('sources 欠落時もフォールバック辞書でセクションが描画される', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiagnosisSourcesCard(sources: []),
        ),
      ),
    );

    expect(find.text('参考にした調査・基準値'), findsOneWidget);
    await tester.tap(find.text('参考にした調査・基準値'));
    await tester.pumpAndSettle();
    expect(find.textContaining('気象庁'), findsOneWidget);
  });

  testWidgets('結果カードに絵文字が現れない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultCard(result: _resultWithDisplay()),
        ),
      ),
    );

    expect(find.textContaining('💡'), findsNothing);
    expect(find.textContaining('⚠'), findsNothing);
    expect(find.textContaining('🔧'), findsNothing);
  });
}
