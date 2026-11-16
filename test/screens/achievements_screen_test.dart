import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';

void main() {
  testWidgets('announces achievement loading state', (tester) async {
    final pending = Completer<ProgressSnapshot>();
    await tester.pumpWidget(
      MaterialApp(home: AchievementsScreen(loader: () => pending.future)),
    );
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังอ่านประวัติความสำเร็จ',
    );
  });

  testWidgets('renders only stored achievement evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(loader: () async => _withAchievement),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ความสำเร็จ'), findsOneWidget);
    expect(find.text('เรียนจบรอบแรก'), findsOneWidget);
    expect(find.text('คะแนนประสบการณ์'), findsOneWidget);
    expect(find.text('คำนวณจาก 2 คำตอบที่บันทึกไว้'), findsOneWidget);
    expect(find.textContaining('ปลดล็อกจากคำตอบที่บันทึกไว้'), findsOneWidget);
    expect(find.textContaining('session-1'), findsNothing);
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(find.textContaining('เกณฑ์รุ่น'), findsNothing);
  });

  testWidgets('fresh account reports zero evidence without sample badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AchievementsScreen(loader: () async => _empty)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีคำตอบที่บันทึกไว้'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
  });

  testWidgets('unknown achievement identifier stays internal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(loader: () async => _unknownAchievement),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ความสำเร็จจากการเรียน'), findsOneWidget);
    expect(find.textContaining('internal_badge_v7'), findsNothing);
  });

  testWidgets('retry recovers one failed achievement read', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async {
            if (calls++ == 0) throw StateError('synthetic failure');
            return _withAchievement;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('เรียนจบรอบแรก'), findsOneWidget);
  });
}

final _withAchievement = ProgressSnapshot(
  sampleSize: 2,
  correctCount: 2,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 2,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
  achievements: [
    AchievementEvidence(
      id: 'first_session',
      definitionVersion: 1,
      sourceEventId: 'session-1',
      unlockedAtUtc: DateTime.utc(2026, 7, 30),
    ),
  ],
);

const _empty = ProgressSnapshot(
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

final _unknownAchievement = ProgressSnapshot(
  sampleSize: 1,
  correctCount: 1,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 1,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
  achievements: [
    AchievementEvidence(
      id: 'internal_badge_v7',
      definitionVersion: 1,
      sourceEventId: 'internal-event-7',
      unlockedAtUtc: DateTime.utc(2026, 10, 24),
    ),
  ],
);
