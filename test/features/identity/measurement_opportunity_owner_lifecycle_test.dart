import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/measurement_opportunity_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

const _guest = 'synthetic-opportunity-guest';
const _account = 'synthetic-opportunity-account';
const _uid = 'synthetic-opportunity-firebase';
const _secondEntry = '00000000-0000-4000-8000-000000000002';
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
      generateConflictId: () => 'opportunity-conflict-${conflict++}',
      generateOwnerId: () => 'synthetic-opportunity-new-guest',
    );
  });
  tearDown(() => database.close());

  Future<OwnerUpgradeResult> merge() =>
      repository.upgrade(activeOwnerId: _guest, firebaseUid: _uid);

  test(
    'base fixtures preserve all opportunity and Presented fields without learning side effects',
    () async {
      final guest = await _seedBundle(database, _guest);
      final target = await _seedBundle(database, _account);

      for (final bundle in [guest, target]) {
        final opportunity =
            (await database
                    .customSelect(
                      'SELECT * FROM measurement_opportunities WHERE id = ?',
                      variables: [
                        drift.Variable<String>(bundle.opportunity.id),
                      ],
                    )
                    .getSingle())
                .data;
        final event =
            (await database
                    .customSelect(
                      'SELECT * FROM events_v2 WHERE event_id = ?',
                      variables: [
                        drift.Variable<String>(bundle.opportunity.eventId!),
                      ],
                    )
                    .getSingle())
                .data;
        expect(opportunity, hasLength(19));
        expect(event, hasLength(22));
        expect(opportunity, bundle.opportunity.opportunity);
        expect(event, bundle.opportunity.event);
        expect(jsonDecode(event['payload_json']! as String), hasLength(4));
        expect(opportunity['learning_session_id'], isNull);
        expect(opportunity['is_index_session'], 0);
        final at = opportunity['presented_at_utc_ms']! as int;
        expect(
          researchEventOccurrence(
            event['event_id']! as String,
            DateTime.fromMillisecondsSinceEpoch(
              (event['occurred_at_utc']! as int) * 1000,
              isUtc: true,
            ),
          ).millisecondsSinceEpoch,
          at,
        );
      }
      expect(await database.select(database.learningSessions).get(), isEmpty);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'source legacy opportunity alone denies merge before business writes',
    () async {
      await _seedMergeGraph(database);
      final target = await _seedBundle(database, _account);
      await database.customStatement(
        'UPDATE measurement_opportunities SET owner_id = ? WHERE id = ?',
        [_guest, target.opportunity.id],
      );
      for (final table in [
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
      ]) {
        expect(await _ownerCount(database, table, _guest), 0);
      }
      await _installMutationProbe(database);
      final before = await _snapshot(database);

      await expectLater(merge(), throwsA(isA<StateError>()));

      expect(await _snapshot(database), before);
    },
  );

  for (final type in [
    'TodayExperiencePresented',
    'TodayExperiencePresentationChanged',
    'TodayExperienceMissionStarted',
    'TodayExperienceMissionCompleted',
  ]) {
    test(
      'orphan $type legacy event denies merge before business writes',
      () async {
        await _seedMergeGraph(database);
        final source = await _seedBundle(database, _guest);
        await database.customStatement(
          'DELETE FROM measurement_opportunities WHERE owner_id = ?',
          [_guest],
        );
        await database.customStatement(
          'DELETE FROM motivation_measurement_runs WHERE owner_id = ?',
          [_guest],
        );
        await database.customStatement(
          'DELETE FROM research_participation_permits WHERE owner_id = ?',
          [_guest],
        );
        await database.customStatement(
          'DELETE FROM experiment_assignments WHERE owner_id = ?',
          [_guest],
        );
        // Other legacy event kinds deliberately retain a malformed stored payload.
        await database.customStatement(
          'UPDATE events_v2 SET event_type = ? WHERE event_id = ?',
          [type, source.opportunity.eventId],
        );
        for (final table in [
          'measurement_opportunities',
          'research_participation_permits',
          'motivation_measurement_runs',
          'motivation_responses',
        ]) {
          expect(await _ownerCount(database, table, _guest), 0);
        }
        await _installMutationProbe(database);
        final before = await _snapshot(database);

        await expectLater(merge(), throwsA(isA<StateError>()));

        expect(await _snapshot(database), before);
      },
    );
  }

  test(
    'target opportunity and event survive ordinary guest merge and replay',
    () async {
      await _seedMergeGraph(database);
      final target = await _seedBundle(database, _account);
      final before = await _researchRows(database);

      final result = await merge();
      final replay = await repository.upgrade(
        activeOwnerId: _account,
        firebaseUid: _uid,
      );

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(await _researchRows(database), before);
      expect(await _ownerCount(database, 'vocabulary_words', _guest), 0);
      expect(await _ownerCount(database, 'vocabulary_words', _account), 1);
      final forbidden = {
        target.opportunity.id,
        target.opportunity.eventId,
        target.measurement.runId,
        target.measurement.responseId,
        target.permit.id,
      };
      expect(
        (await database.select(database.outboxOperations).get()).where(
          (row) => forbidden.contains(row.entityId),
        ),
        isEmpty,
      );
    },
  );

  test(
    'same-owner bind and replay preserve opportunity and full event bytes',
    () async {
      await _seedBundle(database, _guest);
      final before = await _researchRows(database);

      final bound = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-opportunity-same-owner',
      );
      final replay = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-opportunity-same-owner',
      );

      expect(bound.mode, OwnerUpgradeMode.anonymousBound);
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(await _researchRows(database), before);
      expect(await database.select(database.eventsV2).get(), hasLength(1));
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'logout preserves the original opportunity without copying it to the guest',
    () async {
      await _seedBundle(database, _guest);
      final before = await _researchRows(database);

      final logout = await repository.createLocalGuestAfterLogout();

      expect(await _researchRows(database), before);
      expect(
        await _ownerCount(
          database,
          'measurement_opportunities',
          logout.targetOwnerId,
        ),
        0,
      );
      expect(await _ownerCount(database, 'events_v2', logout.targetOwnerId), 0);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('logout rollback cannot erase a new guest opportunity', () async {
    final logout = await repository.createLocalGuestAfterLogout();
    await _seedBundle(database, logout.targetOwnerId);
    final before = await _snapshot(database);

    await expectLater(
      repository.rollbackLocalGuestLogout(
        previousOwnerId: _guest,
        guestOwnerId: logout.targetOwnerId,
      ),
      throwsException,
    );

    expect(await _snapshot(database), before);
  });

  test('persistent deletion fence precedes opportunity preflight', () async {
    await _seedMergeGraph(database);
    await _seedBundle(database, _guest);
    await database.customStatement(
      "UPDATE local_owners SET firebase_uid = ?, account_state = 'firebaseBound' WHERE id = ?",
      ['synthetic-opportunity-deleting-uid', _guest],
    );
    final coordinator = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => _now,
    );
    await coordinator.beginDeletion(
      ownerId: _guest,
      firebaseUid: 'synthetic-opportunity-deleting-uid',
      idempotencyKey: 'delete:synthetic-opportunity-lifecycle',
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

  for (final reference in ['owner', 'run', 'permit', 'event', 'session']) {
    test(
      'opportunity rejects a missing $reference FK without partial mutation',
      () async {
        final source = await _seedBundle(database, _guest);
        final fields = Map<String, Object?>.of(source.opportunity.opportunity)
          ..['id'] = 'synthetic-invalid-$reference-opportunity'
          ..['entry_attempt_id'] = _secondEntry;
        switch (reference) {
          case 'owner':
            fields['owner_id'] = 'synthetic-missing-owner';
          case 'run':
            fields['measurement_run_id'] = 'synthetic-missing-run';
          case 'permit':
            fields['permit_id'] = 'synthetic-missing-permit';
          case 'event':
            fields['presented_event_id'] = 'synthetic-missing-event';
          case 'session':
            fields['learning_session_id'] = 'synthetic-missing-session';
            fields['learning_session_started_at_utc_ms'] =
                (fields['presented_at_utc_ms']! as int) + 1;
            fields['is_index_session'] = 1;
        }
        final before = await _snapshot(database);

        await expectLater(
          _insertOpportunity(database, fields),
          throwsException,
        );

        expect(await _snapshot(database), before);
      },
    );
  }

  test(
    'run cascade removes its opportunity and responses while preserving learning and other owners',
    () async {
      final source = await _seedBundle(database, _guest, indexed: true);
      final target = await _seedBundle(database, _account);
      final targetBefore = target.opportunity.opportunity;

      await database.customStatement(
        'DELETE FROM motivation_measurement_runs WHERE id = ?',
        [source.measurement.runId],
      );

      expect(
        await _ownerCount(database, 'measurement_opportunities', _guest),
        0,
      );
      expect(await _ownerCount(database, 'motivation_responses', _guest), 0);
      expect(await _ownerCount(database, 'learning_sessions', _guest), 1);
      expect(await _ownerCount(database, 'events_v2', _guest), 1);
      expect(
        (await database
                .customSelect(
                  'SELECT * FROM measurement_opportunities WHERE id = ?',
                  variables: [drift.Variable<String>(target.opportunity.id)],
                )
                .getSingle())
            .data,
        targetBefore,
      );
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'an index FK prevents deleting the canonical session behind its link',
    () async {
      final source = await _seedBundle(database, _guest, indexed: true);
      final before = await _snapshot(database);

      await expectLater(
        database.customStatement('DELETE FROM learning_sessions WHERE id = ?', [
          source.sessionId,
        ]),
        throwsException,
      );

      expect(await _snapshot(database), before);
    },
  );

  test(
    'a second attachment cannot reuse an accepted session and leaves no extra event',
    () async {
      final source = await _seedBundle(database, _guest, indexed: true);
      final before = await _snapshot(database);

      await expectLater(
        insertOwnerMeasurementOpportunity(
          database,
          permit: source.permit,
          measurement: source.measurement,
          entryAttemptId: _secondEntry,
          learningSessionId: source.sessionId,
        ),
        throwsException,
      );

      expect(await _snapshot(database), before);
    },
  );

  test(
    'the partial index prevents replacing the first index with another session',
    () async {
      final source = await _seedBundle(database, _guest, indexed: true);
      final second = await _startCanonical(
        database,
        _guest,
        'synthetic-second-index',
        (source.measurement.run['started_at_utc_ms']! as int) + 5,
      );
      final before = await _snapshot(database);

      await expectLater(
        insertOwnerMeasurementOpportunity(
          database,
          permit: source.permit,
          measurement: source.measurement,
          entryAttemptId: _secondEntry,
          learningSessionId: second,
        ),
        throwsException,
      );

      expect(await _snapshot(database), before);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(2),
      );
    },
  );

  test(
    'indexed cloud purge deletes dependency rows first and keeps the other owner intact',
    () async {
      final source = await _seedBundle(
        database,
        _guest,
        indexed: true,
        completed: true,
      );
      final target = await _seedBundle(
        database,
        _account,
        indexed: true,
        completed: true,
      );
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = ?, account_state = 'firebaseBound' WHERE id = ?",
        ['synthetic-opportunity-delete-uid', _guest],
      );
      final targetBefore = await _ownerSnapshot(database, _account);
      final secrets = <String>[];
      final gateway = DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => _now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          secrets.add(ownerId);
        },
      );

      final receipt = await gateway.deleteAfterCloud(
        ownerId: _guest,
        cloudReceipt: CloudDeletionReceipt(
          receiptId: 'synthetic-opportunity-cloud-receipt',
          ownerId: _guest,
          firebaseUid: 'synthetic-opportunity-delete-uid',
          idempotencyKey: 'delete:synthetic-opportunity-purge',
          completedAtUtc: _now,
        ),
      );

      expect(receipt.deletedOwnerId, _guest);
      expect(secrets, [_guest]);
      for (final table in ownerUpgradeInventory) {
        expect(await _ownerCount(database, table, _guest), 0, reason: table);
      }
      expect(await _ownerSnapshot(database, _account), targetBefore);
      expect(
        await _ownerCount(database, 'measurement_opportunities', _account),
        1,
      );
      expect(
        (await database.select(database.outboxOperations).get())
            .single
            .entityType,
        'achievementUnlock',
      );
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
      expect(source.sessionId, isNot(target.sessionId));
    },
  );
}

final class _Bundle {
  const _Bundle(
    this.permit,
    this.measurement,
    this.opportunity,
    this.sessionId,
  );
  final ResearchParticipationPermit permit;
  final SeededMotivationMeasurement measurement;
  final SeededMeasurementOpportunity opportunity;
  final String? sessionId;
}

Future<_Bundle> _seedBundle(
  AppDatabase database,
  String owner, {
  bool indexed = false,
  bool completed = false,
}) async {
  final assignment = await seedOwnerAssignment(database, owner);
  final permit = await insertOwnerParticipation(
    database,
    owner,
    assignmentId: assignment,
  );
  await database.customStatement(
    'INSERT INTO research_consents (id, owner_id, consent_version, consent_state, decided_at_utc_ms) VALUES (?, ?, 1, \'accepted\', 1)',
    ['synthetic-opportunity-consent:$owner', owner],
  );
  final measurement = await insertOwnerMotivationMeasurement(database, permit);
  String? sessionId;
  if (indexed) {
    final start = (measurement.run['started_at_utc_ms']! as int) + 4;
    sessionId = await _startCanonical(
      database,
      owner,
      'synthetic-index:$owner',
      start,
    );
    if (completed) {
      await DriftLearningRepository(database).finishSession(
        ownerId: owner,
        sessionId: sessionId,
        endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          start + 10,
          isUtc: true,
        ),
      );
    }
  }
  final opportunity = await insertOwnerMeasurementOpportunity(
    database,
    permit: permit,
    measurement: measurement,
    learningSessionId: sessionId,
  );
  return _Bundle(permit, measurement, opportunity, sessionId);
}

Future<String> _startCanonical(
  AppDatabase database,
  String owner,
  String id,
  int start,
) async {
  await DriftLearningRepository(database).startSession(
    LearningSessionDraft(
      id: id,
      ownerId: owner,
      activityType: 'quiz',
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      appVersion: 'synthetic-lifecycle-v1',
      buildId: 'synthetic-lifecycle-build',
    ),
  );
  return id;
}

Future<void> _insertOpportunity(
  AppDatabase database,
  Map<String, Object?> fields,
) => database.customStatement(
  'INSERT INTO measurement_opportunities (${fields.keys.join(', ')}) VALUES (${List.filled(fields.length, '?').join(', ')})',
  fields.values.toList(),
);

Future<void> _installMutationProbe(AppDatabase database) =>
    database.customStatement('''
  CREATE TRIGGER synthetic_opportunity_owner_mutation_probe
  BEFORE DELETE ON vocabulary_categories
  BEGIN
    SELECT RAISE(ABORT, 'opportunity preflight happened after business mutation');
  END
''');

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
    result[table] =
        (await database.customSelect('SELECT * FROM $table').get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort();
  }
  return result;
}

Future<Map<String, List<String>>> _researchRows(AppDatabase database) async {
  final result = <String, List<String>>{};
  for (final table in [
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
    'events_v2',
  ]) {
    final query = table == 'events_v2'
        ? "SELECT * FROM events_v2 WHERE event_type = 'TodayExperiencePresented'"
        : 'SELECT * FROM $table';
    result[table] =
        (await database.customSelect(query).get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort();
  }
  return result;
}

Future<Map<String, List<String>>> _ownerSnapshot(
  AppDatabase database,
  String owner,
) async {
  final result = <String, List<String>>{};
  for (final table in ownerUpgradeInventory) {
    result[table] =
        (await database
                .customSelect(
                  'SELECT * FROM $table WHERE owner_id = ?',
                  variables: [drift.Variable<String>(owner)],
                )
                .get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort();
  }
  return result;
}

Future<void> _seedMergeGraph(AppDatabase database) async {
  for (final owner in [_guest, _account]) {
    final suffix = owner == _guest ? 'guest' : 'account';
    await database.customStatement(
      'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, \'Synthetic travel\', \'synthetic travel\', 10, 10)',
      ['opportunity-category-$suffix', owner],
    );
    await database.customStatement(
      'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, \'station\', \'station\', \'synthetic meaning\', \'synthetic meaning\', \'noun\', 10, 10)',
      ['opportunity-word-$suffix', owner, 'opportunity-category-$suffix'],
    );
    await database.customStatement(
      'INSERT INTO reward_transactions (id, owner_id, idempotency_key, transaction_type, amount, item_id, catalog_version, occurred_at_utc_ms) VALUES (?, ?, \'synthetic-opportunity-purchase\', \'purchase\', -10, \'theme_ocean\', 1, 20)',
      ['opportunity-reward-$suffix', owner],
    );
  }
  await database.customStatement(
    'INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) VALUES (\'synthetic-opportunity-word-operation\', ?, \'word\', \'opportunity-word-guest\', \'upsert\', 20)',
    [_guest],
  );
}
