import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/measurement_opportunity_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

const _guest = 'synthetic-measurement-guest';
const _account = 'synthetic-measurement-account';
const _uid = 'synthetic-measurement-firebase';
final _now = DateTime.utc(2026, 10, 29, 12);

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement(
      'INSERT INTO local_owners '
      '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
      "VALUES (?, NULL, 'localGuest', 1, 1), (?, ?, 'firebaseBound', 2, 0)",
      [_guest, _account, _uid],
    );
    var conflict = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => _now,
      generateConflictId: () => 'measurement-conflict-${conflict++}',
      generateOwnerId: () => 'synthetic-measurement-new-guest',
    );
  });
  tearDown(() => database.close());

  Future<OwnerUpgradeResult> merge() =>
      repository.upgrade(activeOwnerId: _guest, firebaseUid: _uid);

  for (final state in ['started', 'skipped', 'abandoned', 'withdrawn']) {
    test(
      'source $state measurement denies merge before business writes',
      () async {
        await _seedMergeGraph(database);
        final seeded = await _seedMeasurement(database, _guest, state: state);
        await _installMutationProbe(database);
        final before = await _snapshot(database);
        expect(seeded.run, hasLength(30));
        expect(seeded.response, hasLength(9));

        await expectLater(merge(), throwsA(isA<StateError>()));

        expect(await _snapshot(database), before);
      },
    );
  }

  for (final table in ['motivation_measurement_runs', 'motivation_responses']) {
    test(
      'source legacy $table alone denies merge before business writes',
      () async {
        await _seedMergeGraph(database);
        await _seedMeasurement(database, _account);
        // Simulate an inconsistent legacy owner pin without inventing a grant.
        await database.customStatement(
          'UPDATE $table SET owner_id = ? WHERE owner_id = ?',
          [_guest, _account],
        );
        expect(
          await _ownerCount(database, 'research_participation_permits', _guest),
          0,
        );
        await _installMutationProbe(database);
        final before = await _snapshot(database);

        await expectLater(merge(), throwsA(isA<StateError>()));

        expect(await _snapshot(database), before);
      },
    );
  }

  test(
    'target measurement facts survive ordinary guest merge and replay',
    () async {
      await _seedMergeGraph(database);
      final seeded = await _seedMeasurement(database, _account);
      final before = await _researchRows(database);
      final eventIds = await _eventIds(database);

      final result = await merge();
      final replay = await repository.upgrade(
        activeOwnerId: _account,
        firebaseUid: _uid,
      );

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(await _researchRows(database), before);
      expect(await _eventIds(database), eventIds);
      expect(await _ownerCount(database, 'vocabulary_words', _guest), 0);
      expect(await _ownerCount(database, 'vocabulary_words', _account), 1);
      final forbiddenIds = {
        seeded.runId,
        seeded.responseId,
        seeded.run['permit_id'],
        seeded.run['assignment_id'],
      };
      final queue = await database.select(database.outboxOperations).get();
      expect(
        queue.where((row) => forbiddenIds.contains(row.entityId)),
        isEmpty,
      );
    },
  );

  test(
    'same-owner anonymous bind and replay preserve every measurement field',
    () async {
      await _seedMeasurement(database, _guest);
      final before = await _researchRows(database);

      final bound = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-measurement-same-owner-uid',
      );
      final replay = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-measurement-same-owner-uid',
      );

      expect(bound.mode, OwnerUpgradeMode.anonymousBound);
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(bound.targetOwnerId, _guest);
      expect(await _researchRows(database), before);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      expect(await _eventIds(database), isEmpty);
    },
  );

  test('logout preserves the original owner measurement cycle', () async {
    await _seedMeasurement(database, _guest);
    final before = await _researchRows(database);

    final result = await repository.createLocalGuestAfterLogout();

    expect(result.mode, OwnerUpgradeMode.localGuestCreated);
    expect(await _researchRows(database), before);
    expect(
      await _ownerCount(
        database,
        'motivation_measurement_runs',
        result.targetOwnerId,
      ),
      0,
    );
    expect(
      await _ownerCount(database, 'motivation_responses', result.targetOwnerId),
      0,
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
    expect(await _eventIds(database), isEmpty);
    final owners = await database.select(database.localOwners).get();
    expect(owners.singleWhere((row) => row.id == _guest).isActive, isFalse);
    expect(owners.singleWhere((row) => row.isActive).id, result.targetOwnerId);
  });

  test('logout rollback cannot erase a new guest measurement cycle', () async {
    final guest = await repository.createLocalGuestAfterLogout();
    await _seedMeasurement(database, guest.targetOwnerId);
    final before = await _snapshot(database);

    await expectLater(
      repository.rollbackLocalGuestLogout(
        previousOwnerId: _guest,
        guestOwnerId: guest.targetOwnerId,
      ),
      throwsException,
    );

    expect(await _snapshot(database), before);
    final owners = await database.select(database.localOwners).get();
    expect(owners.singleWhere((row) => row.isActive).id, guest.targetOwnerId);
  });

  test('persistent deletion fence precedes measurement preflight', () async {
    await _seedMergeGraph(database);
    await _seedMeasurement(database, _guest);
    await database.customStatement(
      "UPDATE local_owners SET firebase_uid = ?, account_state = 'firebaseBound' WHERE id = ?",
      ['synthetic-measurement-deleting-uid', _guest],
    );
    final coordinator = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => _now,
    );
    await coordinator.beginDeletion(
      ownerId: _guest,
      firebaseUid: 'synthetic-measurement-deleting-uid',
      idempotencyKey: 'delete:synthetic-measurement-lifecycle',
    );
    final before = await _snapshot(database);

    await expectLater(
      merge(),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.unavailable,
        ),
      ),
    );

    expect(await _snapshot(database), before);
  });
}

Future<SeededMotivationMeasurement> _seedMeasurement(
  AppDatabase database,
  String owner, {
  String state = 'started',
}) async {
  final assignment = await seedOwnerAssignment(database, owner);
  final permit = await insertOwnerParticipation(
    database,
    owner,
    assignmentId: assignment,
  );
  await database.customStatement(
    'INSERT INTO research_consents '
    '(id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
    "VALUES (?, ?, 1, 'accepted', 1)",
    ['synthetic-consent:$owner', owner],
  );
  final measurement = await insertOwnerMotivationMeasurement(
    database,
    permit,
    state: state,
  );
  await insertOwnerMeasurementOpportunity(
    database,
    permit: permit,
    measurement: measurement,
    presented: false,
  );
  return measurement;
}

Future<void> _installMutationProbe(AppDatabase database) =>
    database.customStatement('''
  CREATE TRIGGER synthetic_measurement_owner_mutation_probe
  BEFORE DELETE ON vocabulary_categories
  BEGIN
    SELECT RAISE(ABORT, 'measurement preflight happened after business mutation');
  END
''');

Future<Map<String, List<Map<String, Object?>>>> _researchRows(
  AppDatabase database,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in [
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
  ]) {
    result[table] =
        (await database.customSelect('SELECT * FROM $table ORDER BY id').get())
            .map((row) => Map<String, Object?>.of(row.data))
            .toList();
  }
  return result;
}

Future<List<String>> _eventIds(AppDatabase database) async =>
    (await database
            .customSelect('SELECT event_id FROM events_v2 ORDER BY event_id')
            .get())
        .map((row) => row.read<String>('event_id'))
        .toList();

Future<int> _ownerCount(
  AppDatabase database,
  String table,
  String owner,
) async =>
    (await database
            .customSelect(
              'SELECT COUNT(*) AS count FROM $table WHERE owner_id = ?',
              variables: [drift.Variable<String>(owner)],
            )
            .getSingle())
        .read<int>('count');

Future<Map<String, List<String>>> _snapshot(AppDatabase database) async {
  final result = <String, List<String>>{};
  for (final table in {
    'local_owners',
    'runtime_flags',
    ...ownerUpgradeInventory,
    'vocabulary_import_rows',
    'quest_objective_progress',
  }) {
    final rows = await database.customSelect('SELECT * FROM $table').get();
    result[table] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return result;
}

Future<void> _seedMergeGraph(AppDatabase database) async {
  for (final owner in [_guest, _account]) {
    final suffix = owner == _guest ? 'guest' : 'account';
    await database.customStatement(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES (?, ?, 'Synthetic travel', 'synthetic travel', 10, 10)",
      ['measurement-category-$suffix', owner],
    );
    await database.customStatement(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, '
      'part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES (?, ?, ?, 'station', 'station', 'synthetic meaning', 'synthetic meaning', 'noun', 10, 10)",
      ['measurement-word-$suffix', owner, 'measurement-category-$suffix'],
    );
    await database.customStatement(
      'INSERT INTO reward_transactions '
      '(id, owner_id, idempotency_key, transaction_type, amount, item_id, catalog_version, occurred_at_utc_ms) '
      "VALUES (?, ?, 'synthetic-measurement-purchase', 'purchase', -10, 'theme_ocean', 1, 20)",
      ['measurement-reward-$suffix', owner],
    );
  }
  await database.customStatement(
    'INSERT INTO outbox_operations '
    '(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) '
    "VALUES ('synthetic-measurement-word-operation', ?, 'word', 'measurement-word-guest', 'upsert', 20)",
    [_guest],
  );
  await database.customStatement(
    'INSERT INTO events_v2 '
    '(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, actor_identity, owner_id, '
    'aggregate_type, aggregate_id, idempotency_key, consent_context_json, app_version, build_id, privacy_classification, payload_json) '
    "VALUES ('synthetic-measurement-existing-event', 'SyntheticFixture', 1, 1, 1, ?, ?, "
    "'LearningSession', 'synthetic-session', 'synthetic-measurement-event-key', '{}', '1.0.0', 'synthetic', 'ownerOnly', '{}')",
    [_guest, _guest],
  );
}
