import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  testWidgets('displays weaknesses derived from attempt evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('คลินิกจุดอ่อน'), findsOneWidget);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.textContaining('ตอบผิด 2/3 ครั้ง'), findsOneWidget);
    expect(find.text('ทบทวนคำที่ถึงกำหนด (1)'), findsOneWidget);
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

    expect(find.textContaining('จำนวนตัวอย่าง: 0'), findsOneWidget);
    expect(find.text('ephemeral'), findsNothing);
  });

  testWidgets('SRS launch fails closed when no feature authority exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    expect(find.byType(SrsFlashcardsScreen), findsNothing);
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
