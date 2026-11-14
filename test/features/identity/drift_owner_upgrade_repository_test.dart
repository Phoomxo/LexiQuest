import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';

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

  group('v12 study owner merge', () {
    Future<List<Map<String, Object?>>> rows(String table) async =>
        (await database
                .customSelect('SELECT * FROM "$table" ORDER BY rowid')
                .get())
            .map((r) => r.data)
            .toList();

    Future<void> merge() async {
      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      expect(result.targetOwnerId, 'account-owner');
    }

    Future<void> expectStableReplay() async {
      final before = {
        for (final table in database.allTables)
          table.actualTableName: await rows(table.actualTableName),
      };
      final replay = await repository.upgrade(
        activeOwnerId: 'account-owner',
        firebaseUid: 'firebase-user',
      );
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      for (final entry in before.entries) {
        expect(await rows(entry.key), entry.value, reason: entry.key);
      }
    }

    test(
      'bookmarks merge by exact sense without restoring deleted target words',
      () async {
        for (final owner in ['guest-owner', 'account-owner']) {
          await database.customStatement(
            'INSERT INTO vocabulary_categories '
            '(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) '
            "VALUES (?,?,'Travel','travel',1,2)",
            ['cat-$owner', owner],
          );
        }
        for (final (id, owner, meaning, marked, deleted) in [
          ('guest-same', 'guest-owner', 'railway', 1, 0),
          ('target-same', 'account-owner', 'railway', 0, 0),
          ('guest-deleted', 'guest-owner', 'broadcast', 1, 0),
          ('target-deleted', 'account-owner', 'broadcast', 0, 1),
          ('guest-distinct', 'guest-owner', 'post', 1, 0),
          ('target-distinct', 'account-owner', 'stop', 0, 0),
          ('target-marked', 'account-owner', 'base', 1, 0),
        ]) {
          await database.customStatement(
            'INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,'
            'meaning,normalized_meaning,part_of_speech,is_bookmarked,is_deleted,created_at_utc_ms,updated_at_utc_ms) '
            "VALUES (?,?,?,'station','station',?,?,'noun',?,?,3,4)",
            [id, owner, 'cat-$owner', meaning, meaning, marked, deleted],
          );
        }
        final targetBefore = (await rows(
          'vocabulary_words',
        )).where((r) => r['owner_id'] == 'account-owner').toList();
        await merge();
        final words = await rows('vocabulary_words');
        expect(words, hasLength(5));
        for (final before in targetBefore) {
          final marked = [
            'target-same',
            'target-deleted',
            'target-marked',
          ].contains(before['id']);
          expect(words.singleWhere((r) => r['id'] == before['id']), {
            ...before,
            'is_bookmarked': marked ? 1 : 0,
          });
        }
        final moved = words.singleWhere((r) => r['id'] == 'guest-distinct');
        expect(
          (
            moved['owner_id'],
            moved['category_id'],
            moved['is_bookmarked'],
            moved['meaning'],
          ),
          ('account-owner', 'cat-account-owner', 1, 'post'),
        );
        await expectStableReplay();
      },
    );

    Future<void> focus(String owner, String state) async {
      await database.customStatement(
        'INSERT INTO owner_calendar_epochs (rule_id,owner_id,origin_owner_id,'
        'effective_utc_us,iana_id,tzdb_revision,is_selected) '
        "VALUES (?,?,?,0,'UTC','synthetic-retained-revision',1)",
        ['rule-$owner', owner, owner],
      );
      await database.customStatement(
        'INSERT INTO focus_sessions (id,owner_id,origin_owner_id,target_ms,started_at_utc_ms,'
        'start_rule_id,start_civil_week,state,revision,spans_json) VALUES (?,?,?,300000,10,?,?,?,4,?)',
        [
          'focus-$owner',
          owner,
          owner,
          'rule-$owner',
          '2026-07-27',
          state,
          '{ "version": 1, "spans": [{"kind":"active","elapsedMs":1234}] }',
        ],
      );
    }

    for (final (guestState, hasTarget) in [
      ('running', true),
      ('paused', true),
      ('running', false),
      ('paused', false),
    ]) {
      test(
        'rehome $guestState focus with targetOpen=$hasTarget preserves measured history',
        () async {
          await focus('guest-owner', guestState);
          if (hasTarget) {
            await focus('account-owner', 'paused');
          }
          await database.customStatement(
            'INSERT INTO local_content_reports '
            '(id,owner_id,source_kind,source_id,source_revision,spelling,meaning,sentence,reason,created_at_utc_ms) '
            "VALUES ('report','guest-owner','localPassage','retained-source',3,'station','สถานี','Original sentence.','sentenceTypo',17)",
          );
          final before = await rows('focus_sessions');
          final reports = await rows('local_content_reports');
          final rules = await rows('owner_calendar_epochs');
          await merge();
          expect(await rows('local_content_reports'), [
            for (final report in reports)
              {...report, 'owner_id': 'account-owner'},
          ]);
          final after = await rows('focus_sessions');
          for (final original in before) {
            final row = after.singleWhere((r) => r['id'] == original['id']);
            final guest = original['owner_id'] == 'guest-owner';
            final interrupted = guest && (guestState == 'running' || hasTarget);
            final expected = {
              ...original,
              'owner_id': 'account-owner',
              if (interrupted) 'state': 'interrupted',
            };
            // Preserve the measured spans and the unknown end of the old lease.
            expect(
              row['revision'],
              interrupted
                  ? greaterThanOrEqualTo(original['revision'] as int)
                  : original['revision'],
            );
            expected['revision'] = row['revision'];
            expect(row, expected);
          }
          for (final original in rules) {
            final retained = (await rows(
              'owner_calendar_epochs',
            )).singleWhere((r) => r['rule_id'] == original['rule_id']);
            expect(retained['owner_id'], 'account-owner');
            expect(retained['origin_owner_id'], original['origin_owner_id']);
            expect(retained['iana_id'], original['iana_id']);
            expect(retained['tzdb_revision'], original['tzdb_revision']);
          }
          for (final table in [
            'answer_attempts',
            'learning_sessions',
            'points_ledger_entries',
            'reward_transactions',
            'achievement_unlocks',
            'events_v2',
            'outbox_operations',
          ]) {
            expect(await rows(table), isEmpty, reason: table);
          }
          await expectStableReplay();
        },
      );
    }

    for (final target in ['skipped', 'completed', 'unset', 'absent']) {
      test(
        'preferences preserve $target target decisions and fill nullable choices',
        () async {
          await database.customStatement(
            'INSERT INTO learning_preferences (owner_id,onboarding_state,purpose,planned_minutes,'
            'learning_method,goal_state,goal_civil_date,updated_at_utc_ms) '
            "VALUES ('guest-owner','completed','travel',5,'read','active','2026-12-01',90)",
          );
          final goalState = target == 'skipped'
              ? 'closed'
              : target == 'completed'
              ? 'active'
              : 'unset';
          final goalDate = target == 'completed' ? '2026-11-20' : null;
          if (target != 'absent') {
            await database.customStatement(
              'INSERT INTO learning_preferences (owner_id,onboarding_state,purpose,planned_minutes,'
              'learning_method,goal_state,goal_civil_date,updated_at_utc_ms) VALUES (?,?,?,?,?,?,?,?)',
              [
                'account-owner',
                target,
                target == 'skipped' ? 'work' : null,
                target == 'completed' ? 10 : null,
                target == 'unset' ? 'speak' : null,
                goalState,
                goalDate,
                target == 'completed' ? 100 : 60,
              ],
            );
          }
          await merge();
          expect(await rows('learning_preferences'), [
            {
              'owner_id': 'account-owner',
              'onboarding_state': target == 'skipped' ? 'skipped' : 'completed',
              'purpose': target == 'skipped' ? 'work' : 'travel',
              'planned_minutes': target == 'completed' ? 10 : 5,
              'learning_method': target == 'unset' ? 'speak' : 'read',
              'goal_state': goalState == 'unset' ? 'active' : goalState,
              'goal_civil_date': goalState == 'unset' ? '2026-12-01' : goalDate,
              'updated_at_utc_ms': target == 'completed' ? 100 : 90,
            },
          ]);
          await expectStableReplay();
        },
      );
    }
  });

  test('merge duplicate earned badge leaves no dangling pending sync operation', () async {
    await _seedEveryOwnerScopedTable(database);
    await database.customInsert(
      "INSERT INTO achievement_unlocks VALUES ('guest-first', 'guest-owner', 'first_answer', 1, 'guest-source', 13)",
    );
    await database.customInsert(
      "INSERT INTO achievement_unlocks VALUES ('target-first', 'account-owner', 'first_answer', 1, 'target-source', 7)",
    );
    await database.customInsert(
      "INSERT INTO outbox_operations (operation_id,owner_id,entity_type,entity_id,operation_kind,state,created_at_utc_ms) VALUES ('guest-badge-pending','guest-owner','achievementUnlock','guest-first','upsert','pending',13)",
    );
    await database.customInsert(
      "INSERT INTO outbox_operations (operation_id,owner_id,entity_type,entity_id,operation_kind,state,created_at_utc_ms,acknowledged_at_utc_ms) VALUES ('target-badge-ack','account-owner','achievementUnlock','target-first','upsert','acknowledged',7,8)",
    );
    await database.customInsert(
      "INSERT INTO outbox_operations (operation_id,owner_id,entity_type,entity_id,operation_kind,state,attempt_count,last_attempt_at_utc_ms,created_at_utc_ms,acknowledged_at_utc_ms) VALUES ('guest-badge-ack','guest-owner','achievementUnlock','guest-first','upsert','acknowledged',2,15,13,16)",
    );
    final targetBefore = await (database.select(
      database.achievementUnlocks,
    )..where((r) => r.id.equals('target-first'))).getSingle();
    final ackBefore = await (database.select(
      database.outboxOperations,
    )..where((r) => r.operationId.equals('target-badge-ack'))).getSingle();
    final guestAckBefore = await (database.select(
      database.outboxOperations,
    )..where((r) => r.operationId.equals('guest-badge-ack'))).getSingle();
    await repository.upgrade(
      activeOwnerId: 'guest-owner',
      firebaseUid: 'firebase-user',
    );
    await repository.upgrade(
      activeOwnerId: 'account-owner',
      firebaseUid: 'firebase-user',
    );
    expect(
      await (database.select(
        database.achievementUnlocks,
      )..where((r) => r.id.equals('target-first'))).getSingle(),
      targetBefore,
    );
    expect(
      await (database.select(
        database.outboxOperations,
      )..where((r) => r.operationId.equals('target-badge-ack'))).getSingle(),
      ackBefore,
    );
    expect(
      await (database.select(
        database.outboxOperations,
      )..where((r) => r.operationId.equals('guest-badge-ack'))).getSingle(),
      guestAckBefore.copyWith(ownerId: 'account-owner'),
    );
    final dangling = await database
        .customSelect(
          "SELECT o.operation_id FROM outbox_operations o WHERE o.owner_id = 'account-owner' AND o.entity_type = 'achievementUnlock' AND o.state IN ('pending','retryWaiting','inFlight','blockedAuth') AND NOT EXISTS (SELECT 1 FROM achievement_unlocks a WHERE a.owner_id = o.owner_id AND a.id = o.entity_id)",
        )
        .get();
    expect(dangling, isEmpty);
    final claims = await DriftSyncStore(database).claimPending(
      ownerId: 'account-owner',
      firebaseUid: 'firebase-user',
      limit: 50,
      leaseToken: 'synthetic-badge-lease',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: DateTime.utc(2026, 7, 30, 13),
    );
    expect(
      claims.where((c) => c.mutation.operationId == 'target-badge-ack'),
      isEmpty,
    );
    expect(
      claims.where((c) => c.mutation.operationId == 'guest-badge-ack'),
      isEmpty,
    );
    expect(claims.where((c) => c.mutation.entityId == 'guest-first'), isEmpty);
    for (final claim in claims.where(
      (c) => c.mutation.collection == SyncCollection.achievementUnlocks,
    )) {
      final row =
          await (database.select(database.achievementUnlocks)..where(
                (a) =>
                    a.id.equals(claim.mutation.entityId) &
                    a.ownerId.equals('account-owner'),
              ))
              .getSingle();
      expect(claim.mutation.payload, {
        'achievementId': row.achievementId,
        'definitionVersion': row.definitionVersion,
        'sourceEventId': row.sourceEventId,
        'unlockedAtUtcMs': row.unlockedAtUtcMs,
      });
    }
  });

  test(
    'merge rebuild preserves retained achievement identity and legacy versions',
    () async {
      await _seedEveryOwnerScopedTable(database);
      await database.customInsert(
        "INSERT INTO achievement_unlocks VALUES ('accepted-target', 'account-owner', 'first_answer', 1, 'accepted-source', 7)",
      );
      await database.customInsert(
        "INSERT INTO achievement_unlocks VALUES ('older-version', 'account-owner', 'first_answer', 2, 'older-source', 8)",
      );
      await database.customInsert(
        "INSERT INTO achievement_unlocks VALUES ('unknown-legacy', 'account-owner', 'legacy_unknown', 1, 'legacy-source', 9)",
      );
      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      final rows = await (database.select(
        database.achievementUnlocks,
      )..where((r) => r.ownerId.equals('account-owner'))).get();
      final snapshot = {
        for (final row in rows)
          row.id: (
            row.achievementId,
            row.definitionVersion,
            row.sourceEventId,
            row.unlockedAtUtcMs,
          ),
      };
      expect(snapshot['accepted-target'], (
        'first_answer',
        1,
        'accepted-source',
        7,
      ));
      expect(snapshot['older-version'], ('first_answer', 2, 'older-source', 8));
      expect(snapshot['unknown-legacy'], (
        'legacy_unknown',
        1,
        'legacy-source',
        9,
      ));
      await repository.upgrade(
        activeOwnerId: 'account-owner',
        firebaseUid: 'firebase-user',
      );
      final replay = await (database.select(
        database.achievementUnlocks,
      )..where((r) => r.ownerId.equals('account-owner'))).get();
      expect({
        for (final row in replay)
          row.id: (
            row.achievementId,
            row.definitionVersion,
            row.sourceEventId,
            row.unlockedAtUtcMs,
          ),
      }, snapshot);
    },
  );

  test(
    'local credits keep stable identities through rehome without reward outbox',
    () async {
      await _seedEveryOwnerScopedTable(database);
      final rewards = DriftRewardRepository(database);
      final before = await rewards.load('guest-owner');
      expect(before.balance, 120);
      final creditsBefore =
          await (database.select(database.rewardTransactions)..where(
                (r) => r.transactionType.isIn([
                  'creditQuizCorrectV1',
                  'creditLegacyCarryV1',
                ]),
              ))
              .get();
      expect(creditsBefore, hasLength(2));
      await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );
      final account = await rewards.load('account-owner');
      expect(account.balance, before.balance);
      expect(account.ownedItemIds, before.ownedItemIds);
      expect(account.equippedBySlot, before.equippedBySlot);
      final creditsAfter =
          await (database.select(database.rewardTransactions)..where(
                (r) => r.transactionType.isIn([
                  'creditQuizCorrectV1',
                  'creditLegacyCarryV1',
                ]),
              ))
              .get();
      expect(
        creditsAfter.map((r) => r.id).toSet(),
        creditsBefore.map((r) => r.id).toSet(),
      );
      expect(
        creditsAfter.every(
          (r) =>
              r.ownerId == 'account-owner' &&
              !r.idempotencyKey.startsWith('merged:'),
        ),
        isTrue,
      );
      final outbox = await database.select(database.outboxOperations).get();
      final creditIds = creditsAfter.map((r) => r.id).toSet();
      expect(outbox.where((r) => creditIds.contains(r.entityId)), isEmpty);
      expect((await rewards.load('guest-owner')).balance, 0);
    },
  );

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
      await (database.select(database.rewardTransactions)..where(
            (row) =>
                row.ownerId.equals('account-owner') &
                row.transactionType.equals('purchase'),
          ))
          .get(),
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
    expect(ledger.fold<int>(0, (sum, row) => sum + row.amount), 200);
    expect(
      (await DriftRewardRepository(database).load('account-owner')).balance,
      120,
    );
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

const _insertLegacyAnswer =
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, provider_provenance) '
    'VALUES ';

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
    "INSERT INTO learning_sessions "
    "(id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, "
    "correct_count, wrong_count, score, app_version, build_id) VALUES "
    "('session-1', 'guest-owner', 'quiz', 'completed', 10, 20, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    "$_insertLegacyAnswer"
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
    "assigned_at_utc_ms, state, completed_at_utc_ms, expired_at_utc_ms) VALUES "
    "('inst-seed-1', 'q-seed-1', 'guest-owner', 1, 20, 'active', NULL, NULL)",
  );
  await database.customInsert(
    "INSERT INTO owner_calendar_epochs "
    "(rule_id, owner_id, origin_owner_id, effective_utc_us, iana_id, "
    "tzdb_revision, is_selected) VALUES "
    "('rule-seed', 'guest-owner', 'guest-owner', 0, 'UTC', 'synthetic', 1)",
  );
  const definition =
      '{"cadence":"daily","criteria":{"correct":true},"target":1,"xpAmount":10}';
  final digest = sha256.convert(utf8.encode(definition)).toString();
  await database.customStatement(
    'INSERT INTO quest_definition_revisions '
    '(quest_id, catalog_version, definition_digest, canonical_definition) '
    "VALUES ('q-seed-1', 1, ?, ?)",
    [digest, definition],
  );
  await database.customStatement(
    'INSERT INTO quest_instances '
    '(instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, '
    'state, completed_at_utc_ms, origin_owner_id, period_key, calendar_rule_id, '
    'civil_label, segments_json, definition_digest, record_kind) VALUES '
    "('inst-paid', 'q-seed-1', 'guest-owner', 1, 0, 'completed', 15, "
    "'guest-owner', 'guest-owner:rule-seed:daily:1970-01-01:q-seed-1', "
    "'rule-seed', '1970-01-01', '[[0,86400000000]]', ?, 'canonical')",
    [digest],
  );
  await database.customStatement(
    'INSERT INTO quest_claim_receipts '
    '(id, owner_id, origin_owner_id, instance_id, issued_at_utc_ms, '
    'completed_at_utc_ms, xp_amount, evidence_json) VALUES '
    "('receipt-seed', 'guest-owner', 'guest-owner', 'inst-paid', 16, 15, 10, ?)",
    ['["attempt-1"]'],
  );
  await database.customInsert(
    'INSERT INTO points_ledger_entries '
    '(id, owner_id, idempotency_key, entry_type, amount, source_event_id, '
    'occurred_at_utc_ms) VALUES '
    "('xp-seed', 'guest-owner', 'quest-claim:receipt-seed', 'questClaimXpV1', "
    "10, 'receipt-seed', 16)",
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
  await database.customInsert(
    'INSERT INTO streak_baselines '
    '(origin_owner_id, owner_id, cutoff_utc_ms, current_streak_days, '
    'longest_streak_days, freeze_count, updated_at_utc_ms, controls_continuity) '
    "VALUES ('guest-owner', 'guest-owner', 20, 1, 1, 0, 20, 1)",
  );
  await database.customInsert(
    'INSERT INTO streak_token_adjustments '
    '(id, owner_id, origin_owner_id, command_id, occurred_at_utc_ms, kind, delta) '
    "VALUES ('token-seed', 'guest-owner', 'guest-owner', 'grant-seed', 21, 'grant', 1)",
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
  await database.customInsert(
    'INSERT INTO local_content_reports '
    '(id, owner_id, source_kind, source_id, source_revision, spelling, meaning, '
    'reason, created_at_utc_ms) VALUES '
    "('report-seed', 'guest-owner', 'word', 'word-1', 1, 'banana', 'fruit', "
    "'Synthetic report', 20)",
  );
  await database.customInsert(
    'INSERT INTO focus_sessions '
    '(id, owner_id, origin_owner_id, target_ms, started_at_utc_ms, start_rule_id, '
    'start_civil_week, state, revision, spans_json, ended_at_utc_ms) VALUES '
    "('focus-seed', 'guest-owner', 'guest-owner', 1000, 20, 'rule-seed', "
    "'1969-12-29', 'completed', 1, '[[20,1020]]', 1020)",
  );
  await database.customInsert(
    'INSERT INTO learning_preferences '
    '(owner_id, onboarding_state, purpose, planned_minutes, learning_method, '
    'goal_civil_date, goal_state, updated_at_utc_ms) VALUES '
    "('guest-owner', 'unset', NULL, NULL, NULL, NULL, 'unset', 20)",
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
    "INSERT INTO learning_sessions "
    "(id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, "
    "correct_count, wrong_count, score, app_version, build_id) VALUES "
    "('session-guest', 'guest-owner', 'quiz', 'completed', 1, 2, 1, 0, 1, '1', '1')",
  );
  await database.customInsert(
    "$_insertLegacyAnswer"
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
    "INSERT INTO learning_sessions "
    "(id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, "
    "correct_count, wrong_count, score, app_version, build_id) VALUES "
    "('session-target', 'account-owner', 'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    "$_insertLegacyAnswer"
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
