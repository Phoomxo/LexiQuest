import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/screens/study_reminder_settings_screen.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  for (final retired in ['replacement', 'disposal']) {
    testWidgets('pending status read cannot overwrite screen after $retired', (
      tester,
    ) async {
      final old = await _Fixture.create(ReminderPermissionState.granted);
      final replacement = await _Fixture.create(
        ReminderPermissionState.granted,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final nativeReturned = Completer<void>();
      Future<void> pumpUntil(bool Function() completed, String reason) async {
        final clock = Stopwatch()..start();
        do {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump();
        } while (!completed() && clock.elapsed < const Duration(seconds: 3));
        expect(completed(), isTrue, reason: reason);
      }

      try {
        for (final fixture in [old, replacement]) {
          expect(
            await fixture.useCases.optIn(
              source: const StudyReminderSource.dueReview(),
              scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
              timezoneId: 'Asia/Bangkok',
              mutationAllowed: () => true,
            ),
            StudyReminderOptInResult.scheduled,
          );
        }
        replacement.scheduler.permission = ReminderPermissionState.denied;
        old.scheduler.beforePendingReturn = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          if (!nativeReturned.isCompleted) nativeReturned.complete();
        };
        Widget screen(_Fixture fixture) => MaterialApp(
          home: StudyReminderSettingsScreen(
            key: const ValueKey('same-reminder-screen'),
            useCases: fixture.useCases,
            source: const StudyReminderSource.dueReview(),
            sourceLabel: 'Synthetic status lifetime',
          ),
        );
        await tester.pumpWidget(screen(old));
        await pumpUntil(
          () => entered.isCompleted,
          'The actual status read must reach native enumeration.',
        );
        await tester.pumpWidget(
          retired == 'replacement'
              ? screen(replacement)
              : const SizedBox.shrink(),
        );
        if (retired == 'replacement') {
          await pumpUntil(
            () => find
                .text('ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ')
                .evaluate()
                .isNotEmpty,
            'Replacement status must settle while the retired read is still held.',
          );
          expect(
            find.text('ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ'),
            findsOneWidget,
            reason:
                'Replacement status must settle while the retired read is still held.',
          );
        }
        release.complete();
        await pumpUntil(
          () => nativeReturned.isCompleted,
          'The retired native read must drain after release.',
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 20),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        if (retired == 'replacement') {
          expect(
            find.text('ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ'),
            findsOneWidget,
          );
          expect(find.text('เปิดการเตือนแล้ว'), findsNothing);
        } else {
          expect(find.byType(StudyReminderSettingsScreen), findsNothing);
        }
        final retiredReads = old.scheduler.permissionReads;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 20),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        expect(old.scheduler.permissionReads, retiredReads);
        expect(tester.takeException(), isNull);
        expect(old.scheduler.requests, hasLength(1));
        expect(replacement.scheduler.requests, hasLength(1));
        expect(old.scheduler.requestCalls, 0);
        expect(replacement.scheduler.requestCalls, 0);
      } finally {
        if (!release.isCompleted) release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        try {
          await pumpUntil(
            () => !entered.isCompleted || nativeReturned.isCompleted,
            'Cleanup must drain the released native read.',
          );
          await tester.pumpAndSettle(
            const Duration(milliseconds: 20),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
        } finally {
          await old.dispose();
          await replacement.dispose();
        }
      }
    });
  }

  testWidgets(
    'pending native schedule stays pending after reopening settings',
    (tester) async {
      final fixture = await _Fixture.create(ReminderPermissionState.granted);
      addTearDown(fixture.dispose);
      fixture.scheduler.failSchedule = true;
      Widget screen(String identity) => MaterialApp(
        home: StudyReminderSettingsScreen(
          key: ValueKey(identity),
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Synthetic pending reminder',
        ),
      );
      await tester.pumpWidget(screen('initial'));
      await tester.pumpAndSettle();
      await _selectLocalDateTime(
        tester,
        'study-reminder/scheduled-at',
        '08/29/2026',
        '09',
        '00',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('study-reminder/opt-in')),
      );
      await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
      await tester.pumpAndSettle();
      final saved = (await fixture.repository.list()).single;
      expect(saved.isEnabled, isTrue);
      expect(await fixture.repository.pendingPlatformIntents(), isNotEmpty);
      expect(fixture.scheduler.pending, isEmpty);
      expect(find.textContaining('บันทึกตัวเลือกแล้ว'), findsOneWidget);
      final attemptedSchedules = fixture.scheduler.requests.length;

      await tester.pumpWidget(screen('reopened'));
      await tester.pumpAndSettle();

      expect(fixture.scheduler.requestCalls, 0);
      expect(fixture.scheduler.requests, hasLength(attemptedSchedules));
      expect(await fixture.repository.pendingPlatformIntents(), isNotEmpty);
      expect(fixture.scheduler.pending, isEmpty);
      expect((await fixture.repository.list()).single.id, saved.id);
      expect(find.text('เปิดการเตือนแล้ว'), findsNothing);
      expect(find.textContaining('บันทึกตัวเลือกแล้ว'), findsOneWidget);

      fixture.scheduler.failSchedule = false;
      await fixture.useCases.reconcile(featureEnabled: true);
      await tester.pumpWidget(screen('after-confirmed-retry'));
      await tester.pumpAndSettle();
      expect(await fixture.repository.pendingPlatformIntents(), isEmpty);
      expect(fixture.scheduler.pending, hasLength(1));
      expect((await fixture.repository.list()).single.id, saved.id);
      expect(find.text('เปิดการเตือนแล้ว'), findsOneWidget);
      expect(fixture.scheduler.requestCalls, 0);
    },
  );

  testWidgets('OS permission revoke refreshes reminder status on resume', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.granted);
    addTearDown(fixture.dispose);
    expect(
      await fixture.useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      ),
      StudyReminderOptInResult.scheduled,
    );
    final saved = (await fixture.repository.list()).single;
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: StudyReminderSettingsScreen(
            useCases: fixture.useCases,
            source: const StudyReminderSource.dueReview(),
            sourceLabel: 'Synthetic revoked reminder',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('เปิดการเตือนแล้ว'), findsOneWidget);
      final readsBeforeResume = fixture.scheduler.permissionReads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      fixture.scheduler.permission = ReminderPermissionState.denied;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(fixture.scheduler.requestCalls, 0);
      expect(fixture.scheduler.requests, hasLength(1));
      final afterResume = (await fixture.repository.list()).single;
      expect(afterResume.id, saved.id);
      expect(afterResume.isEnabled, isTrue);
      expect(afterResume.updatedAtUtc, saved.updatedAtUtc);
      expect(find.text('เปิดการเตือนแล้ว'), findsNothing);
      expect(
        find.text('ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ'),
        findsOneWidget,
      );
      expect(fixture.scheduler.permissionReads, greaterThan(readsBeforeResume));
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
    'opt-in is an explicit calm action and persists the goal source',
    (tester) async {
      final fixture = await _Fixture.create(ReminderPermissionState.unknown);
      addTearDown(fixture.dispose);
      await _insertGoal(
        fixture.database,
        await fixture.repository.activeOwnerId(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StudyReminderSettingsScreen(
            useCases: fixture.useCases,
            source: StudyReminderSource.goalDeadline('goal:ielts'),
            sourceLabel: 'IELTS practice target',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('กิจวัตร'), findsWidgets);
      expect(find.textContaining('missed', findRichText: true), findsNothing);
      expect(find.textContaining('failed', findRichText: true), findsNothing);
      expect(find.textContaining('overdue', findRichText: true), findsNothing);
      expect(fixture.scheduler.requestCalls, 0);

      await _selectLocalDateTime(
        tester,
        'study-reminder/scheduled-at',
        '08/29/2026',
        '09',
        '00',
      );

      await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
      await tester.pumpAndSettle();

      final reminder = (await fixture.repository.list()).single;
      expect(fixture.scheduler.requestCalls, 1);
      expect(reminder.source.stableIdentity, 'goal:goal:ielts');
      expect(reminder.isEnabled, isTrue);
      expect(reminder.scheduledAtUtc, DateTime.utc(2026, 8, 29, 2));
      expect(reminder.timezone.utcOffsetMinutes, 420);
      expect(
        fixture.scheduler.requests.single.scheduledAtUtc,
        DateTime.utc(2026, 8, 29, 2),
      );
      expect(find.text('เปิดการเตือนแล้ว'), findsOneWidget);
    },
  );

  testWidgets(
    'quiet hours show requested and effective time and reopening is read only',
    (tester) async {
      final fixture = await _Fixture.create(ReminderPermissionState.unknown);
      addTearDown(fixture.dispose);
      Widget screen(Key key) => MaterialApp(
        home: StudyReminderSettingsScreen(
          key: key,
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Synthetic review',
        ),
      );
      await tester.pumpWidget(screen(const ValueKey('first')));
      await tester.pumpAndSettle();
      await _selectLocalDateTime(
        tester,
        'study-reminder/scheduled-at',
        '08/29/2026',
        '23',
        '00',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('study-reminder/opt-in')),
      );
      await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
      await tester.pumpAndSettle();
      final saved = (await fixture.repository.list()).single;
      expect(saved.scheduledAtUtc, DateTime.utc(2026, 8, 29, 16));
      expect(saved.quietHours!.startMinutes, 1320);
      expect(saved.quietHours!.endMinutes, 420);
      expect(saved.effectiveScheduledAtUtc, DateTime.utc(2026, 8, 30));
      expect(
        fixture.scheduler.requests.single.scheduledAtUtc,
        saved.effectiveScheduledAtUtc,
      );
      expect(
        find.textContaining('เวลาที่เลือก: 29 ส.ค. 2569 เวลา 23:00'),
        findsOneWidget,
      );
      expect(
        find.textContaining('เวลาแจ้งเตือนที่ตั้งไว้: 30 ส.ค. 2569 เวลา 07:00'),
        findsOneWidget,
      );
      await tester.pumpWidget(screen(const ValueKey('reopened')));
      await tester.pumpAndSettle();
      expect(
        (await fixture.repository.list()).single.scheduledAtUtc,
        saved.scheduledAtUtc,
      );
      expect(fixture.scheduler.requests, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('study-reminder/cancel')));
      await tester.pumpAndSettle();
      expect(fixture.scheduler.pending, isEmpty);
      expect((await fixture.repository.list()).single.id, saved.id);
      expect((await fixture.repository.list()).single.isEnabled, isFalse);
    },
  );

  testWidgets('missing goal and cancelled picker never create reminders', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.unknown);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyReminderSettingsScreen(
          useCases: fixture.useCases,
          source: StudyReminderSource.goalDeadline('goal:absent'),
          sourceLabel: 'Synthetic missing goal',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('study-reminder/scheduled-at/date')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(fixture.scheduler.requestCalls, 0);
    expect(await fixture.repository.list(), isEmpty);
    await _selectLocalDateTime(
      tester,
      'study-reminder/scheduled-at',
      '08/29/2026',
      '09',
      '00',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('study-reminder/opt-in')),
    );
    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();
    expect(await fixture.repository.list(), isEmpty);
    expect(fixture.scheduler.pending, isEmpty);
  });

  testWidgets('permission denial stays non-punitive and does not retry', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.denied);
    fixture.scheduler.requestResult = ReminderPermissionState.denied;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyReminderSettingsScreen(
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Reviews ready',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectLocalDateTime(
      tester,
      'study-reminder/scheduled-at',
      '08/29/2026',
      '09',
      '00',
    );

    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();

    expect(fixture.scheduler.requestCalls, 1);
    expect(await fixture.repository.list(), isEmpty);
    expect(
      find.text('ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ'),
      findsOneWidget,
    );
  });

  testWidgets('past time stays off without permission or durable writes', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.unknown);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyReminderSettingsScreen(
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Reviews ready',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectLocalDateTime(
      tester,
      'study-reminder/scheduled-at',
      '08/28/2026',
      '07',
      '00',
    );
    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();

    expect(fixture.scheduler.requestCalls, 0);
    expect(await fixture.repository.list(includeDeleted: true), isEmpty);
    expect(await fixture.repository.pendingPlatformIntents(), isEmpty);
    expect(find.text('เปิดการเตือนแล้ว'), findsNothing);
    expect(
      find.text('กรุณาเลือกเวลาในอนาคตและเขตเวลาเรียนที่ถูกต้อง'),
      findsOneWidget,
    );
  });

  testWidgets('denied retry keeps the visible local instant and timezone', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.denied);
    fixture.scheduler.requestResult = ReminderPermissionState.denied;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyReminderSettingsScreen(
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Synthetic retry',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('study-reminder/scheduled-at/timezone')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'America/New_York');
    await tester.pumpAndSettle();
    await tester.tap(find.text('America/New_York').last);
    await tester.pumpAndSettle();
    await _selectLocalDateTime(
      tester,
      'study-reminder/scheduled-at',
      '08/29/2026',
      '09',
      '30',
    );
    expect(find.textContaining('29 ส.ค. 2569 เวลา 09:30'), findsOneWidget);
    expect(find.textContaining('UTC-04:00'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('study-reminder/opt-in')),
    );
    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();
    expect(await fixture.repository.list(), isEmpty);
    expect(fixture.scheduler.requests, isEmpty);
    expect(find.textContaining('29 ส.ค. 2569 เวลา 09:30'), findsOneWidget);
    expect(find.textContaining('UTC-04:00'), findsOneWidget);
    fixture.scheduler.requestResult = ReminderPermissionState.granted;
    await tester.ensureVisible(
      find.byKey(const ValueKey('study-reminder/opt-in')),
    );
    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();
    final saved = (await fixture.repository.list()).single;
    expect(saved.scheduledAtUtc, DateTime.utc(2026, 8, 29, 13, 30));
    expect(saved.timezone.timezoneId, 'America/New_York');
    expect(fixture.scheduler.requests, hasLength(1));
    expect(
      fixture.scheduler.requests.single.scheduledAtUtc,
      saved.scheduledAtUtc,
    );
  });
}

Future<void> _insertGoal(AppDatabase database, String ownerId) => database
    .into(database.learningGoals)
    .insert(
      LearningGoalsCompanion.insert(
        id: 'goal:ielts',
        ownerId: ownerId,
        kind: 'exam',
        title: 'IELTS practice target',
        deadlineAtUtcMs: DateTime.utc(2026, 9, 30).millisecondsSinceEpoch,
        timezoneId: 'Asia/Bangkok',
        timezoneOffsetMinutes: 420,
        status: 'active',
        createdAtUtcMs: DateTime.utc(2026, 8, 28).millisecondsSinceEpoch,
        updatedAtUtcMs: DateTime.utc(2026, 8, 28).millisecondsSinceEpoch,
      ),
    );

final class _Fixture {
  _Fixture(this.database, this.repository, this.scheduler, this.useCases);

  static Future<_Fixture> create(ReminderPermissionState permission) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = DriftStudyReminderRepository(
      database,
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner-a',
        nowUtc: () => DateTime.utc(2026, 8, 28),
      ),
    );
    final scheduler = _ScreenScheduler()..permission = permission;
    return _Fixture(
      database,
      repository,
      scheduler,
      StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'reminder:screen',
      ),
    );
  }

  final AppDatabase database;
  final DriftStudyReminderRepository repository;
  final _ScreenScheduler scheduler;
  final StudyReminderUseCases useCases;

  Future<void> dispose() => database.close();
}

final class _ScreenScheduler implements ReminderScheduler {
  ReminderPermissionState permission = ReminderPermissionState.unknown;
  ReminderPermissionState requestResult = ReminderPermissionState.granted;
  int requestCalls = 0;
  int permissionReads = 0;
  bool failSchedule = false;
  Future<void> Function()? beforePendingReturn;
  final Map<int, ReminderPlatformEntry> pending = {};
  final List<ReminderScheduleRequest> requests = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<ReminderPermissionState> permissionState() async {
    permissionReads += 1;
    return permission;
  }

  @override
  Future<ReminderPermissionState> requestPermission() async {
    requestCalls += 1;
    permission = requestResult;
    return requestResult;
  }

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async {
    final snapshot = pending.values.toList(growable: false);
    await beforePendingReturn?.call();
    return snapshot;
  }

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {
    requests.add(request);
    if (failSchedule) throw StateError('Synthetic native scheduling failure');
    pending[request.platformId] = ReminderPlatformEntry(
      platformId: request.platformId,
      ownerId: request.ownerId,
      reminderId: request.reminderId,
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    pending.remove(platformId);
  }
}

Future<void> _selectLocalDateTime(
  WidgetTester tester,
  String prefix,
  String date,
  String hour,
  String minute,
) async {
  final dateButton = find.byKey(ValueKey('$prefix/date'));
  await tester.ensureVisible(dateButton);
  await tester.tap(dateButton);
  await tester.pumpAndSettle();
  await tester.enterText(
    find
        .descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        )
        .first,
    date,
  );
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('$prefix/time')));
  await tester.pumpAndSettle();
  final inputs = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(inputs.at(0), hour);
  await tester.enterText(inputs.at(1), minute);
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
}
