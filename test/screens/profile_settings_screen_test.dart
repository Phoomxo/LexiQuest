import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  testWidgets('profile renders separate canonical learning axes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผู้เรียน Guest'), findsOneWidget);
    for (final label in <String>[
      'ความชำนาญ',
      'ทบทวนแบบเว้นระยะ (SRS)',
      'เวลาเรียนจริง',
      'ความแม่นยำ',
      'จุดที่ควรฝึกเพิ่ม',
      'ความต่อเนื่องในการเรียน',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('80% จาก 10 คำตอบ'), findsOneWidget);
    expect(find.text('42 XP · ต่อเนื่อง 7 วัน'), findsOneWidget);
    expect(find.textContaining('คะแนนรวม'), findsNothing);
  });

  testWidgets('empty profile says no evidence instead of zero proficiency', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () async => _empty)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
      findsOneWidget,
    );
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('does not load while its indexed destination is inactive', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: ProfileSettingsScreen(
            loader: () async {
              calls += 1;
              return _profile;
            },
          ),
        ),
      ),
    );

    expect(calls, 0);
  });
}

final _profile = _profileFixture();
final _empty = _profileFixture(empty: true);

PersonalLearningProfile _profileFixture({bool empty = false}) {
  final availability = empty
      ? ProfileAxisAvailability.noEvidence
      : ProfileAxisAvailability.available;
  final accuracy = empty ? 0 : 10;
  return PersonalLearningProfile(
    ownerId: 'owner-1',
    mastery: PersonalLearningMastery(
      availability: availability,
      masteredWordCount: empty ? 0 : 2,
      observedPracticeCount: accuracy,
      skills: const [],
    ),
    srs: PersonalLearningSrs(
      availability: availability,
      trackedWordCount: empty ? 0 : 3,
      dueReviewCount: empty ? 0 : 1,
    ),
    effort: PersonalLearningEffort(
      availability: availability,
      activeDuration: empty ? Duration.zero : const Duration(minutes: 25),
    ),
    accuracy: PersonalLearningAccuracy(
      availability: availability,
      sampleSize: accuracy,
      correctCount: empty ? 0 : 8,
    ),
    weakness: PersonalLearningWeakness(
      availability: availability,
      items: const [],
    ),
    engagement: PersonalLearningEngagement(
      availability: availability,
      totalXp: empty ? 0 : 42,
      avatarLevel: empty ? 1 : 3,
      completedSessionCount: empty ? 0 : 2,
      currentStreakDays: empty ? 0 : 7,
      longestStreakDays: empty ? 0 : 9,
      activeQuestCount: empty ? 0 : 1,
      completedQuestCount: empty ? 0 : 2,
      achievementCount: empty ? 0 : 1,
      ownedRewardItemCount: empty ? 0 : 2,
    ),
    calendar: _calendar(empty: empty),
  );
}

LearningCalendarSnapshot _calendar({required bool empty}) =>
    LearningCalendarSnapshot(
      timezoneId: 'Asia/Bangkok',
      weekStart: DateTime(2026, 8, 24),
      days: const [],
      weekly: WeeklyLearningAnalytics(
        effort: LearningEffortAxis(
          activeDuration: empty ? Duration.zero : const Duration(minutes: 25),
        ),
        accuracy: LearningAccuracyAxis(
          sampleSize: empty ? 0 : 10,
          correctCount: empty ? 0 : 8,
        ),
        skillDistribution: const [],
        accuracyTrend: const [],
      ),
    );
