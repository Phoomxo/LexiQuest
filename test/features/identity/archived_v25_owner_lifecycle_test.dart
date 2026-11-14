import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

const _guest = 'local:legacy-guest';
const _target = 'local:existing-account';
const _targetUid = 'synthetic-target-uid';
final _now = DateTime.utc(2026, 11, 14);

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    var id = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => _now,
      generateConflictId: () => 'synthetic-${++id}',
      generateOwnerId: () => 'synthetic-new-guest',
    );
    await database.customStatement('''
      INSERT INTO local_owners (id, firebase_uid, account_state, created_at_utc_ms, is_active)
      VALUES ('$_guest', NULL, 'localGuest', 1, 1),
             ('$_target', '$_targetUid', 'firebaseBound', 2, 0)
      ''');
  });

  tearDown(() => database.close());

  test(
    'owner merge keeps ordinary archive identity and exports to the current owner',
    () async {
      const history = 'legacy-v25:learning_profiles:old-goal';
      const current = 'legacy-v25:study_reminder_preferences:target-reminder';
      await _archive(
        database,
        history,
        _guest,
        'learning_profiles',
        'old-goal',
        {'owner_id': _guest, 'goal_text': 'Read the synthetic book'},
      );
      await _archive(
        database,
        current,
        _target,
        'study_reminder_preferences',
        'target-reminder',
        {'owner_id': _target, 'minute_of_day': 480},
      );

      final result = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: _targetUid,
      );
      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(result.targetOwnerId, _target);
      final rows = await _exportArchive(database, _target);
      expect(rows.map((row) => row['id']), unorderedEquals([history, current]));
      final moved = rows.singleWhere((row) => row['id'] == history);
      expect(moved['owner_id'], _target);
      expect(moved['origin_owner_id'], _guest);
      expect(moved['source_row_key'], 'old-goal');
      expect(jsonDecode(moved['payload_json']! as String), {
        'owner_id': _guest,
        'goal_text': 'Read the synthetic book',
      });
      expect(await _exportArchive(database, _guest), isEmpty);
    },
  );

  test(
    'signed historical research blocks transfer to an existing owner',
    () async {
      const permit = 'legacy-v25:research_participation_permits:permit-a';
      await _archive(
        database,
        permit,
        _guest,
        'research_participation_permits',
        'permit-a',
        {'owner_id': _guest, 'fixture': 'synthetic prior permit'},
      );

      await expectLater(
        repository.upgrade(activeOwnerId: _guest, firebaseUid: _targetUid),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'reason',
            contains('signed research owner'),
          ),
        ),
      );
      expect((await _exportArchive(database, _guest)).single['id'], permit);
      expect(await _exportArchive(database, _target), isEmpty);
      expect(
        (await database
                .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
                .getSingle())
            .read<String>('id'),
        _guest,
      );
    },
  );

  for (final (name, uid, owner, mode) in [
    ('bind', 'synthetic-new-uid', _guest, OwnerUpgradeMode.anonymousBound),
    ('merge', _targetUid, _target, OwnerUpgradeMode.mergedExisting),
  ]) {
    test(
      '$name does not revive old answer delivery or create a replacement',
      () async {
        await _seedHistoricalOperations(database);

        final result = await repository.upgrade(
          activeOwnerId: _guest,
          firebaseUid: uid,
        );
        expect((result.targetOwnerId, result.mode), (owner, mode));
        final operations = await database.customSelect('''
        SELECT operation_id, owner_id, entity_id, payload_version, state,
          acknowledged_at_utc_ms FROM outbox_operations
        WHERE entity_type = 'attempt' ORDER BY operation_id
        ''').get();
        expect(operations.map((row) => row.data.values.toList()), [
          [
            'op-a-pending-v2',
            owner,
            'base-attempt-a',
            2,
            'historicalV25',
            null,
          ],
          ['op-b-ack-v2', owner, 'base-attempt-b', 2, 'acknowledged', 5],
          [
            'op-c-history-v1',
            owner,
            'history-attempt',
            1,
            'historicalV25',
            null,
          ],
        ]);
      },
    );
  }
}

Future<void> _archive(
  AppDatabase database,
  String id,
  String owner,
  String table,
  String key,
  Map<String, Object?> payload,
) => database.customStatement(
  'INSERT INTO archived_v25_records '
  '(id, owner_id, origin_owner_id, source_table, source_row_key, payload_json) '
  'VALUES (?, ?, ?, ?, ?, ?)',
  [id, owner, owner, table, key, jsonEncode(payload)],
);

Future<List<Map<String, Object?>>> _exportArchive(
  AppDatabase database,
  String owner,
) async {
  final snapshot = await DriftAccountSnapshotBuilder(
    database,
    nowUtc: () => _now,
  ).build(ownerId: owner);
  expect(snapshot.coveredScopes, contains('archived_v25_records'));
  final payload =
      jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
  return (payload['data']['archived_v25_records'] as List)
      .cast<Map<String, Object?>>();
}

Future<void> _seedHistoricalOperations(AppDatabase database) async {
  await database.customStatement('''
    INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name,
      created_at_utc_ms, updated_at_utc_ms)
    VALUES ('legacy-cat', '$_guest', 'Travel', 'travel', 1, 1)
    ''');
  await database.customStatement('''
    INSERT INTO vocabulary_words (id, owner_id, category_id, spelling,
      normalized_spelling, meaning, normalized_meaning, part_of_speech,
      created_at_utc_ms, updated_at_utc_ms)
    VALUES ('legacy-word', '$_guest', 'legacy-cat', 'station', 'station',
      'สถานี', 'สถานี', 'noun', 1, 1)
    ''');
  await database.customStatement('''
    INSERT INTO learning_sessions (id, owner_id, activity_type, state,
      started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count,
      score, app_version, build_id, legacy_evidence_disposition)
    VALUES
      ('base-session', '$_guest', 'quiz', 'completed', 1, 5, 1, 1, 50,
        '1.0.0', 'synthetic-v25', 'base-v25'),
      ('history-session', '$_guest', 'dictation', 'completed', 1, 5, 2, 0, 100,
        '1.0.0', 'synthetic-v25', 'history-v25')
    ''');
  await database.customStatement('''
    INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode,
      is_correct, attempt_number, occurred_at_utc_ms, legacy_evidence_disposition)
    VALUES
      ('base-attempt-a', '$_guest', 'base-session', 'legacy-word', 'meaningChoice', 0, 1, 2, 'base-v25'),
      ('base-attempt-b', '$_guest', 'base-session', 'legacy-word', 'meaningChoice', 1, 2, 3, 'base-v25'),
      ('history-attempt', '$_guest', 'history-session', 'legacy-word', 'dictation', 1, 1, 2, 'history-v25'),
      ('history-no-operation', '$_guest', 'history-session', 'legacy-word', 'dictation', 1, 2, 3, 'history-v25')
    ''');
  for (final (id, attempt, version, oldState, state, acknowledged) in [
    ('op-a-pending-v2', 'base-attempt-a', 2, 'pending', 'historicalV25', null),
    ('op-b-ack-v2', 'base-attempt-b', 2, 'acknowledged', 'acknowledged', 5),
    ('op-c-history-v1', 'history-attempt', 1, 'pending', 'historicalV25', null),
  ]) {
    await database.customStatement(
      'INSERT INTO outbox_operations (operation_id, owner_id, entity_type, '
      'entity_id, operation_kind, payload_version, state, created_at_utc_ms, '
      'acknowledged_at_utc_ms) VALUES (?, ?, \'attempt\', ?, \'upsert\', ?, ?, 2, ?)',
      [id, _guest, attempt, version, state, acknowledged],
    );
    await _archive(
      database,
      'legacy-v25:outbox_operations:$id',
      _guest,
      'outbox_operations',
      id,
      {
        'operation_id': id,
        'owner_id': _guest,
        'entity_id': attempt,
        'payload_version': version,
        'state': oldState,
      },
    );
  }
}
