import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart'
    show experimentAssignmentId;

import '../../support/answer_attempt_evidence_fixture.dart';

void main() {
  test('v12 facts and deletion intent survive the participation migration', () async {
    final before = <String, List<Map<String, Object?>>>{};
    final schema = File('test/fixtures/schema_v12.sql').readAsStringSync();
    expect(RegExp('CREATE TABLE').allMatches(schema), hasLength(30));
    expect(schema, isNot(contains('research_participation_permits')));
    final evidence = jsonEncode(ordinaryAnswerEvidence().toJson());
    final token = DeletionIntentToken.bind(
      ownerId: 'owner-a',
      firebaseUid: 'uid-a',
      idempotencyKey: 'delete:synthetic-v12-migration',
      nonce: 'synthetic-v12-nonce',
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
              "INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) VALUES (?, ?, 'quiz', 'active', 3000, 'test', 'v12-snapshot')",
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
          sqlite.execute('PRAGMA user_version = 12');
        },
      ),
    );
    addTearDown(database.close);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      14,
    );
    expect(before, hasLength(30));
    expect(database.allTables, hasLength(33));
    expect(
      await database
          .customSelect('SELECT * FROM research_participation_permits')
          .get(),
      isEmpty,
    );
    for (final table in before.entries) {
      final after = await database
          .customSelect('SELECT * FROM "${table.key}" ORDER BY rowid')
          .get();
      expect(
        after.map((row) => row.data).toList(),
        table.value,
        reason: table.key,
      );
    }
    final columns = await database
        .customSelect('PRAGMA table_info(research_participation_permits)')
        .get();
    expect(columns.map((row) => row.read<String>('name')).toSet(), {
      'id',
      'owner_id',
      'local_revision',
      'cloud_revision',
      'is_deleted',
      'participant_class',
      'age_band_code',
      'assignment_id',
      'assigned_treatment',
      'consent_receipt_id',
      'guardian_permission_receipt_ref',
      'learner_assent_receipt_ref',
      'protocol_id',
      'protocol_version',
      'issued_at_utc_ms',
      'expires_at_utc_ms',
      'revoked_at_utc_ms',
      'issuer_key_id',
      'payload_sha256',
      'signature',
    });
    final foreignKeys = await database
        .customSelect('PRAGMA foreign_key_list(research_participation_permits)')
        .get();
    expect(foreignKeys.map((row) => row.read<String>('table')).toSet(), {
      'local_owners',
      'experiment_assignments',
    });
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
