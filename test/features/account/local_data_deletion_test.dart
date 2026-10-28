import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  test('deletion inventory stays aligned with every owner-scoped table', () {
    expect(localDataDeletionInventory, ownerLifecyclePhysicalDeletionOrder);
    expect(
      localDataDeletionInventory.where(ownerUpgradeInventory.contains).toSet(),
      ownerUpgradeInventory,
    );
  });

  test(
    'erases one owner transactionally and preserves another owner',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedOwner(database, 'owner-a');
      await _seedOwner(database, 'owner-b');
      final deletedSecretOwnerIds = <String>[];

      final deleted = await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (ownerId) async {
          deletedSecretOwnerIds.add(ownerId);
        },
      ).eraseAll(ownerId: 'owner-a');

      expect(deleted, 12);
      expect(deletedSecretOwnerIds, ['owner-a']);
      expect(await _rootRows(database, 'owner-a'), 0);
      expect(await _importRowCount(database, 'owner-a'), 0);
      expect(await _questProgressCount(database, 'owner-a'), 0);
      expect(await _ownerRows(database, 'research_consents', 'owner-a'), 0);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 0);
      expect(await _ownerRows(database, 'reward_transactions', 'owner-a'), 0);
      expect(await _ownerRows(database, 'owned_reward_items', 'owner-a'), 0);
      expect(await _ownerRows(database, 'equipped_reward_items', 'owner-a'), 0);
      expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 0);
      expect(await _ownerRows(database, 'vocabulary_words', 'owner-a'), 0);
      expect(await _ownerRows(database, 'vocabulary_categories', 'owner-a'), 0);
      expect(await _ownerRows(database, 'research_consents', 'owner-b'), 1);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-b'), 1);
      expect(await _ownerRows(database, 'reward_transactions', 'owner-b'), 1);
      expect(await _ownerRows(database, 'owned_reward_items', 'owner-b'), 1);
      expect(await _ownerRows(database, 'equipped_reward_items', 'owner-b'), 1);
      expect(await _ownerRows(database, 'vocabulary_imports', 'owner-b'), 1);
      expect(await _ownerRows(database, 'vocabulary_words', 'owner-b'), 1);
      expect(await _ownerRows(database, 'vocabulary_categories', 'owner-b'), 1);
      expect(await _rootRows(database, 'owner-b'), 1);
      expect(await _importRowCount(database, 'owner-b'), 1);
      expect(await _questProgressCount(database, 'owner-b'), 1);
      expect(await _questDefinitionCount(database, 'owner-a'), 1);
    },
  );

  test('a late delete failure rolls back earlier table deletes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedOwner(database, 'owner-a');
    final deletedSecretOwnerIds = <String>[];
    await database.customStatement('''
      CREATE TRIGGER fail_vocabulary_category_delete
      BEFORE DELETE ON vocabulary_categories
      WHEN OLD.owner_id = 'owner-a'
      BEGIN
        SELECT RAISE(ABORT, 'injected deletion failure');
      END
    ''');

    await expectLater(
      LocalDataDeletion(
        database,
        deleteOwnerSecrets: (ownerId) async {
          deletedSecretOwnerIds.add(ownerId);
        },
      ).eraseAll(ownerId: 'owner-a'),
      throwsA(anything),
    );

    expect(await _ownerRows(database, 'research_consents', 'owner-a'), 1);
    expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_words', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_categories', 'owner-a'), 1);
    expect(deletedSecretOwnerIds, ['owner-a']);
  });

  test('secret erasure failure leaves database rows untouched', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedOwner(database, 'owner-a');

    await expectLater(
      LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) => throw StateError('secure storage failed'),
      ).eraseAll(ownerId: 'owner-a'),
      throwsStateError,
    );

    expect(await _ownerRows(database, 'research_consents', 'owner-a'), 1);
    expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 1);
  });

  test(
    'owner reminder cleanup runs while exact rows exist and before local erase',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedOwner(database, 'owner-a');
      await _seedOwner(database, 'owner-b');
      await _seedReminder(database, 'owner-a');
      await _seedReminder(database, 'owner-b');
      final cleanupOwners = <String>[];

      await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
        beforeOwnerDeletion: (ownerId) async {
          cleanupOwners.add(ownerId);
          expect(await _ownerRows(database, 'study_reminders', ownerId), 1);
          expect(await _ownerRows(database, 'outbox_operations', ownerId), 1);
          expect(await _ownerRows(database, 'study_reminders', 'owner-b'), 1);
        },
      ).eraseAll(ownerId: 'owner-a');

      expect(cleanupOwners, ['owner-a']);
      expect(await _ownerRows(database, 'study_reminders', 'owner-a'), 0);
      expect(await _ownerRows(database, 'outbox_operations', 'owner-a'), 0);
      expect(await _ownerRows(database, 'study_reminders', 'owner-b'), 1);
      expect(await _ownerRows(database, 'outbox_operations', 'owner-b'), 1);
    },
  );

  test(
    'reminder serialization spans cancellation through the complete local erase',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'erasure-owner',
        nowUtc: () => DateTime.utc(2026, 8, 28),
      );
      final repository = DriftStudyReminderRepository(database, owners: owners);
      final scheduler = _DeletionReminderScheduler();
      final reminders = StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'erasure-reminder',
      );
      await reminders.optIn(
        source: const StudyReminderSource.dueReview(),
        scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
        timezoneId: 'Asia/Bangkok',
        mutationAllowed: () => true,
      );
      final ownerId = await repository.activeOwnerId();
      final secretDeletionStarted = Completer<void>();
      final releaseSecretDeletion = Completer<void>();
      final ownerGate = DriftOwnerOperationGate(database);
      final ownerCoordinator = OwnerOperationCoordinator(
        gate: ownerGate,
        activeOwnerId: () async => ownerId,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateToken: () => 'reminder-erasure-token',
        leaseDuration: const Duration(minutes: 1),
        heartbeatInterval: const Duration(seconds: 20),
      );
      final deletion = LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
        deleteOwnerSecretsFenced: (_, _) async {
          secretDeletionStarted.complete();
          await releaseSecretDeletion.future;
        },
        fenceOwnerOperation: (operationToken) => ownerGate.requireOwned(
          token: operationToken,
          nowUtc: DateTime.utc(2026, 8, 28),
        ),
        coordinate: (erasedOwnerId, operation) => ownerCoordinator.run(
          AiCancellation(),
          (activeOwnerId) async {
            expect(activeOwnerId, erasedOwnerId);
            final operationToken = OwnerOperationCoordinator.currentLeaseToken!;
            final deleted = await operation(operationToken);
            ownerCoordinator.markCurrentOperationResultCommitted();
            return deleted;
          },
        ),
        coordinateReminderErasure: (erasedOwnerId, operation) {
          return reminders.coordinateOwnerErasure(
            ownerId: erasedOwnerId,
            operationToken: OwnerOperationCoordinator.currentLeaseToken!,
            operation: operation,
          );
        },
      );

      final erasure = deletion.eraseAll(ownerId: ownerId);
      await secretDeletionStarted.future;
      expect(scheduler.pending, isEmpty);
      var reconciliationCompleted = false;
      final reconciliation = reminders
          .reconcile(featureEnabled: true)
          .then((_) => reconciliationCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(reconciliationCompleted, isFalse);

      releaseSecretDeletion.complete();
      await erasure;
      await reconciliation;

      expect(scheduler.pending, isEmpty);
      expect(await database.select(database.studyReminders).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'one shared owner lease spans secret cleanup and the database erase',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedOwner(database, 'owner-a');
      final gate = DriftOwnerOperationGate(database);
      final secretDeleteStarted = Completer<void>();
      final allowSecretDelete = Completer<void>();
      final now = DateTime.utc(2026, 8, 11);
      final coordinator = OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () async => 'owner-a',
        nowUtc: () => now,
        generateToken: () => 'erase-owner-a',
        leaseDuration: const Duration(minutes: 1),
        heartbeatInterval: const Duration(seconds: 20),
      );
      final deletion = LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
        deleteOwnerSecretsFenced: (ownerId, operationToken) async {
          expect(ownerId, 'owner-a');
          expect(operationToken, 'erase-owner-a');
          secretDeleteStarted.complete();
          await allowSecretDelete.future;
        },
        fenceOwnerOperation: (operationToken) =>
            gate.requireOwned(token: operationToken, nowUtc: now),
        coordinate: (ownerId, operation) => coordinator.run(AiCancellation(), (
          activeOwnerId,
        ) {
          expect(activeOwnerId, ownerId);
          final operationToken = OwnerOperationCoordinator.currentLeaseToken;
          expect(operationToken, isNotNull);
          return operation(operationToken!);
        }),
      );

      final erasure = deletion.eraseAll(ownerId: 'owner-a');
      await secretDeleteStarted.future;

      expect(
        await gate.tryAcquire(
          token: 'competing-operation',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isFalse,
      );

      allowSecretDelete.complete();
      expect(await erasure, 12);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 0);
      expect(
        await gate.tryAcquire(
          token: 'competing-operation',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 1),
        ),
        isTrue,
      );
      await gate.release(token: 'competing-operation');
    },
  );

  test(
    'expired owner lease after secret cleanup fences every database delete',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedOwner(database, 'owner-a');
      final gate = DriftOwnerOperationGate(database);
      var now = DateTime.utc(2026, 8, 11);
      final coordinator = OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () async => 'owner-a',
        nowUtc: () => now,
        generateToken: () => 'stale-erasure',
        leaseDuration: const Duration(minutes: 1),
        heartbeatInterval: const Duration(seconds: 20),
      );
      final deletion = LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
        deleteOwnerSecretsFenced: (_, _) async {
          now = now.add(const Duration(minutes: 2));
          expect(
            await gate.tryAcquire(
              token: 'replacement-operation',
              nowUtc: now,
              leaseDuration: const Duration(minutes: 1),
            ),
            isTrue,
          );
        },
        fenceOwnerOperation: (operationToken) =>
            gate.requireOwned(token: operationToken, nowUtc: now),
        coordinate: (_, operation) => coordinator.run(
          AiCancellation(),
          (_) => operation(OwnerOperationCoordinator.currentLeaseToken!),
        ),
      );

      await expectLater(
        deletion.eraseAll(ownerId: 'owner-a'),
        throwsStateError,
      );

      expect(await _ownerRows(database, 'research_consents', 'owner-a'), 1);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 1);
      expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 1);
      await gate.release(token: 'replacement-operation');
    },
  );

  test(
    'committed erasure result survives lease loss immediately after commit',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedOwner(database, 'owner-a');
      final gate = DriftOwnerOperationGate(database);
      var now = DateTime.utc(2026, 8, 11);
      final coordinator = OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () async => 'owner-a',
        nowUtc: () => now,
        generateToken: () => 'committed-erasure',
        leaseDuration: const Duration(minutes: 1),
        heartbeatInterval: const Duration(seconds: 20),
      );
      final deletion = LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
        deleteOwnerSecretsFenced: (_, _) async {},
        fenceOwnerOperation: (operationToken) =>
            gate.requireOwned(token: operationToken, nowUtc: now),
        coordinate: (_, operation) =>
            coordinator.run(AiCancellation(), (_) async {
              final result = await operation(
                OwnerOperationCoordinator.currentLeaseToken!,
              );
              coordinator.markCurrentOperationResultCommitted();
              now = now.add(const Duration(minutes: 2));
              expect(
                await gate.tryAcquire(
                  token: 'replacement-after-commit',
                  nowUtc: now,
                  leaseDuration: const Duration(minutes: 1),
                ),
                isTrue,
              );
              return result;
            }),
      );

      expect(await deletion.eraseAll(ownerId: 'owner-a'), 12);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 0);
      await gate.release(token: 'replacement-after-commit');
    },
  );
}

Future<void> _seedOwner(AppDatabase database, String ownerId) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: ownerId, createdAtUtcMs: 1));
  await database
      .into(database.researchConsents)
      .insert(
        ResearchConsentsCompanion.insert(
          id: 'consent:$ownerId',
          ownerId: ownerId,
          consentVersion: 1,
          consentState: 'accepted',
          decidedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.aiUsageEvents)
      .insert(
        AiUsageEventsCompanion.insert(
          eventId: 'usage:$ownerId',
          ownerId: ownerId,
          occurredAtUtcMs: 1,
          providerId: 'gemini',
          model: 'model',
          requestType: 'tutorReply',
          outcome: 'success',
          latencyMs: 1,
        ),
      );
  await database.customInsert(
    'INSERT INTO reward_transactions '
    '(id, owner_id, idempotency_key, transaction_type, amount, item_id, '
    'catalog_version, occurred_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('reward-transaction:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('reward-key:$ownerId'),
      const Variable<String>('purchase'),
      const Variable<int>(-10),
      const Variable<String>('theme-blue'),
      const Variable<int>(1),
    ],
  );
  await database.customInsert(
    'INSERT INTO owned_reward_items '
    '(id, owner_id, item_id, catalog_version, acquired_by_transaction_id, '
    'acquired_at_utc_ms) VALUES (?, ?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('owned-reward:$ownerId'),
      Variable<String>(ownerId),
      const Variable<String>('theme-blue'),
      const Variable<int>(1),
      Variable<String>('reward-transaction:$ownerId'),
    ],
  );
  await database.customInsert(
    'INSERT INTO equipped_reward_items '
    '(id, owner_id, slot, item_id, equipped_at_utc_ms) '
    'VALUES (?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('equipped-reward:$ownerId'),
      Variable<String>(ownerId),
      const Variable<String>('theme'),
      const Variable<String>('theme-blue'),
    ],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
    variables: [
      Variable<String>('category:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('Category $ownerId'),
      Variable<String>('category-$ownerId'),
    ],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    variables: [
      Variable<String>('word:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('category:$ownerId'),
      Variable<String>('word-$ownerId'),
      Variable<String>('word-$ownerId'),
      const Variable<String>('meaning'),
      const Variable<String>('meaning'),
      const Variable<String>('noun'),
    ],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_imports '
    '(id, owner_id, category_id, source_type, source_name, source_hash, '
    'status, created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('import:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('category:$ownerId'),
      const Variable<String>('csv'),
      const Variable<String>('words.csv'),
      Variable<String>('hash:$ownerId'),
      const Variable<String>('complete'),
    ],
  );
  await database
      .into(database.vocabularyImportRows)
      .insert(
        VocabularyImportRowsCompanion.insert(
          id: 'import-row:$ownerId',
          importId: 'import:$ownerId',
          rowNumber: 1,
          payloadHash: 'payload:$ownerId',
          status: 'accepted',
        ),
      );
  await database
      .into(database.questDefinitions)
      .insert(
        QuestDefinitionsCompanion.insert(
          questId: 'quest:$ownerId',
          catalogVersion: 1,
          title: 'Quest $ownerId',
          description: 'description',
          type: 'daily',
          objectivesJson: '[]',
          rewardJson: '{}',
        ),
      );
  await database
      .into(database.questInstances)
      .insert(
        QuestInstancesCompanion.insert(
          instanceId: 'quest-instance:$ownerId',
          questId: 'quest:$ownerId',
          ownerId: ownerId,
          catalogVersion: 1,
          assignedAtUtcMs: 1,
          state: 'active',
        ),
      );
  await database
      .into(database.questObjectiveProgress)
      .insert(
        QuestObjectiveProgressCompanion.insert(
          id: 'quest-progress:$ownerId',
          instanceId: 'quest-instance:$ownerId',
          objectiveId: 'objective',
          targetCount: 1,
        ),
      );
}

Future<void> _seedReminder(AppDatabase database, String ownerId) async {
  await database.customInsert(
    'INSERT INTO study_reminders '
    '(id, owner_id, source_kind, scheduled_at_utc_ms, timezone_id, '
    'timezone_offset_minutes, is_enabled, created_at_utc_ms, '
    'updated_at_utc_ms, local_revision, is_deleted) '
    'VALUES (?, ?, ?, ?, ?, ?, 1, 1, 1, 1, 0)',
    variables: [
      Variable<String>('reminder:$ownerId'),
      Variable<String>(ownerId),
      const Variable<String>('dueReview'),
      Variable<int>(DateTime.utc(2026, 8, 29).millisecondsSinceEpoch),
      const Variable<String>('Asia/Bangkok'),
      const Variable<int>(420),
    ],
  );
  await database.customInsert(
    'INSERT INTO outbox_operations '
    '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
    'base_revision, state, created_at_utc_ms, attempt_count) '
    'VALUES (?, ?, ?, ?, ?, 1, ?, 1, 0)',
    variables: [
      Variable<String>('studyReminderPlatform:reminder:$ownerId:1:schedule'),
      Variable<String>(ownerId),
      const Variable<String>('studyReminderPlatform'),
      Variable<String>('reminder:$ownerId'),
      const Variable<String>('schedule'),
      const Variable<String>('platformPending'),
    ],
  );
}

Future<int> _ownerRows(AppDatabase database, String table, String ownerId) =>
    database
        .customSelect(
          'SELECT COUNT(*) AS count FROM $table WHERE owner_id = ?',
          variables: [Variable<String>(ownerId)],
        )
        .map((row) => row.read<int>('count'))
        .getSingle();

Future<int> _rootRows(AppDatabase database, String ownerId) => database
    .customSelect(
      'SELECT COUNT(*) AS count FROM local_owners WHERE id = ?',
      variables: [Variable<String>(ownerId)],
    )
    .map((row) => row.read<int>('count'))
    .getSingle();

Future<int> _importRowCount(AppDatabase database, String ownerId) => database
    .customSelect(
      'SELECT COUNT(*) AS count FROM vocabulary_import_rows '
      'WHERE import_id = ?',
      variables: [Variable<String>('import:$ownerId')],
    )
    .map((row) => row.read<int>('count'))
    .getSingle();

Future<int> _questProgressCount(AppDatabase database, String ownerId) =>
    database
        .customSelect(
          'SELECT COUNT(*) AS count FROM quest_objective_progress '
          'WHERE instance_id = ?',
          variables: [Variable<String>('quest-instance:$ownerId')],
        )
        .map((row) => row.read<int>('count'))
        .getSingle();

Future<int> _questDefinitionCount(AppDatabase database, String ownerId) =>
    database
        .customSelect(
          'SELECT COUNT(*) AS count FROM quest_definitions WHERE quest_id = ?',
          variables: [Variable<String>('quest:$ownerId')],
        )
        .map((row) => row.read<int>('count'))
        .getSingle();

final class _DeletionReminderScheduler implements ReminderScheduler {
  final Map<int, ReminderPlatformEntry> pending = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<ReminderPermissionState> permissionState() async =>
      ReminderPermissionState.granted;

  @override
  Future<ReminderPermissionState> requestPermission() async =>
      ReminderPermissionState.granted;

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async =>
      pending.values.toList(growable: false);

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {
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
