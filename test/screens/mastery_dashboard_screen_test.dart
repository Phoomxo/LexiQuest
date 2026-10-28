import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';

void main() {
  testWidgets('renders all six axes without a combined score', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ภาพรวมการเรียน'), findsOneWidget);
    for (final text in const [
      'Mastery',
      'Listening',
      'จำนวนตัวอย่าง: 4',
      'SRS',
      'Effort',
      'Accuracy',
      'Weakness',
      'Engagement',
    ]) {
      await _scrollToText(tester, text);
      expect(find.text(text), findsOneWidget);
      expect(find.textContaining('คะแนนรวม'), findsNothing);
    }
  });

  testWidgets('empty evidence is an honest typed empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _empty)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีหลักฐานการเรียนที่เพียงพอ'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('calendar action receives the exact canonical f25 snapshot', (
    tester,
  ) async {
    LearningCalendarSnapshot? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () async => _profile,
          openLearningCalendar: (context, calendar) async {
            opened = calendar;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToCalendarAction(tester);
    await tester.tap(find.byKey(const Key('learning-calendar-action')));
    await tester.pump();

    expect(opened, same(_profile.calendar));
  });

  testWidgets('default calendar action opens the existing f25 screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();

    await _scrollToCalendarAction(tester);
    await tester.tap(find.byKey(const Key('learning-calendar-action')));
    await tester.pumpAndSettle();

    expect(find.byType(LearningCalendarScreen), findsOneWidget);
    expect(find.text('ปฏิทินการเรียน'), findsOneWidget);
  });

  testWidgets('reloads profile whenever an indexed tab becomes active', (
    tester,
  ) async {
    final active = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    var profile = _empty;
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
                return profile;
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
    expect(find.text('ยังไม่มีหลักฐานการเรียนที่เพียงพอ'), findsOneWidget);

    active.value = false;
    await tester.pump();
    profile = _profile;
    active.value = true;
    await tester.pumpAndSettle();

    expect(loadCalls, 2);
    expect(find.text('Listening'), findsOneWidget);
  });

  testWidgets('remains readable without overflow at 200 percent text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MasteryDashboardScreen(loader: () async => _profile),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToCalendarAction(tester);

    expect(find.byKey(const Key('learning-calendar-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _scrollToText(WidgetTester tester, String text) =>
    tester.scrollUntilVisible(
      find.text(text),
      240,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );

Future<void> _scrollToCalendarAction(WidgetTester tester) =>
    tester.scrollUntilVisible(
      find.byKey(const Key('learning-calendar-action')),
      240,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );

final _profile = _profileFixture();
final _empty = _profileFixture(empty: true);

PersonalLearningProfile _profileFixture({bool empty = false}) {
  final availability = empty
      ? ProfileAxisAvailability.noEvidence
      : ProfileAxisAvailability.available;
  return PersonalLearningProfile(
    ownerId: 'owner-1',
    mastery: PersonalLearningMastery(
      availability: availability,
      masteredWordCount: empty ? 0 : 2,
      observedPracticeCount: empty ? 0 : 10,
      skills: empty
          ? const []
          : const [
              SkillEvidence(
                key: 'listening',
                label: 'Listening',
                sampleSize: 4,
                accuracy: .75,
              ),
            ],
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
      sampleSize: empty ? 0 : 10,
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
