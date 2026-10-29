import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';

import '../../support/answer_attempt_evidence_fixture.dart';
import '../../support/experiment_assignment_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

const _source = 'owner-a';
const _target = 'owner-b';
const _targetUid = 'synthetic-target-uid';
final _now = DateTime.utc(2026, 10, 30, 12);

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement(
      'INSERT INTO local_owners '
      '(id,firebase_uid,account_state,is_active,created_at_utc_ms) VALUES '
      "(?, NULL, 'localGuest', 1, 1), (?, ?, 'firebaseBound', 0, 2)",
      [_source, _target, _targetUid],
    );
    var sequence = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => _now,
      generateConflictId: () => 'synthetic-assessment-conflict-${sequence++}',
      generateOwnerId: () => 'synthetic-assessment-logout',
    );
  });
  tearDown(() => database.close());

  for (final vector in ['assessment', 'legacy-context', 'ordinary-session']) {
    test(
      'same-ID binding excludes $vector Assessment answers while requeuing ordinary evidence',
      () async {
        await _ordinaryGraph(database, _source);
        await _session(database, 'synthetic-ordinary-session', _source, 'quiz');
        await _attempt(
          database,
          id: 'synthetic-ordinary-answer',
          session: 'synthetic-ordinary-session',
          context: ordinaryAnswerEvidence(),
        );
        await _session(
          database,
          'synthetic-assessment-session',
          _source,
          vector == 'ordinary-session' ? 'quiz' : 'assessment',
        );
        await _attempt(
          database,
          id: 'synthetic-assessment-answer',
          session: 'synthetic-assessment-session',
          context: vector == 'legacy-context'
              ? ordinaryAnswerEvidence()
              : _assessmentEvidence(),
        );
        final before = await _rows(database, 'answer_attempts');
        final sessions = await _rows(database, 'learning_sessions');
        final rewards = await _rows(database, 'reward_transactions');

        final bound = await repository.upgrade(
          activeOwnerId: _source,
          firebaseUid: 'synthetic-new-bind-uid',
        );

        expect(bound.mode, OwnerUpgradeMode.anonymousBound);
        expect(bound.targetOwnerId, _source);
        expect(await _rows(database, 'answer_attempts'), before);
        expect(await _rows(database, 'learning_sessions'), sessions);
        expect(await _rows(database, 'reward_transactions'), rewards);
        final outbox = await _rows(database, 'outbox_operations');
        expect(
          outbox
              .where((row) => row['entity_type'] == 'attempt')
              .map((row) => row['entity_id']),
          ['synthetic-ordinary-answer'],
          reason:
              'Assessment must not enter the ordinary queue, even if upload rejects it later',
        );
        expect(outbox, hasLength(4));
        expect(outbox.map((row) => row['entity_type']).toSet(), {
          'category',
          'word',
          'attempt',
          'rewardTransaction',
        });
        expect(await _rows(database, 'events_v2'), isEmpty);
        expect(await _rows(database, 'srs_states'), isEmpty);
        expect(await _rows(database, 'points_ledger_entries'), isEmpty);
      },
    );
  }

  test(
    'a foreign-owner Assessment container cannot authorize source namespace requeue',
    () async {
      await _ordinaryGraph(database, _source);
      await _session(database, 'synthetic-ordinary-session', _source, 'quiz');
      await _attempt(
        database,
        id: 'synthetic-ordinary-answer',
        session: 'synthetic-ordinary-session',
        context: ordinaryAnswerEvidence(),
      );
      await _session(
        database,
        'synthetic-foreign-assessment-session',
        _target,
        'assessment',
      );
      // Deliberately damaged owner lineage is possible under the single-ID FK.
      // Legacy-looking metadata cannot turn another owner's Assessment into
      // ordinary source-owner upload evidence.
      await _attempt(
        database,
        id: 'synthetic-foreign-assessment-answer',
        session: 'synthetic-foreign-assessment-session',
        context: ordinaryAnswerEvidence(),
      );
      final before = await _rows(database, 'answer_attempts');
      final sessions = await _rows(database, 'learning_sessions');
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );

      await repository.upgrade(
        activeOwnerId: _source,
        firebaseUid: 'synthetic-new-bind-uid',
      );

      expect(await _rows(database, 'answer_attempts'), before);
      expect(await _rows(database, 'learning_sessions'), sessions);
      final outbox = await _rows(database, 'outbox_operations');
      expect(
        outbox
            .where((row) => row['entity_type'] == 'attempt')
            .map((row) => row['entity_id']),
        ['synthetic-ordinary-answer'],
      );
      expect(outbox, hasLength(4));
      expect(outbox.map((row) => row['entity_type']).toSet(), {
        'category',
        'word',
        'attempt',
        'rewardTransaction',
      });
    },
  );

  for (final state in ['active', 'completed', 'abandoned']) {
    test(
      '$state source assessment pins reject changing owner before business writes',
      () async {
        await _ordinaryGraph(database, _source);
        await _ordinaryGraph(database, _target);
        final source = await _assessmentBundle(database, _source, state: state);
        await _mutationProbe(database);
        final before = await _allRows(database);

        await expectLater(
          repository.upgrade(activeOwnerId: _source, firebaseUid: _targetUid),
          _rehomeDenied,
        );

        expect(await _allRows(database), before);
        expect(
          (await _rows(database, 'assessment_runs', owner: _source)).single,
          source,
        );
        expect(await _rows(database, 'outbox_operations'), isEmpty);
      },
    );
  }

  test(
    'a damaged source-owned assessment with target-owned pins never enters generic rehome',
    () async {
      await _ordinaryGraph(database, _source);
      await _ordinaryGraph(database, _target);
      final target = await _assessmentBundle(database, _target);
      await _session(
        database,
        'synthetic-damaged-assessment-session',
        _source,
        'assessment',
      );
      // This deliberately inconsistent storage row tests fail-closed recovery.
      // Target-owned signed parents are not authority to re-enroll its source.
      final damaged = Map<String, Object?>.of(target)
        ..['id'] = 'synthetic-damaged-source-assessment'
        ..['owner_id'] = _source
        ..['learning_session_id'] = 'synthetic-damaged-assessment-session';
      await _insert(database, 'assessment_runs', damaged);
      for (final table in [
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
        'events_v2',
      ]) {
        expect(await _rows(database, table, owner: _source), isEmpty);
      }
      await _mutationProbe(database);
      final before = await _allRows(database);

      await expectLater(
        repository.upgrade(activeOwnerId: _source, firebaseUid: _targetUid),
        _rehomeDenied,
      );

      expect(await _allRows(database), before);
    },
  );

  test(
    'target-only assessment pins survive an ordinary guest merge unchanged',
    () async {
      await _ordinaryGraph(database, _source);
      await _ordinaryGraph(database, _target);
      final target = await _assessmentBundle(database, _target);
      final before = await _researchRows(database, _target);

      final merged = await repository.upgrade(
        activeOwnerId: _source,
        firebaseUid: _targetUid,
      );

      expect(merged.mode, OwnerUpgradeMode.mergedExisting);
      expect(merged.targetOwnerId, _target);
      expect(await _researchRows(database, _target), before);
      expect(
        (await _rows(database, 'assessment_runs', owner: _target)).single,
        target,
      );
      for (final table in ownerUpgradeInventory) {
        expect(
          await _rows(database, table, owner: _source),
          isEmpty,
          reason: table,
        );
      }
      expect(
        (await _rows(
          database,
          'outbox_operations',
        )).every((row) => row['entity_type'] == 'rewardTransaction'),
        isTrue,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'same owner bind and exact replay preserve all37 fields and create no Research operations',
    () async {
      final source = await _assessmentBundle(database, _source);
      final before = await _researchRows(database, _source);

      final bound = await repository.upgrade(
        activeOwnerId: _source,
        firebaseUid: 'synthetic-bound-uid',
      );

      expect(bound.mode, OwnerUpgradeMode.anonymousBound);
      expect(bound.targetOwnerId, _source);
      expect(await _researchRows(database, _source), before);
      expect((await _rows(database, 'assessment_runs')).single, source);
      expect(await _rows(database, 'outbox_operations'), isEmpty);
      final beforeReplay = await _allRows(database);
      final replay = await repository.upgrade(
        activeOwnerId: _source,
        firebaseUid: 'synthetic-bound-uid',
      );
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(await _allRows(database), beforeReplay);
    },
  );

  test(
    'logout preserves old assessment while rollback rejects guest assessment atomically',
    () async {
      final source = await _assessmentBundle(database, _source);
      final before = await _researchRows(database, _source);

      final logout = await repository.createLocalGuestAfterLogout();

      expect(logout.mode, OwnerUpgradeMode.localGuestCreated);
      expect(await _researchRows(database, _source), before);
      expect(
        (await _rows(database, 'assessment_runs', owner: _source)).single,
        source,
      );
      expect(
        await _rows(database, 'assessment_runs', owner: logout.targetOwnerId),
        isEmpty,
      );
      await _assessmentBundle(database, logout.targetOwnerId);
      final beforeRollback = await _allRows(database);
      await expectLater(
        repository.rollbackLocalGuestLogout(
          previousOwnerId: _source,
          guestOwnerId: logout.targetOwnerId,
        ),
        throwsException,
      );
      expect(await _allRows(database), beforeRollback);
      expect(await _rows(database, 'outbox_operations'), isEmpty);
    },
  );

  test(
    'personal export and durable cloud purge cover all37 fields in dependency order and isolate the other owner',
    () async {
      final source = await _assessmentBundle(
        database,
        _source,
        state: 'abandoned',
      );
      final target = await _assessmentBundle(
        database,
        _target,
        state: 'completed',
      );
      expect(
        ownerUpgradeInventory.last,
        'assessment_runs',
        reason:
            'Reverse purge must delete Assessment before cycle/session/permit/assignment parents',
      );
      expect(requiredFullAccountExportScopes, contains('assessment_runs'));
      final export = await _export(database, _source);
      final data =
          (jsonDecode(utf8.decode(export.bytes)) as Map)['data'] as Map;
      expect(export.coveredScopes, requiredFullAccountExportScopes);
      expect((data['assessment_runs'] as List).single, source);
      expect((data['assessment_runs'] as List).single, hasLength(37));
      expect(utf8.decode(export.bytes), isNot(contains(target['id'])));
      final otherBefore = await _export(database, _target);
      final secretPurges = <String>[];
      final (core, token, cloud) = await _cloudConfirmed(database, repository);

      final local = await DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => _now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          secretPurges.add('$ownerId/$firebaseUid');
        },
      ).deleteAfterCloud(ownerId: _source, cloudReceipt: cloud);
      await core.markLocal(token, cloud, local);

      expect(secretPurges, ['$_source/${cloud.firebaseUid}']);
      expect(
        local.newGuestOwnerId,
        accountDeletionReplacementGuestOwnerId(cloud),
      );
      expect((await core.inspect())!.phase, DeletionIntentPhase.localCompleted);
      for (final table in ownerUpgradeInventory) {
        expect(
          await _rows(database, table, owner: _source),
          isEmpty,
          reason: table,
        );
      }
      expect((await _export(database, _target)).bytes, otherBefore.bytes);
      expect((await _rows(database, 'assessment_runs')).single, target);
      expect(await _rows(database, 'outbox_operations'), isEmpty);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      await core.clearCompleted(token);
      expect(await core.inspect(), isNull);
      expect((await _export(database, _target)).bytes, otherBefore.bytes);
    },
  );

  test(
    'an orphan Assessment residual prevents local completion proof and retains the deletion fence',
    () async {
      final source = await _assessmentBundle(database, _source);
      final (core, token, cloud) = await _cloudConfirmed(database, repository);
      final local = await DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => _now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {},
      ).deleteAfterCloud(ownerId: _source, cloudReceipt: cloud);
      // Simulate a damaged local store after deletion, not new collection.
      await database.customStatement('PRAGMA foreign_keys = OFF');
      try {
        await _insert(database, 'assessment_runs', source);
      } finally {
        await database.customStatement('PRAGMA foreign_keys = ON');
      }
      final before = await _allRows(database);

      await expectLater(
        core.markLocal(token, cloud, local),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.invalidLocalReceipt,
          ),
        ),
      );

      expect((await core.inspect())!.phase, DeletionIntentPhase.cloudConfirmed);
      expect(await _allRows(database), before);
      await expectLater(
        core.requireOwnerUnfenced(local.newGuestOwnerId),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.unavailable,
          ),
        ),
      );
      expect(await _rows(database, 'outbox_operations'), isEmpty);
    },
  );
}

EvidenceContext _assessmentEvidence() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'word-meaning',
  hintLevel: 0,
  contentRevision: 'synthetic-assessment-content',
  rolloutMode: EvidencePolicyRolloutMode.enforced,
  protocolId: 'synthetic-assessment-protocol',
  protocolVersion: '1',
  experimentId: 'synthetic-assessment-experiment',
  experimentVersion: 1,
  assignmentId: 'synthetic-assessment-assignment',
  cohort: 'standard',
  researchConsentVersion: 4,
  instrumentId: 'synthetic-assessment-instrument',
  instrumentVersion: '1',
  formId: 'synthetic-assessment-form',
  formVersion: '1',
  assessmentItemId: 'synthetic-assessment-item',
  assessmentResponseCode: 'incorrect',
  scoringRuleVersion: 'synthetic-assessment-score',
  engagementAllowed: false,
);

Future<void> _ordinaryGraph(AppDatabase database, String owner) async {
  await database.customStatement(
    'INSERT INTO vocabulary_categories '
    '(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) '
    "VALUES (?, ?, 'Synthetic travel', 'synthetic travel', 10, 10)",
    ['synthetic-category:$owner', owner],
  );
  await database.customStatement(
    'INSERT INTO vocabulary_words '
    '(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) '
    "VALUES (?, ?, ?, 'station', 'station', 'synthetic meaning', 'synthetic meaning', 'noun', 10, 10)",
    ['synthetic-word:$owner', owner, 'synthetic-category:$owner'],
  );
  await database.customStatement(
    'INSERT INTO reward_transactions '
    '(id,owner_id,idempotency_key,transaction_type,amount,item_id,catalog_version,occurred_at_utc_ms) '
    "VALUES (?, ?, 'synthetic-assessment-purchase', 'purchase', -5, 'theme_ocean', 1, 20)",
    ['synthetic-purchase:$owner', owner],
  );
}

Future<void> _session(
  AppDatabase database,
  String id,
  String owner,
  String purpose,
) => database.customStatement(
  'INSERT INTO learning_sessions '
  '(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
  "VALUES (?, ?, ?, 'active', 1, 'synthetic-owner', 'synthetic-build')",
  [id, owner, purpose],
);

Future<void> _attempt(
  AppDatabase database, {
  required String id,
  required String session,
  required EvidenceContext context,
}) => database.customStatement(
  'INSERT INTO answer_attempts '
  '(id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,evidence_class,evidence_context_json) '
  "VALUES (?, ?, ?, ?, 'meaningChoice', 0, 100, 1, 3, ?, ?)",
  [
    id,
    _source,
    session,
    'synthetic-word:$_source',
    context.evidenceClass.name,
    jsonEncode(context.toJson()),
  ],
);

Future<List<Map<String, Object?>>> _rows(
  AppDatabase database,
  String table, {
  String? owner,
}) async => [
  for (final row
      in await database
          .customSelect(
            'SELECT * FROM "$table"${owner == null ? '' : ' WHERE owner_id = ?'} ORDER BY rowid',
            variables: owner == null ? [] : [drift.Variable<String>(owner)],
          )
          .get())
    Map<String, Object?>.from(row.data),
];

Matcher get _rehomeDenied => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    contains('re-enrollment'),
  ),
);

Future<Map<String, Object?>> _assessmentBundle(
  AppDatabase database,
  String owner, {
  String state = 'active',
}) async {
  // Historical synthetic storage facts with a real test-only P256 signature.
  // They are not verified response/comparison evidence or collection grants.
  final assignment = await seedOwnerAssignment(database, owner);
  final permit = await insertOwnerParticipation(
    database,
    owner,
    assignmentId: assignment,
  );
  await database.customStatement(
    'INSERT INTO research_consents '
    '(id,owner_id,consent_version,consent_state,decided_at_utc_ms) '
    "VALUES (?, ?, 1, 'accepted', 1)",
    ['synthetic-assessment-consent:$owner', owner],
  );
  final measurement = await insertOwnerMotivationMeasurement(database, permit);
  final start = (measurement.run['started_at_utc_ms']! as int) + 5;
  final completed = state == 'completed' ? start + 10 : null;
  final abandoned = state == 'abandoned' ? start + 11 : null;
  final sessionId = 'synthetic-assessment-session:$owner';
  await _insert(database, 'learning_sessions', {
    'id': sessionId,
    'owner_id': owner,
    'activity_type': 'assessment',
    'state': state,
    'started_at_utc_ms': start,
    'ended_at_utc_ms': completed ?? abandoned,
    'app_version': 'synthetic-assessment-owner',
    'build_id': 'synthetic-owner-build',
  });
  final row = <String, Object?>{
    'id': 'synthetic-assessment:$owner',
    'owner_id': owner,
    'learning_session_id': sessionId,
    'study_cycle_id': measurement.runId,
    'phase': 'pre',
    'state': state,
    'protocol_id': permit.protocolId,
    'protocol_version': permit.protocolVersion,
    'experiment_id': 'synthetic-study',
    'experiment_version': 1,
    'assignment_id': assignment,
    'cohort': permit.assignedTreatment.name,
    'consent_version': 1,
    'consent_decided_at_utc_ms': 1,
    'instrument_id': 'synthetic-assessment-owner-instrument',
    'instrument_version': 'synthetic-instrument-v1',
    'form_id': 'synthetic-assessment-owner-form',
    'form_version': 'synthetic-form-v1',
    'instrument_checksum_sha256': 'a' * 64,
    'form_checksum_sha256': 'b' * 64,
    'app_version': 'synthetic-assessment-owner',
    'build_id': 'synthetic-owner-build',
    'database_schema_version': database.schemaVersion,
    'content_revision': 'synthetic-assessment-content',
    'evidence_policy_version': 'learning-evidence-v1',
    'feature_contract_revision': 'synthetic-assessment-contract',
    'feature_contract_hash': 'c' * 64,
    'started_at_utc_ms': start,
    'completed_at_utc_ms': completed,
    'abandoned_at_utc_ms': abandoned,
    'assignment_revision': 1,
    'protocol_revision': 1,
    'instrument_revision': 19,
    'form_content_revision': 7,
    'participation_permit_id': permit.id,
    'participation_permit_revision': permit.localRevision,
    'participation_permit_payload_sha256': permit.payloadSha256,
  };
  expect(row, hasLength(37));
  await _insert(database, 'assessment_runs', row);
  return row;
}

Future<void> _insert(
  AppDatabase database,
  String table,
  Map<String, Object?> row,
) => database.customStatement(
  'INSERT INTO "$table" (${row.keys.join(',')}) '
  'VALUES (${List.filled(row.length, '?').join(',')})',
  row.values.toList(),
);

Future<Map<String, List<Map<String, Object?>>>> _allRows(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: await _rows(database, table.actualTableName),
};

Future<Map<String, List<Map<String, Object?>>>> _researchRows(
  AppDatabase database,
  String owner,
) async => {
  for (final table in [
    'research_consents',
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
    'assessment_runs',
    'events_v2',
  ])
    table: await _rows(database, table, owner: owner),
  'assessment_sessions': [
    for (final row in await _rows(database, 'learning_sessions', owner: owner))
      if (row['activity_type'] == 'assessment') row,
  ],
};

Future<void> _mutationProbe(AppDatabase database) =>
    database.customStatement('''
  CREATE TRIGGER synthetic_assessment_business_mutation_probe
  BEFORE DELETE ON vocabulary_categories
  BEGIN
    SELECT RAISE(ABORT, 'Assessment source guard ran after business mutation');
  END
''');

Future<LocalAccountSnapshot> _export(AppDatabase database, String owner) =>
    DriftAccountSnapshotBuilder(
      database,
      nowUtc: () => _now,
    ).build(ownerId: owner);

Future<(DriftOwnerWriteCoordinator, DeletionIntentToken, CloudDeletionReceipt)>
_cloudConfirmed(
  AppDatabase database,
  DriftOwnerUpgradeRepository repository,
) async {
  await repository.upgrade(
    activeOwnerId: _source,
    firebaseUid: 'synthetic-deleting-assessment-uid',
  );
  final owner = await database
      .customSelect(
        'SELECT firebase_uid FROM local_owners WHERE id = ?',
        variables: [drift.Variable<String>(_source)],
      )
      .getSingle();
  final uid = owner.read<String>('firebase_uid');
  const key = 'delete:synthetic-assessment-owner';
  final core = DriftOwnerWriteCoordinator(database, nowUtc: () => _now);
  final token = await core.beginDeletion(
    ownerId: _source,
    firebaseUid: uid,
    idempotencyKey: key,
  );
  await core.markPending(token);
  // Synthetic completed-cloud evidence uses the actual stored UID and the same
  // durable marker as the production deletion flow. No cloud API is contacted.
  final cloud = CloudDeletionReceipt(
    receiptId: 'synthetic-assessment-cloud-receipt',
    ownerId: _source,
    firebaseUid: uid,
    idempotencyKey: key,
    completedAtUtc: _now,
  ).durableMarker();
  await core.markCloud(token, cloud);
  return (core, token, cloud);
}
