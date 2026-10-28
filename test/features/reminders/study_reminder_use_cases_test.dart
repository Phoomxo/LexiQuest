import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder_repository.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  late AppDatabase database;
  late DriftStudyReminderRepository repository;
  late _Scheduler scheduler;
  late StudyReminderUseCases useCases;
  late bool durableFeatureEnabled;
  late int durableFeatureEpoch;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftStudyReminderRepository(
      database,
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner-a',
        nowUtc: () => DateTime.utc(2026, 8, 28),
      ),
    );
    scheduler = _Scheduler();
    durableFeatureEnabled = true;
    durableFeatureEpoch = 0;
    useCases = StudyReminderUseCases(
      repository: repository,
      scheduler: scheduler,
      nowUtc: () => DateTime.utc(2026, 8, 28),
      generateId: () => 'reminder:generated',
      loadFeatureEligibility: () async => StudyReminderFeatureEligibility(
        enabled: durableFeatureEnabled,
        epoch: durableFeatureEpoch,
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'only an explicit opt-in requests permission and schedules after commit',
    () async {
      scheduler.permission = ReminderPermissionState.unknown;
      scheduler.requestResult = ReminderPermissionState.granted;
      scheduler.beforeSchedule = (request) async {
        final row = await database.select(database.studyReminders).getSingle();
        final outbox = await database
            .select(database.outboxOperations)
            .getSingle();
        expect(row.isEnabled, isTrue);
        expect(outbox.state, studyReminderPlatformPendingState);
        expect(outbox.operationKind, 'schedule');
      };

      await useCases.reconcile(
        featureEnabled: true,
        currentTimezoneId: 'Asia/Bangkok',
      );
      expect(scheduler.requestCalls, 0);

      final result = await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        quietHours: const ReminderQuietHours(
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ),
        mutationAllowed: () => true,
      );

      expect(result, StudyReminderOptInResult.scheduled);
      expect(scheduler.requestCalls, 1);
      expect(scheduler.scheduled, hasLength(1));
      expect(scheduler.scheduled.single.ownerId, 'local:owner-a');
      expect(scheduler.scheduled.single.body, contains('whenever'));
      expect(
        scheduler.scheduled.single.body.toLowerCase(),
        isNot(
          anyOf(contains('missed'), contains('failed'), contains('overdue')),
        ),
      );
      expect(await repository.pendingPlatformIntents(), isEmpty);
    },
  );

  test(
    'denied and unknown permission fail closed without background retry',
    () async {
      scheduler.permission = ReminderPermissionState.unknown;
      scheduler.requestResult = ReminderPermissionState.denied;

      final result = await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      await useCases.reconcile(
        featureEnabled: true,
        currentTimezoneId: 'Asia/Bangkok',
      );
      await useCases.reconcile(
        featureEnabled: true,
        currentTimezoneId: 'Asia/Bangkok',
      );

      expect(result, StudyReminderOptInResult.permissionDenied);
      expect(scheduler.requestCalls, 1);
      expect(scheduler.scheduled, isEmpty);
      expect(await repository.list(includeDeleted: true), isEmpty);
    },
  );

  test(
    'past, exact-now, and invalid-zone opt-ins fail before permission or durability',
    () async {
      scheduler.permission = ReminderPermissionState.unknown;

      for (final candidate in <({DateTime at, String zone})>[
        (at: DateTime.utc(2026, 8, 27, 23, 59), zone: 'Asia/Bangkok'),
        (at: DateTime.utc(2026, 8, 28), zone: 'Asia/Bangkok'),
        (at: DateTime.utc(2026, 8, 29), zone: 'Invalid/Timezone'),
      ]) {
        final result = await useCases.optIn(
          source: const StudyReminderSource.dueReview(),
          scheduledAtUtc: candidate.at,
          timezoneId: candidate.zone,
          quietHours: const ReminderQuietHours(
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
          ),
          mutationAllowed: () => true,
        );

        expect(result, StudyReminderOptInResult.invalidSchedule);
      }

      expect(scheduler.requestCalls, 0);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, isEmpty);
      expect(await database.select(database.studyReminders).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'strictly future opt-in remains valid across a quiet-hour shift',
    () async {
      scheduler.permission = ReminderPermissionState.granted;

      final result = await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 28, 17), // Midnight in Bangkok.
        timezoneId: 'Asia/Bangkok',
        quietHours: const ReminderQuietHours(
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ),
        mutationAllowed: () => true,
      );

      expect(result, StudyReminderOptInResult.scheduled);
      expect(
        scheduler.scheduled.single.scheduledAtUtc,
        DateTime.utc(2026, 8, 29),
      );
    },
  );

  test(
    'failed OS scheduling leaves durable intent for idempotent reconcile',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      scheduler.failSchedules = 1;
      await _insertGoal(database, await repository.activeOwnerId());

      final result = await useCases.optIn(
        source: StudyReminderSource.goalDeadline('goal:ielts'),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );

      expect(result, StudyReminderOptInResult.pendingRetry);
      var pending = await repository.pendingPlatformIntents();
      expect(pending, hasLength(1));
      expect(pending.single.attemptCount, 1);
      expect(
        (await repository.list()).single.source.stableIdentity,
        'goal:goal:ielts',
      );

      await useCases.reconcile(
        featureEnabled: true,
        currentTimezoneId: 'Asia/Bangkok',
      );
      pending = await repository.pendingPlatformIntents();
      expect(pending, isEmpty);
      expect(scheduler.scheduled, hasLength(1));
    },
  );

  test('quiet hours shift across midnight and the spring DST boundary', () {
    final reminder = StudyReminder(
      id: 'reminder:dst',
      ownerId: 'owner-a',
      source: const StudyReminderSource.dueReview(),
      scheduledAtUtc: DateTime.utc(2026, 3, 8, 6, 30),
      timezone: const StudyReminderTimezoneContext(
        timezoneId: 'America/New_York',
        utcOffsetMinutes: -300,
      ),
      quietHours: const ReminderQuietHours(
        startMinutes: 22 * 60,
        endMinutes: 7 * 60,
      ),
      isEnabled: true,
      createdAtUtc: DateTime.utc(2026, 3, 1),
      updatedAtUtc: DateTime.utc(2026, 3, 1),
    );

    expect(reminder.effectiveScheduledAtUtc, DateTime.utc(2026, 3, 8, 11));
    expect(reminder.effectiveScheduledAtUtc.isUtc, isTrue);
  });

  test('timezone rebasing preserves wall time and recomputes DST offset', () {
    final bangkok = StudyReminder(
      id: 'reminder:travel',
      ownerId: 'owner-a',
      source: const StudyReminderSource.dueReview(),
      scheduledAtUtc: DateTime.utc(2026, 3, 9, 2),
      timezone: const StudyReminderTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
      isEnabled: true,
      createdAtUtc: DateTime.utc(2026, 3, 1),
      updatedAtUtc: DateTime.utc(2026, 3, 1),
    );

    final newYork = bangkok.rebaseTimezone(
      'America/New_York',
      updatedAtUtc: DateTime.utc(2026, 3, 8),
    );

    expect(newYork.scheduledAtUtc, DateTime.utc(2026, 3, 9, 13));
    expect(newYork.timezone.utcOffsetMinutes, -240);
  });

  test(
    'restart reconciliation preserves the persisted IANA timezone and DST instant',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      final ownerId = await repository.activeOwnerId();
      await repository.save(
        StudyReminder(
          id: 'reminder:new-york',
          ownerId: ownerId,
          source: const StudyReminderSource.dueReview(),
          scheduledAtUtc: DateTime.utc(2026, 3, 8, 6, 30),
          timezone: const StudyReminderTimezoneContext(
            timezoneId: 'America/New_York',
            utcOffsetMinutes: -300,
          ),
          quietHours: const ReminderQuietHours(
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
          ),
          isEnabled: true,
          createdAtUtc: DateTime.utc(2026, 3, 1),
          updatedAtUtc: DateTime.utc(2026, 3, 1),
        ),
      );
      useCases = StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 3, 1),
        generateId: () => 'unused',
      );

      await useCases.reconcile(
        featureEnabled: true,
        currentTimezoneId: 'Asia/Bangkok',
      );

      final persisted = (await repository.list()).single;
      expect(persisted.timezone.timezoneId, 'America/New_York');
      expect(persisted.timezone.utcOffsetMinutes, -300);
      expect(persisted.scheduledAtUtc, DateTime.utc(2026, 3, 8, 6, 30));
      expect(scheduler.scheduled.single.timezoneId, 'America/New_York');
      expect(
        scheduler.scheduled.single.scheduledAtUtc,
        DateTime.utc(2026, 3, 8, 11),
      );
    },
  );

  test(
    'invalid persisted timezone fails closed and cancels platform work',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      final ownerId = await repository.activeOwnerId();
      const reminderId = 'reminder:invalid-zone';
      await database.customInsert(
        'INSERT INTO study_reminders '
        '(id, owner_id, source_kind, scheduled_at_utc_ms, timezone_id, '
        'timezone_offset_minutes, is_enabled, created_at_utc_ms, '
        'updated_at_utc_ms, local_revision, is_deleted) '
        'VALUES (?, ?, ?, ?, ?, 0, 1, ?, ?, 1, 0)',
        variables: [
          Variable<String>(reminderId),
          Variable<String>(ownerId),
          const Variable<String>('dueReview'),
          Variable<int>(DateTime.utc(2026, 8, 29).millisecondsSinceEpoch),
          const Variable<String>('Invalid/Timezone'),
          Variable<int>(DateTime.utc(2026, 8, 28).millisecondsSinceEpoch),
          Variable<int>(DateTime.utc(2026, 8, 28).millisecondsSinceEpoch),
        ],
      );
      final platformId = studyReminderPlatformId(ownerId, reminderId);
      scheduler.pending[platformId] = ReminderPlatformEntry(
        platformId: platformId,
        ownerId: ownerId,
        reminderId: reminderId,
      );

      final result = await useCases.reconcile(featureEnabled: true);

      expect(result.failed, greaterThan(0));
      expect(scheduler.pending, isEmpty);
      expect(scheduler.cancelled, contains(platformId));
    },
  );

  test(
    'kill switch cancels future platform work without deleting intent',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      durableFeatureEnabled = false;
      durableFeatureEpoch += 1;

      await useCases.reconcile(
        featureEnabled: false,
        currentTimezoneId: 'Asia/Bangkok',
      );

      final reminder = (await repository.list()).single;
      expect(reminder.isEnabled, isTrue);
      expect(reminder.isDeleted, isFalse);
      expect(scheduler.pending, isEmpty);
      expect(scheduler.cancelled, isNotEmpty);
    },
  );

  test('runtime hint cannot disable a durably enabled reminder', () async {
    scheduler.permission = ReminderPermissionState.granted;
    await useCases.optIn(
      source: const StudyReminderSource.dueReview(),
      scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
      timezoneId: 'Asia/Bangkok',
      mutationAllowed: () => true,
    );
    final platformId = scheduler.pending.keys.single;
    scheduler.pending.clear();

    await useCases.reconcile(featureEnabled: false);

    expect(durableFeatureEnabled, isTrue);
    expect(scheduler.pending.keys, orderedEquals(<int>[platformId]));
  });

  test(
    'unsupported platform is an intentional no-op, not degradation',
    () async {
      scheduler.supported = false;

      final result = await useCases.reconcile(featureEnabled: true);

      expect(result.availability, StudyReminderAvailability.unsupported);
      expect(result.failureKinds, isEmpty);
      expect(result.failed, 0);
      expect(useCases.availability, StudyReminderAvailability.unsupported);
    },
  );

  test('cancel and delete commit before the OS adapter is invoked', () async {
    scheduler.permission = ReminderPermissionState.granted;
    await useCases.optIn(
      source: const StudyReminderSource.dueReview(),
      scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
      timezoneId: 'Asia/Bangkok',
      mutationAllowed: () => true,
    );
    final reminder = (await repository.list()).single;
    await useCases.reconcile(
      featureEnabled: true,
      currentTimezoneId: 'Asia/Bangkok',
    );
    scheduler.beforeCancel = (platformId) async {
      final row = await database.select(database.studyReminders).getSingle();
      expect(row.isEnabled, isFalse);
      expect(
        (await repository.pendingPlatformIntents()).single.kind,
        StudyReminderPlatformIntentKind.cancel,
      );
    };

    await useCases.cancel(reminder.id, mutationAllowed: () => true);
    await useCases.delete(reminder.id, mutationAllowed: () => true);

    final row = await database.select(database.studyReminders).getSingle();
    expect(row.isDeleted, isTrue);
    expect(scheduler.pending, isEmpty);
  });

  test(
    'a cancelled reminder can opt in again without losing evidence',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      final original = (await repository.list()).single;
      await useCases.cancel(original.id, mutationAllowed: () => true);

      final result = await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 30, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );

      final restored = (await repository.list()).single;
      expect(result, StudyReminderOptInResult.scheduled);
      expect(restored.id, original.id);
      expect(restored.createdAtUtc, original.createdAtUtc);
      expect(restored.updatedAtUtc.isAfter(original.updatedAtUtc), isTrue);
      expect(restored.isEnabled, isTrue);
      expect(restored.scheduledAtUtc, DateTime.utc(2026, 8, 30, 2));
    },
  );

  for (final mutation in <String>['cancel', 'delete']) {
    test(
      'serialized reconcile cannot resurrect a concurrent $mutation intent',
      () async {
        scheduler.permission = ReminderPermissionState.granted;
        final scheduleEntered = Completer<void>();
        final releaseSchedule = Completer<void>();
        var blocked = false;
        scheduler.beforeSchedule = (_) async {
          if (blocked) return;
          blocked = true;
          scheduleEntered.complete();
          await releaseSchedule.future;
        };

        final optIn = useCases.optIn(
          source: const StudyReminderSource.dueReview(),
          scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
          timezoneId: 'Asia/Bangkok',
          mutationAllowed: () => true,
        );
        await scheduleEntered.future;
        final reminderId = (await repository.list()).single.id;
        final mutationFuture = mutation == 'cancel'
            ? useCases.cancel(reminderId, mutationAllowed: () => true)
            : useCases.delete(reminderId, mutationAllowed: () => true);

        releaseSchedule.complete();
        await Future.wait<void>([optIn.then((_) {}), mutationFuture]);

        final durable = (await repository.list(includeDeleted: true)).single;
        expect(durable.isEnabled, isFalse);
        expect(durable.isDeleted, mutation == 'delete');
        expect(scheduler.pending, isEmpty);
        expect(await repository.pendingPlatformIntents(), isEmpty);
      },
    );
  }

  test(
    'shared coordinator queues a restarted instance behind in-flight repair',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      final scheduleEntered = Completer<void>();
      final releaseSchedule = Completer<void>();
      scheduler.beforeSchedule = (_) async {
        if (!scheduleEntered.isCompleted) {
          scheduleEntered.complete();
          await releaseSchedule.future;
        }
      };
      final restarted = StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'unused',
      );

      final staleReconcile = useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      await scheduleEntered.future;
      final reminderId = (await repository.list()).single.id;
      var cancellationCompleted = false;
      final cancellation = restarted
          .cancel(reminderId, mutationAllowed: () => true)
          .then((_) => cancellationCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(cancellationCompleted, isFalse);

      releaseSchedule.complete();
      await staleReconcile;
      await cancellation;

      expect((await repository.list()).single.isEnabled, isFalse);
      expect(scheduler.pending, isEmpty);
      expect(await repository.pendingPlatformIntents(), isEmpty);
    },
  );

  test(
    'unrelated repositories do not share a scheduler-keyed operation lock',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      final scheduleEntered = Completer<void>();
      final releaseSchedule = Completer<void>();
      scheduler.beforeSchedule = (_) async {
        if (!scheduleEntered.isCompleted) {
          scheduleEntered.complete();
          await releaseSchedule.future;
        }
      };
      final firstOperation = useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      await scheduleEntered.future;

      final otherDatabase = AppDatabase(NativeDatabase.memory());
      addTearDown(otherDatabase.close);
      final otherRepository = DriftStudyReminderRepository(
        otherDatabase,
        owners: DriftLocalOwnerRepository(
          otherDatabase,
          generateId: () => 'owner-b',
          nowUtc: () => DateTime.utc(2026, 8, 28),
        ),
      );
      final unrelated = StudyReminderUseCases(
        repository: otherRepository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'unused',
      );
      var unrelatedCompleted = false;
      final unrelatedOperation = unrelated
          .reconcile(featureEnabled: false)
          .then((_) => unrelatedCompleted = true);
      await Future<void>.delayed(Duration.zero);
      final completedWithoutRelease = unrelatedCompleted;

      releaseSchedule.complete();
      await Future.wait<void>([
        firstOperation.then((_) {}),
        unrelatedOperation,
      ]);
      expect(completedWithoutRelease, isTrue);
    },
  );

  test(
    'compensating schedule is fenced when a newer cancel commits before it lands',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      final ownerId = await repository.activeOwnerId();
      final enabled = StudyReminder(
        id: 'reminder:compensation-race',
        ownerId: ownerId,
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezone: const StudyReminderTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        isEnabled: true,
        createdAtUtc: DateTime.utc(2026, 8, 28),
        updatedAtUtc: DateTime.utc(2026, 8, 28),
      );
      await repository.save(enabled);
      await repository.acknowledgePlatformIntent(
        (await repository.pendingPlatformIntents()).single,
        acknowledgedAtUtc: DateTime.utc(2026, 8, 28, 0, 1),
      );
      await repository.cancel(
        enabled.id,
        updatedAtUtc: DateTime.utc(2026, 8, 28, 0, 2),
      );
      await repository.acknowledgePlatformIntent(
        (await repository.pendingPlatformIntents()).single,
        acknowledgedAtUtc: DateTime.utc(2026, 8, 28, 0, 3),
      );
      final platformId = studyReminderPlatformId(ownerId, enabled.id);
      scheduler.pending[platformId] = ReminderPlatformEntry(
        platformId: platformId,
        ownerId: ownerId,
        reminderId: enabled.id,
      );
      scheduler.hidePendingEntriesCalls = 1;
      var reenabled = false;
      scheduler.beforeCancel = (_) async {
        if (reenabled) return;
        reenabled = true;
        final disabled = (await repository.desiredState(ownerId, enabled.id))!;
        await repository.save(
          disabled.reminder.copyWith(
            isEnabled: true,
            updatedAtUtc: DateTime.utc(2026, 8, 28, 0, 4),
          ),
        );
      };
      final compensationEntered = Completer<void>();
      final releaseCompensation = Completer<void>();
      scheduler.beforeSchedule = (_) async {
        compensationEntered.complete();
        await releaseCompensation.future;
      };

      final reconciliation = useCases.reconcile(featureEnabled: true);
      await compensationEntered.future;
      await repository.cancel(
        enabled.id,
        updatedAtUtc: DateTime.utc(2026, 8, 28, 0, 5),
      );
      releaseCompensation.complete();
      await reconciliation;

      final durable = (await repository.list(includeDeleted: true)).single;
      expect(durable.isEnabled, isFalse);
      expect(scheduler.pending, isEmpty);
      final pendingIntent = (await repository.pendingPlatformIntents()).single;
      expect(pendingIntent.kind, StudyReminderPlatformIntentKind.cancel);
    },
  );

  test(
    'serialized feature-off reconcile cancels an in-flight schedule',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      final scheduleEntered = Completer<void>();
      final releaseSchedule = Completer<void>();
      scheduler.beforeSchedule = (_) async {
        if (!scheduleEntered.isCompleted) scheduleEntered.complete();
        await releaseSchedule.future;
      };

      final optIn = useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      await scheduleEntered.future;
      durableFeatureEnabled = false;
      durableFeatureEpoch += 1;
      final featureOff = useCases.reconcile(featureEnabled: false);

      releaseSchedule.complete();
      await Future.wait<void>([optIn.then((_) {}), featureOff.then((_) {})]);

      expect(scheduler.pending, isEmpty);
      expect((await repository.list()).single.isEnabled, isTrue);
    },
  );

  test(
    'owner change isolates source cleanup before feature-off target cleanup',
    () async {
      scheduler.permission = ReminderPermissionState.granted;
      await useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      final oldReminder = (await repository.list()).single;
      const newOwnerPlatformId = 900001;
      scheduler.pending[newOwnerPlatformId] = const ReminderPlatformEntry(
        platformId: newOwnerPlatformId,
        ownerId: 'local:owner-b',
        reminderId: 'reminder:owner-b',
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'local:owner-b',
              createdAtUtcMs: DateTime.utc(2026, 8, 28).millisecondsSinceEpoch,
              isActive: const Value(false),
            ),
          );

      durableFeatureEnabled = false;
      durableFeatureEpoch += 1;

      final target = await useCases.coordinateOwnerChange<String>(
        sourceOwnerId: 'local:owner-a',
        operation: () async {
          expect(
            scheduler.pending.containsKey(
              studyReminderPlatformId('local:owner-a', oldReminder.id),
            ),
            isFalse,
          );
          expect(scheduler.pending.containsKey(newOwnerPlatformId), isTrue);
          expect(
            await database.select(database.studyReminders).get(),
            hasLength(1),
          );
          await database.customUpdate('UPDATE local_owners SET is_active = 0');
          await database.customUpdate(
            "UPDATE local_owners SET is_active = 1 WHERE id = 'local:owner-b'",
          );
          return 'local:owner-b';
        },
        targetOwnerId: (result) => result,
        featureEnabled: false,
      );

      expect(target, 'local:owner-b');
      expect(scheduler.pending, isEmpty);
      expect(scheduler.cancelled, contains(newOwnerPlatformId));
      expect(
        await database.select(database.studyReminders).get(),
        hasLength(1),
      );
    },
  );
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

final class _Scheduler implements ReminderScheduler {
  bool supported = true;
  ReminderPermissionState permission = ReminderPermissionState.unknown;
  ReminderPermissionState requestResult = ReminderPermissionState.granted;
  int requestCalls = 0;
  int failSchedules = 0;
  int hidePendingEntriesCalls = 0;
  final List<ReminderScheduleRequest> scheduled = [];
  final List<int> cancelled = [];
  final Map<int, ReminderPlatformEntry> pending = {};
  Future<void> Function(ReminderScheduleRequest request)? beforeSchedule;
  Future<void> Function(int platformId)? beforeCancel;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermission() async {
    requestCalls += 1;
    permission = requestResult;
    return requestResult;
  }

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async {
    if (hidePendingEntriesCalls > 0) {
      hidePendingEntriesCalls -= 1;
      return const [];
    }
    return pending.values.toList(growable: false);
  }

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {
    await beforeSchedule?.call(request);
    if (failSchedules > 0) {
      failSchedules -= 1;
      throw StateError('transient platform failure');
    }
    scheduled
      ..removeWhere((entry) => entry.platformId == request.platformId)
      ..add(request);
    pending[request.platformId] = ReminderPlatformEntry(
      platformId: request.platformId,
      ownerId: request.ownerId,
      reminderId: request.reminderId,
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    await beforeCancel?.call(platformId);
    pending.remove(platformId);
    cancelled.add(platformId);
  }
}
