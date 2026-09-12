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
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

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

  group('read-only reminder status snapshot', () {
    const source = StudyReminderSource.dueReview();
    final statusNow = DateTime.utc(2026, 8, 28);

    Future<StudyReminder> seed({
      bool acknowledge = true,
      bool native = true,
      bool elapsed = false,
    }) async {
      final ownerId = await repository.activeOwnerId();
      final reminder = StudyReminder(
        id: 'status-reminder',
        ownerId: ownerId,
        source: source,
        scheduledAtUtc: elapsed
            ? statusNow
            : statusNow.add(const Duration(days: 1)),
        timezone: const StudyReminderTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        isEnabled: true,
        createdAtUtc: statusNow,
        updatedAtUtc: statusNow,
      );
      await repository.save(reminder);
      if (acknowledge) {
        await repository.acknowledgePlatformIntent(
          (await repository.pendingPlatformIntents()).single,
          acknowledgedAtUtc: statusNow,
        );
      }
      scheduler.permission = ReminderPermissionState.granted;
      if (native) {
        final id = studyReminderPlatformId(ownerId, reminder.id);
        scheduler.pending[id] = ReminderPlatformEntry(
          platformId: id,
          ownerId: ownerId,
          reminderId: reminder.id,
        );
      }
      return reminder;
    }

    Future<StudyReminderStatusSnapshot> read(String ownerId) =>
        useCases.loadStatus(expectedOwnerId: ownerId, source: source);

    test(
      'no desired reminder is disabled without permission prompt or writes',
      () async {
        final owner = await repository.activeOwnerId();
        final result = await read(owner);
        expect(result.status, StudyReminderDisplayStatus.disabled);
        expect(result.reminder, isNull);
        expect(scheduler.requestCalls, 0);
        expect(scheduler.scheduled, isEmpty);
        expect(await database.select(database.studyReminders).get(), isEmpty);
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );

    test(
      'persisted disabled reminder stays disabled despite a native entry',
      () async {
        final reminder = await seed();
        await repository.cancel(
          reminder.id,
          updatedAtUtc: statusNow.add(const Duration(seconds: 1)),
        );
        final beforeRows =
            (await database.select(database.studyReminders).get())
                .map((row) => row.toJson())
                .toList();
        final beforeOutbox =
            (await database.select(database.outboxOperations).get())
                .map((row) => row.toJson())
                .toList();
        final result = await read(reminder.ownerId);
        expect(result.status, StudyReminderDisplayStatus.disabled);
        expect(result.reminder!.id, reminder.id);
        expect(result.reminder!.isEnabled, isFalse);
        expect(
          (await database.select(database.studyReminders).get())
              .map((row) => row.toJson())
              .toList(),
          beforeRows,
        );
        expect(
          (await database.select(database.outboxOperations).get())
              .map((row) => row.toJson())
              .toList(),
          beforeOutbox,
        );
        expect(scheduler.pending, hasLength(1));
        expect(scheduler.cancelled, isEmpty);
        expect(scheduler.scheduled, isEmpty);
        expect(scheduler.requestCalls, 0);
      },
    );

    test(
      'stale expected owner is rejected at entry before native queries',
      () async {
        final reminder = await seed();
        var nativeQueried = false;
        scheduler.beforePermissionReturn = () async {
          nativeQueried = true;
        };
        scheduler.beforePendingReturn = () async {
          nativeQueried = true;
        };
        await expectLater(
          read('retired-status-owner'),
          throwsA(isA<StudyReminderMutationUnavailable>()),
        );
        expect(nativeQueried, isFalse);
        expect((await repository.list()).single.id, reminder.id);
        expect(scheduler.requestCalls, 0);
        expect(scheduler.scheduled, isEmpty);
        expect(scheduler.cancelled, isEmpty);
      },
    );

    test(
      'confirmed scheduled snapshot is read-only and retains exact reminder',
      () async {
        final reminder = await seed();
        final beforeRows =
            (await database.select(database.studyReminders).get())
                .map((row) => row.toJson())
                .toList();
        final beforeOutbox =
            (await database.select(database.outboxOperations).get())
                .map((row) => row.toJson())
                .toList();
        for (var i = 0; i < 2; i++) {
          final result = await read(reminder.ownerId);
          expect(result.status, StudyReminderDisplayStatus.scheduled);
          expect(result.reminder!.id, reminder.id);
          expect(result.reminder!.updatedAtUtc, reminder.updatedAtUtc);
        }
        expect(
          (await database.select(database.studyReminders).get())
              .map((row) => row.toJson())
              .toList(),
          beforeRows,
        );
        expect(
          (await database.select(database.outboxOperations).get())
              .map((row) => row.toJson())
              .toList(),
          beforeOutbox,
        );
        expect(scheduler.requestCalls, 0);
        expect(scheduler.scheduled, isEmpty);
        expect(scheduler.cancelled, isEmpty);
        expect(scheduler.pending, hasLength(1));
      },
    );

    for (final native in [false, true]) {
      test(
        'unresolved platform intent remains pending native=$native',
        () async {
          final reminder = await seed(acknowledge: false, native: native);
          expect(
            (await read(reminder.ownerId)).status,
            StudyReminderDisplayStatus.pendingRetry,
          );
          expect(await repository.pendingPlatformIntents(), hasLength(1));
          expect(scheduler.requestCalls, 0);
          expect(scheduler.scheduled, isEmpty);
        },
      );
    }

    for (final mismatch in ['missing', 'platform-id', 'owner', 'reminder']) {
      test(
        'acknowledged intent cannot confirm $mismatch native identity',
        () async {
          final reminder = await seed(native: false);
          if (mismatch != 'missing') {
            final id =
                studyReminderPlatformId(reminder.ownerId, reminder.id) +
                (mismatch == 'platform-id' ? 1 : 0);
            scheduler.pending[id] = ReminderPlatformEntry(
              platformId: id,
              ownerId: mismatch == 'owner' ? 'foreign-owner' : reminder.ownerId,
              reminderId: mismatch == 'reminder'
                  ? 'foreign-reminder'
                  : reminder.id,
            );
          }
          expect(
            (await read(reminder.ownerId)).status,
            StudyReminderDisplayStatus.pendingRetry,
          );
          expect(scheduler.cancelled, isEmpty);
          expect(scheduler.scheduled, isEmpty);
        },
      );
    }

    for (final permission in [
      ReminderPermissionState.denied,
      ReminderPermissionState.unknown,
    ]) {
      test(
        'current permission $permission overrides native scheduled entry',
        () async {
          final reminder = await seed();
          scheduler.permission = permission;
          expect(
            (await read(reminder.ownerId)).status,
            permission == ReminderPermissionState.denied
                ? StudyReminderDisplayStatus.permissionDenied
                : StudyReminderDisplayStatus.unavailable,
          );
          expect(scheduler.requestCalls, 0);
          expect(scheduler.pending, hasLength(1));
          expect(scheduler.cancelled, isEmpty);
        },
      );
    }

    for (final failure in [
      'permission',
      'native',
      'feature-off',
      'unsupported',
    ]) {
      test('$failure cannot report a confirmed scheduled reminder', () async {
        final reminder = await seed();
        if (failure == 'permission')
          scheduler.beforePermissionReturn = () async =>
              throw StateError('synthetic permission failure');
        if (failure == 'native')
          scheduler.beforePendingReturn = () async =>
              throw StateError('synthetic native enumeration failure');
        if (failure == 'feature-off') {
          durableFeatureEnabled = false;
          durableFeatureEpoch++;
        }
        if (failure == 'unsupported') scheduler.supported = false;
        expect(
          (await read(reminder.ownerId)).status,
          StudyReminderDisplayStatus.unavailable,
        );
        expect(scheduler.requestCalls, 0);
        expect(scheduler.scheduled, isEmpty);
        expect(scheduler.cancelled, isEmpty);
      });
    }

    test(
      'elapsed one-shot time is not confirmation of notification delivery',
      () async {
        final reminder = await seed(elapsed: true);
        expect(
          (await read(reminder.ownerId)).status,
          StudyReminderDisplayStatus.elapsed,
        );
        expect(scheduler.scheduled, isEmpty);
        expect(scheduler.cancelled, isEmpty);
      },
    );

    for (final mutation in ['revision', 'feature-epoch', 'owner']) {
      test(
        '$mutation change during native read rejects the obsolete snapshot',
        () async {
          final reminder = await seed();
          scheduler.beforePendingReturn = () async {
            scheduler.beforePendingReturn = null;
            switch (mutation) {
              case 'revision':
                await repository.save(
                  reminder.copyWith(
                    scheduledAtUtc: reminder.scheduledAtUtc.add(
                      const Duration(hours: 1),
                    ),
                    updatedAtUtc: statusNow.add(const Duration(seconds: 1)),
                  ),
                );
              case 'feature-epoch':
                durableFeatureEpoch++;
              case 'owner':
                await database.transaction(() async {
                  await database.customStatement(
                    'UPDATE local_owners SET is_active = 0',
                  );
                  await database
                      .into(database.localOwners)
                      .insert(
                        LocalOwnersCompanion.insert(
                          id: 'status-owner-b',
                          createdAtUtcMs: 1,
                        ),
                      );
                });
            }
          };
          if (mutation == 'owner') {
            await expectLater(
              read(reminder.ownerId),
              throwsA(isA<StudyReminderMutationUnavailable>()),
            );
          } else {
            expect(
              (await read(reminder.ownerId)).status,
              StudyReminderDisplayStatus.unavailable,
            );
          }
          expect(scheduler.requestCalls, 0);
          expect(scheduler.scheduled, isEmpty);
          expect(scheduler.cancelled, isEmpty);
        },
      );
    }

    test(
      'canonical owner fence makes status unavailable without native mutation',
      () async {
        final reminder = await seed();
        final gate = DriftOwnerOperationGate(database);
        const token = 'status-owner-transition';
        expect(
          await gate.tryAcquire(
            token: token,
            nowUtc: statusNow,
            leaseDuration: const Duration(minutes: 1),
          ),
          isTrue,
        );
        try {
          await repository.beginOwnerOperationFence(
            ownerId: reminder.ownerId,
            operationToken: token,
            nowUtc: statusNow,
          );
          expect(
            (await read(reminder.ownerId)).status,
            StudyReminderDisplayStatus.unavailable,
          );
          expect(scheduler.requestCalls, 0);
          expect(scheduler.scheduled, isEmpty);
          expect(scheduler.cancelled, isEmpty);
        } finally {
          await repository.endOwnerOperationFence(
            ownerId: reminder.ownerId,
            operationToken: token,
          );
          await gate.release(token: token);
        }
      },
    );
  });

  group('owner transition reminder lifecycle', () {
    late DateTime transitionNow;
    late DriftOwnerOperationGate gate;
    const token = 'synthetic-reminder-transition';

    setUp(() {
      transitionNow = DateTime.utc(2026, 8, 28);
      gate = DriftOwnerOperationGate(database);
      useCases = StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => transitionNow,
        generateId: () => 'unused-transition-id',
        loadFeatureEligibility: () async => StudyReminderFeatureEligibility(
          enabled: durableFeatureEnabled,
          epoch: durableFeatureEpoch,
        ),
      );
      scheduler.permission = ReminderPermissionState.granted;
    });

    Future<String> seed({bool two = false}) async {
      final owner = await repository.activeOwnerId();
      if (two) await _insertGoal(database, owner);
      for (var i = 0; i < (two ? 2 : 1); i++) {
        final reminder = StudyReminder(
          id: 'transition-reminder-$i',
          ownerId: owner,
          source: i == 0
              ? const StudyReminderSource.dueReview()
              : StudyReminderSource.goalDeadline('goal:ielts'),
          scheduledAtUtc: transitionNow.add(const Duration(days: 1)),
          timezone: const StudyReminderTimezoneContext(
            timezoneId: 'Asia/Bangkok',
            utcOffsetMinutes: 420,
          ),
          isEnabled: true,
          createdAtUtc: transitionNow,
          updatedAtUtc: transitionNow,
        );
        await repository.save(reminder);
      }
      await useCases.reconcile(featureEnabled: true);
      scheduler.cancelled.clear();
      scheduler.scheduled.clear();
      expect(
        await gate.tryAcquire(
          token: token,
          nowUtc: transitionNow,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      return owner;
    }

    Future<String> changeOwner() async {
      await database.transaction(() async {
        await database.customStatement('UPDATE local_owners SET is_active = 0');
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'transition-target',
                createdAtUtcMs: 1,
              ),
            );
      });
      return 'transition-target';
    }

    for (final failure in ['partial-precancel', 'operation']) {
      test(
        '$failure aborts or rolls back and restores source only after unfence',
        () async {
          final owner = await seed(two: true);
          final originalIds = scheduler.pending.keys.toSet();
          final operationFailure = StateError(
            'synthetic authoritative operation failure',
          );
          var cancelledCalls = 0;
          var operationCalls = 0;
          scheduler.beforeCancel = (_) async {
            cancelledCalls++;
            if (failure == 'partial-precancel' && cancelledCalls == 2)
              throw StateError('synthetic second precancel failure');
          };
          scheduler.beforeSchedule = (_) async {
            expect(
              await repository.isOwnerOperationFenced(
                ownerId: owner,
                nowUtc: transitionNow,
              ),
              isFalse,
            );
            expect(
              await gate.isOwned(token: token, nowUtc: transitionNow),
              isTrue,
            );
          };
          try {
            await expectLater(
              useCases.coordinateOwnerChange<String>(
                sourceOwnerId: owner,
                operationToken: token,
                operation: () async {
                  operationCalls++;
                  throw operationFailure;
                },
                targetOwnerId: (result) => result,
                featureEnabled: true,
              ),
              failure == 'operation'
                  ? throwsA(same(operationFailure))
                  : throwsStateError,
            );
            expect(operationCalls, failure == 'operation' ? 1 : 0);
            expect(await repository.activeOwnerId(), owner);
            expect(scheduler.pending.keys.toSet(), originalIds);
            expect(
              scheduler.scheduled,
              isNotEmpty,
              reason:
                  'At least the successfully precancelled entry must be restored.',
            );
            expect(
              await repository.isOwnerOperationFenced(
                ownerId: owner,
                nowUtc: transitionNow,
              ),
              isFalse,
            );
            expect(scheduler.requestCalls, 0);
          } finally {
            await gate.release(token: token);
          }
        },
      );
    }

    for (final outcome in ['committed', 'failed']) {
      test(
        'end-fence failure preserves $outcome outcome and never restores behind marker',
        () async {
          final owner = await seed();
          final originalError = StateError(
            'synthetic original transition failure',
          );
          await database.customStatement('''
          CREATE TEMP TRIGGER fail_transition_unfence BEFORE DELETE ON runtime_flags
          WHEN OLD.source = '$token' AND OLD."key" <> '${DriftOwnerOperationGate.gateKey}'
          BEGIN SELECT RAISE(ABORT, 'synthetic unfence failure'); END
        ''');
          try {
            final pending = useCases.coordinateOwnerChange<String>(
              sourceOwnerId: owner,
              operationToken: token,
              operation: () async {
                if (outcome == 'failed') throw originalError;
                return changeOwner();
              },
              targetOwnerId: (result) => result,
              featureEnabled: true,
            );
            if (outcome == 'failed') {
              await expectLater(pending, throwsA(same(originalError)));
            } else {
              expect(await pending, 'transition-target');
            }
            expect(
              await repository.activeOwnerId(),
              outcome == 'failed' ? owner : 'transition-target',
            );
            expect(useCases.availability, StudyReminderAvailability.degraded);
            expect(scheduler.scheduled, isEmpty);
            expect(
              await repository.isOwnerOperationFenced(
                ownerId: owner,
                nowUtc: transitionNow,
              ),
              isTrue,
            );
            await gate.release(token: token);
            expect(
              await repository.isOwnerOperationFenced(
                ownerId: owner,
                nowUtc: transitionNow,
              ),
              isFalse,
              reason:
                  'A failed marker deletion is inert after its actual lease ends.',
            );
          } finally {
            await database.customStatement(
              'DROP TRIGGER IF EXISTS fail_transition_unfence',
            );
            await repository.endOwnerOperationFence(
              ownerId: owner,
              operationToken: token,
            );
            await gate.release(token: token);
          }
        },
      );
    }

    test(
      'same-owner takeover during precancel prevents mutation and further cleanup',
      () async {
        final owner = await seed(two: true);
        var cancelCalls = 0;
        var operationCalls = 0;
        scheduler.beforeCancel = (_) async {
          cancelCalls++;
          if (cancelCalls != 1) return;
          await gate.release(token: token);
          expect(
            await gate.tryAcquire(
              token: 'replacement-transition',
              nowUtc: transitionNow,
              leaseDuration: const Duration(minutes: 1),
            ),
            isTrue,
          );
        };
        try {
          await expectLater(
            useCases.coordinateOwnerChange<String>(
              sourceOwnerId: owner,
              operationToken: token,
              operation: () async {
                operationCalls++;
                return owner;
              },
              targetOwnerId: (result) => result,
              featureEnabled: true,
            ),
            throwsStateError,
          );
          expect(operationCalls, 0);
          expect(cancelCalls, 1);
          expect(scheduler.scheduled, isEmpty);
          expect(await repository.activeOwnerId(), owner);
          expect(
            await gate.isOwned(
              token: 'replacement-transition',
              nowUtc: transitionNow,
            ),
            isTrue,
          );
        } finally {
          await gate.release(token: token);
          await gate.release(token: 'replacement-transition');
        }
      },
    );

    for (final loss in ['expired', 'taken-over']) {
      test(
        'postcommit $loss token cannot sweep replacement native state',
        () async {
          final owner = await seed();
          final captured = scheduler.pending.values.single;
          try {
            final result = await useCases.coordinateOwnerChange<String>(
              sourceOwnerId: owner,
              operationToken: token,
              operation: () async {
                final target = await changeOwner();
                scheduler.cancelled.clear();
                scheduler.pending[captured.platformId] = ReminderPlatformEntry(
                  platformId: captured.platformId,
                  ownerId: target,
                  reminderId: 'replacement-native',
                );
                transitionNow = transitionNow.add(const Duration(minutes: 1));
                if (loss == 'taken-over') {
                  expect(
                    await gate.tryAcquire(
                      token: 'replacement-transition',
                      nowUtc: transitionNow,
                      leaseDuration: const Duration(minutes: 1),
                    ),
                    isTrue,
                  );
                }
                return target;
              },
              targetOwnerId: (result) => result,
              featureEnabled: true,
            );
            expect(result, 'transition-target');
            expect(scheduler.cancelled, isEmpty);
            expect(
              scheduler.pending[captured.platformId]!.ownerId,
              'transition-target',
            );
            expect(scheduler.scheduled, isEmpty);
          } finally {
            await gate.release(token: token);
            await gate.release(token: 'replacement-transition');
          }
        },
      );
    }

    test(
      'postcommit cancel failure preserves result and fresh reconcile repairs actual captured ID',
      () async {
        final owner = await seed();
        const actualId = 776611;
        final orphan = ReminderPlatformEntry(
          platformId: actualId,
          ownerId: owner,
          reminderId: 'deleted-native-only-reminder',
        );
        scheduler.pending[actualId] = orphan;
        var committed = false;
        scheduler.beforeCancel = (_) async {
          if (committed)
            throw StateError(
              'synthetic persistent native cancellation failure',
            );
        };
        try {
          final target = await useCases.coordinateOwnerChange<String>(
            sourceOwnerId: owner,
            operationToken: token,
            operation: () async {
              final target = await changeOwner();
              await database.customStatement(
                'DELETE FROM outbox_operations WHERE owner_id = ?',
                [owner],
              );
              await database.customStatement(
                'DELETE FROM study_reminders WHERE owner_id = ?',
                [owner],
              );
              scheduler.pending[actualId] = orphan;
              committed = true;
              return target;
            },
            targetOwnerId: (result) => result,
            featureEnabled: true,
          );
          expect(target, 'transition-target');
          expect(await repository.activeOwnerId(), target);
          expect(scheduler.pending, contains(actualId));
          expect(
            useCases.availability,
            StudyReminderAvailability.degraded,
            reason:
                'Successful target reconciliation cannot erase a known captured-ID cancellation failure.',
          );
        } finally {
          await gate.release(token: token);
        }
        scheduler.beforeCancel = null;
        scheduler.cancelled.clear();
        final restarted = StudyReminderUseCases(
          repository: repository,
          scheduler: scheduler,
          nowUtc: () => transitionNow,
          generateId: () => 'unused-restart-id',
        );
        final repaired = await restarted.reconcile(featureEnabled: true);
        expect(repaired.failed, 0);
        expect(scheduler.cancelled, contains(actualId));
        expect(scheduler.pending, isNot(contains(actualId)));
        expect(scheduler.scheduled, isEmpty);
        expect(scheduler.requestCalls, 0);
      },
    );
  });

  for (final boundary in ['enumeration', 'issued-cancel']) {
    test(
      'independent fenced worker $boundary cannot remove restored same-owner reminder',
      () async {
        scheduler.permission = ReminderPermissionState.granted;
        expect(
          await useCases.optIn(
            source: const StudyReminderSource.dueReview(),
            scheduledAtUtc: DateTime.utc(2026, 8, 29),
            timezoneId: 'Asia/Bangkok',
            mutationAllowed: () => true,
          ),
          StudyReminderOptInResult.scheduled,
        );
        final original = scheduler.pending.values.single;
        final independentRepository = DriftStudyReminderRepository(
          database,
          owners: DriftLocalOwnerRepository(
            database,
            generateId: () => 'must-not-create-worker-owner',
            nowUtc: () => DateTime.utc(2026, 8, 28),
          ),
        );
        final worker = StudyReminderUseCases(
          repository: independentRepository,
          scheduler: scheduler,
          nowUtc: () => DateTime.utc(2026, 8, 28),
          generateId: () => 'must-not-create-worker-reminder',
          loadFeatureEligibility: () async => StudyReminderFeatureEligibility(
            enabled: durableFeatureEnabled,
            epoch: durableFeatureEpoch,
          ),
        );
        final gate = DriftOwnerOperationGate(database);
        const token = 'synthetic-same-owner-fence';
        final entered = Completer<void>();
        final release = Completer<void>();
        Future<void>? drained;
        try {
          expect(
            await gate.tryAcquire(
              token: token,
              nowUtc: DateTime.utc(2026, 8, 28),
              leaseDuration: const Duration(minutes: 1),
            ),
            isTrue,
          );
          await repository.beginOwnerOperationFence(
            ownerId: original.ownerId,
            operationToken: token,
            nowUtc: DateTime.utc(2026, 8, 28),
          );
          if (boundary == 'enumeration') {
            scheduler.beforePendingReturn = () async {
              scheduler.beforePendingReturn = null;
              entered.complete();
              await release.future;
            };
          } else {
            scheduler.beforeCancel = (id) async {
              if (id != original.platformId) return;
              scheduler.beforeCancel = null;
              entered.complete();
              await release.future;
            };
          }
          final pending = worker.reconcile(featureEnabled: true);
          drained = pending.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          await entered.future.timeout(const Duration(seconds: 3));
          // The foreground finishes its cleanup and restores the SAME owner
          // after its exact canonical fence ends. The worker still holds old
          // native work, in a distinct reminder serializer/repository.
          await scheduler.cancel(original.platformId);
          await repository.endOwnerOperationFence(
            ownerId: original.ownerId,
            operationToken: token,
          );
          await gate.release(token: token);
          scheduler.scheduled.clear();
          await useCases.reconcile(featureEnabled: true);
          expect(await repository.activeOwnerId(), original.ownerId);
          expect(
            scheduler.scheduled.map((request) => request.platformId),
            contains(original.platformId),
          );
          expect(scheduler.pending[original.platformId], original);
          release.complete();
          final result = await pending.timeout(const Duration(seconds: 3));
          expect(result.failed, 0);
          expect(
            scheduler.pending[original.platformId],
            original,
            reason:
                'A retired fence cannot authorize deletion of the restored schedule.',
          );
          expect(scheduler.requestCalls, 0);
        } finally {
          if (!release.isCompleted) release.complete();
          if (drained != null)
            await drained.timeout(const Duration(seconds: 3));
          await repository.endOwnerOperationFence(
            ownerId: original.ownerId,
            operationToken: token,
          );
          await gate.release(token: token);
        }
      },
    );
  }

  test(
    'issued orphan cancellation converges after payload owner reactivates with revised desired state',
    () async {
      final originalOwner = await repository.activeOwnerId();
      const returningOwner = 'returning-native-owner';
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: returningOwner,
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      Future<void> activate(String owner) => database.transaction(() async {
        await database.customStatement('UPDATE local_owners SET is_active = 0');
        await database.customStatement(
          'UPDATE local_owners SET is_active = 1 WHERE id = ?',
          [owner],
        );
      });
      scheduler.permission = ReminderPermissionState.granted;
      await activate(returningOwner);
      expect(
        await useCases.optIn(
          source: const StudyReminderSource.dueReview(),
          scheduledAtUtc: DateTime.utc(2026, 8, 29),
          timezoneId: 'Asia/Bangkok',
          mutationAllowed: () => true,
        ),
        StudyReminderOptInResult.scheduled,
      );
      final native = scheduler.pending.values.single;
      await activate(originalOwner);
      final workerRepository = DriftStudyReminderRepository(
        database,
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unused-orphan-worker',
          nowUtc: () => DateTime.utc(2026, 8, 28),
        ),
      );
      final worker = StudyReminderUseCases(
        repository: workerRepository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'unused-worker-reminder',
        loadFeatureEligibility: () async => StudyReminderFeatureEligibility(
          enabled: durableFeatureEnabled,
          epoch: durableFeatureEpoch,
        ),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      scheduler.beforeCancel = (id) async {
        if (id != native.platformId) return;
        scheduler.beforeCancel = null;
        entered.complete();
        await release.future;
      };
      final pending = worker.reconcile(featureEnabled: true);
      final drained = pending.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        await entered.future.timeout(const Duration(seconds: 3));
        await activate(returningOwner);
        await scheduler.cancel(native.platformId);
        final revisedTime = DateTime.utc(2026, 8, 30);
        expect(
          await useCases.optIn(
            source: const StudyReminderSource.dueReview(),
            scheduledAtUtc: revisedTime,
            timezoneId: 'Asia/Bangkok',
            mutationAllowed: () => true,
          ),
          StudyReminderOptInResult.scheduled,
        );
        expect(scheduler.pending[native.platformId], native);
        scheduler.scheduled.clear();
        release.complete();
        final result = await pending.timeout(const Duration(seconds: 3));
        expect(result.failed, 0);
        expect(await repository.activeOwnerId(), returningOwner);
        expect(scheduler.pending[native.platformId], native);
        expect(
          scheduler.scheduled.single.scheduledAtUtc,
          revisedTime,
          reason:
              'Repair must read the fresh desired revision, not replay a captured request.',
        );
        expect(scheduler.requestCalls, 0);
      } finally {
        if (!release.isCompleted) release.complete();
        await drained.timeout(const Duration(seconds: 3));
      }
    },
  );

  for (final failingBoundary in ['enumeration', 'cancel']) {
    test(
      'fenced worker native $failingBoundary failure reports degraded status',
      () async {
        final owner = await repository.activeOwnerId();
        final gate = DriftOwnerOperationGate(database);
        const token = 'synthetic-fenced-failure';
        const nativeId = 432114;
        scheduler.pending[nativeId] = ReminderPlatformEntry(
          platformId: nativeId,
          ownerId: owner,
          reminderId: 'fenced-native-failure',
        );
        try {
          expect(
            await gate.tryAcquire(
              token: token,
              nowUtc: DateTime.utc(2026, 8, 28),
              leaseDuration: const Duration(minutes: 1),
            ),
            isTrue,
          );
          await repository.beginOwnerOperationFence(
            ownerId: owner,
            operationToken: token,
            nowUtc: DateTime.utc(2026, 8, 28),
          );
          if (failingBoundary == 'enumeration') {
            scheduler.beforePendingReturn = () async =>
                throw StateError('synthetic fenced enumeration failure');
          } else {
            scheduler.beforeCancel = (_) async =>
                throw StateError('synthetic fenced cancellation failure');
          }
          final result = await useCases.reconcile(featureEnabled: true);
          expect(result.failed, greaterThan(0));
          expect(result.availability, StudyReminderAvailability.degraded);
          expect(useCases.availability, StudyReminderAvailability.degraded);
          expect(
            result.failureKinds,
            contains(
              failingBoundary == 'enumeration'
                  ? StudyReminderFailureKind.pendingEntries
                  : StudyReminderFailureKind.platformSideEffect,
            ),
          );
          expect(scheduler.pending, contains(nativeId));
        } finally {
          await repository.endOwnerOperationFence(
            ownerId: owner,
            operationToken: token,
          );
          await gate.release(token: token);
        }
      },
    );
  }

  for (final mode in ['enabled', 'feature-off', 'permission-denied']) {
    test('reconcile removes inactive-owner native orphan mode=$mode', () async {
      final activeOwner = await repository.activeOwnerId();
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'retired-source',
              accountState: const Value('localGuest'),
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      const actualNativeId = 432109;
      scheduler.pending[actualNativeId] = const ReminderPlatformEntry(
        platformId: actualNativeId,
        ownerId: 'retired-source',
        reminderId: 'deleted-source-reminder',
      );
      scheduler.permission = mode == 'permission-denied'
          ? ReminderPermissionState.denied
          : ReminderPermissionState.granted;
      durableFeatureEnabled = mode != 'feature-off';
      // A fresh use case has no captured transition IDs: cleanup must discover
      // the native payload even though its source desired-state row is gone.
      final restarted = StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'unused-orphan-repair-id',
        loadFeatureEligibility: () async => StudyReminderFeatureEligibility(
          enabled: durableFeatureEnabled,
          epoch: durableFeatureEpoch,
        ),
      );
      final result = await restarted.reconcile(
        featureEnabled: durableFeatureEnabled,
      );
      expect(result.failed, 0);
      expect(scheduler.cancelled, contains(actualNativeId));
      expect(scheduler.pending, isNot(contains(actualNativeId)));
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.requestCalls, 0);
      expect(await repository.activeOwnerId(), activeOwner);
    });
  }

  test(
    'failed orphan cancellation stays degraded and discoverable on retry',
    () async {
      await repository.activeOwnerId();
      const orphanId = 432110;
      scheduler.permission = ReminderPermissionState.granted;
      scheduler.pending[orphanId] = const ReminderPlatformEntry(
        platformId: orphanId,
        ownerId: 'deleted-owner',
        reminderId: 'deleted-reminder',
      );
      scheduler.beforeCancel = (id) async {
        if (id == orphanId)
          throw StateError('synthetic native cancellation failure');
      };
      final failed = await useCases.reconcile(featureEnabled: true);
      expect(failed.failed, greaterThan(0));
      expect(scheduler.pending, contains(orphanId));
      scheduler.beforeCancel = null;
      final retry = await useCases.reconcile(featureEnabled: true);
      expect(retry.failed, 0);
      expect(scheduler.cancelled, contains(orphanId));
      expect(scheduler.pending, isNot(contains(orphanId)));
      expect(scheduler.scheduled, isEmpty);
    },
  );

  for (final fencedOwner in ['active', 'orphan']) {
    test(
      'new $fencedOwner canonical fence while native enumeration waits stops orphan cancellation',
      () async {
        final activeOwner = await repository.activeOwnerId();
        const orphanOwner = 'retired-fenced-owner';
        const nativeId = 432112;
        const token = 'synthetic-enumeration-fence';
        final fenceOwner = fencedOwner == 'active' ? activeOwner : orphanOwner;
        final gate = DriftOwnerOperationGate(database);
        final entered = Completer<void>();
        final release = Completer<void>();
        scheduler.permission = ReminderPermissionState.granted;
        scheduler.pending[nativeId] = const ReminderPlatformEntry(
          platformId: nativeId,
          ownerId: orphanOwner,
          reminderId: 'retired-reminder',
        );
        scheduler.beforePendingReturn = () async {
          scheduler.beforePendingReturn = null;
          entered.complete();
          await release.future;
        };
        final pending = useCases.reconcile(featureEnabled: true);
        final drained = pending.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        try {
          await entered.future.timeout(const Duration(seconds: 3));
          expect(
            await gate.tryAcquire(
              token: token,
              nowUtc: DateTime.utc(2026, 8, 28),
              leaseDuration: const Duration(minutes: 1),
            ),
            isTrue,
          );
          await repository.beginOwnerOperationFence(
            ownerId: fenceOwner,
            operationToken: token,
            nowUtc: DateTime.utc(2026, 8, 28),
          );
          release.complete();
          await pending.timeout(const Duration(seconds: 3));
          expect(scheduler.pending, contains(nativeId));
          expect(scheduler.cancelled, isNot(contains(nativeId)));
          expect(scheduler.scheduled, isEmpty);
        } finally {
          if (!release.isCompleted) release.complete();
          await drained.timeout(const Duration(seconds: 3));
          await repository.endOwnerOperationFence(
            ownerId: fenceOwner,
            operationToken: token,
          );
          await gate.release(token: token);
        }
      },
    );
  }

  test(
    'owner reactivation during native enumeration stops stale orphan cleanup',
    () async {
      final originalOwner = await repository.activeOwnerId();
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'reactivated-owner',
              accountState: const Value('localGuest'),
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      const nativeId = 432111;
      scheduler.permission = ReminderPermissionState.granted;
      scheduler.pending[nativeId] = const ReminderPlatformEntry(
        platformId: nativeId,
        ownerId: 'reactivated-owner',
        reminderId: 'returning-reminder',
      );
      scheduler.beforePendingReturn = () async {
        scheduler.beforePendingReturn = null;
        await database.transaction(() async {
          await database.customUpdate('UPDATE local_owners SET is_active = 0');
          await database.customUpdate(
            "UPDATE local_owners SET is_active = 1 WHERE id = 'reactivated-owner'",
          );
        });
      };
      await useCases.reconcile(featureEnabled: true);
      expect(await repository.activeOwnerId(), isNot(originalOwner));
      expect(scheduler.pending, contains(nativeId));
      expect(scheduler.cancelled, isNot(contains(nativeId)));
      expect(scheduler.scheduled, isEmpty);
    },
  );

  test(
    'queued opt-in pins the opening owner before canonical owner capture',
    () async {
      final ownerA = await repository.activeOwnerId();
      final release = Completer<void>();
      final blocker = useCases.operationCoordinator.run(() => release.future);
      final pending = useCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        expectedOwnerId: ownerA,
        mutationAllowed: () => true,
      );
      final rejection = expectLater(
        pending,
        throwsA(isA<StudyReminderMutationUnavailable>()),
      );
      await database.transaction(() async {
        await database.customUpdate('UPDATE local_owners SET is_active = 0');
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'synthetic-queued-owner-b',
                createdAtUtcMs: DateTime.utc(
                  2026,
                  8,
                  28,
                ).millisecondsSinceEpoch,
              ),
            );
      });
      release.complete();
      await blocker;
      await rejection;
      expect(await database.select(database.studyReminders).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      expect(scheduler.requestCalls, 0);
      expect(scheduler.pending, isEmpty);
      expect(
        await useCases.optIn(
          source: const StudyReminderSource.dueReview(),
          scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
          timezoneId: 'Asia/Bangkok',
          expectedOwnerId: 'synthetic-queued-owner-b',
          mutationAllowed: () => true,
        ),
        StudyReminderOptInResult.scheduled,
      );
      expect(
        (await database.select(database.studyReminders).get()).single.ownerId,
        'synthetic-queued-owner-b',
      );
    },
  );

  test(
    'requested offset remains requested across effective DST delivery',
    () async {
      final springUseCases = StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2027, 3, 13),
        generateId: () => 'reminder:synthetic-dst',
      );
      scheduler.permission = ReminderPermissionState.granted;
      final result = await springUseCases.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2027, 3, 14, 6, 30),
        timezoneId: 'America/New_York',
        quietHours: const ReminderQuietHours(
          startMinutes: 1320,
          endMinutes: 420,
        ),
        mutationAllowed: () => true,
      );
      expect(result, StudyReminderOptInResult.scheduled);
      final reminder = (await repository.list()).single;
      expect(reminder.timezone.utcOffsetMinutes, -300);
      expect(reminder.scheduledAtUtc, DateTime.utc(2027, 3, 14, 6, 30));
      expect(reminder.effectiveScheduledAtUtc, DateTime.utc(2027, 3, 14, 11));
      expect(
        StudyReminderUseCases.timezoneContext(
          'America/New_York',
          reminder.effectiveScheduledAtUtc,
        ).utcOffsetMinutes,
        -240,
      );
    },
  );

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

      final transitionGate = DriftOwnerOperationGate(database);
      const transitionToken = 'synthetic-feature-off-owner-transition';
      expect(
        await transitionGate.tryAcquire(
          token: transitionToken,
          nowUtc: DateTime.utc(2026, 8, 28),
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      try {
        final target = await useCases.coordinateOwnerChange<String>(
          sourceOwnerId: 'local:owner-a',
          operationToken: transitionToken,
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
            await database.customUpdate(
              'UPDATE local_owners SET is_active = 0',
            );
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
      } finally {
        await transitionGate.release(token: transitionToken);
      }
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
  Future<void> Function()? beforePendingReturn;
  Future<void> Function()? beforePermissionReturn;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<ReminderPermissionState> permissionState() async {
    await beforePermissionReturn?.call();
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
    if (hidePendingEntriesCalls > 0) {
      hidePendingEntriesCalls -= 1;
      return const [];
    }
    final snapshot = pending.values.toList(growable: false);
    await beforePendingReturn?.call();
    return snapshot;
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
