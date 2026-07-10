import 'dart:convert';

import 'package:bosai_app/models/diagnosis.dart';
import 'package:bosai_app/screens/history_detail_screen.dart';
import 'package:bosai_app/screens/history_screen.dart';
import 'package:bosai_app/widgets/diagnosis_result_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _samplePayload() {
  return {
    'status': 'ok',
    'primary_index': 0,
    'results': [
      {
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
          'base_level': 'mid',
          'modifiers': [],
        },
        'display': {
          'title': '本棚',
          'headline': '転倒リスク：中',
          'summary': '揺れの条件によっては、本棚が倒れる可能性があります。',
          'reason_chain': ['テスト用の判定理由'],
          'badge': {'level': 'mid', 'label': '中', 'shape': 'diamond'},
        },
        'warnings': [],
        'suggestions': [],
        'reference_only': true,
      },
    ],
    'unknowns': ['収納物の重さ・重心'],
    'sources': [
      {
        'id': 'NILIM',
        'title': '国土技術政策総合研究所',
        'summary': 'テスト用ソース',
      },
    ],
  };
}

Diagnosis _diagnosisWithPayload() {
  return Diagnosis(
    id: 1,
    createdAt: '2026-07-11T10:00:00.000',
    riskLevel: '注意',
    intensity: '震度6弱',
    fixations: '木造',
    comment: 'テストコメント',
    payloadJson: jsonEncode(_samplePayload()),
  );
}

Diagnosis _legacyDiagnosis() {
  return const Diagnosis(
    id: 2,
    createdAt: '2026-06-01T10:00:00.000',
    riskLevel: '注意',
    intensity: '震度6弱',
    fixations: '木造',
    comment: '旧履歴のコメント',
  );
}

void main() {
  testWidgets('DiagnosisResultPanel shows display headline from payload', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosisResultPanel(payload: _samplePayload()),
        ),
      ),
    );

    expect(find.text('転倒リスク：中'), findsOneWidget);
    expect(find.text('この診断でわからないこと'), findsOneWidget);
  });

  testWidgets('HistoryDetailScreen shows payload detail headline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryDetailScreen(diagnosis: _diagnosisWithPayload()),
      ),
    );

    expect(find.text('診断詳細'), findsOneWidget);
    expect(find.text('2026-07-11'), findsOneWidget);
    expect(find.text('転倒リスク：中'), findsOneWidget);
  });

  testWidgets('HistoryDetailScreen shows legacy fallback note', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryDetailScreen(diagnosis: _legacyDiagnosis()),
      ),
    );

    expect(find.text('詳細データは保存されていません。'), findsOneWidget);
    expect(find.text('旧履歴のコメント'), findsOneWidget);
    expect(find.text('転倒リスク：中'), findsNothing);
  });

  testWidgets('HistoryScreen navigates to detail on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          diagnosesFuture: Future.value([_diagnosisWithPayload()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('注意（2026-07-11）'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryDetailScreen), findsOneWidget);
    expect(find.text('転倒リスク：中'), findsOneWidget);
  });
}
