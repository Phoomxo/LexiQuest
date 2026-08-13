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
    expect(
      find.text('จำนวนตัวอย่างทั้งหมด: 10 • อัลกอริทึมเวอร์ชัน 1'),
      findsOneWidget,
    );
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

  testWidgets('reloads evidence whenever an indexed tab becomes active', (
    tester,
  ) async {
    final active = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    var progress = _emptySnapshot;
    var loadCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, enabled, _) => TickerMode(
            enabled: enabled,
            child: MasteryDashboardScreen(
              loader: () async {
                loadCalls += 1;
                return progress;
              },
            ),
          ),
        ),
      ),
    );
    expect(loadCalls, 0);

    active.value = true;
    await tester.pumpAndSettle();
    expect(loadCalls, 1);
    expect(find.textContaining('จำนวนตัวอย่าง: 0'), findsOneWidget);

    active.value = false;
    await tester.pump();
    progress = _snapshot;
    active.value = true;
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.text('Listening'), findsOneWidget);
  });
}

const _snapshot = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: 0.8,
  totalXp: 8,
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
