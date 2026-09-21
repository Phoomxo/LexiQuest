import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';

import '../support/r15_visual_capture.dart';

void main() {
  for (final empty in [false, true]) {
    testWidgets(
      'optional progress context preserves availability empty=$empty',
      (tester) async {
        final profile = empty ? _empty : _profile;
        String? owner = profile.ownerId;
        final registry = MenuActionRegistry(currentOwner: () => owner);
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MaterialApp(
              home: MasteryDashboardScreen(loader: () async => profile),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final data =
            jsonDecode(
                  (registry.snapshot()['context'] as List).single['value']
                      as String,
                )
                as Map<String, dynamic>;
        expect(
          data['weekly']['accuracy']['availability'],
          profile.accuracy.availability.name,
        );
        expect(
          data['weekly']['accuracy']['sampleSize'],
          empty ? null : profile.accuracy.sampleSize,
        );
        expect(data['weekly']['accuracy']['fraction'], profile.accuracy.value);
        expect(
          data['cumulative']['mastery']['masteredWordCount'],
          empty ? null : profile.mastery.masteredWordCount,
        );
        expect(
          data['current']['srs']['dueReviewCount'],
          empty ? null : profile.srs.dueReviewCount,
        );
        expect(data['weekly']['timezone'], profile.calendar.timezoneId);
        expect(data['interpretation'], 'separate-axes-not-overall-proficiency');
        owner = 'different-owner';
        expect(registry.snapshot()['context'], isEmpty);
      },
    );
  }
  testWidgets('optional progress context clears during reload and failure', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => _profile.ownerId);
    Future<PersonalLearningProfile> initial() async => _profile;
    final pending = Completer<PersonalLearningProfile>();
    Widget app(MasteryProfileLoader loader) => MenuActionScope(
      registry: registry,
      child: MaterialApp(home: MasteryDashboardScreen(loader: loader)),
    );
    await tester.pumpWidget(app(initial));
    await tester.pumpAndSettle();
    expect(registry.snapshot()['context'], isNotEmpty);
    await tester.pumpWidget(app(() => pending.future));
    await tester.pump();
    expect(registry.snapshot()['context'], isEmpty);
    pending.completeError(StateError('test unavailable'));
    await tester.pumpAndSettle();
    expect(registry.snapshot()['context'], isEmpty);
  });

  testWidgets('R15.5 opens existing goals route from dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MasteryDashboardScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();
    await _scrollToText(tester, 'เป้าหมายและการแจ้งเตือน');
    await tester.tap(find.text('เป้าหมายและการแจ้งเตือน'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningGoalsScreen), findsOneWidget);
  });

  testWidgets('R15.5 actual dashboard surfaces remain readable at large text', (
    tester,
  ) async {
    await loadR15Fonts();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final empty in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(empty ? 1 : 2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('synthetic-r15-surface'),
            child: MasteryDashboardScreen(
              loader: () async => _profileFixture(
                empty: empty,
                sampleSize: 6,
                correctCount: 5,
                activeDuration: const Duration(seconds: 79),
              ),
            ),
          ),
        ),
      );
      await captureR15Surface(
        tester,
        empty ? 'r15-dashboard-empty' : 'r15-dashboard-large-text',
      );
      await _scrollToText(tester, 'ความแม่นยำ');
      await captureR15Surface(
        tester,
        empty ? 'r15-dashboard-empty-details' : 'r15-dashboard-details',
      );
    }
  });
  testWidgets(
    'R15.5 summary shows 5 of 6, rounded accuracy and active seconds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () async => _profileFixture(
              sampleSize: 6,
              correctCount: 5,
              activeDuration: const Duration(seconds: 79),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5 / 6'), findsOneWidget);
      expect(find.text('ตอบถูก 5 จาก 6 คำตอบ · 83%'), findsOneWidget);
      expect(find.text('1 นาที 19 วินาที'), findsOneWidget);
      expect(find.text('ถึงกำหนดทบทวนตอนนี้: 1 คำ'), findsOneWidget);
      expect(find.textContaining('10 นาที'), findsNothing);
    },
  );

  for (final availability in ProfileAxisAvailability.values) {
    testWidgets('R15.5 zero sample is unavailable $availability', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MasteryDashboardScreen(
            loader: () async => _profileFixture(
              sampleSize: 0,
              correctCount: 0,
              accuracyAvailability: availability,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีข้อมูลคำตอบที่ใช้คำนวณ'), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });
  }

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

    expect(find.text('ตอบถูก 8 จาก 10 คำตอบ · 80%'), findsOneWidget);
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

    expect(find.text('ตอบถูก 1 จาก 1 คำตอบ · 100%'), findsOneWidget);
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
    expect(find.text('ตอบถูก 8 จาก 10 คำตอบ · 80%'), findsOneWidget);
    await _scrollToText(tester, 'Listening');
    expect(find.text('Listening'), findsOneWidget);
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
      expect(find.text('ตอบถูก 8 จาก 10 คำตอบ · 80%'), findsOneWidget);

      loader.value = () => second.future;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('ตอบถูก 8 จาก 10 คำตอบ · 80%'), findsNothing);

      final replacement = _profileFixture(sampleSize: 1, correctCount: 1);
      loader.value = () => third.future;
      await tester.pump();
      third.complete(replacement);
      await tester.pumpAndSettle();
      expect(find.text('ตอบถูก 1 จาก 1 คำตอบ · 100%'), findsOneWidget);

      second.complete(_empty);
      await tester.pumpAndSettle();
      expect(find.text('ตอบถูก 1 จาก 1 คำตอบ · 100%'), findsOneWidget);
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
  Duration activeDuration = const Duration(minutes: 25),
  ProfileAxisAvailability? accuracyAvailability,
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
      activeDuration: empty ? Duration.zero : activeDuration,
    ),
    accuracy: PersonalLearningAccuracy(
      availability: accuracyAvailability ?? availability,
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
