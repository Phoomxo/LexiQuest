import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  late List<String> deletedSecretOwnerIds;
  var conflictSequence = 0;
  var ownerOperationSequence = 0;

  setUp(() async {
    deletedSecretOwnerIds = <String>[];
    ownerOperationSequence = 0;
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'upgrade-conflict-${conflictSequence++}',
      generateOwnerId: () => 'new-guest-owner',
      generateOwnerOperationToken: () =>
          'owner-operation-${ownerOperationSequence++}',
      deleteOwnerSecrets: (ownerId) async {
        deletedSecretOwnerIds.add(ownerId);
      },
    );
    await _seedOwners(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('migration inventory covers every owner-scoped Drift table', () async {
    final rows = await database.customSelect('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND sql LIKE '%owner_id%'
      ORDER BY name
    ''').get();
    final actual = rows.map((row) => row.read<String>('name')).toSet();

    expect(ownerUpgradeInventory, actual);
  });

  test(
    'anonymous bind without a prior UID owner retains one local owner',
    () async {
      await (database.delete(
        database.localOwners,
      )..where((row) => row.id.equals('account-owner'))).go();

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'new-firebase-user',
      );

      final owners = await database.select(database.localOwners).get();
      expect(result.mode, OwnerUpgradeMode.anonymousBound);
      expect(result.targetOwnerId, 'guest-owner');
      expect(owners, hasLength(1));
      expect(owners.single.id, 'guest-owner');
      expect(owners.single.firebaseUid, 'new-firebase-user');
      expect(owners.single.isActive, isTrue);
    },
  );

  test(
    'later guest withdrawal replaces canonical target consent decision',
    () async {
      await database.customInsert(
        "INSERT INTO research_consents VALUES "
        "('consent-target', 'account-owner', 1, 'accepted', 100, NULL)",
      );
      await database.customInsert(
        "INSERT INTO research_consents VALUES "
        "('consent-guest', 'guest-owner', 1, 'withdrawn', 200, 200)",
      );
      await database.customInsert(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
        "VALUES ('foreign-owner', 'firebase-foreign', 'firebaseBound', 3, 0)",
      );
      await database.customInsert(
        "INSERT INTO research_consents VALUES "
        "('consent-foreign', 'foreign-owner', 1, 'accepted', 300, NULL)",
      );
      final foreignBefore = await database
          .customSelect(
            'SELECT * FROM research_consents WHERE id = ?',
            variables: const [Variable<String>('consent-foreign')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final consent = await (database.select(
        database.researchConsents,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      expect(consent.id, 'consent-target');
      expect(consent.consentState, 'withdrawn');
      expect(consent.decidedAtUtcMs, 200);
      expect(consent.withdrawnAtUtcMs, 200);
      expect(
        await database
            .customSelect(
              'SELECT * FROM research_consents WHERE id = ?',
              variables: const [Variable<String>('consent-foreign')],
            )
            .getSingle()
            .then((row) => Map<String, Object?>.from(row.data)),
        foreignBefore,
      );
      expect(
        await (database.select(
          database.researchConsents,
        )..where((row) => row.ownerId.equals('guest-owner'))).get(),
        isEmpty,
      );
    },
  );

  test('newer target withdrawal beats an older guest acceptance', () async {
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-target', 'account-owner', 1, 'withdrawn', 300, 300)",
    );
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-guest', 'guest-owner', 1, 'accepted', 200, NULL)",
    );

    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    final consent = await (database.select(
      database.researchConsents,
    )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
    expect(consent.id, 'consent-target');
    expect(consent.consentState, 'withdrawn');
    expect(consent.decidedAtUtcMs, 300);
    expect(consent.withdrawnAtUtcMs, 300);
  });

  test('withdrawal wins an exact consent decision tie', () async {
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-target', 'account-owner', 1, 'accepted', 300, NULL)",
    );
    await database.customInsert(
      "INSERT INTO research_consents VALUES "
      "('consent-guest', 'guest-owner', 1, 'withdrawn', 300, 300)",
    );

    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    final consent = await (database.select(
      database.researchConsents,
    )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
    expect(consent.id, 'consent-target');
    expect(consent.consentState, 'withdrawn');
    expect(consent.decidedAtUtcMs, 300);
    expect(consent.withdrawnAtUtcMs, 300);
  });

  test(
    'merge conflict evidence identifies target guest and merged outcomes',
    () async {
      await database.customInsert(
        'INSERT INTO association_records '
        '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
        "('association-target', 'account-owner', 'station', 'keyword', "
        "'target-newer', 200)",
      );
      await database.customInsert(
        'INSERT INTO association_records '
        '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
        "('association-guest', 'guest-owner', 'station', 'keyword', "
        "'guest-older', 100)",
      );
      await database.customInsert(
        'INSERT INTO associative_memory_states '
        '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
        'lapse_count, last_reviewed_at_utc_ms, next_due_at_utc_ms, '
        'algorithm_version) VALUES '
        "('memory-target', 'account-owner', 'station', 2, 4, 0.2, 1, "
        "100, 200, 'v1')",
      );
      await database.customInsert(
        'INSERT INTO associative_memory_states '
        '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
        'lapse_count, last_reviewed_at_utc_ms, next_due_at_utc_ms, '
        'algorithm_version) VALUES '
        "('memory-guest', 'guest-owner', 'station', 9, 3, 0.1, 2, "
        "200, 300, 'v2')",
      );
      await database.customInsert(
        'INSERT INTO learning_day_log '
        '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
        "('day-target', 'account-owner', '2026-08-11', 200)",
      );
      await database.customInsert(
        'INSERT INTO learning_day_log '
        '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
        "('day-guest', 'guest-owner', '2026-08-11', 100)",
      );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final association = await (database.select(
        database.associationRecords,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      final associationConflict = await _mergeConflictFor(
        database,
        'associationRecord',
      );
      expect(
        associationConflict.read<String>('resolution_policy'),
        'guestUpgradeLatestAssociation',
      );
      expect(associationConflict.read<String>('outcome'), 'targetRetained');
      final associationTarget =
          jsonDecode(associationConflict.read<String>('cloud_snapshot_json'))
              as Map<String, dynamic>;
      expect(association.id, associationTarget['id']);
      expect(association.content, associationTarget['content']);
      expect(association.createdAtUtcMs, associationTarget['createdAtUtcMs']);

      final memory = await (database.select(
        database.associativeMemoryStates,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      final memoryConflict = await _mergeConflictFor(
        database,
        'associativeMemoryState',
      );
      expect(
        memoryConflict.read<String>('resolution_policy'),
        'guestUpgradeLatestMemory',
      );
      expect(memoryConflict.read<String>('outcome'), 'guestRetained');
      final memoryGuest =
          jsonDecode(memoryConflict.read<String>('local_snapshot_json'))
              as Map<String, dynamic>;
      expect(memory.stability, memoryGuest['stability']);
      expect(memory.lastReviewedAtUtcMs, memoryGuest['lastReviewedAtUtcMs']);
      expect(memory.nextDueAtUtcMs, memoryGuest['nextDueAtUtcMs']);

      final day = await (database.select(
        database.learningDayLog,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      final dayConflict = await _mergeConflictFor(database, 'learningDay');
      expect(
        dayConflict.read<String>('resolution_policy'),
        'guestUpgradeEarliestLearningDay',
      );
      expect(dayConflict.read<String>('outcome'), 'evidenceMerged');
      final guestDay =
          jsonDecode(dayConflict.read<String>('local_snapshot_json'))
              as Map<String, dynamic>;
      final targetDay =
          jsonDecode(dayConflict.read<String>('cloud_snapshot_json'))
              as Map<String, dynamic>;
      expect(day.id, targetDay['id']);
      expect(
        day.firstSessionAtUtcMs,
        <int>[
          guestDay['firstSessionAtUtcMs'] as int,
          targetDay['firstSessionAtUtcMs'] as int,
        ].reduce((left, right) => left < right ? left : right),
      );
    },
  );

  test('anonymous rehome creates an anchored SRS operation identity', () async {
    await (database.delete(
      database.localOwners,
    )..where((row) => row.id.equals('account-owner'))).go();
    await database.customInsert(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, created_at_utc_ms, "
      "updated_at_utc_ms) VALUES "
      "('category-srs', 'guest-owner', 'SRS', 'srs', 1, 1)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_words "
      "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
      "normalized_meaning, part_of_speech, created_at_utc_ms, "
      "updated_at_utc_ms) VALUES "
      "('word-srs', 'guest-owner', 'category-srs', 'one', 'one', 'one', "
      "'one', 'noun', 1, 1)",
    );
    await database.customInsert(
      "INSERT INTO learning_sessions VALUES "
      "('session-srs', 'guest-owner', 'quiz', 'completed', 1, 2, 1, 0, "
      "100, '1', '1')",
    );
    await database.customInsert(
      'INSERT INTO answer_attempts '
      '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
      'response_time_ms, attempt_number, occurred_at_utc_ms, '
      'provider_provenance) VALUES '
      "('answer-srs', 'guest-owner', 'session-srs', 'word-srs', 'meaning', "
      '1, 10, 1, 2, NULL)',
    );
    await database.customInsert(
      "INSERT INTO srs_states VALUES "
      "('state-srs', 'guest-owner', 'word-srs', 1, 1, 1, 1, 0, 2, 3, 1)",
    );

    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'new-firebase-user',
    );

    final operation = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('srsState'))).getSingle();
    expect(
      operation.operationId,
      matches(RegExp(r'^srsState:v2:[0-9a-f]{64}:r1$')),
    );
    expect(operation.entityId, 'word-srs');
    expect(operation.baseRevision, 0);
  });

  test('moves every owner-scoped row and replays as a no-op', () async {
    await _seedEveryOwnerScopedTable(database);

    final result = await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );
    final replayed = await repository.upgrade(
      activeOwnerId: result.targetOwnerId,
      firebaseUid: 'firebase-user',
    );

    expect(result.mode, OwnerUpgradeMode.mergedExisting);
    expect(result.targetOwnerId, 'account-owner');
    expect(deletedSecretOwnerIds, ['guest-owner']);
    expect(replayed.mode, OwnerUpgradeMode.alreadyBound);
    for (final table in ownerUpgradeInventory) {
      expect(
        await _ownerCount(database, table, 'guest-owner'),
        0,
        reason: '$table retained guest ownership',
      );
      expect(
        await _ownerCount(database, table, 'account-owner'),
        greaterThanOrEqualTo(1),
        reason: '$table did not reach the account owner',
      );
    }
    expect(
      await database
          .customSelect(
            'SELECT COUNT(*) AS count FROM vocabulary_import_rows '
            'WHERE import_id = ? AND word_id = ?',
            variables: const [
              Variable<String>('import-1'),
              Variable<String>('word-1'),
            ],
          )
          .getSingle()
          .then((row) => row.read<int>('count')),
      1,
    );
    final migratedEvidenceOutbox = await database
        .customSelect(
          'SELECT entity_type FROM outbox_operations '
          'WHERE owner_id = ? AND entity_type IN (?, ?) ORDER BY entity_type',
          variables: const [
            Variable<String>('account-owner'),
            Variable<String>('attempt'),
            Variable<String>('readingEvent'),
          ],
        )
        .map((row) => row.read<String>('entity_type'))
        .get();
    expect(migratedEvidenceOutbox, ['attempt', 'readingEvent']);
  });

  test(
    'resolves category and word collisions and remaps dependent rows',
    () async {
      await _seedCollisionGraph(database);

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.conflictCount, 2);
      expect(
        await database
            .customSelect(
              'SELECT word_id FROM answer_attempts WHERE id = ?',
              variables: const [Variable<String>('attempt-guest')],
            )
            .getSingle()
            .then((row) => row.read<String>('word_id')),
        'word-target',
      );
      final operation = await database
          .customSelect(
            'SELECT owner_id, entity_id, state FROM outbox_operations '
            'WHERE operation_id = ?',
            variables: const [Variable<String>('operation-guest')],
          )
          .getSingle();
      expect(operation.read<String>('owner_id'), 'account-owner');
      expect(operation.read<String>('entity_id'), 'word-target');
      expect(operation.read<String>('state'), 'superseded');
      expect(
        await database
            .customSelect(
              'SELECT COUNT(*) AS count FROM sync_conflicts '
              'WHERE owner_id = ? AND resolution_policy = ? AND outcome = ?',
              variables: const [
                Variable<String>('account-owner'),
                Variable<String>('guestUpgradeCanonicalTarget'),
                Variable<String>('targetRetained'),
              ],
            )
            .getSingle()
            .then((row) => row.read<int>('count')),
        2,
      );
    },
  );

  test(
    'collision remaps leave a third owner bookkeeping byte-equivalent',
    () async {
      await _seedCollisionGraph(database);
      await database.customInsert(
        "INSERT INTO local_owners "
        "(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES "
        "('foreign-owner', 'firebase-foreign', 'firebaseBound', 3, 0)",
      );
      await database.customInsert(
        "INSERT INTO outbox_operations "
        "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
        "state, attempt_count, created_at_utc_ms) VALUES "
        "('foreign-operation', 'foreign-owner', 'word', 'word-guest', "
        "'upsert', 'retryWaiting', 2, 3)",
      );
      await database.customInsert(
        "INSERT INTO sync_conflicts "
        "(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, "
        "resolution_policy, outcome, local_snapshot_json, cloud_snapshot_json, "
        "resolved_at_utc_ms) VALUES "
        "('foreign-conflict', 'foreign-owner', 'word', 'word-guest', 1, 2, "
        "'foreignPolicy', 'foreignOutcome', '{\"foreign\":true}', "
        "'{\"foreign\":false}', 3)",
      );
      final outboxBefore = await database
          .customSelect(
            'SELECT * FROM outbox_operations WHERE operation_id = ?',
            variables: const [Variable<String>('foreign-operation')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));
      final conflictBefore = await database
          .customSelect(
            'SELECT * FROM sync_conflicts WHERE id = ?',
            variables: const [Variable<String>('foreign-conflict')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final outboxAfter = await database
          .customSelect(
            'SELECT * FROM outbox_operations WHERE operation_id = ?',
            variables: const [Variable<String>('foreign-operation')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));
      final conflictAfter = await database
          .customSelect(
            'SELECT * FROM sync_conflicts WHERE id = ?',
            variables: const [Variable<String>('foreign-conflict')],
          )
          .getSingle()
          .then((row) => Map<String, Object?>.from(row.data));

      expect(outboxAfter, outboxBefore);
      expect(conflictAfter, conflictBefore);
    },
  );

  test(
    'file-backed merge retires colliding SRS and unlock outbox before claim',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-owner-merge-outbox-',
      );
      final path = '${directory.path}${Platform.pathSeparator}identity.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _seedOwners(firstDatabase);
        await _seedProjectionCollisionGraph(firstDatabase);
        await firstDatabase.customInsert(
          "INSERT INTO achievement_unlocks VALUES "
          "('unlock-target', 'account-owner', 'first_answer', 1, "
          "'target-source', 1)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO achievement_unlocks VALUES "
          "('unlock-guest', 'guest-owner', 'first_answer', 1, "
          "'guest-source', 2)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO outbox_operations "
          "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
          "created_at_utc_ms) VALUES "
          "('srsState:word-guest:1', 'guest-owner', 'srsState', "
          "'word-guest', 'upsert', 2)",
        );
        await firstDatabase.customInsert(
          "INSERT INTO outbox_operations "
          "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
          "created_at_utc_ms) VALUES "
          "('achievementUnlock:unlock-guest:1', 'guest-owner', "
          "'achievementUnlock', 'unlock-guest', 'upsert', 2)",
        );
        var tokenSequence = 0;
        await DriftOwnerUpgradeRepository(
          firstDatabase,
          nowUtc: () => DateTime.utc(2026, 7, 30, 12),
          generateConflictId: () => 'merge-conflict-${tokenSequence++}',
          generateOwnerId: () => 'unused-owner',
          generateOwnerOperationToken: () => 'merge-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(activeOwnerId: 'guest-owner', firebaseUid: 'firebase-user');
      } finally {
        await firstDatabase.close();
      }

      final reopenedDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await reopenedDatabase.customSelect('SELECT 1').getSingle();
        final now = DateTime.utc(2026, 7, 30, 12, 1);
        expect(
          await DriftOwnerOperationGate(reopenedDatabase).tryAcquire(
            token: 'sync-after-merge',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final claims = await DriftSyncStore(reopenedDatabase).claimPending(
          ownerId: 'account-owner',
          firebaseUid: 'firebase-user',
          limit: 50,
          leaseToken: 'claim-after-merge',
          ownerGateToken: 'sync-after-merge',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: now,
        );
        final retired =
            await (reopenedDatabase.select(reopenedDatabase.outboxOperations)
                  ..where(
                    (row) => row.operationId.isIn(const [
                      'srsState:word-guest:1',
                      'achievementUnlock:unlock-guest:1',
                    ]),
                  ))
                .get();

        expect(retired.map((row) => row.state).toSet(), {'superseded'});
        expect(
          retired
              .singleWhere((row) => row.operationId == 'srsState:word-guest:1')
              .entityId,
          'word-target',
        );
        expect(
          claims.map((claim) => claim.mutation.operationId),
          isNot(contains('srsState:word-guest:1')),
        );
        expect(
          claims.map((claim) => claim.mutation.operationId),
          isNot(contains('achievementUnlock:unlock-guest:1')),
        );
        expect(
          await (reopenedDatabase.select(
            reopenedDatabase.achievementUnlocks,
          )..where((row) => row.id.equals('unlock-target'))).getSingleOrNull(),
          isNot(equals(null)),
          reason: 'projection rebuild must preserve the target unlock identity',
        );
      } finally {
        await reopenedDatabase.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
        await directory.delete(recursive: true);
      }
    },
  );

  test('deduplicates AI usage event ids while merging owners', () async {
    for (final owner in ['guest-owner', 'account-owner']) {
      await database.customInsert(
        "INSERT INTO ai_usage_events "
        "(event_id, owner_id, occurred_at_utc_ms, provider_id, model, "
        "request_type, outcome, latency_ms) VALUES "
        "('shared-event', ?, 20, 'gemini', 'model', "
        "'tutorReply', 'success', 10)",
        variables: [Variable<String>(owner)],
      );
    }

    final result = await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    expect(result.mode, OwnerUpgradeMode.mergedExisting);
    expect(await _ownerCount(database, 'ai_usage_events', 'account-owner'), 1);
  });

  test(
    'mergedExisting normalizes cursor prefix and quest reward owner',
    () async {
      final guestFirst = DateTime.utc(2026, 8, 9, 10);
      final guestPending = DateTime.utc(2026, 8, 9, 11);
      final accountLater = DateTime.utc(2026, 8, 9, 12);
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-first',
        occurredAt: guestFirst,
      );
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-pending',
        occurredAt: guestPending,
      );
      await _insertLearningEvent(
        database,
        ownerId: 'account-owner',
        eventId: 'learning-event:account-later',
        occurredAt: accountLater,
      );
      await _insertProjectionResult(
        database,
        ownerId: 'guest-owner',
        sourceEventId: 'learning-event:guest-first',
        projection: 'quest',
        occurredAt: guestFirst,
        result: {
          'eligible': true,
          'rewardGrants': [
            {
              'ownerId': 'guest-owner',
              'idempotencyKey': 'quest-complete:guest-first',
              'xpAmount': 25,
            },
          ],
        },
      );
      await _insertProjectionCursor(
        database,
        ownerId: 'guest-owner',
        sourceEventId: 'learning-event:guest-first',
        projection: 'quest',
        occurredAt: guestFirst,
      );
      await _insertProjectionResult(
        database,
        ownerId: 'account-owner',
        sourceEventId: 'learning-event:account-later',
        projection: 'quest',
        occurredAt: accountLater,
        result: const {'eligible': true, 'rewardGrants': []},
      );
      await _insertProjectionCursor(
        database,
        ownerId: 'account-owner',
        sourceEventId: 'learning-event:account-later',
        projection: 'quest',
        occurredAt: accountLater,
      );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final cursors =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.eventType.equals('LearningProjectionCursor'),
              ))
              .get();
      expect(cursors, hasLength(1));
      expect(
        (cursors.single.eventId, cursors.single.aggregateId),
        (
          'learning-projection-cursor:account-owner:quest:v1',
          'learning-event:guest-first',
        ),
        reason: 'the safe merged prefix is the earlier guest cursor',
      );

      final guestReceipt =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-projection:quest:'
                  'learning-event:guest-first:v1',
                ),
              ))
              .getSingle();
      final payload =
          jsonDecode(guestReceipt.payloadJson) as Map<String, dynamic>;
      final result = (payload['result'] as Map).cast<String, dynamic>();
      final grants = (result['rewardGrants'] as List).cast<Map>();
      expect(grants.single['ownerId'], 'account-owner');

      final replayed = <String>[];
      final rewarded = <String>[];
      String? rewardOwner;
      var questUnavailable = true;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (event) async {
          replayed.add(event.eventId);
          if (questUnavailable &&
              event.eventId == 'learning-event:guest-pending') {
            throw StateError('quest projection unavailable');
          }
          return const LearningProjectionResult.applied();
        },
        rewardSink: (event, questResult) async {
          rewarded.add(event.eventId);
          final grants = (questResult['rewardGrants'] as List? ?? const []);
          if (grants.isNotEmpty) {
            rewardOwner = (grants.single as Map)['ownerId'] as String;
          }
          return const LearningProjectionResult.applied();
        },
      );
      await reconciler.reconcileOwner('account-owner');
      expect(replayed, contains('learning-event:guest-pending'));
      expect(
        rewarded,
        ['learning-event:guest-first'],
        reason: 'missing earlier quest result must block the reward prefix',
      );
      expect(rewardOwner, 'account-owner');

      questUnavailable = false;
      await reconciler.reconcileOwner('account-owner');
      expect(rewarded, [
        'learning-event:guest-first',
        'learning-event:guest-pending',
        'learning-event:account-later',
      ]);
    },
  );

  test(
    'owner upgrade drains guest replay and schedules buffered work on account',
    () async {
      final firstAt = DateTime.utc(2026, 8, 9, 10);
      final secondAt = DateTime.utc(2026, 8, 9, 11);
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-in-flight',
        occurredAt: firstAt,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final projected = <String>[];
      final scheduler = LearningReconciliationScheduler(
        LearningSideEffectReconciler(
          database,
          streakSink: (event) async {
            projected.add(event.eventId);
            if (event.eventId == 'learning-event:guest-in-flight') {
              entered.complete();
              await release.future;
            }
            return const LearningProjectionResult.applied();
          },
        ),
      );
      final upgrade = UpgradeGuestOwner(
        repository,
        coordinate: (sourceOwnerId, operation) =>
            scheduler.coordinateOwnerChange(
              sourceOwnerId,
              operation,
              (result) => result.targetOwnerId,
            ),
      );

      scheduler.request('guest-owner');
      await entered.future;
      final upgrading = upgrade.call(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      await _insertLearningEvent(
        database,
        ownerId: 'guest-owner',
        eventId: 'learning-event:guest-buffered',
        occurredAt: secondAt,
      );
      scheduler.request('guest-owner');
      release.complete();

      final result = await upgrading;
      expect(result.targetOwnerId, 'account-owner');
      await scheduler.drain();
      expect(projected, [
        'learning-event:guest-in-flight',
        'learning-event:guest-buffered',
      ]);
      final guestProjectionRows =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals('guest-owner') &
                    (row.eventType.equals('LearningProjectionApplied') |
                        row.eventType.equals('LearningProjectionCursor')),
              ))
              .get();
      expect(guestProjectionRows, isEmpty);
      expect(
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.ownerId.equals('account-owner') &
                  row.eventType.equals('LearningProjectionApplied'),
            ))
            .get(),
        hasLength(2),
      );
      await scheduler.dispose();
    },
  );

  test('rolls back the whole upgrade when any table update fails', () async {
    await _seedEveryOwnerScopedTable(database);
    await database.customStatement('''
      CREATE TRIGGER fail_owner_upgrade
      BEFORE UPDATE OF owner_id ON reading_events
      WHEN NEW.owner_id = 'account-owner'
      BEGIN
        SELECT RAISE(ABORT, 'injected migration failure');
      END
    ''');

    await expectLater(
      repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      ),
      throwsA(isA<Object>()),
    );

    expect(
      await _ownerCount(database, 'vocabulary_categories', 'guest-owner'),
      1,
    );
    expect(await _ownerCount(database, 'reading_events', 'guest-owner'), 1);
    final guest = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals('guest-owner'))).getSingle();
    expect(guest.isActive, isTrue);
    expect(deletedSecretOwnerIds, ['guest-owner']);
  });

  test('owner upgrade waits for the persisted owner-operation gate', () async {
    final gate = DriftOwnerOperationGate(database);
    final gateReleased = Completer<void>();
    final waitingRepository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'waiting-conflict',
      generateOwnerId: () => 'waiting-owner',
      generateOwnerOperationToken: () => 'waiting-upgrade-token',
      deleteOwnerSecrets: (ownerId) async {
        deletedSecretOwnerIds.add(ownerId);
      },
      ownerOperationGate: gate,
      ownerGateDelay: (_) => gateReleased.future,
    );
    expect(
      await gate.tryAcquire(
        token: 'active-sync-token',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );
    var completed = false;

    final upgrading = waitingRepository
        .upgrade(activeOwnerId: 'guest-owner', firebaseUid: 'firebase-user')
        .whenComplete(() => completed = true);
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    await gate.release(token: 'active-sync-token');
    gateReleased.complete();
    final result = await upgrading;
    expect(result.targetOwnerId, 'account-owner');
  });

  test(
    'owner transition heartbeat renews while external work is held',
    () async {
      final initialNow = DateTime.utc(2026, 7, 30, 12);
      var heartbeatNow = initialNow;
      final scheduler = _ManualOwnerGateDelay();
      final secretsEntered = Completer<void>();
      final releaseSecrets = Completer<void>();
      final trackingGate = _TrackingOwnerGate(
        DriftOwnerOperationGate(database),
      );
      final heartbeatRepository = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => heartbeatNow,
        generateConflictId: () => 'heartbeat-conflict',
        generateOwnerId: () => 'heartbeat-owner',
        generateOwnerOperationToken: () => 'heartbeat-owner-operation',
        deleteOwnerSecrets: (_) async {
          secretsEntered.complete();
          await releaseSecrets.future;
        },
        ownerOperationGate: trackingGate,
        ownerGateDelay: scheduler.wait,
      );

      final upgrading = heartbeatRepository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      await secretsEntered.future;
      expect(
        scheduler.delays.single,
        heartbeatRepository.ownerGateHeartbeatInterval,
      );
      heartbeatNow = heartbeatNow.add(scheduler.delays.single);
      scheduler.elapseNext();
      await trackingGate.renewed.future;
      heartbeatNow = initialNow.add(heartbeatRepository.ownerGateLeaseDuration);

      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'competing-transition',
          nowUtc: heartbeatNow,
          leaseDuration: const Duration(minutes: 10),
        ),
        isFalse,
      );
      releaseSecrets.complete();
      final result = await upgrading;
      expect(result.targetOwnerId, 'account-owner');
    },
  );

  test('owner transition transaction rejects a stale acquired token', () async {
    final gate = _StealingOwnerGate(
      DriftOwnerOperationGate(database),
      replacementToken: 'replacement-owner-operation',
    );
    final fencedRepository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'fenced-conflict',
      generateOwnerId: () => 'fenced-owner',
      generateOwnerOperationToken: () => 'stale-owner-operation',
      deleteOwnerSecrets: (ownerId) async {
        deletedSecretOwnerIds.add(ownerId);
      },
      ownerOperationGate: gate,
    );

    await expectLater(
      fencedRepository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      ),
      throwsA(isA<StateError>()),
    );

    final guest = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals('guest-owner'))).getSingle();
    final account = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals('account-owner'))).getSingle();
    expect(guest.isActive, isTrue);
    expect(guest.firebaseUid, isNull);
    expect(account.isActive, isFalse);
    expect(deletedSecretOwnerIds, ['guest-owner']);
  });

  test(
    'logout activates a fresh local guest without deleting account rows',
    () async {
      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      await database.customInsert(
        "INSERT INTO reading_events VALUES "
        "('account-reading', 'account-owner', 'doc-2', 1, 'opened', 0, 30)",
      );

      final result = await repository.createLocalGuestAfterLogout();

      expect(result.mode, OwnerUpgradeMode.localGuestCreated);
      expect(result.targetOwnerId, 'local:new-guest-owner');
      expect(await _ownerCount(database, 'reading_events', 'account-owner'), 1);
      final active = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).getSingle();
      expect(active.id, 'local:new-guest-owner');
      expect(active.firebaseUid, isNull);
    },
  );

  test('logout rollback restores the previous account owner', () async {
    final guest = await repository.createLocalGuestAfterLogout();

    await repository.rollbackLocalGuestLogout(
      previousOwnerId: 'guest-owner',
      guestOwnerId: guest.targetOwnerId,
    );

    final active = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).getSingle();
    expect(active.id, 'guest-owner');
    expect(
      await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals(guest.targetOwnerId))).getSingleOrNull(),
      isNull,
    );
  });

  test(
    'merge rebuilds SRS and reading projections from combined evidence',
    () async {
      await _seedProjectionCollisionGraph(database);

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final srs =
          await (database.select(database.srsStates)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.wordId.equals('word-target'),
              ))
              .getSingle();
      expect(srs.repetitions, 2);
      final reading =
          await (database.select(database.readingProgressEntries)..where(
                (row) =>
                    row.ownerId.equals('account-owner') &
                    row.documentId.equals('shared-doc') &
                    row.documentRevision.equals(1),
              ))
              .getSingle();
      expect(reading.lastPosition, 42);
      expect(reading.isCompleted, isTrue);
    },
  );

  test('merge preserves colliding reward evidence and debits once', () async {
    for (final ownerId in ['guest-owner', 'account-owner']) {
      await database.customInsert(
        "INSERT INTO points_ledger_entries "
        "(id, owner_id, idempotency_key, entry_type, amount, "
        "occurred_at_utc_ms) VALUES "
        "('seed:$ownerId', '$ownerId', 'seed:$ownerId', 'learning', 100, 1)",
      );
    }
    await database.customInsert(
      "INSERT INTO reward_transactions VALUES "
      "('reward-target', 'account-owner', 'same-tap', 'purchase', -80, "
      "'theme_ocean', 1, NULL, 2)",
    );
    await database.customInsert(
      "INSERT INTO reward_transactions VALUES "
      "('reward-guest', 'guest-owner', 'same-tap', 'purchase', -80, "
      "'theme_ocean', 1, NULL, 2)",
    );

    final result = await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );

    expect(result.conflictCount, 1);
    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((row) => row.ownerId.equals('account-owner'))).get(),
      hasLength(2),
    );
    expect(
      await (database.select(
        database.ownedRewardItems,
      )..where((row) => row.ownerId.equals('account-owner'))).get(),
      hasLength(1),
    );
    final ledger = await (database.select(
      database.pointsLedgerEntries,
    )..where((row) => row.ownerId.equals('account-owner'))).get();
    expect(ledger.fold<int>(0, (sum, row) => sum + row.amount), 120);
  });

  test(
    'merge rehomes acknowledged anonymous cloud data to account sync',
    () async {
      await _seedEveryOwnerScopedTable(database);
      await database.customInsert(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'attempt_count, state, failure_code, created_at_utc_ms) VALUES '
        "('srs:word-1:stable', 'guest-owner', 'srsState', 'word-1', "
        "'upsert', 5, 'permanentFailure', 'offline', 20)",
      );
      await database.customInsert(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'attempt_count, state, failure_code, created_at_utc_ms) VALUES '
        "('achievement:stable', 'guest-owner', 'achievementUnlock', "
        "'achievement-1', 'upsert', 5, 'permanentFailure', 'offline', 20)",
      );
      await database.customUpdate(
        "UPDATE local_owners SET firebase_uid = 'anonymous-user' "
        "WHERE id = 'guest-owner'",
      );
      await database.customUpdate(
        'UPDATE vocabulary_categories SET cloud_revision = 4, '
        'last_acknowledged_at_utc_ms = 40, server_updated_at_utc_ms = 40 '
        "WHERE owner_id = 'guest-owner'",
      );
      await database.customUpdate(
        'UPDATE vocabulary_words SET cloud_revision = 4, '
        'last_acknowledged_at_utc_ms = 40, server_updated_at_utc_ms = 40 '
        "WHERE owner_id = 'guest-owner'",
      );
      await database.customUpdate(
        "UPDATE outbox_operations SET state = 'acknowledged', "
        'base_revision = 3, acknowledged_at_utc_ms = 40 '
        "WHERE owner_id = 'guest-owner'",
      );
      await database.customUpdate(
        "UPDATE sync_checkpoints SET server_cursor = 'anonymous-cursor', "
        "last_success_at_utc_ms = 40 WHERE owner_id = 'guest-owner'",
      );

      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      final category = await (database.select(
        database.vocabularyCategories,
      )..where((row) => row.id.equals('category-1'))).getSingle();
      final word = await (database.select(
        database.vocabularyWords,
      )..where((row) => row.id.equals('word-1'))).getSingle();
      expect(category.cloudRevision, 0);
      expect(category.lastAcknowledgedAtUtcMs, isNull);
      expect(word.cloudRevision, 0);
      expect(word.serverUpdatedAtUtcMs, isNull);
      final rehomedOutbox = await (database.select(
        database.outboxOperations,
      )..where((row) => row.ownerId.equals('account-owner'))).get();
      for (final entityType in const [
        'category',
        'word',
        'attempt',
        'readingEvent',
        'rewardTransaction',
        'srsState',
        'achievementUnlock',
      ]) {
        expect(
          rehomedOutbox.where((row) => row.entityType == entityType),
          isNotEmpty,
          reason: '$entityType was not queued for the account namespace',
        );
      }
      expect(
        rehomedOutbox
            .where(
              (row) => const {
                'category',
                'word',
                'attempt',
                'readingEvent',
                'rewardTransaction',
                'srsState',
                'achievementUnlock',
              }.contains(row.entityType),
            )
            .every(
              (row) =>
                  row.state == 'pending' &&
                  row.baseRevision == 0 &&
                  row.attemptCount == 0 &&
                  row.nextAttemptAtUtcMs == null &&
                  row.failureCode == null,
            ),
        isTrue,
      );
      expect(
        rehomedOutbox
            .singleWhere((row) => row.operationId == 'srs:word-1:stable')
            .entityId,
        'word-1',
      );
      expect(
        rehomedOutbox
            .singleWhere((row) => row.operationId == 'achievement:stable')
            .entityId,
        'achievement-1',
      );
      final checkpoint = await (database.select(
        database.syncCheckpoints,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      expect(checkpoint.serverCursor, isNull);
      expect(checkpoint.lastSuccessAtUtcMs, isNull);

      await database.customUpdate(
        "UPDATE outbox_operations SET state = 'permanentFailure' "
        "WHERE operation_id <> 'srs:word-1:stable'",
        updates: {database.outboxOperations},
      );
      final reservationNow = DateTime.utc(2026, 7, 30, 13);
      final gate = DriftOwnerOperationGate(database);
      expect(
        await gate.tryAcquire(
          token: 'new-namespace-gate',
          nowUtc: reservationNow,
          leaseDuration: const Duration(days: 1),
        ),
        isTrue,
      );
      final syncStore = DriftSyncStore(database);
      for (var reservation = 1; reservation <= 5; reservation++) {
        final claim = (await syncStore.claimPending(
          ownerId: 'account-owner',
          firebaseUid: 'firebase-user',
          limit: 1,
          leaseToken: 'new-namespace-attempt-$reservation',
          ownerGateToken: 'new-namespace-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reservationNow,
        )).single;
        final attempted = (await syncStore.beginAttempt(
          claim: claim,
          ownerGateToken: 'new-namespace-gate',
          nowUtc: reservationNow,
        ))!;
        expect(attempted.mutation.operationId, 'srs:word-1:stable');
        expect(attempted.attemptCount, reservation);
        await syncStore.markRetry(
          operationId: attempted.mutation.operationId,
          leaseToken: attempted.leaseToken,
          ownerGateToken: 'new-namespace-gate',
          nowUtc: reservationNow,
          nextAttemptAtUtc: reservationNow,
          failure: const OfflineSyncFailure(),
        );
      }
      expect(
        await syncStore.claimPending(
          ownerId: 'account-owner',
          firebaseUid: 'firebase-user',
          limit: 1,
          leaseToken: 'new-namespace-attempt-6',
          ownerGateToken: 'new-namespace-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reservationNow,
        ),
        isEmpty,
      );
    },
  );
}

final class _ManualOwnerGateDelay {
  final List<Duration> delays = <Duration>[];
  final List<Completer<void>> _scheduled = <Completer<void>>[];

  Future<void> wait(Duration delay) {
    delays.add(delay);
    final completer = Completer<void>();
    _scheduled.add(completer);
    return completer.future;
  }

  void elapseNext() {
    _scheduled.firstWhere((item) => !item.isCompleted).complete();
  }
}

final class _TrackingOwnerGate implements OwnerOperationGate {
  _TrackingOwnerGate(this.delegate);

  final OwnerOperationGate delegate;
  final Completer<void> renewed = Completer<void>();

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.tryAcquire(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final result = await delegate.renew(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
    if (!renewed.isCompleted) renewed.complete();
    return result;
  }

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

final class _StealingOwnerGate implements OwnerOperationGate {
  _StealingOwnerGate(this.delegate, {required this.replacementToken});

  final OwnerOperationGate delegate;
  final String replacementToken;
  bool _stolen = false;

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final acquired = await delegate.tryAcquire(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
    if (acquired && !_stolen) {
      _stolen = true;
      await delegate.release(token: token);
      await delegate.tryAcquire(
        token: replacementToken,
        nowUtc: nowUtc,
        leaseDuration: leaseDuration,
      );
    }
    return acquired;
  }

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.renew(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

Future<QueryRow> _mergeConflictFor(AppDatabase database, String entityType) {
  return database
      .customSelect(
        'SELECT * FROM sync_conflicts '
        'WHERE owner_id = ? AND entity_type = ?',
        variables: [
          const Variable<String>('account-owner'),
          Variable<String>(entityType),
        ],
      )
      .getSingle();
}

Future<void> _seedOwners(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('guest-owner', NULL, 'localGuest', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('account-owner', 'firebase-user', 'firebaseBound', 2, 0)",
  );
}

Future<void> _seedEveryOwnerScopedTable(AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO research_consents VALUES "
    "('consent-1', 'guest-owner', 1, 'accepted', 10, NULL)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, sort_order, local_revision, "
    "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('category-1', 'guest-owner', 'Travel', 'travel', 0, 1, 0, 0, 10, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_words "
    "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
    "normalized_meaning, part_of_speech, source, is_global, local_revision, "
    "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('word-1', 'guest-owner', 'category-1', 'station', 'station', "
    "'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 0, 0, 10, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_imports VALUES "
    "('import-1', 'guest-owner', 'category-1', 'csv', 'travel.csv', "
    "'hash-1', 'complete', 1, 0, 0, 10, 11)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_import_rows VALUES "
    "('import-row-1', 'import-1', 1, 'row-hash-1', 'accepted', NULL, 'word-1')",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES "
    "('session-1', 'guest-owner', 'quiz', 'completed', 10, 20, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-1', 'guest-owner', 'session-1', 'word-1', 'meaning', 1, "
    '100, 1, 15, NULL)',
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('srs-1', 'guest-owner', 'word-1', 1, 1, 1, 1, 0, 15, 30, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('reading-progress-1', 'guest-owner', 'doc-1', 1, 5, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('reading-event-1', 'guest-owner', 'doc-1', 1, 'position', 5, 20)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES "
    "('points-1', 'guest-owner', 'answer:1', 'quiz', 200, 'attempt-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES "
    "('achievement-1', 'guest-owner', 'first-answer', 1, 'attempt-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES "
    "('reward-1', 'guest-owner', 'reward-key-1', 'purchase', -80, "
    "'theme_ocean', 1, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES "
    "('reward-equip-1', 'guest-owner', 'reward-equip-key-1', 'equip', 0, "
    "'theme_ocean', 1, NULL, 21)",
  );
  await database.customInsert(
    "INSERT INTO owned_reward_items VALUES "
    "('owned-1', 'guest-owner', 'theme_ocean', 1, 'reward-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO equipped_reward_items VALUES "
    "('equipped-1', 'guest-owner', 'theme', 'theme_ocean', 20)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('operation-1', 'guest-owner', 'word', 'word-1', 'upsert', 20)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('attempt:attempt-1:1', 'guest-owner', 'attempt', 'attempt-1', "
    "'upsert', 20)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('readingEvent:reading-event-1:1', 'guest-owner', 'readingEvent', "
    "'reading-event-1', 'upsert', 20)",
  );
  await database.customInsert(
    "INSERT INTO sync_checkpoints VALUES "
    "('checkpoint-1', 'guest-owner', 'words', NULL, NULL)",
  );
  await database.customInsert(
    "INSERT INTO sync_conflicts "
    "(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, "
    "resolution_policy, outcome, resolved_at_utc_ms) VALUES "
    "('conflict-1', 'guest-owner', 'word', 'word-1', 1, 2, "
    "'cloudWins', 'cloudApplied', 20)",
  );
  await database.customInsert(
    "INSERT INTO events_v2 "
    "(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, "
    "actor_identity, owner_id, aggregate_type, aggregate_id, idempotency_key, "
    "consent_context_json, app_version, build_id, privacy_classification, "
    "payload_json) VALUES "
    "('evt-seed-1', 'QuizCompleted', 1, '2026-08-04T10:00:00.000Z', "
    "'2026-08-04T10:00:01.000Z', 'guest-owner', 'guest-owner', "
    "'LearningSession', 'sess-1', 'idem-seed-1', '{}', "
    "'1.0.0', 'sha1', 'anonymized', '{}')",
  );
  // Phase 0 Week 10-11 — quest catalog row (no owner_id) + instance row.
  await database.customInsert(
    "INSERT INTO quest_definitions "
    "(quest_id, catalog_version, title, description, type, "
    "objectives_json, reward_json) VALUES "
    "('q-seed-1', 1, 'Seed Quest', 'Seed', 'daily', '[]', "
    "'{\"xpAmount\":10,\"rewardItemId\":null}')",
  );
  await database.customInsert(
    "INSERT INTO quest_instances "
    "(instance_id, quest_id, owner_id, catalog_version, "
    "assigned_at_utc_ms, state) VALUES "
    "('inst-seed-1', 'q-seed-1', 'guest-owner', 1, 20, 'active')",
  );
  // Phase 1 D7.2 — streak state and learning day log (owner-scoped).
  await database.customInsert(
    "INSERT INTO streak_states "
    "(owner_id, current_streak_days, longest_streak_days, freeze_count, "
    "updated_at_utc_ms) VALUES "
    "('guest-owner', 1, 1, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO learning_day_log "
    "(id, owner_id, learning_day, first_session_at_utc_ms) VALUES "
    "('day:guest-owner:2026-08-04', 'guest-owner', '2026-08-04', 20)",
  );
  // Phase 2 D8.3 — associative learning data (owner-scoped).
  await database.customInsert(
    "INSERT INTO association_records "
    "(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES "
    "('assoc-seed-1', 'guest-owner', 'banana', 'keyword', 'yellow fruit', 20)",
  );
  await database.customInsert(
    "INSERT INTO associative_memory_states "
    "(id, owner_id, word_key, stability, difficulty, cue_dependency, "
    "lapse_count, next_due_at_utc_ms, algorithm_version) VALUES "
    "('ams-seed-1', 'guest-owner', 'banana', 1.0, 5.0, 0.0, "
    "0, 1722844800000, 'v1.0.0')",
  );
  // Schema v11 — speech evidence (owner-scoped).
  await database.customInsert(
    "INSERT INTO speech_evidence "
    "(id, owner_id, session_id, word_id, prompt_mode, target_content, "
    "recognized_transcript, locale, stt_engine, similarity_algorithm, "
    "similarity_score, is_exact_match, recognition_confidence, sample_size, "
    "occurred_at_utc_ms, duration_ms) VALUES "
    "('evidence-seed-1', 'guest-owner', 'session-1', 'word-1', 'meaning', "
    "'station', 'station', 'en-US', 'speech_to_text', 'levenshtein', "
    "100, 1, 0.95, 1, 20, 500)",
  );

  // Schema v12 — provider-neutral AI usage is owner-scoped.
  await database.customInsert(
    "INSERT INTO ai_usage_events "
    "(event_id, owner_id, occurred_at_utc_ms, provider_id, model, "
    "request_type, outcome, latency_ms) VALUES "
    "('ai-usage-seed-1', 'guest-owner', 20, 'gemini', 'model', "
    "'tutorReply', 'success', 10)",
  );
}

Future<void> _seedCollisionGraph(AppDatabase database) async {
  for (final values in [
    "('category-target', 'account-owner', 'Travel', 'travel', 0, 1, 0, 0, 1, 1)",
    "('category-guest', 'guest-owner', 'Travel', 'travel', 0, 1, 0, 0, 1, 1)",
  ]) {
    await database.customInsert(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, sort_order, local_revision, '
      'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES $values',
    );
  }
  for (final values in [
    "('word-target', 'account-owner', 'category-target', 'station', 'station', "
        "'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
    "('word-guest', 'guest-owner', 'category-guest', 'station', 'station', "
        "'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
  ]) {
    await database.customInsert(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
      'normalized_meaning, part_of_speech, source, is_global, local_revision, '
      'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES $values',
    );
  }
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES "
    "('session-guest', 'guest-owner', 'quiz', 'completed', 1, 2, 1, 0, 1, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-guest', 'guest-owner', 'session-guest', 'word-guest', "
    "'meaning', 1, 10, 1, 2, NULL)",
  );
  await database.customInsert(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, "
    "created_at_utc_ms) VALUES "
    "('operation-guest', 'guest-owner', 'word', 'word-guest', 'upsert', 2)",
  );
}

Future<void> _seedProjectionCollisionGraph(AppDatabase database) async {
  await _seedCollisionGraph(database);
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES "
    "('session-target', 'account-owner', 'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-target', 'account-owner', 'session-target', 'word-target', "
    "'meaning', 1, 10, 1, 1, NULL)",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('srs-target', 'account-owner', 'word-target', 1, 1, 1, 1, 0, 1, 2, 1)",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('srs-guest', 'guest-owner', 'word-guest', 1, 1, 1, 1, 0, 2, 3, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('reading-target', 'account-owner', 'shared-doc', 1, 5, 0, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('reading-guest', 'guest-owner', 'shared-doc', 1, 42, 1, 2)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('reading-event-target', 'account-owner', 'shared-doc', 1, "
    "'position', 5, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('reading-event-guest', 'guest-owner', 'shared-doc', 1, "
    "'completed', 42, 2)",
  );
}

Future<int> _ownerCount(
  AppDatabase database,
  String table,
  String ownerId,
) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM $table WHERE owner_id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .getSingle();
  return row.read<int>('count');
}

Future<void> _insertLearningEvent(
  AppDatabase database, {
  required String ownerId,
  required String eventId,
  required DateTime occurredAt,
}) => database
    .into(database.eventsV2)
    .insert(
      EventsV2Companion.insert(
        eventId: eventId,
        eventType: 'QuizCompleted',
        eventVersion: 1,
        occurredAtUtc: occurredAt,
        recordedAtUtc: occurredAt,
        actorIdentity: ownerId,
        ownerId: ownerId,
        aggregateType: 'LearningSession',
        aggregateId: 'session:$ownerId',
        idempotencyKey: 'learning-attempt:$eventId:v1',
        consentContextJson: '{}',
        appVersion: '1.0.0',
        buildId: 'owner-upgrade-test',
        privacyClassification: 'anonymized',
        payloadJson: '{"correct":true}',
      ),
    );

Future<void> _insertProjectionResult(
  AppDatabase database, {
  required String ownerId,
  required String sourceEventId,
  required String projection,
  required DateTime occurredAt,
  required Map<String, dynamic> result,
}) {
  final key = 'learning-projection:$projection:$sourceEventId:v1';
  return database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: key,
          eventType: 'LearningProjectionApplied',
          eventVersion: 1,
          occurredAtUtc: occurredAt,
          recordedAtUtc: occurredAt,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningProjection',
          aggregateId: sourceEventId,
          causationId: Value(sourceEventId),
          idempotencyKey: key,
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode({
            'sourceEventId': sourceEventId,
            'projection': projection,
            'appliedVersion': 1,
            'outcome': 'applied',
            'result': result,
          }),
        ),
      );
}

Future<void> _insertProjectionCursor(
  AppDatabase database, {
  required String ownerId,
  required String sourceEventId,
  required String projection,
  required DateTime occurredAt,
}) {
  final key = 'learning-projection-cursor:$ownerId:$projection:v1';
  return database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: key,
          eventType: 'LearningProjectionCursor',
          eventVersion: 1,
          occurredAtUtc: occurredAt,
          recordedAtUtc: occurredAt,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningProjectionCursor',
          aggregateId: sourceEventId,
          causationId: Value(sourceEventId),
          idempotencyKey: key,
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'owner-upgrade-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode({
            'sourceEventId': sourceEventId,
            'projection': projection,
            'appliedVersion': 1,
          }),
        ),
      );
}
