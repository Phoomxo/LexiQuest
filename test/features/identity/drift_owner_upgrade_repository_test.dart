import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  var conflictSequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      generateConflictId: () => 'upgrade-conflict-${conflictSequence++}',
      generateOwnerId: () => 'new-guest-owner',
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
              'WHERE owner_id = ? AND resolution_policy = ?',
              variables: const [
                Variable<String>('account-owner'),
                Variable<String>('guestUpgradeTargetWins'),
              ],
            )
            .getSingle()
            .then((row) => row.read<int>('count')),
        2,
      );
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
              }.contains(row.entityType),
            )
            .every((row) => row.state == 'pending' && row.baseRevision == 0),
        isTrue,
      );
      final checkpoint = await (database.select(
        database.syncCheckpoints,
      )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
      expect(checkpoint.serverCursor, isNull);
      expect(checkpoint.lastSuccessAtUtcMs, isNull);
    },
  );
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
    "INSERT INTO answer_attempts VALUES "
    "('attempt-1', 'guest-owner', 'session-1', 'word-1', 'meaning', 1, 100, 1, 15, NULL)",
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
    "INSERT INTO answer_attempts VALUES "
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
    "INSERT INTO answer_attempts VALUES "
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
