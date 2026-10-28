import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  _recoveryTests();
  testWidgets(
    'S01-AA profile secondary actions survive failed profile loading',
    (tester) async {
      var openedMastery = 0;
      var openedSettings = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileSettingsScreen(
            loader: () async => throw StateError('unavailable'),
            onOpenMastery: () => openedMastery++,
            secondaryActions: [
              TextButton(
                onPressed: () => openedSettings++,
                child: const Text('ตั้งค่า'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-open-mastery')));
      await tester.tap(find.text('ตั้งค่า'));
      expect(openedMastery, 1);
      expect(openedSettings, 1);
    },
  );

  testWidgets(
    'MCP reads actual profile axes and expands details without account data',
    (tester) async {
      final registry = MenuActionRegistry(currentOwner: () => _profile.ownerId);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: ProfileSettingsScreen(loader: () async => _profile),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = registry.snapshot();
      expect(
        (before['context'] as List).any(
          (e) => e['id'] == 'profile/mastery' && e['value'] == '2 คำที่ชำนาญ',
        ),
        isTrue,
      );
      expect(
        (await registry.execute(
          id: 'profile/show-learning-details',
          owner: _profile.ownerId,
          revision: before['revision'] as int,
          requestId: 'expand',
        ))['status'],
        'invoked',
      );
      await tester.pumpAndSettle();
      final context = registry.snapshot()['context'] as List;
      expect(
        context.map((e) => e['id']).toSet(),
        NavigationGlossary.profileAxisIds,
      );
      expect(
        context.any(
          (e) =>
              e['id'] == 'profile/accuracy' && e['value'] == '80% จาก 10 คำตอบ',
        ),
        isTrue,
      );
      expect(context.toString(), isNot(contains('@')));
    },
  );

  testWidgets('replacement clears loaded axes and ignores pending old loader', (
    tester,
  ) async {
    final first = Completer<PersonalLearningProfile>();
    final second = Completer<PersonalLearningProfile>();
    final third = Completer<PersonalLearningProfile>();
    final loader = ValueNotifier<ProfileSettingsProfileLoader>(
      () => first.future,
    );
    addTearDown(loader.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<ProfileSettingsProfileLoader>(
          valueListenable: loader,
          builder: (context, current, _) =>
              ProfileSettingsScreen(loader: current),
        ),
      ),
    );
    first.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.text('2 คำที่ชำนาญ'), findsOneWidget);
    loader.value = () => second.future;
    await tester.pump();
    expect(find.text('2 คำที่ชำนาญ'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loader.value = () => third.future;
    await tester.pump();
    third.complete(_empty);
    await tester.pumpAndSettle();
    second.complete(_profile);
    await tester.pumpAndSettle();
    expect(find.text('2 คำที่ชำนาญ'), findsNothing);
    expect(
      find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
      findsOneWidget,
    );
  });

  testWidgets(
    'same loader reloads on tab reactivation and contains synchronous failure',
    (tester) async {
      var calls = 0;
      final active = ValueNotifier<bool>(true);
      addTearDown(active.dispose);
      Future<PersonalLearningProfile> loader() {
        calls++;
        if (calls == 2) throw StateError('synthetic read failure');
        return Future.value(_profile);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (context, enabled, _) => TickerMode(
              enabled: enabled,
              child: ProfileSettingsScreen(loader: loader),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      active.value = false;
      await tester.pump();
      expect(calls, 1);
      active.value = true;
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsOneWidget);
    },
  );

  testWidgets('profile stays compact and delegates its full overview', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(
          loader: () async => _profile,
          onOpenMastery: () => opens++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('80% จาก 10 คำตอบ'), findsNothing);
    final action = find.byKey(const ValueKey('profile-open-mastery'));
    await _reveal(tester, action);
    await tester.tap(action);
    expect(opens, 1);
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-open-mastery')), findsNothing);
  });
  testWidgets(
    'Thai glossary profile axes remain distinct read-only semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileSettingsScreen(loader: () async => _profile),
          ),
        );
        await tester.pumpAndSettle();

        final details = find.byKey(const ValueKey('profile-learning-details'));
        await _reveal(tester, details);
        await tester.tap(details);
        await tester.pumpAndSettle();

        for (final label in <String>[
          'ความชำนาญ',
          'ทบทวนคำศัพท์',
          'เวลาเรียนจริง',
          'ความแม่นยำ',
          'จุดที่ควรฝึกเพิ่ม',
          'ความต่อเนื่องในการเรียน',
        ]) {
          await _reveal(tester, find.text(label));
          expect(find.text(label), findsOneWidget);
        }
        await _reveal(tester, find.text('80% จาก 10 คำตอบ'));
        expect(find.text('80% จาก 10 คำตอบ'), findsOneWidget);
        await _reveal(tester, find.text('42 XP · ต่อเนื่อง 7 วัน'));
        expect(find.text('42 XP · ต่อเนื่อง 7 วัน'), findsOneWidget);
        expect(find.textContaining('คะแนนรวม'), findsNothing);
        for (final MapEntry(key: entryId, value: expectedValue)
            in _axisValues.entries) {
          final entry = NavigationGlossary.require(entryId);
          await _reveal(tester, find.text(entry.fullThaiLabel));
          final tooltip = find.byWidgetPredicate(
            (widget) => widget is Tooltip && widget.message == entry.tooltip,
          );
          expect(tooltip, findsOneWidget);
          expect(
            find.descendant(
              of: tooltip,
              matching: find.text(entry.fullThaiLabel),
            ),
            findsOneWidget,
          );
          final semanticAxis = find.bySemanticsLabel(
            RegExp('^${RegExp.escape(entry.semanticsLabel)}\$'),
          );
          expect(semanticAxis, findsOneWidget);
          final data = tester.getSemantics(semanticAxis).getSemanticsData();
          expect(data.label, entry.semanticsLabel);
          expect(data.value, expectedValue);
          expect(data.hasAction(SemanticsAction.tap), isFalse);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Thai glossary local profile copy has no Guest fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () async => _profile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
    expect(find.textContaining('Guest'), findsNothing);
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

Future<void> _reveal(WidgetTester tester, Finder target) async {
  tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(target, 160);
  await tester.pump();
}

final _profile = _profileFixture();
final _empty = _profileFixture(empty: true);

const _axisValues = <String, String>{
  'profile/mastery': '2 คำที่ชำนาญ',
  'profile/srs': '1 คำถึงกำหนด จาก 3 คำ',
  'profile/effort': '25 นาที 0 วินาที',
  'profile/accuracy': '80% จาก 10 คำตอบ',
  'profile/weakness': 'ไม่พบจุดอ่อนในหลักฐานปัจจุบัน',
  'profile/engagement': '42 XP · ต่อเนื่อง 7 วัน',
};

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

void _recoveryTests() {
  testWidgets(
    'AN detached mastery callback cannot open after cover or replacement',
    (tester) async {
      var opens = 0;
      final nav = GlobalKey<NavigatorState>();
      Future<PersonalLearningProfile> load() async => _profile;
      Widget app(VoidCallback open) => MaterialApp(
        navigatorKey: nav,
        home: ProfileSettingsScreen(loader: load, onOpenMastery: open),
      );
      await tester.pumpWidget(app(() => opens++));
      await tester.pumpAndSettle();
      final old = tester
          .widget<FilledButton>(find.byKey(const Key('profile-open-mastery')))
          .onPressed!;
      await tester.pumpWidget(app(() => opens += 10));
      old();
      expect(opens, 0);
      final current = tester
          .widget<FilledButton>(find.byKey(const Key('profile-open-mastery')))
          .onPressed!;
      nav.currentState!.push(
        DialogRoute<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(content: Text('cover')),
        ),
      );
      current();
      await tester.pumpAndSettle();
      expect(opens, 0);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const Key('profile-open-mastery')))
          .onPressed!();
      expect(opens, 10);
      await tester.pumpWidget(const SizedBox());
      current();
      expect(opens, 10);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'AN personal menu context retires immediately when registry owner changes',
    (tester) async {
      var owner = _profile.ownerId;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: ProfileSettingsScreen(loader: () async => _profile),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (registry.snapshot()['context'] as List).any(
          (e) => e['id'] == 'profile/mastery',
        ),
        isTrue,
      );
      owner = 'replacement';
      expect(
        (registry.snapshot()['context'] as List).any(
          (e) => e['id'] == 'profile/mastery',
        ),
        isFalse,
      );
    },
  );
  testWidgets('AN late inactive read stays private before tab returns', (
    tester,
  ) async {
    final old = Completer<PersonalLearningProfile>();
    var calls = 0;
    Future<PersonalLearningProfile> load() =>
        ++calls == 1 ? old.future : Future.value(_empty);
    Widget app(bool active) => MaterialApp(
      home: TickerMode(
        enabled: active,
        child: ProfileSettingsScreen(loader: load),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pumpWidget(app(false));
    old.complete(_profile);
    await tester.pump();
    expect(find.text('2 คำที่ชำนาญ', skipOffstage: false), findsNothing);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
      findsOneWidget,
    );
  });

  testWidgets(
    'AN app inactivity hides private snapshot and refreshes on resume',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileSettingsScreen(
            loader: () async => ++calls == 1 ? _profile : _empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('2 คำที่ชำนาญ'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
        findsOneWidget,
      );
      expect(calls, 2);
    },
  );
  for (final lateError in [false, true]) {
    testWidgets(
      'AN disposed pending profile ignores completion error=$lateError',
      (tester) async {
        final pending = Completer<PersonalLearningProfile>();
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileSettingsScreen(loader: () => pending.future),
          ),
        );
        await tester.pumpWidget(const SizedBox());
        if (lateError) {
          pending.completeError(StateError('retired'));
        } else {
          pending.complete(_profile);
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final synchronous in [false, true]) {
    testWidgets(
      'AN immediate failure and repeated bounded retry sync=$synchronous',
      (tester) async {
        var calls = 0;
        final pending = Completer<PersonalLearningProfile>();
        Future<PersonalLearningProfile> load() {
          calls++;
          if (calls <= 2) {
            if (synchronous) throw StateError('unavailable');
            return Future.error(StateError('unavailable'));
          }
          return pending.future;
        }

        await tester.pumpWidget(
          MaterialApp(home: ProfileSettingsScreen(loader: load)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(calls, 1);
        var retry = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ลองอีกครั้ง'),
            )
            .onPressed!;
        retry();
        retry();
        await tester.pumpAndSettle();
        expect(calls, 2);
        retry = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ลองอีกครั้ง'),
            )
            .onPressed!;
        retry();
        retry();
        await tester.pump();
        expect(calls, 3);
        pending.complete(_profile);
        await tester.pumpAndSettle();
        expect(find.text('2 คำที่ชำนาญ'), findsOneWidget);
        retry();
        await tester.pump();
        expect(calls, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('AN loader replacement hides old data and ignores late result', (
    tester,
  ) async {
    final old = Completer<PersonalLearningProfile>();
    final next = Completer<PersonalLearningProfile>();
    Widget app(ProfileSettingsProfileLoader loader) =>
        MaterialApp(home: ProfileSettingsScreen(loader: loader));
    await tester.pumpWidget(app(() => old.future));
    await tester.pumpWidget(app(() => next.future));
    old.complete(_profile);
    await tester.pump();
    expect(find.text('2 คำที่ชำนาญ'), findsNothing);
    next.complete(_empty);
    await tester.pumpAndSettle();
    expect(
      find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
      findsOneWidget,
    );
  });
  testWidgets('AN inactive profile retires data and rereads on return', (
    tester,
  ) async {
    var calls = 0;
    Future<PersonalLearningProfile> load() async =>
        ++calls == 1 ? _profile : _empty;
    Widget app(bool active) => MaterialApp(
      home: TickerMode(
        enabled: active,
        child: ProfileSettingsScreen(loader: load),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.text('2 คำที่ชำนาญ'), findsOneWidget);
    await tester.pumpWidget(app(false));
    expect(find.text('2 คำที่ชำนาญ'), findsNothing);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
      findsOneWidget,
    );
  });
  testWidgets('AN cover retires snapshot and rereads after return', (
    tester,
  ) async {
    var calls = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: ProfileSettingsScreen(
          loader: () async => ++calls == 1 ? _profile : _empty,
        ),
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.push(
      DialogRoute<void>(
        context: nav.currentContext!,
        builder: (_) => const AlertDialog(content: Text('cover')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 คำที่ชำนาญ', skipOffstage: false), findsNothing);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
      findsOneWidget,
    );
  });
  testWidgets('AN popped retry and disposed pending read stay retired', (
    tester,
  ) async {
    var calls = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Scaffold()),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSettingsScreen(
          loader: () {
            calls++;
            return Future.error(StateError('read'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองอีกครั้ง'))
        .onPressed!;
    nav.currentState!.pop();
    retry();
    await tester.pumpAndSettle();
    retry();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('AN Thai recovery is reachable at 360px and 200 percent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ProfileSettingsScreen(
          loader: () async => throw StateError('read'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ลองอีกครั้ง'));
    expect(find.bySemanticsLabel('ลองอีกครั้ง'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
