import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';

void main() {
  testWidgets(
    'mastery delegates review and weakness without creating its own session',
    (tester) async {
      var reviews = 0;
      var weaknesses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () async => _empty,
            onOpenReview: () => reviews++,
            onOpenWeakness: () => weaknesses++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mastery-open-review')));
      await tester.tap(find.byKey(const ValueKey('home/weakness')));
      expect([reviews, weaknesses], [1, 1]);
      await tester.pumpWidget(
        MaterialApp(home: MasteryDashboardScreen(loader: () async => _empty)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mastery-open-review')), findsNothing);
      expect(find.byKey(const ValueKey('home/weakness')), findsNothing);
    },
  );
  testWidgets('renders all six axes without a combined score', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ภาพรวมการเรียน'), findsOneWidget);
    for (final text in const [
      'ความชำนาญ',
      'Listening',
      'จำนวนตัวอย่าง: 4',
      'ทบทวนแบบเว้นระยะ',
      'เวลาเรียนจริง',
      'ความแม่นยำ',
      'จุดที่ควรฝึกเพิ่ม',
      'ความต่อเนื่องในการเรียน',
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

  testWidgets('weekly summary leads with canonical counts and calendar week', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตอบถูก 8 จาก 10 คำตอบ'), findsOneWidget);
    expect(find.textContaining('24 ส.ค. 2569'), findsOneWidget);
    expect(find.textContaining('30 ส.ค. 2569'), findsOneWidget);
    expect(find.textContaining('เวลาประเทศไทย'), findsOneWidget);
    expect(find.textContaining('กิจกรรมหลายรูปแบบ'), findsOneWidget);
    expect(
      find.text(
        'ข้อมูลนี้ยังใช้สรุปว่าจำคำศัพท์ได้เองไม่ได้ และยังไม่มีผลก่อนและหลังที่เปรียบเทียบกันได้',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ดีขึ้น'), findsNothing);
    expect(find.textContaining('พร้อมสอบ'), findsNothing);
  });

  testWidgets('one weekly answer is factual and explicitly limited evidence', (
    tester,
  ) async {
    final oneAnswer = _profileFixture(sampleSize: 1, correctCount: 1);
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => oneAnswer)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตอบถูก 1 จาก 1 คำตอบ'), findsOneWidget);
    expect(find.textContaining('มีข้อมูลน้อย'), findsOneWidget);
    expect(
      find.text(
        'ข้อมูลนี้ยังใช้สรุปว่าจำคำศัพท์ได้เองไม่ได้ และยังไม่มีผลก่อนและหลังที่เปรียบเทียบกันได้',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ดีขึ้น'), findsNothing);
  });

  testWidgets('no weekly evidence is not rendered as zero ability', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _empty)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีคำตอบในสัปดาห์นี้'), findsOneWidget);
    expect(find.textContaining('24 ส.ค. 2569'), findsOneWidget);
    expect(find.textContaining('30 ส.ค. 2569'), findsOneWidget);
    expect(find.textContaining('ตอบถูก 0'), findsNothing);
    expect(find.textContaining('ความสามารถ 0'), findsNothing);
  });

  testWidgets('unavailable profile keeps the existing readable error state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MasteryDashboardScreen(
          loader: () async => throw StateError('profile unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
      findsOneWidget,
    );
    expect(find.textContaining('ตอบถูก'), findsNothing);
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
    expect(find.text('ตอบถูก 8 จาก 10 คำตอบ'), findsOneWidget);
  });

  testWidgets(
    'loader replacement clears old owner data and ignores stale completion',
    (tester) async {
      final first = Completer<PersonalLearningProfile>();
      final second = Completer<PersonalLearningProfile>();
      final third = Completer<PersonalLearningProfile>();
      final loader = ValueNotifier<MasteryProfileLoader>(() => first.future);
      addTearDown(loader.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<MasteryProfileLoader>(
            valueListenable: loader,
            builder: (context, current, _) =>
                MasteryDashboardScreen(loader: current),
          ),
        ),
      );
      first.complete(_profile);
      await tester.pumpAndSettle();
      expect(find.text('ตอบถูก 8 จาก 10 คำตอบ'), findsOneWidget);

      loader.value = () => second.future;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('ตอบถูก 8 จาก 10 คำตอบ'), findsNothing);

      final replacement = _profileFixture(sampleSize: 1, correctCount: 1);
      loader.value = () => third.future;
      await tester.pump();
      third.complete(replacement);
      await tester.pumpAndSettle();
      expect(find.text('ตอบถูก 1 จาก 1 คำตอบ'), findsOneWidget);

      second.complete(_empty);
      await tester.pumpAndSettle();
      expect(find.text('ตอบถูก 1 จาก 1 คำตอบ'), findsOneWidget);
      expect(find.text('ยังไม่มีคำตอบในสัปดาห์นี้'), findsNothing);
    },
  );

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

Future<void> _scrollToCalendarAction(WidgetTester tester) async {
  final action = find.byKey(const Key('learning-calendar-action'));
  await tester.scrollUntilVisible(
    find.byKey(const Key('learning-calendar-action')),
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 20,
  );
  await tester.pump();
  await tester.ensureVisible(action);
  await tester.pump();
  expect(action.hitTestable(), findsOneWidget);
}

final _profile = _profileFixture();
final _empty = _profileFixture(empty: true);

PersonalLearningProfile _profileFixture({
  bool empty = false,
  int sampleSize = 10,
  int correctCount = 8,
}) {
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
      sampleSize: empty ? 0 : sampleSize,
      correctCount: empty ? 0 : correctCount,
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
