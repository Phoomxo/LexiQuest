import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  late AppDatabase database;
  late DriftStudyReminderRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = _repository(database, ownerId: 'owner-a');
  });

  tearDown(() => database.close());

  for (final operation in ['create', 'update', 'cancel']) {
    test(
      'AL retired $operation rolls desired state and outbox back together',
      () async {
        final original = _reminder(ownerId: 'local:owner-a');
        if (operation != 'create') await repository.save(original);
        final before = await repository.list(includeDeleted: true);
        final intents = await database.select(database.outboxOperations).get();
        var allowed = true;
        bool guard() {
          if (allowed) scheduleMicrotask(() => allowed = false);
          return allowed;
        }

        final write = operation == 'cancel'
            ? repository.cancel(
                original.id,
                updatedAtUtc: original.updatedAtUtc.add(
                  const Duration(seconds: 1),
                ),
                mutationAllowed: guard,
              )
            : repository.save(
                operation == 'create'
                    ? original
                    : original.copyWith(
                        scheduledAtUtc: original.scheduledAtUtc.add(
                          const Duration(hours: 1),
                        ),
                        updatedAtUtc: original.updatedAtUtc.add(
                          const Duration(seconds: 1),
                        ),
                      ),
                mutationAllowed: guard,
              );
        await expectLater(
          write,
          throwsA(isA<StudyReminderMutationUnavailable>()),
        );
        final after = await repository.list(includeDeleted: true);
        expect(after.length, before.length);
        if (before.isNotEmpty) {
          expect(after.single.scheduledAtUtc, before.single.scheduledAtUtc);
          expect(after.single.isEnabled, before.single.isEnabled);
          expect(after.single.updatedAtUtc, before.single.updatedAtUtc);
        }
        expect(await database.select(database.outboxOperations).get(), intents);
      },
    );
  }

  test(
    'reminder token proof requires the exact unexpired canonical lease',
    () async {
      await repository.activeOwnerId();
      final gate = DriftOwnerOperationGate(database);
      final now = DateTime.utc(2026, 8, 28);
      const token = 'synthetic-reminder-lease';
      expect(
        await repository.isOwnerOperationTokenOwned(
          operationToken: token,
          nowUtc: now,
        ),
        isFalse,
      );
      expect(
        await gate.tryAcquire(
          token: token,
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      try {
        // A real lease is sufficient proof; an in-memory or owner fence marker
        // is neither required nor accepted as a substitute for its token.
        expect(
          await repository.isOwnerOperationTokenOwned(
            operationToken: token,
            nowUtc: now,
          ),
          isTrue,
        );
        expect(
          await repository.isOwnerOperationTokenOwned(
            operationToken: 'unrelated-token',
            nowUtc: now,
          ),
          isFalse,
        );
        expect(
          await repository.isOwnerOperationTokenOwned(
            operationToken: token,
            nowUtc: now.add(const Duration(minutes: 1)),
          ),
          isFalse,
        );
      } finally {
        await gate.release(token: token);
      }
    },
  );

  test(
    'same-owner token takeover invalidates stale reminder authority',
    () async {
      final owner = await repository.activeOwnerId();
      final gate = DriftOwnerOperationGate(database);
      final now = DateTime.utc(2026, 8, 28);
      expect(
        await gate.tryAcquire(
          token: 'old-reminder-token',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      try {
        await repository.beginOwnerOperationFence(
          ownerId: owner,
          operationToken: 'old-reminder-token',
          nowUtc: now,
        );
        final later = now.add(const Duration(minutes: 1));
        expect(
          await gate.tryAcquire(
            token: 'new-reminder-token',
            nowUtc: later,
            leaseDuration: const Duration(minutes: 1),
          ),
          isTrue,
        );
        expect(await repository.activeOwnerId(), owner);
        expect(
          await repository.isOwnerOperationTokenOwned(
            operationToken: 'old-reminder-token',
            nowUtc: later,
          ),
          isFalse,
        );
        expect(
          await repository.isOwnerOperationTokenOwned(
            operationToken: 'new-reminder-token',
            nowUtc: later,
          ),
          isTrue,
        );
      } finally {
        await repository.endOwnerOperationFence(
          ownerId: owner,
          operationToken: 'old-reminder-token',
        );
        await gate.release(token: 'old-reminder-token');
        await gate.release(token: 'new-reminder-token');
      }
    },
  );

  test(
    'save commits canonical desired state and platform outbox atomically',
    () async {
      final reminder = _reminder(ownerId: 'local:owner-a');

      await repository.save(reminder);

      final row = await database.select(database.studyReminders).getSingle();
      final outbox = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(row.ownerId, 'local:owner-a');
      expect(row.sourceKind, 'dueReview');
      expect(row.isEnabled, isTrue);
      expect(row.isDeleted, isFalse);
      expect(outbox.ownerId, 'local:owner-a');
      expect(outbox.entityType, studyReminderPlatformOutboxEntityType);
      expect(outbox.entityId, reminder.id);
      expect(outbox.operationKind, 'schedule');
      expect(outbox.state, studyReminderPlatformPendingState);
    },
  );

  test(
    'identical retries are idempotent and conflicting replays fail',
    () async {
      final reminder = _reminder(ownerId: 'local:owner-a');
      await repository.save(reminder);
      await repository.save(reminder);

      expect(
        await database.select(database.studyReminders).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );

      await expectLater(
        repository.save(
          reminder.copyWith(
            scheduledAtUtc: reminder.scheduledAtUtc.add(
              const Duration(hours: 1),
            ),
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'restart restores v19 desired state and pending platform intent',
    () async {
      final directory = await Directory.systemTemp.createTemp('f27-reminder-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}state.sqlite',
      );
      var first = AppDatabase(NativeDatabase(file));
      final firstRepository = _repository(first, ownerId: 'owner-a');
      await firstRepository.save(_reminder(ownerId: 'local:owner-a'));
      await first.close();

      first = AppDatabase(NativeDatabase(file));
      final reopened = _repository(first, ownerId: 'owner-a');
      final reminders = await reopened.list(includeDeleted: true);
      final intents = await reopened.pendingPlatformIntents();

      expect(reminders, hasLength(1));
      expect(reminders.single.id, 'reminder:due-review');
      expect(intents, hasLength(1));
      expect(intents.single.kind, StudyReminderPlatformIntentKind.schedule);
      await first.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'cancel and delete preserve desired evidence and enqueue cancellation',
    () async {
      final reminder = _reminder(ownerId: 'local:owner-a');
      await repository.save(reminder);
      await repository.cancel(
        reminder.id,
        updatedAtUtc: DateTime.utc(2026, 8, 28, 2),
      );

      var row = await database.select(database.studyReminders).getSingle();
      expect(row.isEnabled, isFalse);
      expect(row.isDeleted, isFalse);
      expect(
        (await repository.pendingPlatformIntents()).single.kind,
        StudyReminderPlatformIntentKind.cancel,
      );

      await repository.acknowledgePlatformIntent(
        (await repository.pendingPlatformIntents()).single,
        acknowledgedAtUtc: DateTime.utc(2026, 8, 28, 2, 1),
      );
      await repository.delete(
        reminder.id,
        updatedAtUtc: DateTime.utc(2026, 8, 28, 3),
      );

      row = await database.select(database.studyReminders).getSingle();
      expect(row.isEnabled, isFalse);
      expect(row.isDeleted, isTrue);
      expect(await repository.list(), isEmpty);
      expect(await repository.list(includeDeleted: true), hasLength(1));
      expect(
        (await repository.pendingPlatformIntents()).single.kind,
        StudyReminderPlatformIntentKind.cancel,
      );
    },
  );

  test(
    'active-owner reads and mutations never cross owner boundaries',
    () async {
      await repository.save(_reminder(ownerId: 'local:owner-a'));
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner-b',
              createdAtUtcMs: DateTime.utc(2026, 8, 28).millisecondsSinceEpoch,
            ),
          );
      await database.customUpdate('UPDATE local_owners SET is_active = 0');
      await database.customUpdate(
        "UPDATE local_owners SET is_active = 1 WHERE id = 'owner-b'",
      );
      final ownerB = _repository(database, ownerId: 'unused-owner');

      expect(await ownerB.list(includeDeleted: true), isEmpty);
      expect(await ownerB.pendingPlatformIntents(), isEmpty);
      await expectLater(
        ownerB.save(_reminder(ownerId: 'local:owner-a')),
        throwsStateError,
      );
    },
  );

  test('stale revision cannot resolve or acknowledge a newer intent', () async {
    final reminder = _reminder(ownerId: 'local:owner-a');
    await repository.save(reminder);
    final stale = (await repository.pendingPlatformIntents()).single;

    await repository.cancel(
      reminder.id,
      updatedAtUtc: DateTime.utc(2026, 8, 28, 2),
    );

    expect(await repository.resolvePlatformIntent(stale), isNull);
    expect(
      await repository.acknowledgePlatformIntent(
        stale,
        acknowledgedAtUtc: DateTime.utc(2026, 8, 28, 2, 1),
      ),
      isFalse,
    );
    final current = (await repository.pendingPlatformIntents()).single;
    expect(current.localRevision, stale.localRevision + 1);
    expect(current.kind, StudyReminderPlatformIntentKind.cancel);
    expect(await repository.resolvePlatformIntent(current), isNotNull);
  });
}

DriftStudyReminderRepository _repository(
  AppDatabase database, {
  required String ownerId,
}) => DriftStudyReminderRepository(
  database,
  owners: DriftLocalOwnerRepository(
    database,
    generateId: () => ownerId,
    nowUtc: () => DateTime.utc(2026, 8, 28),
  ),
);

StudyReminder _reminder({required String ownerId}) => StudyReminder(
  id: 'reminder:due-review',
  ownerId: ownerId,
  source: const StudyReminderSource.dueReview(),
  scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
  timezone: const StudyReminderTimezoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
  quietHours: const ReminderQuietHours(
    startMinutes: 22 * 60,
    endMinutes: 7 * 60,
  ),
  isEnabled: true,
  createdAtUtc: DateTime.utc(2026, 8, 28),
  updatedAtUtc: DateTime.utc(2026, 8, 28),
);
