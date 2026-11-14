import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/focus_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_focus_repository.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/focus_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/focus_planner_panel.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  testWidgets('Mastery focus week separates active portions from a pause', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase(NativeDatabase.memory());
    final clock = _Clock();
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-focus-owner',
      nowUtc: () => clock.now,
    );
    final calendar = DriftStreakRepository(
      database,
      calendarVisible: () => true,
    );
    final streak = StreakUseCases(
      repository: calendar,
      owners: owners,
      nowUtc: () => clock.now,
    );
    final repository = DriftFocusRepository(database, calendar: calendar);
    final focus = FocusUseCases(
      repository: repository,
      owners: owners,
      clock: clock,
      generateId: () => 'synthetic-focus-round',
    );
    final deps = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      database: database,
      localOwners: owners,
      focus: focus,
      streak: streak,
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => clock.now,
      ),
    );

    try {
      final owner = (await tester.runAsync(owners.getOrCreateActiveOwner))!;
      final rule = (await tester.runAsync(
        () =>
            streak.selectHomeTimezone(expectedOwnerId: owner.id, ianaId: 'UTC'),
      ))!;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const MasteryDashboardScreen(),
          ),
        ),
      );
      await _tap(tester, 'วางแผนการฝึก');
      await _tap(tester, 'จับเวลาฝึก', inPlanner: true);
      await _tap(tester, 'เริ่มจับเวลา', inPlanner: true);
      await _waitFor(tester, _enabledButton('พักเวลา'));

      clock.elapsed = const Duration(minutes: 1);
      await _tap(tester, 'พักเวลา', inPlanner: true);
      await _waitFor(tester, _enabledButton('ฝึกต่อ'));
      clock.elapsed = const Duration(minutes: 4);
      await _tap(tester, 'ฝึกต่อ', inPlanner: true);
      await _waitFor(tester, _enabledButton('พักเวลา'));
      clock.elapsed = const Duration(minutes: 5);
      await _tap(tester, 'บันทึกเวลารอบนี้', inPlanner: true);
      await _showPlannerText(
        tester,
        'ฝึกจริง 2 นาที 0 วินาที · พัก 3 นาที 0 วินาที',
      );
      await _tap(tester, 'ดูเวลาเรียนที่บันทึกไว้', inPlanner: true);

      await _showPlannerText(tester, 'เวลาฝึกที่บันทึก 2 นาที 0 วินาที');
      await _showPlannerText(
        tester,
        'ฝึกจริง 2 นาที 0 วินาที · พัก 3 นาที 0 วินาที',
      );
      final saved = (await tester.runAsync(
        () => repository.load(ownerId: owner.id, id: 'synthetic-focus-round'),
      ))!;
      expect(saved.state, FocusState.completed);
      expect(saved.targetMs, 300000);
      expect(saved.startRuleId, rule.ruleId);
      expect(saved.startCivilWeek, '2026-11-09');
      expect(saved.activeMs, 120000);
      expect(saved.pausedMs, 180000);
      expect(
        saved.spans.map(
          (span) => (
            span.kind,
            span.observedStartUtcMs - _start.millisecondsSinceEpoch,
            span.observedEndUtcMs - _start.millisecondsSinceEpoch,
            span.elapsedUs,
          ),
        ),
        [
          (FocusSpanKind.active, 0, 60000, 60000000),
          (FocusSpanKind.paused, 60000, 240000, 180000000),
          (FocusSpanKind.active, 240000, 300000, 60000000),
        ],
      );
      await _tap(tester, 'กลับไปภาพรวมการเรียน', inPlanner: true);
      await _pumpUntil(
        tester,
        () => find.byType(BottomSheet).evaluate().isEmpty,
        'planner dismissal',
      );
      expect(_text('วางแผนการฝึก').hitTestable(), findsOneWidget);
      expect(_text('เวลาฝึกที่บันทึก 2 นาที 0 วินาที'), findsNothing);

      await tester.runAsync(() async {
        expect(
          await database.select(database.focusSessions).get(),
          hasLength(1),
        );
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'points_ledger_entries',
          'reward_transactions',
          'achievement_unlocks',
          'learning_day_log',
          'outbox_operations',
          'events_v2',
          'research_consents',
        ]) {
          expect(
            await database.customSelect('SELECT * FROM $table').get(),
            isEmpty,
            reason: 'Focus alone must not write $table',
          );
        }
      });
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var closed = false;
      final closing = focus
          .dispose()
          .then((_) => database.close())
          .whenComplete(() => closed = true);
      unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
      await _pumpUntil(tester, () => closed, 'database close');
      await closing;
      await tester.pump();
    }
  });
  testWidgets('paused planner reloads the background revision before resuming', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final database = AppDatabase(NativeDatabase.memory());
    final clock = _Clock();
    final updates = ValueNotifier<int>(0);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'lifecycle-focus-owner',
      nowUtc: () => clock.now,
    );
    final repository = DriftFocusRepository(database);
    final focus = FocusUseCases(
      repository: repository,
      owners: owners,
      clock: clock,
      generateId: () => 'lifecycle-focus-round',
      onChanged: () => updates.value++,
    );
    final deps = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      database: database,
      localOwners: owners,
      focus: focus,
      progressUpdates: updates,
    );
    try {
      final owner = (await tester.runAsync(owners.getOrCreateActiveOwner))!;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showFocusPlanner(context),
                  child: const Text('วางแผนการฝึก'),
                ),
              ),
            ),
          ),
        ),
      );
      await _tap(tester, 'วางแผนการฝึก');
      await _tap(tester, 'จับเวลาฝึก', inPlanner: true);
      await _tap(tester, 'เริ่มจับเวลา', inPlanner: true);
      await _waitFor(tester, _enabledButton('พักเวลา'));
      clock.elapsed = const Duration(minutes: 1);
      await _tap(tester, 'พักเวลา', inPlanner: true);
      await _waitFor(tester, _enabledButton('ฝึกต่อ'));
      final paused = (await tester.runAsync(
        () => repository.load(ownerId: owner.id, id: 'lifecycle-focus-round'),
      ))!;
      expect(paused.revision, 2);
      expect(paused.activeMs, 60000);

      clock.elapsed = const Duration(minutes: 2);
      final backgroundSample = clock.sample();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      // Exercise the same checkpoint as MyApp, without its unrelated services.
      final checkpoint = (await tester.runAsync(
        () => focus.background(
          expectedOwnerId: owner.id,
          sample: backgroundSample,
        ),
      ))!;
      expect(checkpoint.revision, 3);
      expect(checkpoint.state, FocusState.paused);
      expect(checkpoint.activeMs, 60000);
      expect(checkpoint.pausedMs, 60000);
      expect(checkpoint.hasUnknownGap, isTrue);
      clock.elapsed = const Duration(minutes: 4);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpUntil(
        tester,
        () =>
            _planner(find.byType(LinearProgressIndicator)).evaluate().isEmpty &&
            _enabledButton('ฝึกต่อ').evaluate().isNotEmpty,
        'paused planner refresh after background',
      );
      await _tap(tester, 'ฝึกต่อ', inPlanner: true);
      await _waitFor(tester, _enabledButton('พักเวลา'));
      final resumed = (await tester.runAsync(
        () => repository.load(ownerId: owner.id, id: 'lifecycle-focus-round'),
      ))!;
      expect(resumed.revision, 4);
      expect(resumed.state, FocusState.running);
      expect(resumed.activeMs, 60000);
      expect(resumed.pausedMs, 60000);
      expect(resumed.spans.last.elapsedUs, isNull);
      expect(resumed.hasUnknownGap, isTrue);
      clock.elapsed = const Duration(minutes: 5);
      await _tap(tester, 'บันทึกเวลารอบนี้', inPlanner: true);
      await _showPlannerText(
        tester,
        'ฝึกจริง 2 นาที 0 วินาที · พัก 1 นาที 0 วินาที',
      );
      await tester.runAsync(() async {
        final rows = await database.select(database.focusSessions).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, paused.id);
        expect(rows.single.revision, 5);
        expect(rows.single.state, 'completed');
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
      });
      expect(find.text('บันทึกเวลาไม่สำเร็จ กรุณาลองอีกครั้ง'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      var closed = false;
      final closing = focus
          .dispose()
          .then((_) => database.close())
          .whenComplete(() => closed = true);
      unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
      await _pumpUntil(tester, () => closed, 'lifecycle focus database close');
      await closing;
      updates.dispose();
    }
  });
}

final _start = DateTime.utc(2026, 11, 13, 9);

final class _Clock implements FocusClock {
  Duration elapsed = Duration.zero;
  DateTime get now => _start.add(elapsed);

  @override
  FocusSample sample() => FocusSample(
    utcMs: now.millisecondsSinceEpoch,
    monotonicUs: elapsed.inMicroseconds,
    continuityId: 'synthetic-focus-clock',
  );
}

Finder _text(String text) => find.text(text);

Finder _planner(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Finder _enabledButton(String label) => find.ancestor(
  of: _text(label),
  matching: find.byWidgetPredicate(
    (widget) => widget is ButtonStyleButton && widget.onPressed != null,
  ),
);

Future<void> _showPlannerText(WidgetTester tester, String label) =>
    _scrollPlannerTo(tester, _planner(_text(label)));

Future<void> _scrollPlannerTo(WidgetTester tester, Finder target) async {
  final scrollable = _planner(find.byType(Scrollable));
  await _waitFor(tester, scrollable);
  await _pumpUntil(tester, () async {
    if (target.evaluate().isNotEmpty) return true;
    await tester.drag(scrollable, const Offset(0, -150));
    return false;
  }, '$target in the planner');
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _tap(
  WidgetTester tester,
  String label, {
  bool inPlanner = false,
}) async {
  final button = _enabledButton(label);
  final target = inPlanner ? _planner(button) : button;
  if (inPlanner) {
    await _scrollPlannerTo(tester, target);
  } else {
    await _waitFor(tester, target);
  }
  await tester.ensureVisible(target);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target.hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _waitFor(WidgetTester tester, Finder finder) =>
    _pumpUntil(tester, () => finder.evaluate().isNotEmpty, '$finder');

Future<void> _pumpUntil(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String description,
) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (await ready()) return;
  }
  fail('Timed out waiting for $description in the focus planner journey');
}

final class _GuestSession extends Fake implements GuestSessionService {}
