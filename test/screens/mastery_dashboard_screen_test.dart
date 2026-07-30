import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';

void main() {
  testWidgets('renders evidence-backed streak, skills, and sample sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ภาพรวมการเรียน'), findsOneWidget);
    expect(find.text('7 วัน'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('จำนวนตัวอย่าง: 4'), findsOneWidget);
    expect(find.text('จำนวนตัวอย่างทั้งหมด: 10'), findsOneWidget);
  });

  testWidgets('empty evidence shows sample size zero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(loader: () async => _emptySnapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('จำนวนตัวอย่าง: 0'), findsOneWidget);
  });
}

const _snapshot = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: 0.8,
  points: 8,
  completedSessions: 2,
  streakDays: 7,
  dueReviewCount: 1,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 1,
  skills: [
    SkillEvidence(
      key: 'listening',
      label: 'Listening',
      sampleSize: 4,
      accuracy: 0.75,
    ),
  ],
  weaknesses: [],
  recommendations: [],
);

const _emptySnapshot = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  points: 0,
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
