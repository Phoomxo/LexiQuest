import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/research/domain/research_session_proof.dart';

import '../../support/pair_purpose_fixture.dart';
import '../identity/research_lifecycle_fixtures.dart';

const _source = 'private-proof-owner-a';
const _other = 'private-proof-owner-b';
const _table = 'research_session_proofs';
const _fields = {
  'proofAlias',
  'sessionAlias',
  'runAlias',
  'permitAlias',
  'proofRevision',
  'activityType',
  'sessionState',
  'startedAtUtc',
  'endedAtUtc',
  'appVersion',
  'buildId',
  'sessionConfigurationIdentity',
  'purpose',
  'isDeleted',
};

void main() {
  late AppDatabase db;
  late OwnerLifecycleArchiveExporter exporter;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedLifecycleOwner(db, _source, active: true);
    await seedLifecycleOwner(db, _other, firebaseUid: 'synthetic-target-uid');
    exporter = OwnerLifecycleArchiveExporter(
      database: db,
      nowUtc: () => DateTime.utc(2026, 9, 9),
    );
  });
  tearDown(() => db.close());

  test(
    'two proof phases export linked personal facts without canonical history',
    () async {
      await _parents(db, _source);
      final start = _quiz(_source);
      final end = _quiz(_source, phase: 2);
      // Reverse insertion order must not determine the phase/session alias.
      await _insertProof(db, end);
      await _insertProof(db, start);
      final before = await _snapshot(db, _source);
      final artifact = await exporter.prepareActive();
      final tables = _archive(artifact);
      final records = _records(tables, 'researchSessionProofs');
      expect(records.first, {'recordCount': 2});
      final phases = records.skip(1).toList();
      expect(phases, hasLength(2));
      for (final row in phases) {
        expect(row.keys.toSet(), _fields);
        expect(row['sessionAlias'], 'research-session-1');
        expect(
          row['runAlias'],
          _records(tables, 'motivationMeasurementRuns')[1]['runAlias'],
        );
        expect(
          row['permitAlias'],
          _records(tables, 'researchParticipationPermits')[1]['permitAlias'],
        );
        expect(row['activityType'], 'quiz');
        expect(
          row['startedAtUtc'],
          DateTime.fromMillisecondsSinceEpoch(2, isUtc: true).toIso8601String(),
        );
        expect(row['sessionConfigurationIdentity'], isNull);
        expect(row['purpose'], isNull);
        expect(row['appVersion'], '1');
        expect(row['buildId'], 'fixture');
        expect(row['isDeleted'], false);
      }
      expect(phases.map((row) => row['proofAlias']).toSet(), {
        'research-proof-1',
        'research-proof-2',
      });
      final started = phases.singleWhere((row) => row['proofRevision'] == 1);
      final completed = phases.singleWhere((row) => row['proofRevision'] == 2);
      expect(started['sessionState'], 'active');
      expect(started['endedAtUtc'], isNull);
      expect(completed['sessionState'], 'completed');
      expect(
        completed['endedAtUtc'],
        DateTime.fromMillisecondsSinceEpoch(4, isUtc: true).toIso8601String(),
      );
      _privateFieldsAbsent(jsonEncode(records), [start, end]);
      expect(await lifecycleRows(db, 'learning_sessions', _source), isEmpty);
      expect(await lifecycleRows(db, 'events_v2', _source), isEmpty);
      expect(await _snapshot(db, _source), before);
      expect((await exporter.prepareActive()).sha256, artifact.sha256);
    },
  );

  test(
    'matching proof exports validated configuration identity and learning purpose only',
    () async {
      await _parents(db, _source);
      final proof = await _matching(db);
      await _insertProof(db, proof);
      final rows = _records(
        _archive(await exporter.prepareActive()),
        'researchSessionProofs',
      );
      expect(rows, hasLength(2));
      expect(rows[1].keys.toSet(), _fields);
      expect(rows[1]['purpose'], 'learning');
      expect(
        rows[1]['sessionConfigurationIdentity'],
        proof.sessionConfigurationIdentity,
      );
      expect(
        proof.sessionConfigurationIdentity,
        matches(RegExp(r'^sha256:[0-9a-f]{64}$')),
      );
      _privateFieldsAbsent(jsonEncode(rows), [proof]);
      expect(await lifecycleRows(db, 'learning_sessions', _source), isEmpty);
      expect(await lifecycleRows(db, 'events_v2', _source), isEmpty);
    },
  );

  test(
    'matching corruption cannot manufacture a learning-purpose export',
    () async {
      await _parents(db, _source);
      final proof = await _matching(db);
      // Well-formed JSON satisfies storage shape, but is not a valid Pair start.
      await _insertProof(db, proof, override: {'pair_start_operation': '{}'});
      await expectLater(
        exporter.prepareActive(),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
    },
  );

  test(
    'revoked and tombstoned proof history remains personally exportable',
    () async {
      await seedLifecycleResearch(
        db,
        _source,
        response: false,
        opportunity: false,
        deleted: true,
        withdrawn: true,
      );
      final proof = _quiz(_source, phase: 2);
      await _insertProof(db, proof, override: {'is_deleted': 1});
      final records = _records(
        _archive(await exporter.prepareActive()),
        'researchSessionProofs',
      );
      expect(records.first, {'recordCount': 1});
      expect(records, hasLength(2));
      expect(records[1]['isDeleted'], true);
      expect(records[1]['sessionState'], 'completed');
      expect(records[1]['proofRevision'], 2);
      _privateFieldsAbsent(jsonEncode(records), [proof]);
    },
  );

  test(
    'physical deletion removes proof-bound opportunities before parents and preserves B',
    () async {
      await _parents(db, _source);
      await _parents(db, _other);
      await _insertProof(db, _quiz(_source));
      await _insertProof(db, _quiz(_other));
      await _opportunity(db, _source);
      await _opportunity(db, _other);
      final other = await _snapshot(db, _other);
      final secrets = <String>[];
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (owner) async => secrets.add(owner),
      ).eraseAll(ownerId: _source);
      for (final rows in (await _snapshot(db, _source)).values) {
        expect(rows, isEmpty);
      }
      expect(secrets, [_source]);
      expect(await _snapshot(db, _other), other);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'late physical deletion failure rolls back proof history and dependent opportunities',
    () async {
      await _parents(db, _source);
      await _insertProof(db, _quiz(_source));
      await _opportunity(db, _source);
      final before = await _snapshot(db, _source);
      await db.customStatement(
        '''CREATE TRIGGER fail_proof_owner_delete
      BEFORE DELETE ON local_owners WHEN OLD.id = 'private-proof-owner-a'
      BEGIN SELECT RAISE(ABORT, 'synthetic late proof deletion failure'); END''',
      );
      await expectLater(
        LocalDataDeletion(
          db,
          deleteOwnerSecrets: (_) async {},
        ).eraseAll(ownerId: _source),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'synthetic late proof deletion failure',
            ),
          ),
        ),
      );
      expect(await _snapshot(db, _source), before);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  for (final state in ['pending', 'retryWaiting', 'inFlight']) {
    test(
      'withdrawal supersedes $state proof upload while retaining history and unrelated operations',
      () async {
        await _parents(db, _source);
        await _parents(db, _other);
        final proof = _quiz(_source);
        final foreign = _quiz(_other);
        await _insertProof(db, proof);
        await _insertProof(db, foreign);
        await _outbox(
          db,
          'affected',
          _source,
          'researchSessionProof',
          proof.id,
          state,
        );
        await _outbox(
          db,
          'ack',
          _source,
          'researchSessionProof',
          proof.id,
          'acknowledged',
        );
        await _outbox(
          db,
          'denial',
          _source,
          'researchWithdrawal',
          'permit:$_source',
          'retryWaiting',
        );
        await _outbox(
          db,
          'learning',
          _source,
          'eventsV2',
          'ordinary-learning-event',
          'pending',
        );
        await _outbox(
          db,
          'foreign',
          _other,
          'researchSessionProof',
          foreign.id,
          state,
        );
        await insertLifecycleRow(db, 'learning_sessions', {
          'id': 'ordinary-learning-session',
          'owner_id': _source,
          'activity_type': 'quiz',
          'state': 'active',
          'started_at_utc_ms': 2,
          'app_version': '1',
          'build_id': 'fixture',
        });
        final learningBefore = await lifecycleRows(
          db,
          'learning_sessions',
          _source,
        );
        final proofBefore = await lifecycleRows(db, _table, _source);
        final otherBefore = await _snapshot(db, _other);
        final controls = (await lifecycleRows(
          db,
          'outbox_operations',
          _source,
        )).where((row) => row['operation_id'] != 'affected').toList();
        await DriftResearchConsentRepository(db).decide(
          ownerId: _source,
          version: 1,
          accepted: false,
          decidedAtUtc: DateTime.fromMillisecondsSinceEpoch(10, isUtc: true),
        );
        final operations = await lifecycleRows(
          db,
          'outbox_operations',
          _source,
        );
        final affected = operations.singleWhere(
          (row) => row['operation_id'] == 'affected',
        );
        expect(affected['state'], 'superseded');
        expect(affected['failure_code'], 'researchConsentWithdrawn');
        expect(affected['lease_token'], isNull);
        expect(affected['lease_expires_at_utc_ms'], isNull);
        expect(affected['next_attempt_at_utc_ms'], isNull);
        expect(affected['attempt_count'], 3);
        for (final control in controls) {
          expect(
            operations.singleWhere(
              (row) => row['operation_id'] == control['operation_id'],
            ),
            control,
          );
        }
        expect(await lifecycleRows(db, _table, _source), proofBefore);
        expect(
          await lifecycleRows(db, 'learning_sessions', _source),
          learningBefore,
        );
        expect(await _snapshot(db, _other), otherBefore);
        expect(
          operations.any(
            (row) =>
                row['entity_type'] == 'researchWithdrawal' &&
                row['state'] == 'pending',
          ),
          true,
        );
      },
    );
  }

  test(
    'proof history keeps reenrollment conflict before owner or secret mutation',
    () async {
      await _parents(db, _source);
      await _insertProof(db, _quiz(_source));
      final before = await _snapshot(db, _source);
      final other = await _snapshot(db, _other);
      final secrets = <String>[];
      final repository = _upgrade(db, secrets);
      for (final uid in ['synthetic-target-uid', 'synthetic-new-uid']) {
        await expectLater(
          repository.upgrade(activeOwnerId: _source, firebaseUid: uid),
          throwsA(isA<ResearchOwnerUpgradeConflict>()),
        );
        expect(await _snapshot(db, _source), before);
        expect(await _snapshot(db, _other), other);
        expect(secrets, isEmpty);
      }
    },
  );

  test(
    'already-bound upgrade replay retains proof pins and owner history',
    () async {
      await db.customStatement(
        "UPDATE local_owners SET firebase_uid = 'synthetic-source-uid', account_state = 'firebaseBound' WHERE id = 'private-proof-owner-a'",
      );
      await _parents(db, _source);
      await _insertProof(db, _quiz(_source));
      final before = await _snapshot(db, _source);
      final secrets = <String>[];
      final result = await _upgrade(
        db,
        secrets,
      ).upgrade(activeOwnerId: _source, firebaseUid: 'synthetic-source-uid');
      expect(result.mode, OwnerUpgradeMode.alreadyBound);
      expect(await _snapshot(db, _source), before);
      expect(secrets, isEmpty);
    },
  );
}

Future<void> _parents(AppDatabase db, String owner) =>
    seedLifecycleResearch(db, owner, response: false, opportunity: false);

ResearchSessionProof _quiz(String owner, {int phase = 1}) =>
    ResearchSessionProof.fromCanonicalSnapshot(
      ownerId: owner,
      permitId: 'permit:$owner',
      permitPayloadSha256: 'a' * 64,
      permitRevision: 3,
      measurementRunId: 'run:$owner',
      proofRevision: phase,
      session: {
        'id': 'private-session:$owner',
        'owner_id': owner,
        'activity_type': 'quiz',
        'state': 'completed',
        'started_at_utc_ms': 2,
        'ended_at_utc_ms': 4,
        'app_version': '1',
        'build_id': 'fixture',
        'session_configuration_identity': null,
        'session_configuration_json': null,
      },
    );

Future<ResearchSessionProof> _matching(AppDatabase db) async {
  // Reuse the actual Pair serializer/purpose decoder; this is synthetic
  // consistency evidence, not a signature or canonical provenance claim.
  await seedSyntheticReplayPurpose(
    db,
    owner: _source,
    at: DateTime.fromMillisecondsSinceEpoch(2, isUtc: true),
    purpose: PairSessionPurpose.learning,
    buildId: 'fixture',
  );
  final proof = ResearchSessionProof.fromCanonicalSnapshot(
    ownerId: _source,
    permitId: 'permit:$_source',
    permitPayloadSha256: 'a' * 64,
    permitRevision: 3,
    measurementRunId: 'run:$_source',
    proofRevision: 1,
    session: (await lifecycleRows(db, 'learning_sessions', _source)).single,
    checkpoints: await lifecycleRows(db, 'events_v2', _source),
    historicalOwners: await lifecycleRows(db, 'local_owners', _source),
  );
  await db.customStatement('DELETE FROM events_v2 WHERE owner_id = ?', [
    _source,
  ]);
  await db.customStatement('DELETE FROM learning_sessions WHERE owner_id = ?', [
    _source,
  ]);
  return proof;
}

Future<void> _insertProof(
  AppDatabase db,
  ResearchSessionProof proof, {
  Map<String, Object?> override = const {},
}) => insertLifecycleRow(db, _table, {
  'id': proof.id,
  'owner_id': proof.ownerId,
  'measurement_run_id': proof.measurementRunId,
  'permit_id': proof.permitId,
  'learning_session_id': proof.learningSessionId,
  'proof_revision': proof.proofRevision,
  'activity_type': proof.activityType,
  'session_state': proof.sessionState,
  'started_at_utc_ms': proof.startedAtUtcMs,
  'ended_at_utc_ms': proof.endedAtUtcMs,
  'app_version': proof.appVersion,
  'build_id': proof.buildId,
  'session_configuration_identity': proof.sessionConfigurationIdentity,
  'session_configuration_json': proof.sessionConfigurationJson,
  'pair_start_operation': proof.pairStartOperation,
  'pair_checkpoint_event_version': proof.pairCheckpointEventVersion,
  'pair_owner_lineage_json': proof.pairOwnerLineage == null
      ? null
      : jsonEncode(proof.pairOwnerLineage),
  'permit_payload_sha256': proof.permitPayloadSha256,
  'permit_revision': proof.permitRevision,
  ...override,
});

Future<void> _opportunity(AppDatabase db, String owner) =>
    insertLifecycleRow(db, 'measurement_opportunities', {
      'id': 'opportunity:$owner',
      'owner_id': owner,
      'measurement_run_id': 'run:$owner',
      'permit_id': 'permit:$owner',
      'entry_attempt_id': '11111111-1111-4111-8111-111111111111',
      'assigned_treatment': 'adventure',
      'effective_presentation': 'standard',
      'presented_event_id': 'presented:$owner',
      'learning_session_id': 'private-session:$owner',
      'started_event_id': 'started:$owner',
      'opened_at_utc_ms': 2,
    });

Future<void> _outbox(
  AppDatabase db,
  String id,
  String owner,
  String type,
  String entity,
  String state,
) => insertLifecycleRow(db, 'outbox_operations', {
  'operation_id': id,
  'owner_id': owner,
  'entity_type': type,
  'entity_id': entity,
  'operation_kind': 'upsert',
  'state': state,
  'created_at_utc_ms': 2,
  'attempt_count': 3,
  'next_attempt_at_utc_ms': state == 'retryWaiting' ? 30 : null,
  'lease_token': state == 'inFlight' ? 'synthetic-lease' : null,
  'lease_expires_at_utc_ms': state == 'inFlight' ? 40 : null,
  'acknowledged_at_utc_ms': state == 'acknowledged' ? 5 : null,
});

Future<Map<String, Object?>> _snapshot(AppDatabase db, String owner) async => {
  ...await lifecycleSnapshot(db, owner),
  _table: await lifecycleRows(db, _table, owner),
};

DriftOwnerUpgradeRepository _upgrade(AppDatabase db, List<String> secrets) =>
    DriftOwnerUpgradeRepository(
      db,
      nowUtc: () => DateTime.utc(2026, 9, 9),
      generateConflictId: () => 'synthetic-conflict',
      generateOwnerId: () => 'synthetic-new-owner',
      generateOwnerOperationToken: () => 'synthetic-operation',
      deleteOwnerSecrets: (owner) async => secrets.add(owner),
    );

List<Map<String, Object?>> _archive(OwnerLifecycleArchiveArtifact artifact) =>
    (((jsonDecode(utf8.decode(artifact.bytes)) as Map)['content']
                as Map)['tables']
            as List)
        .cast<Map<String, Object?>>();

List<Map<String, Object?>> _records(
  List<Map<String, Object?>> tables,
  String alias,
) => (tables.singleWhere((table) => table['alias'] == alias)['records'] as List)
    .cast<Map<String, Object?>>();

void _privateFieldsAbsent(String encoded, List<ResearchSessionProof> proofs) {
  for (final proof in proofs) {
    for (final value in [
      proof.id,
      proof.ownerId,
      proof.learningSessionId,
      proof.measurementRunId,
      proof.permitId,
      proof.permitPayloadSha256,
      proof.sessionConfigurationJson,
      proof.pairStartOperation,
      'private-signature:${proof.ownerId}',
    ]) {
      if (value != null) expect(encoded, isNot(contains(value)));
    }
  }
  for (final key in [
    'ownerId',
    'learningSessionId',
    'permitPayloadSha256',
    'permitRevision',
    'sessionConfigurationJson',
    'pairStartOperation',
    'pairOwnerLineage',
  ]) {
    expect(encoded, isNot(contains('"$key"')));
  }
}
