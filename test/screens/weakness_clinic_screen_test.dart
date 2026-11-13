import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';

void main() {
  testWidgets('loading analysis has a contextual accessible label', (
    tester,
  ) async {
    final pending = Completer<ProgressSnapshot>();
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () => pending.future)),
    );

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังวิเคราะห์คำที่ควรฝึก',
    );
    pending.complete(_emptySnapshot);
    await tester.pumpAndSettle();
  });

  testWidgets('practice batch keeps the top 20 weakness ranks', (tester) async {
    final ranked = List.generate(
      21,
      (i) => WeaknessEvidence(
        wordId: 'word-${21 - i}',
        spelling: 'synthetic$i',
        meaning: 'คำสังเคราะห์',
        sampleSize: 100,
        incorrectCount: 99 - i,
        errorRate: (99 - i) / 100,
        dueAtUtc: null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          loader: () async => ProgressSnapshot(
            sampleSize: 100,
            correctCount: 1,
            wrongCount: 99,
            accuracy: 0.01,
            totalXp: 0,
            completedSessions: 1,
            streakDays: 0,
            dueReviewCount: 0,
            masteredWordCount: 0,
            achievementCount: 0,
            gameLevel: 1,
            skills: [],
            weaknesses: ranked,
            recommendations: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ฝึกคำที่ผิด (20)'), findsOneWidget);
    await tester.tap(find.text('ฝึกคำที่ผิด (20)'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<QuizScreen>(find.byType(QuizScreen)).wordIds,
      ranked.take(20).map((item) => item.wordId).toList(),
    );
  });

  testWidgets(
    'weakness practice stays available before the next SRS due date',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WeaknessClinicScreen(
            loader: () async => ProgressSnapshot(
              sampleSize: 3,
              correctCount: 1,
              wrongCount: 2,
              accuracy: 1 / 3,
              totalXp: 1,
              completedSessions: 1,
              streakDays: 1,
              dueReviewCount: 0,
              masteredWordCount: 0,
              achievementCount: 0,
              gameLevel: 1,
              skills: [],
              weaknesses: _snapshot.weaknesses,
              recommendations: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ฝึกคำที่ผิด (1)'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)'),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('ยังไม่มีคำที่ถึงกำหนดทบทวน'), findsOneWidget);
    },
  );

  testWidgets('displays weaknesses derived from attempt evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ฝึกจุดอ่อน'), findsOneWidget);
    expect(
      find.text('จัดอันดับจากสัดส่วนคำตอบผิด จาก 3 คำตอบที่บันทึกไว้'),
      findsOneWidget,
    );
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.textContaining('ตอบผิด 2/3 ครั้ง'), findsOneWidget);
    expect(find.text('ทบทวนคำที่ถึงกำหนด (1)'), findsOneWidget);
  });

  testWidgets('does not bypass hidden quiz and review features', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          loader: () async => _snapshot,
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.weakness: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ฝึกคำที่ผิด (1)'), findsNothing);
    expect(find.text('ทบทวนคำที่ถึงกำหนด (1)'), findsNothing);
    expect(find.text('เปิดแบบฝึกที่รองรับจากหน้าเรียน'), findsOneWidget);
  });

  testWidgets('new account shows sample size zero instead of sample words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(loader: () async => _emptySnapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);
    expect(find.text('ephemeral'), findsNothing);
  });

  testWidgets('retry recovers one failed progress read', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(
          loader: () async {
            if (calls++ == 0) throw StateError('synthetic failure');
            return _snapshot;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.text('อ่านข้อมูลจุดอ่อนไม่สำเร็จ'),
              matching: find.byType(Semantics),
            ),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );

    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('ephemeral'), findsOneWidget);
  });

  testWidgets('keeps one primary action and reflows at 200 percent text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WeaknessClinicScreen(loader: () async => _snapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'ทบทวนคำที่ถึงกำหนด (1)'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsOneWidget);
    final title = tester.renderObject<RenderParagraph>(find.text('ฝึกจุดอ่อน'));
    expect(title.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}

const _snapshot = ProgressSnapshot(
  sampleSize: 3,
  correctCount: 1,
  wrongCount: 2,
  accuracy: 1 / 3,
  totalXp: 1,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 1,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'ephemeral',
      meaning: 'ชั่วคราว',
      sampleSize: 3,
      incorrectCount: 2,
      errorRate: 2 / 3,
      dueAtUtc: null,
    ),
  ],
  recommendations: [],
);

const _emptySnapshot = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
