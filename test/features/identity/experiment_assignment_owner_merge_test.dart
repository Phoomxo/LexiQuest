import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';

const _guest = 'synthetic-assignment-guest';
const _account = 'synthetic-assignment-account';
const _uid = 'synthetic-assignment-firebase';

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    sequence = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 10, 29),
      generateConflictId: () => 'synthetic-assignment-conflict-${sequence++}',
      generateOwnerId: () => 'unused-assignment-guest',
    );
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement(
      'INSERT INTO local_owners (id, firebase_uid, account_state, created_at_utc_ms, is_active) '
      "VALUES (?, NULL, 'localGuest', 1, 1), (?, ?, 'firebaseBound', 2, 0)",
      [_guest, _account, _uid],
    );
  });
  tearDown(() => database.close());

  Future<OwnerUpgradeResult> merge() =>
      repository.upgrade(activeOwnerId: _guest, firebaseUid: _uid);

  test(
    'rekeys every guest fact while preserving the immutable assignment fields',
    () async {
      await _seedMergeGraph(database);
      await _insertAssignment(database);
      await _insertAssignment(database, version: 2, assigned: 200);
      await _insertAssignment(
        database,
        owner: _account,
        experiment: 'target-only-study',
        assigned: 50,
      );
      final before = await _assignments(database);
      final eventPayload =
          (await database
                  .customSelect('SELECT payload_json FROM events_v2')
                  .getSingle())
              .read<String>('payload_json');

      final result = await merge();

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      final rows = await _assignments(database);
      expect(rows, hasLength(3));
      for (final fact in before) {
        final targetId = experimentAssignmentId(
          ownerId: _account,
          experimentId: fact['experiment_id']! as String,
          experimentVersion: fact['experiment_version']! as int,
        );
        expect(rows.singleWhere((row) => row['id'] == targetId), {
          ...fact,
          'id': targetId,
          'owner_id': _account,
        });
      }
      expect(
        (await database
                .customSelect('SELECT payload_json FROM events_v2')
                .getSingle())
            .read<String>('payload_json'),
        eventPayload,
      );
      expect(await _count(database, 'vocabulary_categories', owner: _guest), 0);
      expect(await _count(database, 'vocabulary_words', owner: _guest), 0);
      final assignmentIds = {
        ...before.map((row) => row['id']),
        ...rows.map((row) => row['id']),
      };
      final outbox = await database.select(database.outboxOperations).get();
      expect(
        outbox.where((operation) => assignmentIds.contains(operation.entityId)),
        isEmpty,
      );
    },
  );

  test('deduplicates only an exactly identical target fact', () async {
    await _insertAssignment(database);
    await _insertAssignment(database, owner: _account);
    final target = (await _assignments(
      database,
    )).singleWhere((row) => row['owner_id'] == _account);

    final result = await merge();

    expect(result.conflictCount, 0);
    expect(await _assignments(database), [target]);
    expect(await _count(database, 'sync_conflicts'), 0);
  });

  for (final mismatch in <({String name, Map<String, Object?> changes})>[
    (name: 'cohort', changes: {'cohort': 'treatment-b'}),
    (name: 'protocol', changes: {'protocol_version': 'protocol-v2'}),
    (name: 'first admission time', changes: {'assigned_at_utc_ms': 101}),
  ]) {
    test(
      'a different ${mismatch.name} rolls back the entire populated upgrade',
      () async {
        await _seedMergeGraph(database);
        await _insertAssignment(database);
        await _insertAssignment(
          database,
          owner: _account,
          overrides: mismatch.changes,
        );
        final before = await _snapshot(database);

        await expectLater(merge(), throwsA(isA<StateError>()));

        expect(await _snapshot(database), before);
      },
    );
  }

  for (final owner in [_guest, _account]) {
    for (final invalid in <({String name, Map<String, Object?> changes})>[
      (
        name: 'noncanonical ID',
        changes: {'id': 'synthetic-noncanonical-assignment'},
      ),
      (name: 'blank experiment', changes: {'experiment_id': '   '}),
      (name: 'blank cohort', changes: {'cohort': ''}),
      (name: 'blank protocol', changes: {'protocol_version': '\t'}),
      (name: 'nonpositive version', changes: {'experiment_version': 0}),
      (name: 'negative admission time', changes: {'assigned_at_utc_ms': -1}),
    ]) {
      test(
        'rejects ${invalid.name} on $owner without changing any owner data',
        () async {
          await _seedMergeGraph(database);
          // Corrupt persisted fixtures exercise the merge boundary beyond SQL CHECKs.
          await database.customStatement(
            'PRAGMA ignore_check_constraints = ON',
          );
          await _insertAssignment(
            database,
            owner: owner,
            overrides: invalid.changes,
          );
          await database.customStatement(
            'PRAGMA ignore_check_constraints = OFF',
          );
          final before = await _snapshot(database);

          await expectLater(merge(), throwsA(isA<StateError>()));

          expect(await _snapshot(database), before);
        },
      );
    }
  }

  test(
    'a canonical destination ID occupied by a third owner aborts the whole merge',
    () async {
      await _seedMergeGraph(database);
      await _insertAssignment(database);
      await database.customStatement(
        'INSERT INTO local_owners (id, firebase_uid, created_at_utc_ms, is_active) '
        "VALUES ('synthetic-third-owner', NULL, 3, 0)",
      );
      await _insertAssignment(
        database,
        owner: 'synthetic-third-owner',
        overrides: {
          'id': experimentAssignmentId(
            ownerId: _account,
            experimentId: 'synthetic-study',
            experimentVersion: 1,
          ),
        },
      );
      final before = await _snapshot(database);

      await expectLater(merge(), throwsA(isA<StateError>()));

      expect(await _snapshot(database), before);
    },
  );

  test(
    'a later owner-table failure restores rekeyed facts, vocabulary, rewards and outbox',
    () async {
      await _seedMergeGraph(database);
      await _insertAssignment(database);
      await database.customStatement('''
      CREATE TRIGGER synthetic_assignment_late_owner_failure
      BEFORE UPDATE OF owner_id ON events_v2
      WHEN NEW.owner_id = '$_account'
        AND EXISTS (SELECT 1 FROM experiment_assignments
          WHERE owner_id = '$_account'
            AND id = '${experimentAssignmentId(ownerId: _account, experimentId: 'synthetic-study', experimentVersion: 1)}')
      BEGIN
        SELECT RAISE(ABORT, 'synthetic failure after assignment rekey');
      END
    ''');
      final before = await _snapshot(database);

      await expectLater(merge(), throwsA(isA<Object>()));

      expect(await _snapshot(database), before);
    },
  );

  test(
    'same-owner anonymous binding and already-bound replay preserve the original fact ID',
    () async {
      await _insertAssignment(database);
      final before = await _assignments(database);

      final bound = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-new-uid',
      );
      final replay = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-new-uid',
      );

      expect(bound.mode, OwnerUpgradeMode.anonymousBound);
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(bound.targetOwnerId, _guest);
      expect(await _assignments(database), before);
      expect(await _count(database, 'outbox_operations'), 0);
      expect(await _count(database, 'events_v2'), 0);
    },
  );

  test(
    'assignment rehome creates no research event or outbox operation',
    () async {
      await _insertAssignment(database);

      await merge();

      expect((await _assignments(database)).single['owner_id'], _account);
      expect(await _count(database, 'outbox_operations'), 0);
      expect(await _count(database, 'events_v2'), 0);
    },
  );
}

Future<void> _insertAssignment(
  AppDatabase database, {
  String owner = _guest,
  String experiment = 'synthetic-study',
  int version = 1,
  int assigned = 100,
  Map<String, Object?> overrides = const {},
}) async {
  final persistedExperiment =
      overrides['experiment_id'] as String? ?? experiment;
  final persistedVersion = overrides['experiment_version'] as int? ?? version;
  final values = <String, Object?>{
    'id': experimentAssignmentId(
      ownerId: owner,
      experimentId: persistedExperiment,
      experimentVersion: persistedVersion,
    ),
    'owner_id': owner,
    'experiment_id': persistedExperiment,
    'experiment_version': persistedVersion,
    'cohort': 'control',
    'protocol_version': 'protocol-v1',
    'assigned_at_utc_ms': assigned,
    ...overrides,
  };
  await database.customStatement(
    'INSERT INTO experiment_assignments (${values.keys.join(', ')}) VALUES (?, ?, ?, ?, ?, ?, ?)',
    values.values.toList(),
  );
}

Future<List<Map<String, Object?>>> _assignments(AppDatabase database) async =>
    (await database
            .customSelect('SELECT * FROM experiment_assignments ORDER BY id')
            .get())
        .map((row) => Map<String, Object?>.of(row.data))
        .toList();

Future<Map<String, List<String>>> _snapshot(AppDatabase database) async {
  final snapshot = <String, List<String>>{};
  for (final table in {
    'local_owners',
    'runtime_flags',
    ...ownerUpgradeInventory,
    'experiment_assignments',
  }) {
    final rows = await database.customSelect('SELECT * FROM $table').get();
    snapshot[table] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return snapshot;
}

Future<int> _count(AppDatabase database, String table, {String? owner}) async =>
    (await database
            .customSelect(
              'SELECT COUNT(*) AS count FROM $table${owner == null ? '' : ' WHERE owner_id = ?'}',
              variables: owner == null ? [] : [drift.Variable<String>(owner)],
            )
            .getSingle())
        .read<int>('count');

Future<void> _seedMergeGraph(AppDatabase database) async {
  for (final owner in [_guest, _account]) {
    final suffix = owner == _guest ? 'guest' : 'account';
    await database.customStatement(
      'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES (?, ?, 'Synthetic travel', 'synthetic travel', 10, 10)",
      ['category-$suffix', owner],
    );
    await database.customStatement(
      'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, '
      'part_of_speech, source, is_global, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES (?, ?, ?, 'station', 'station', 'synthetic meaning', 'synthetic meaning', 'noun', 'manual', 0, 10, 10)",
      ['word-$suffix', owner, 'category-$suffix'],
    );
    await database.customStatement(
      'INSERT INTO reward_transactions (id, owner_id, idempotency_key, transaction_type, amount, item_id, catalog_version, occurred_at_utc_ms) '
      "VALUES (?, ?, 'synthetic-shared-purchase', 'purchase', -10, 'theme_ocean', 1, 20)",
      ['reward-$suffix', owner],
    );
  }
  await database.customStatement(
    'INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) '
    "VALUES ('synthetic-guest-word-operation', ?, 'word', 'word-guest', 'upsert', 20)",
    [_guest],
  );
  await database.customStatement(
    'INSERT INTO events_v2 (event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, actor_identity, owner_id, '
    'aggregate_type, aggregate_id, idempotency_key, consent_context_json, app_version, build_id, privacy_classification, payload_json) '
    "VALUES ('synthetic-assignment-event', 'SyntheticFixture', 1, '2026-10-29T00:00:00.000Z', '2026-10-29T00:00:01.000Z', ?, ?, "
    "'LearningSession', 'synthetic-session', 'synthetic-event-key', '{}', '1.0.0', 'synthetic', 'anonymized', ?)",
    [
      _guest,
      _guest,
      jsonEncode({
        'assignmentPin': experimentAssignmentId(
          ownerId: _guest,
          experimentId: 'synthetic-study',
          experimentVersion: 1,
        ),
      }),
    ],
  );
}
