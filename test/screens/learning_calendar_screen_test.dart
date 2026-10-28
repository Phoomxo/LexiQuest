import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';

void main() {
  testWidgets('labels effort accuracy skills and trend as separate axes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: LearningCalendarScreen(loader: () async => _calendar)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ปฏิทินการเรียน'), findsOneWidget);
    expect(find.text('ความพยายาม (เวลาที่เรียนจริง)'), findsOneWidget);
    expect(find.text('ความแม่นยำ'), findsOneWidget);
    expect(find.text('การกระจายทักษะ'), findsOneWidget);
    expect(find.text('แนวโน้มความแม่นยำ'), findsOneWidget);
    expect(find.text('75 วินาที'), findsOneWidget);
    expect(find.text('100% จาก 1 คำตอบ'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนความพยายาม'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนความแม่นยำ'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนการกระจายทักษะ'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนแนวโน้มความแม่นยำ'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('empty calendar states preserve separate null accuracy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LearningCalendarScreen(loader: () async => _emptyCalendar),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 วินาที'), findsOneWidget);
    expect(find.text('ยังไม่มีคำตอบที่นับความแม่นยำได้'), findsOneWidget);
    expect(find.text('ยังไม่มีทักษะจากคำตอบในสัปดาห์นี้'), findsOneWidget);
  });
}

final _calendar = LearningCalendarSnapshot(
  timezoneId: 'Asia/Bangkok',
  weekStart: DateTime(2026, 8, 24),
  days: [
    LearningCalendarDay(
      day: DateTime(2026, 8, 24),
      effort: LearningEffortAxis(activeDuration: Duration(seconds: 75)),
      accuracy: LearningAccuracyAxis(sampleSize: 1, correctCount: 1),
      skillDistribution: [
        LearningSkillDistribution(
          skillId: 'listening',
          sampleSize: 1,
          correctCount: 1,
        ),
      ],
    ),
  ],
  weekly: WeeklyLearningAnalytics(
    effort: LearningEffortAxis(activeDuration: Duration(seconds: 75)),
    accuracy: LearningAccuracyAxis(sampleSize: 1, correctCount: 1),
    skillDistribution: [
      LearningSkillDistribution(
        skillId: 'listening',
        sampleSize: 1,
        correctCount: 1,
      ),
    ],
    accuracyTrend: [
      LearningAccuracyTrendPoint(
        day: DateTime(2026, 8, 24),
        accuracy: LearningAccuracyAxis(sampleSize: 1, correctCount: 1),
      ),
    ],
  ),
);

final _emptyCalendar = LearningCalendarSnapshot(
  timezoneId: 'Asia/Bangkok',
  weekStart: DateTime(2026, 8, 24),
  days: [
    LearningCalendarDay(
      day: DateTime(2026, 8, 24),
      effort: LearningEffortAxis(activeDuration: Duration.zero),
      accuracy: LearningAccuracyAxis(sampleSize: 0, correctCount: 0),
      skillDistribution: [],
    ),
  ],
  weekly: WeeklyLearningAnalytics(
    effort: LearningEffortAxis(activeDuration: Duration.zero),
    accuracy: LearningAccuracyAxis(sampleSize: 0, correctCount: 0),
    skillDistribution: [],
    accuracyTrend: [
      LearningAccuracyTrendPoint(
        day: DateTime(2026, 8, 24),
        accuracy: LearningAccuracyAxis(sampleSize: 0, correctCount: 0),
      ),
    ],
  ),
);
