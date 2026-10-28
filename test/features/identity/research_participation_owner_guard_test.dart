import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_admission_signing.dart';

const _guest = 'synthetic-signed-owner-guest';
const _account = 'synthetic-signed-owner-account';
const _uid = 'synthetic-signed-owner-firebase';
final _now = DateTime.utc(2026, 10, 29, 12);

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    var sequence = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => _now,
      generateConflictId: () => 'signed-owner-conflict-${sequence++}',
      generateOwnerId: () => 'synthetic-signed-owner-after-logout',
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

  for (final participantClass in ResearchParticipantClass.values) {
    for (final state in ['active', 'revoked', 'deleted']) {
      test(
        'rejects $state ${participantClass.name} source pins before any merge mutation',
        () async {
          await _seedMergeGraph(database);
          final signed = await _seedPermit(
            database,
            participantClass: participantClass,
            state: state,
          );
          // A late FK failure is insufficient: reconciliation must never start.
          await database.customStatement('''
          CREATE TRIGGER synthetic_signed_owner_mutation_probe
          BEFORE DELETE ON vocabulary_categories
          BEGIN
            SELECT RAISE(ABORT, 'merge mutation preceded signed owner preflight');
          END
        ''');
          final before = await _snapshot(database);
          final signedBefore = await _signedRows(database);
          expect(signedBefore.single, hasLength(20));

          await expectLater(merge(), throwsA(isA<StateError>()));

          expect(await _snapshot(database), before);
          expect(await _signedRows(database), signedBefore);
          expect(signedBefore.single['signature'], signed.signature);
          expect(signedBefore.single['payload_sha256'], signed.payloadSha256);
        },
      );
    }
  }

  test(
    'target-only signed participation does not block an ordinary guest merge',
    () async {
      await _seedMergeGraph(database);
      final signed = await _seedPermit(
        database,
        owner: _account,
        experiment: 'synthetic-target-only-study',
      );
      final before = await _signedRows(database);
      final eventIds = await _eventIds(database);

      final result = await merge();

      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(result.targetOwnerId, _account);
      expect(await _signedRows(database), before);
      expect(await _eventIds(database), eventIds);
      expect(await _ownerCount(database, 'vocabulary_words', _guest), 0);
      expect(await _ownerCount(database, 'vocabulary_words', _account), 1);
      final queue = await database.select(database.outboxOperations).get();
      expect(
        queue.where(
          (row) =>
              row.entityId == signed.id || row.entityId == signed.assignmentId,
        ),
        isEmpty,
      );
      expect(
        (await database.select(database.localOwners).get())
            .singleWhere((owner) => owner.isActive)
            .id,
        _account,
      );
    },
  );

  test(
    'same-owner anonymous bind and already-bound replay preserve all signed bytes',
    () async {
      await _seedPermit(database);
      final before = await _signedRows(database);
      final assignmentsBefore = await _assignmentRows(database);

      final bound = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-new-same-owner-uid',
      );
      final replay = await repository.upgrade(
        activeOwnerId: _guest,
        firebaseUid: 'synthetic-new-same-owner-uid',
      );

      expect(bound.mode, OwnerUpgradeMode.anonymousBound);
      expect(replay.mode, OwnerUpgradeMode.alreadyBound);
      expect(bound.targetOwnerId, _guest);
      expect(await _signedRows(database), before);
      expect(await _assignmentRows(database), assignmentsBefore);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      expect(await _eventIds(database), isEmpty);
    },
  );

  test(
    'logout retains original signed owner and assignment without re-enrolling',
    () async {
      await _seedPermit(database);
      final before = await _signedRows(database);
      final assignmentsBefore = await _assignmentRows(database);

      final result = await repository.createLocalGuestAfterLogout();

      expect(result.mode, OwnerUpgradeMode.localGuestCreated);
      expect(result.targetOwnerId, isNot(_guest));
      expect(await _signedRows(database), before);
      expect(await _assignmentRows(database), assignmentsBefore);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      expect(await _eventIds(database), isEmpty);
      final owners = await database.select(database.localOwners).get();
      expect(
        owners.singleWhere((owner) => owner.id == _guest).isActive,
        isFalse,
      );
      expect(
        owners.singleWhere((owner) => owner.isActive).id,
        result.targetOwnerId,
      );
    },
  );

  test(
    'rollback cannot delete a new guest holding signed research facts',
    () async {
      final guest = await repository.createLocalGuestAfterLogout();
      await _seedPermit(database, owner: guest.targetOwnerId);
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
      expect(
        owners.singleWhere((owner) => owner.isActive).id,
        guest.targetOwnerId,
      );
    },
  );

  test(
    'persistent deletion fence is checked before signed-owner preflight',
    () async {
      await _seedMergeGraph(database);
      await _seedPermit(database);
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = ?, account_state = 'firebaseBound' WHERE id = ?",
        ['synthetic-source-bound-uid', _guest],
      );
      final coordinator = DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => _now,
      );
      await coordinator.beginDeletion(
        ownerId: _guest,
        firebaseUid: 'synthetic-source-bound-uid',
        idempotencyKey: 'delete:synthetic-signed-owner-operation',
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
    },
  );
}

Future<ResearchParticipationPermit> _seedPermit(
  AppDatabase database, {
  String owner = _guest,
  String experiment = 'synthetic-participation-study',
  ResearchParticipantClass participantClass = ResearchParticipantClass.adult,
  String state = 'active',
}) async {
  final assignmentId = experimentAssignmentId(
    ownerId: owner,
    experimentId: experiment,
    experimentVersion: 1,
  );
  final presentation = participantClass == ResearchParticipantClass.minor
      ? TodayExperiencePresentation.adventure
      : TodayExperiencePresentation.standard;
  final issued = _now.subtract(const Duration(hours: 1));
  final revision = state == 'active' ? 1 : 2;
  final signed = signAdmissionParticipation(
    ResearchParticipationPermit(
      id: 'permit:$owner',
      ownerId: owner,
      participantClass: participantClass,
      ageBandCode: participantClass == ResearchParticipantClass.minor
          ? 'synthetic-14-17'
          : 'synthetic-18-plus',
      assignmentId: assignmentId,
      assignedTreatment: presentation,
      consentReceiptId: 'synthetic-consent:$owner',
      guardianPermissionReceiptRef:
          participantClass == ResearchParticipantClass.minor
          ? 'synthetic-guardian:$owner'
          : null,
      learnerAssentReceiptRef:
          participantClass == ResearchParticipantClass.minor
          ? 'synthetic-assent:$owner'
          : null,
      protocolId: 'synthetic-protocol',
      protocolVersion: 'synthetic-protocol-v1',
      issuedAtUtc: issued,
      expiresAtUtc: _now.add(const Duration(days: 1)),
      revokedAtUtc: state == 'revoked'
          ? _now.subtract(const Duration(minutes: 5))
          : null,
      issuerKeyId: syntheticAdmissionP256KeyId,
      payloadSha256: '0' * 64,
      signature: 'unsigned-fixture',
      localRevision: revision,
      cloudRevision: revision,
      isDeleted: state == 'deleted',
    ),
  );
  expect(
    admissionP256Verifier().verify(
      issuerKeyId: signed.issuerKeyId,
      canonicalPayload: signed.canonicalPayload(),
      signature: signed.signature,
    ),
    isTrue,
  );
  await database.customStatement(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      assignmentId,
      owner,
      experiment,
      1,
      presentation.wireName,
      signed.protocolVersion,
      _now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
    ],
  );
  final fields = <String, Object?>{
    'id': signed.id,
    'owner_id': signed.ownerId,
    'participant_class': signed.participantClass.name,
    'age_band_code': signed.ageBandCode,
    'assignment_id': signed.assignmentId,
    'assigned_treatment': signed.assignedTreatment.wireName,
    'consent_receipt_id': signed.consentReceiptId,
    'guardian_permission_receipt_ref': signed.guardianPermissionReceiptRef,
    'learner_assent_receipt_ref': signed.learnerAssentReceiptRef,
    'protocol_id': signed.protocolId,
    'protocol_version': signed.protocolVersion,
    'issued_at_utc_ms': signed.issuedAtUtc.millisecondsSinceEpoch,
    'expires_at_utc_ms': signed.expiresAtUtc.millisecondsSinceEpoch,
    'revoked_at_utc_ms': signed.revokedAtUtc?.millisecondsSinceEpoch,
    'issuer_key_id': signed.issuerKeyId,
    'payload_sha256': signed.payloadSha256,
    'signature': signed.signature,
    'local_revision': signed.localRevision,
    'cloud_revision': signed.cloudRevision,
    'is_deleted': signed.isDeleted ? 1 : 0,
  };
  await database.customStatement(
    'INSERT INTO research_participation_permits (${fields.keys.join(', ')}) '
    'VALUES (${List.filled(fields.length, '?').join(', ')})',
    fields.values.toList(),
  );
  await insertOwnerMotivationMeasurement(database, signed);
  return signed;
}

Future<List<Map<String, Object?>>> _signedRows(AppDatabase database) async =>
    (await database
            .customSelect(
              'SELECT * FROM research_participation_permits ORDER BY id',
            )
            .get())
        .map((row) => Map<String, Object?>.of(row.data))
        .toList();

Future<List<Map<String, Object?>>> _assignmentRows(
  AppDatabase database,
) async =>
    (await database
            .customSelect('SELECT * FROM experiment_assignments ORDER BY id')
            .get())
        .map((row) => Map<String, Object?>.of(row.data))
        .toList();

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
  final before = <String, List<String>>{};
  for (final table in {
    'local_owners',
    'runtime_flags',
    ...ownerUpgradeInventory,
    'research_participation_permits',
    'vocabulary_import_rows',
    'quest_objective_progress',
  }) {
    final rows = await database.customSelect('SELECT * FROM $table').get();
    before[table] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return before;
}

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
    "VALUES ('synthetic-word-operation', ?, 'word', 'word-guest', 'upsert', 20)",
    [_guest],
  );
  await database.customStatement(
    'INSERT INTO events_v2 (event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, actor_identity, owner_id, '
    'aggregate_type, aggregate_id, idempotency_key, consent_context_json, app_version, build_id, privacy_classification, payload_json) '
    "VALUES ('synthetic-signed-owner-event', 'SyntheticFixture', 1, '2026-10-29T00:00:00.000Z', '2026-10-29T00:00:01.000Z', ?, ?, "
    "'LearningSession', 'synthetic-session', 'synthetic-event-key', '{}', '1.0.0', 'synthetic', 'anonymized', '{}')",
    [_guest, _guest],
  );
}
