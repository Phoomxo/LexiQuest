import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart'
    show experimentAssignmentId;

import '../../support/answer_attempt_evidence_fixture.dart';
import '../../support/motivation_measurement_fixture.dart'
    show lifecycleMotivationInstrument;
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import '../../support/research_participation_harness.dart'
    show participationPermit;

void main() {
  test('fresh sessions retain null recovery fields and revision zero', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms) VALUES ('owner-a', 1)",
    );
    await database.customStatement(
      'INSERT INTO learning_sessions '
      '(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) '
      "VALUES ('legacy', 'owner-a', 'quiz', 'active', 2, 'test', 'test')",
    );
    final row = await database
        .customSelect(
          'SELECT accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json '
          "FROM learning_sessions WHERE id = 'legacy'",
        )
        .getSingle();
    expect(row.data, {
      'accepted_plan_id': null,
      'accepted_plan_json': null,
      'checkpoint_revision': 0,
      'checkpoint_json': null,
    });
    final columns = await database
        .customSelect('PRAGMA table_info(learning_sessions)')
        .get();
    expect(columns, hasLength(15));
    final revision = columns.singleWhere(
      (row) => row.read<String>('name') == 'checkpoint_revision',
    );
    expect(revision.read<int>('notnull'), 1);
    expect(revision.read<String>('dflt_value'), '0');
    for (final name in [
      'accepted_plan_id',
      'accepted_plan_json',
      'checkpoint_json',
    ]) {
      final column = columns.singleWhere(
        (row) => row.read<String>('name') == name,
      );
      expect(column.read<int>('notnull'), 0);
      expect(column.read<String>('type'), 'TEXT');
    }
    expect(database.allTables, hasLength(35));
  });

  test('v15 facts and deletion intent survive accepted quiz migration', () async {
    final before = <String, List<Map<String, Object?>>>{};
    final schema = File('test/fixtures/schema_v15.sql').readAsStringSync();
    expect(RegExp('CREATE TABLE').allMatches(schema), hasLength(34));
    expect(schema, contains('motivation_measurement_runs'));
    expect(schema, contains('motivation_responses'));
    expect(schema, contains('measurement_opportunities'));
    expect(schema, isNot(contains('accepted_plan_json')));
    final evidence = jsonEncode(ordinaryAnswerEvidence().toJson());
    final token = DeletionIntentToken.bind(
      ownerId: 'owner-a',
      firebaseUid: 'uid-a',
      idempotencyKey: 'delete:synthetic-v15-migration',
      nonce: 'synthetic-v14-nonce',
    );
    final intent = jsonEncode({
      'version': 1,
      'phase': 'pendingCloud',
      'ownerBinding': token.ownerBinding,
      'firebaseUidBinding': token.firebaseUidBinding,
      'operationBinding': token.operationBinding,
      'nonceBinding': token.nonceBinding,
    });
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          for (final statement in schema.split(';')) {
            if (statement.trim().isNotEmpty) sqlite.execute(statement);
          }
          sqlite.execute(
            "INSERT INTO local_owners (id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES ('owner-a', 'uid-a', 'registered', 1, 1), ('owner-b', 'uid-b', 'registered', 2, 0)",
          );
          for (final suffix in ['a', 'b']) {
            final owner = 'owner-$suffix';
            sqlite.execute(
              "INSERT INTO research_consents (id, owner_id, consent_version, consent_state, decided_at_utc_ms) VALUES (?, ?, 4, 'accepted', 1000)",
              ['consent-$suffix', owner],
            );
            sqlite.execute(
              'INSERT INTO experiment_assignments (id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, 1, ?, ?, 2000)',
              [
                experimentAssignmentId(
                  ownerId: owner,
                  experimentId: 'synthetic-retained-study',
                  experimentVersion: 1,
                ),
                owner,
                'synthetic-retained-study',
                'standard',
                'synthetic-protocol-v1',
              ],
            );
            final permit = participationPermit(
              id: 'synthetic-retained-permit-$suffix',
              ownerId: owner,
              assignmentId: experimentAssignmentId(
                ownerId: owner,
                experimentId: 'synthetic-retained-study',
                experimentVersion: 1,
              ),
            );
            final permitValues = <String, Object?>{
              'id': permit.id,
              'owner_id': permit.ownerId,
              'local_revision': permit.localRevision,
              'cloud_revision': permit.cloudRevision,
              'is_deleted': permit.isDeleted ? 1 : 0,
              'participant_class': permit.participantClass.name,
              'age_band_code': permit.ageBandCode,
              'assignment_id': permit.assignmentId,
              'assigned_treatment': permit.assignedTreatment.wireName,
              'consent_receipt_id': permit.consentReceiptId,
              'guardian_permission_receipt_ref':
                  permit.guardianPermissionReceiptRef,
              'learner_assent_receipt_ref': permit.learnerAssentReceiptRef,
              'protocol_id': permit.protocolId,
              'protocol_version': permit.protocolVersion,
              'issued_at_utc_ms': permit.issuedAtUtc.millisecondsSinceEpoch,
              'expires_at_utc_ms': permit.expiresAtUtc.millisecondsSinceEpoch,
              'revoked_at_utc_ms': permit.revokedAtUtc?.millisecondsSinceEpoch,
              'issuer_key_id': permit.issuerKeyId,
              'payload_sha256': permit.payloadSha256,
              'signature': permit.signature,
            };
            sqlite.execute(
              'INSERT INTO research_participation_permits (${permitValues.keys.join(', ')}) '
              'VALUES (${List.filled(permitValues.length, '?').join(', ')})',
              permitValues.values.toList(),
            );
            final instrument = lifecycleMotivationInstrument();
            final started = permit.issuedAtUtc.millisecondsSinceEpoch + 1000;
            final runId = motivationMeasurementRunId(
              ownerId: owner,
              permitId: permit.id,
              protocolId: permit.protocolId,
              protocolVersion: permit.protocolVersion,
              instrumentChecksumSha256: instrument.checksumSha256,
            );
            final run = <String, Object?>{
              'id': runId,
              'owner_id': owner,
              'local_revision': 2,
              'permit_id': permit.id,
              'permit_payload_sha256': permit.payloadSha256,
              'assignment_id': permit.assignmentId,
              'assignment_revision': 1,
              'consent_version': 4,
              'consent_decided_at_utc_ms': 1000,
              'protocol_id': permit.protocolId,
              'protocol_version': permit.protocolVersion,
              'protocol_revision': 1,
              'treatment': permit.assignedTreatment.wireName,
              'instrument_id': instrument.instrumentId,
              'instrument_version': instrument.instrumentVersion,
              'instrument_revision': 1,
              'instrument_checksum_sha256': instrument.checksumSha256,
              'form_id': instrument.formId,
              'form_version': instrument.formVersion,
              'item_catalog_version': instrument.itemCatalogVersion,
              'scoring_rule_version': motivationScoringRuleVersion,
              'app_version': 'synthetic-migration',
              'build_id': 'v15-snapshot',
              'database_schema_version': 15,
              'content_revision': 'synthetic-content-v1',
              'evidence_policy_version': 'learning-evidence-v1',
              'catalog_version': 'synthetic-v1',
              'state': 'started',
              'started_at_utc_ms': started,
              'closed_at_utc_ms': null,
            };
            sqlite.execute(
              'INSERT INTO motivation_measurement_runs (${run.keys.join(', ')}) '
              'VALUES (${List.filled(run.length, '?').join(', ')})',
              run.values.toList(),
            );
            final response = <String, Object?>{
              'id': motivationResponseId(
                runId: runId,
                itemId: 'synthetic-baseline',
              ),
              'owner_id': owner,
              'local_revision': 1,
              'run_id': runId,
              'item_id': 'synthetic-baseline',
              'item_catalog_version': instrument.itemCatalogVersion,
              'response_code': 'synthetic-high',
              'ordinal_value': 100,
              'answered_at_utc_ms': started + 1000,
            };
            sqlite.execute(
              'INSERT INTO motivation_responses (${response.keys.join(', ')}) '
              'VALUES (${List.filled(response.length, '?').join(', ')})',
              response.values.toList(),
            );
            sqlite.execute(
              'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
              ['category-$suffix', owner, suffix, suffix],
            );
            sqlite.execute(
              'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
              [
                'word-$suffix',
                owner,
                'category-$suffix',
                suffix,
                suffix,
                'meaning $suffix',
                'meaning $suffix',
                'noun',
              ],
            );
            sqlite.execute(
              "INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) VALUES (?, ?, 'quiz', 'active', 3000, 'test', 'v15-snapshot')",
              ['session-$suffix', owner],
            );
            sqlite.execute(
              "INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode, is_correct, response_time_ms, attempt_number, occurred_at_utc_ms, evidence_class, evidence_context_json) VALUES (?, ?, ?, ?, 'meaningChoice', 1, 320, 1, 4000, 'recognition', ?)",
              [
                'answer-$suffix',
                owner,
                'session-$suffix',
                'word-$suffix',
                evidence,
              ],
            );
            sqlite.execute(
              'INSERT INTO measurement_opportunities '
              '(id, owner_id, local_revision, measurement_run_id, permit_id, '
              'entry_attempt_id, assigned_treatment, effective_presentation, opened_at_utc_ms, is_index_session) '
              'VALUES (?, ?, 2, ?, ?, ?, ?, ?, ?, 0)',
              [
                'synthetic-opportunity-$suffix',
                owner,
                runId,
                permit.id,
                suffix == 'a'
                    ? '00000000-0000-4000-8000-000000000001'
                    : '00000000-0000-4000-8000-000000000002',
                'standard',
                'standard',
                started + 1,
              ],
            );
          }
          sqlite.execute(
            "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms, payload_version) VALUES ('attempt:answer-a:1', 'owner-a', 'attempt', 'answer-a', 'append', 4000, 2)",
          );
          sqlite.execute(
            "INSERT INTO runtime_flags (key, bool_value, source, updated_at_utc_ms) VALUES ('accountDeletion.ownerWriteIntent', 1, ?, 5000)",
            [intent],
          );
          for (final table in sqlite.select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )) {
            final name = table['name'] as String;
            before[name] = [
              for (final row in sqlite.select(
                'SELECT * FROM "$name" ORDER BY rowid',
              ))
                Map<String, Object?>.from(row),
            ];
          }
          sqlite.execute('PRAGMA user_version = 15');
        },
      ),
    );
    addTearDown(database.close);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      18,
    );
    expect(before, hasLength(34));
    expect(database.allTables, hasLength(35));
    expect(
      await database.customSelect('SELECT * FROM assessment_runs').get(),
      isEmpty,
    );
    expect(
      await database
          .customSelect('SELECT * FROM measurement_opportunities')
          .get(),
      hasLength(2),
    );
    for (final table in before.entries) {
      final after = await database
          .customSelect('SELECT * FROM "${table.key}" ORDER BY rowid')
          .get();
      expect(
        after
            .map(
              (row) => Map<String, Object?>.from(row.data)
                ..remove('accepted_plan_id')
                ..remove('accepted_plan_json')
                ..remove('checkpoint_revision')
                ..remove('checkpoint_json')
                ..remove('last_switch_ordinal')
                ..remove('suppressed_switch_count')
                ..remove('started_effective_presentation')
                ..remove('pending_presentation_change_json'),
            )
            .toList(),
        table.value,
        reason: table.key,
      );
    }
    final sessions = await database
        .customSelect(
          'SELECT accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json '
          'FROM learning_sessions ORDER BY id',
        )
        .get();
    expect(sessions, hasLength(2));
    for (final row in sessions) {
      expect(row.data, {
        'accepted_plan_id': null,
        'accepted_plan_json': null,
        'checkpoint_revision': 0,
        'checkpoint_json': null,
      });
    }
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    final coordinator = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => DateTime.utc(2026, 10, 29),
    );
    final retained = await coordinator.inspect();
    expect(retained?.phase, DeletionIntentPhase.pendingCloud);
    expect(retained?.casToken?.sameAttempt(token), isTrue);
    await expectLater(
      coordinator.requireOwnerUnfenced('owner-a'),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.unavailable,
        ),
      ),
    );
  });
}
