import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/measurement_opportunity_fixture.dart';
import '../../support/measurement_opportunity_harness.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

void main() {
  test(
    'fresh v18 adds one empty assessment table with all37 pinned fields',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      expect(database.schemaVersion, 18);
      expect(database.allTables, hasLength(35));
      final columns = await database
          .customSelect('PRAGMA table_info(assessment_runs)')
          .get();
      expect(columns, hasLength(37));
      expect(
        columns.map((row) => row.read<String>('name')).toSet(),
        _assessmentColumns,
      );
      for (final column in columns) {
        final name = column.read<String>('name');
        expect(
          column.read<String>('type'),
          _integerColumns.contains(name) ? 'INTEGER' : 'TEXT',
          reason: name,
        );
        expect(
          column.read<int>('notnull'),
          {'completed_at_utc_ms', 'abandoned_at_utc_ms'}.contains(name) ? 0 : 1,
          reason: name,
        );
      }
      expect(
        await database.customSelect('SELECT * FROM assessment_runs').get(),
        isEmpty,
      );
      final foreignKeys = await database
          .customSelect('PRAGMA foreign_key_list(assessment_runs)')
          .get();
      expect(foreignKeys, hasLength(5));
      expect(
        {
          for (final row in foreignKeys)
            row.read<String>('from'): (
              row.read<String>('table'),
              row.read<String>('to'),
            ),
        },
        {
          'owner_id': ('local_owners', 'id'),
          'learning_session_id': ('learning_sessions', 'id'),
          'assignment_id': ('experiment_assignments', 'id'),
          'participation_permit_id': ('research_participation_permits', 'id'),
          'study_cycle_id': ('motivation_measurement_runs', 'id'),
        },
      );
      for (final row in foreignKeys) {
        if (row.read<String>('from') == 'owner_id') continue;
        expect(row.read<String>('on_delete'), isIn(['NO ACTION', 'RESTRICT']));
      }
      final uniqueKeys = <List<String>>[];
      for (final index
          in await database
              .customSelect('PRAGMA index_list(assessment_runs)')
              .get()) {
        if (index.read<int>('unique') != 1) continue;
        final name = index.read<String>('name');
        final fields = await database
            .customSelect('PRAGMA index_info("$name")')
            .get();
        uniqueKeys.add(fields.map((row) => row.read<String>('name')).toList());
      }
      expect(uniqueKeys, contains(equals(['learning_session_id'])));
      expect(
        uniqueKeys,
        contains(equals(['owner_id', 'study_cycle_id', 'phase'])),
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
  test(
    'assessment parent FKs and logical uniqueness reject partial writes',
    () async {
      final fixture = await OpportunityFixture.open();
      addTearDown(fixture.database.close);
      await fixture.startRun();
      final database = fixture.database;
      for (final session in [
        'synthetic-assessment-one',
        'synthetic-assessment-two',
      ]) {
        await database.customStatement(
          'INSERT INTO learning_sessions '
          '(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
          "VALUES (?, 'owner-a', 'assessment', 'active', ?, 'synthetic-assessment', 'storage-only')",
          [
            session,
            participationStart
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
          ],
        );
      }
      // Storage-only synthetic pins; this row is not a collection grant.
      final row = await _assessmentRow(fixture);
      expect(row.keys.toSet(), _assessmentColumns);
      for (final field in [
        'owner_id',
        'learning_session_id',
        'assignment_id',
        'participation_permit_id',
        'study_cycle_id',
      ]) {
        final invalid = Map<String, Object?>.of(row)
          ..['id'] = 'synthetic-invalid-$field'
          ..[field] = 'synthetic-missing-$field';
        final before = await _allRows(database);
        await expectLater(
          _insert(database, 'assessment_runs', invalid),
          throwsException,
        );
        expect(await _allRows(database), before, reason: field);
      }
      await _insert(database, 'assessment_runs', row);
      expect(
        (await database
                .customSelect('SELECT * FROM assessment_runs')
                .getSingle())
            .data,
        row,
      );
      for (final collision in [
        Map<String, Object?>.of(row)
          ..['id'] = 'synthetic-reused-assessment-session'
          ..['phase'] = 'post',
        Map<String, Object?>.of(row)
          ..['id'] = 'synthetic-reused-assessment-phase'
          ..['learning_session_id'] = 'synthetic-assessment-two',
      ]) {
        final before = await _allRows(database);
        await expectLater(
          _insert(database, 'assessment_runs', collision),
          throwsException,
        );
        expect(await _allRows(database), before);
      }
      for (final parent in [
        ('learning_sessions', row['learning_session_id']),
        ('motivation_measurement_runs', row['study_cycle_id']),
      ]) {
        final before = await _allRows(database);
        await expectLater(
          database.customStatement('DELETE FROM ${parent.$1} WHERE id = ?', [
            parent.$2,
          ]),
          throwsException,
        );
        expect(await _allRows(database), before, reason: parent.$1);
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        await database.customSelect('SELECT * FROM outbox_operations').get(),
        isEmpty,
      );
      expect(
        await database.customSelect('SELECT * FROM events_v2').get(),
        isEmpty,
      );
    },
  );

  test(
    'genuine v17 DDL retains every populated old table and pending command while assessment starts empty',
    () async {
      final schema = File(
        'test/fixtures/schema_v17.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        sha256.convert(utf8.encode(schema)).toString(),
        '1829afc95e6c6d1217123d3eda4532a96bafa2df613a4a5da6c63167cf167a0c',
      );
      expect(
        RegExp(r'^CREATE TABLE', multiLine: true).allMatches(schema),
        hasLength(34),
      );
      expect(schema, isNot(contains('assessment_runs')));
      expect(schema, contains('pending_presentation_change_json'));
      expect(schema, contains('accepted_plan_json'));
      final source = await OpportunityFixture.open(
        treatment: TodayExperiencePresentation.adventure,
      );
      late Map<String, List<Map<String, Object?>>> oldRows;
      late DeletionIntentToken token;
      late DateTime checkedAt;
      try {
        // These are real canonical synthetic facts on the current API, projected
        // to the genuine historical17 shape. They do not claim old-runtime
        // enrollment, historical production collection or continuing authority.
        await _populateOldFacts(source);
        checkedAt = source.participation.clock.now;
        token = await source.participation.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'delete:synthetic-assessment-v17-migration',
        );
        await source.participation.ownerWrites.markPending(token);
        oldRows = (await _allRows(source.database))..remove('assessment_runs');
        expect(oldRows, hasLength(34));
        for (final table in oldRows.entries) {
          expect(
            table.value,
            isNotEmpty,
            reason: 'Populate ${table.key} before retaining it',
          );
        }
      } finally {
        await source.database.close();
      }
      final before = <String, List<Map<String, Object?>>>{};
      final oldObjects = <String, String>{};
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory(
        tempRoot,
      ).createTemp('lexiquest-assessment-v17-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}historical.sqlite',
      );
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            for (final statement in schema.split(';')) {
              if (statement.trim().isNotEmpty) sqlite.execute(statement);
            }
            for (final table in oldRows.entries) {
              for (final row in table.value) {
                sqlite.execute(
                  'INSERT INTO "${table.key}" (${row.keys.join(',')}) '
                  'VALUES (${List.filled(row.length, '?').join(',')})',
                  row.values.toList(),
                );
              }
            }
            for (final object in sqlite.select(
              "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )) {
              oldObjects[object['name']! as String] = object['sql']! as String;
              if (object['type'] != 'table') continue;
              final name = object['name']! as String;
              before[name] = [
                for (final row in sqlite.select(
                  'SELECT * FROM "$name" ORDER BY rowid',
                ))
                  Map<String, Object?>.from(row),
              ];
            }
            sqlite.execute('PRAGMA user_version = 17');
          },
        ),
      );
      var closed = false;
      AppDatabase? reopened;
      addTearDown(() async {
        await reopened?.close();
        if (!closed) await database.close();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved.startsWith('$tempRoot${Platform.pathSeparator}'),
          isTrue,
          reason: 'Delete only this verified test-owned temp directory',
        );
        await Directory(resolved).delete(recursive: true);
      });
      expect(database.schemaVersion, 18);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        18,
      );
      expect(database.allTables, hasLength(35));
      expect(before, oldRows);
      final after = await _allRows(database);
      expect(
        after['assessment_runs'],
        isEmpty,
        reason:
            'A migration cannot fabricate Assessment runs, responses or grants',
      );
      expect(
        Map<String, List<Map<String, Object?>>>.of(after)
          ..remove('assessment_runs'),
        before,
      );
      final newObjects = await database
          .customSelect(
            "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final byName = {
        for (final row in newObjects)
          row.read<String>('name'): row.read<String>('sql'),
      };
      for (final object in oldObjects.entries) {
        expect(
          byName[object.key],
          object.value,
          reason: 'Do not rewrite old DDL ${object.key}',
        );
      }
      final pendingQuiz = after['learning_sessions']!.singleWhere(
        (row) => row['id'] == 'synthetic-retained-pending-quiz',
      );
      final plan = AcceptedQuizPlan.parse(
        id: pendingQuiz['accepted_plan_id']! as String,
        json: pendingQuiz['accepted_plan_json']! as String,
      );
      final checkpoint = QuizCheckpoint.parse(
        pendingQuiz['checkpoint_json']! as String,
        plan: plan,
      );
      expect(checkpoint, isA<PendingQuizAnswer>());
      expect(checkpoint.answer!.capturedOwnerId, 'owner-a');
      expect(
        checkpoint.assistance.hintFirstShownAtUtcMs,
        participationStart.millisecondsSinceEpoch + 10,
      );
      expect(
        checkpoint.assistance.revealRequestedAtUtcMs,
        participationStart.millisecondsSinceEpoch + 15,
      );
      final pendingOpportunity = after['measurement_opportunities']!
          .singleWhere((row) => row['owner_id'] == 'owner-a');
      expect(pendingOpportunity, hasLength(19));
      expect(pendingOpportunity['last_switch_ordinal'], 10);
      expect(pendingOpportunity['suppressed_switch_count'], 2);
      expect(pendingOpportunity['started_effective_presentation'], 'adventure');
      final receipt = PendingPresentationChange.fromJson(
        pendingOpportunity['pending_presentation_change_json']! as String,
      );
      expect(receipt.position, 13);
      expect(
        receipt.canonicalJson,
        pendingOpportunity['pending_presentation_change_json'],
      );
      expect(
        after['events_v2']!.where(
          (row) => row['event_type'] == measurementPresentationChangedEventType,
        ),
        hasLength(10),
      );
      expect(after['answer_attempts'], hasLength(1));
      expect(after['outbox_operations'], hasLength(3));
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final coordinator = DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => checkedAt,
      );
      final intent = (await coordinator.inspect())!;
      expect(intent.phase, DeletionIntentPhase.pendingCloud);
      expect(intent.casToken!.sameAttempt(token), isTrue);
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
      expect(await _allRows(database), after);
      await database.close();
      closed = true;
      final secondOpen = AppDatabase(NativeDatabase(file));
      reopened = secondOpen;
      expect(
        await _allRows(secondOpen),
        after,
        reason:
            'Reopen cannot reset accepted plans, pending receipts, signed rows or fence',
      );
      expect(
        await secondOpen.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

const _assessmentColumns = <String>{
  'id',
  'owner_id',
  'learning_session_id',
  'study_cycle_id',
  'phase',
  'state',
  'protocol_id',
  'protocol_version',
  'experiment_id',
  'experiment_version',
  'assignment_id',
  'cohort',
  'consent_version',
  'consent_decided_at_utc_ms',
  'instrument_id',
  'instrument_version',
  'form_id',
  'form_version',
  'instrument_checksum_sha256',
  'form_checksum_sha256',
  'app_version',
  'build_id',
  'database_schema_version',
  'content_revision',
  'evidence_policy_version',
  'feature_contract_revision',
  'feature_contract_hash',
  'started_at_utc_ms',
  'completed_at_utc_ms',
  'abandoned_at_utc_ms',
  'assignment_revision',
  'protocol_revision',
  'instrument_revision',
  'form_content_revision',
  'participation_permit_id',
  'participation_permit_revision',
  'participation_permit_payload_sha256',
};

const _integerColumns = <String>{
  'experiment_version',
  'consent_version',
  'consent_decided_at_utc_ms',
  'database_schema_version',
  'started_at_utc_ms',
  'completed_at_utc_ms',
  'abandoned_at_utc_ms',
  'assignment_revision',
  'protocol_revision',
  'instrument_revision',
  'form_content_revision',
  'participation_permit_revision',
};

Future<Map<String, Object?>> _assessmentRow(OpportunityFixture fixture) async {
  final run =
      (await fixture.database
              .customSelect(
                "SELECT * FROM motivation_measurement_runs WHERE owner_id = 'owner-a'",
              )
              .getSingle())
          .data;
  final permit = fixture.participation.current;
  return {
    'id': 'synthetic-assessment-storage-run',
    'owner_id': 'owner-a',
    'learning_session_id': 'synthetic-assessment-one',
    'study_cycle_id': run['id'],
    'phase': 'pre',
    'state': 'active',
    'protocol_id': run['protocol_id'],
    'protocol_version': run['protocol_version'],
    'experiment_id': 'synthetic-experiment',
    'experiment_version': 2,
    'assignment_id': permit.assignmentId,
    'cohort': permit.assignedTreatment.wireName,
    'consent_version': run['consent_version'],
    'consent_decided_at_utc_ms': run['consent_decided_at_utc_ms'],
    'instrument_id': 'synthetic-distinct-assessment',
    'instrument_version': 'synthetic-assessment-v1',
    'form_id': 'synthetic-assessment-form',
    'form_version': 'synthetic-form-v1',
    'instrument_checksum_sha256': 'a' * 64,
    'form_checksum_sha256': 'b' * 64,
    'app_version': 'synthetic-assessment',
    'build_id': 'storage-only',
    'database_schema_version': fixture.database.schemaVersion,
    'content_revision': 'synthetic-assessment-content-v1',
    'evidence_policy_version': 'learning-evidence-v1',
    'feature_contract_revision': 'synthetic-assessment-contract-v1',
    'feature_contract_hash': 'c' * 64,
    'started_at_utc_ms': participationStart
        .add(const Duration(minutes: 1))
        .millisecondsSinceEpoch,
    'completed_at_utc_ms': null,
    'abandoned_at_utc_ms': null,
    'assignment_revision': run['assignment_revision'],
    'protocol_revision': run['protocol_revision'],
    'instrument_revision': 19,
    'form_content_revision': 7,
    'participation_permit_id': permit.id,
    'participation_permit_revision': permit.localRevision,
    'participation_permit_payload_sha256': permit.payloadSha256,
  };
}

Future<void> _populateOldFacts(OpportunityFixture fixture) async {
  final pending = await fixture.accept(
    id: 'synthetic-retained-pending-quiz',
    at: participationStart,
  );
  final assistance = QuizAssistance()
      .showHint(participationStart.millisecondsSinceEpoch + 10)
      .hideHint()
      .withReveal(participationStart.millisecondsSinceEpoch + 15);
  fixture.participation.clock.now = participationStart.add(
    const Duration(milliseconds: 30),
  );
  await fixture.learning.saveQuizCheckpoint(
    sessionId: pending.sessionId,
    expectedOwnerId: 'owner-a',
    expectedRevision: pending.checkpointRevision,
    checkpoint: PendingQuizAnswer(
      planId: pending.plan.id,
      questionOrdinal: 0,
      assistance: assistance,
      answer: QuizAnswerReceipt.capture(
        plan: pending.plan,
        ownerId: 'owner-a',
        attemptId: 'synthetic-retained-unsubmitted-answer',
        questionOrdinal: 0,
        selectedOptionOrdinal: null,
        revealed: true,
        assistance: assistance,
        occurredAtUtcMs: participationStart.millisecondsSinceEpoch + 15,
        responseTimeMs: null,
      ),
    ),
  );
  await fixture.accept(
    id: 'synthetic-retained-history',
    at: participationStart.add(const Duration(milliseconds: 100)),
  );
  await fixture.finish(
    id: 'synthetic-retained-history',
    at: participationStart.add(const Duration(seconds: 1)),
  );
  await fixture.ready(at: participationStart.add(const Duration(minutes: 1)));
  await fixture.accept();
  for (var position = 1; position <= 13; position++) {
    fixture.participation.clock.now = fixture.participation.clock.now.add(
      const Duration(milliseconds: 1),
    );
    final current = (await fixture.repository.load(
      'owner-a',
      fixture.opportunityId,
    ))!;
    final prepared = await fixture.repository.preparePresentationChange(
      'owner-a',
      fixture.opportunityId,
      attemptId:
          '40000000-0000-4000-8000-${position.toString().padLeft(12, '0')}',
      expectedRevision: current.localRevision,
      target: oppositePresentation(current.currentPresentation),
      stillCurrent: () => true,
    );
    if (position == 13) break;
    fixture.participation.clock.now = fixture.participation.clock.now.add(
      const Duration(milliseconds: 1),
    );
    await fixture.repository.commitPresentationChange(
      'owner-a',
      fixture.opportunityId,
      receipt: prepared.pendingPresentationChange!,
      stillVisible: () => true,
    );
  }
  expect(await fixture.facts(), isNull);
  final targetAssignment = await seedOwnerAssignment(
    fixture.database,
    'owner-b',
  );
  final targetPermit = await insertOwnerParticipation(
    fixture.database,
    'owner-b',
    assignmentId: targetAssignment,
  );
  await fixture.database.customStatement(
    'INSERT INTO research_consents '
    '(id,owner_id,consent_version,consent_state,decided_at_utc_ms) '
    "VALUES ('synthetic-retained-other-consent', 'owner-b', 1, 'accepted', 1)",
  );
  final targetRun = await insertOwnerMotivationMeasurement(
    fixture.database,
    targetPermit,
  );
  await insertOwnerMeasurementOpportunity(
    fixture.database,
    permit: targetPermit,
    measurement: targetRun,
  );
  await _populateRemainingTables(fixture.database);
}

Future<void> _populateRemainingTables(AppDatabase database) async {
  // Historical synthetic storage rows exercise every old table. These never
  // call a downloader, upload, reward authority, Research admission or model.
  final rows = <String, Map<String, Object?>>{
    'vocabulary_imports': {
      'id': 'synthetic-retained-import',
      'owner_id': 'owner-a',
      'category_id': opportunityCategoryId,
      'source_type': 'csv',
      'source_name': 'synthetic.csv',
      'source_hash': 'synthetic-retained-source',
      'status': 'complete',
      'accepted_count': 1,
      'duplicate_count': 0,
      'rejected_count': 0,
      'created_at_utc_ms': 10,
      'completed_at_utc_ms': 11,
    },
    'vocabulary_import_rows': {
      'id': 'synthetic-retained-import-row',
      'import_id': 'synthetic-retained-import',
      'row_number': 1,
      'payload_hash': 'synthetic-retained-row',
      'status': 'accepted',
      'failure_code': null,
      'word_id': opportunityWordId,
    },
    'reading_progress_entries': {
      'id': 'synthetic-retained-reading',
      'owner_id': 'owner-a',
      'document_id': 'synthetic-document',
      'document_revision': 3,
      'last_position': 5,
      'is_completed': 0,
      'updated_at_utc_ms': 20,
    },
    'reading_events': {
      'id': 'synthetic-retained-reading-event',
      'owner_id': 'owner-a',
      'document_id': 'synthetic-document',
      'document_revision': 3,
      'event_type': 'position',
      'position': 5,
      'occurred_at_utc_ms': 20,
    },
    'points_ledger_entries': {
      'id': 'synthetic-retained-points',
      'owner_id': 'owner-a',
      'idempotency_key': 'synthetic-retained-points',
      'entry_type': 'quiz',
      'amount': 10,
      'source_event_id': 'synthetic-historical-source',
      'occurred_at_utc_ms': 20,
    },
    'reward_transactions': {
      'id': 'synthetic-retained-purchase',
      'owner_id': 'owner-a',
      'idempotency_key': 'synthetic-retained-purchase',
      'transaction_type': 'purchase',
      'amount': -10,
      'item_id': 'theme_ocean',
      'catalog_version': 1,
      'source_event_id': null,
      'occurred_at_utc_ms': 20,
    },
    'owned_reward_items': {
      'id': 'synthetic-retained-owned',
      'owner_id': 'owner-a',
      'item_id': 'theme_ocean',
      'catalog_version': 1,
      'acquired_by_transaction_id': 'synthetic-retained-purchase',
      'acquired_at_utc_ms': 20,
    },
    'equipped_reward_items': {
      'id': 'synthetic-retained-equipped',
      'owner_id': 'owner-a',
      'slot': 'theme',
      'item_id': 'theme_ocean',
      'equipped_at_utc_ms': 20,
    },
    'sync_checkpoints': {
      'id': 'synthetic-retained-sync-cursor',
      'owner_id': 'owner-a',
      'collection_name': 'words',
      'server_cursor': 'synthetic-cursor',
      'last_success_at_utc_ms': 20,
    },
    'sync_conflicts': {
      'id': 'synthetic-retained-sync-conflict',
      'owner_id': 'owner-a',
      'entity_type': 'word',
      'entity_id': opportunityWordId,
      'local_revision': 2,
      'cloud_revision': 3,
      'resolution_policy': 'cloudWins',
      'outcome': 'cloudApplied',
      'local_snapshot_json': '{}',
      'cloud_snapshot_json': '{}',
      'resolved_at_utc_ms': 20,
    },
    'quest_definitions': {
      'quest_id': 'synthetic-retained-quest',
      'catalog_version': 1,
      'title': 'Synthetic quest',
      'description': 'Synthetic retention only',
      'type': 'daily',
      'objectives_json': '[]',
      'reward_json': '{"xpAmount":10,"rewardItemId":null}',
      'expires_in_ms': null,
      'tags_json': '[]',
    },
    'quest_instances': {
      'instance_id': 'synthetic-retained-instance',
      'quest_id': 'synthetic-retained-quest',
      'owner_id': 'owner-a',
      'catalog_version': 1,
      'assigned_at_utc_ms': 20,
      'state': 'active',
      'completed_at_utc_ms': null,
      'expired_at_utc_ms': null,
    },
    'quest_objective_progress': {
      'id': 'synthetic-retained-objective',
      'instance_id': 'synthetic-retained-instance',
      'objective_id': 'synthetic-objective',
      'current_count': 1,
      'target_count': 3,
      'source_event_ids_json': '["synthetic-historical-source"]',
    },
    'association_records': {
      'id': 'synthetic-retained-association',
      'owner_id': 'owner-a',
      'word_key': 'station',
      'type': 'keyword',
      'content': 'synthetic association',
      'created_at_utc_ms': 20,
    },
    'associative_memory_states': {
      'id': 'synthetic-retained-associative-state',
      'owner_id': 'owner-a',
      'word_key': 'station',
      'stability': 2.5,
      'difficulty': 4.0,
      'cue_dependency': 0.25,
      'lapse_count': 1,
      'last_reviewed_at_utc_ms': 20,
      'next_due_at_utc_ms': 50,
      'algorithm_version': 'synthetic-v1',
    },
    'model_downloads': {
      'id': 'synthetic-retained-model',
      'model_version': 'synthetic-retained-v17',
      'source_url': 'synthetic:never-download',
      'expected_checksum': 'd' * 64,
      'expected_bytes': 100,
      'downloaded_bytes': 25,
      'retry_count': 1,
      'state': 'paused',
      'local_path': null,
      'failure_code': null,
      'updated_at_utc_ms': 20,
    },
  };
  for (final row in rows.entries) {
    await _insert(database, row.key, row.value);
  }
  if ((await database.customSelect('SELECT * FROM streak_states').get())
      .isEmpty) {
    await _insert(database, 'streak_states', {
      'owner_id': 'owner-a',
      'current_streak_days': 1,
      'longest_streak_days': 1,
      'freeze_count': 0,
      'last_learned_at_utc_ms': 20,
      'updated_at_utc_ms': 20,
    });
  }
  if ((await database.customSelect('SELECT * FROM learning_day_log').get())
      .isEmpty) {
    await _insert(database, 'learning_day_log', {
      'id': 'synthetic-retained-learning-day',
      'owner_id': 'owner-a',
      'learning_day': '2026-10-29',
      'first_session_at_utc_ms': 20,
    });
  }
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
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        Map<String, Object?>.from(row.data),
    ],
};
