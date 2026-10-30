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

import '../../support/measurement_opportunity_harness.dart';
import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test(
    'current schema retains an empty assessment table with all37 pinned fields',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      expect(database.schemaVersion, 19);
      expect(database.allTables, hasLength(36));
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
      expect(
        await database.customSelect('SELECT * FROM saved_words').get(),
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
      final row = await assessmentMigrationRow(fixture);
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
        final before = await ownerMigrationRows(database);
        await expectLater(
          insertOwnerMigrationRow(database, 'assessment_runs', invalid),
          throwsException,
        );
        expect(await ownerMigrationRows(database), before, reason: field);
      }
      await insertOwnerMigrationRow(database, 'assessment_runs', row);
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
        final before = await ownerMigrationRows(database);
        await expectLater(
          insertOwnerMigrationRow(database, 'assessment_runs', collision),
          throwsException,
        );
        expect(await ownerMigrationRows(database), before);
      }
      for (final parent in [
        ('learning_sessions', row['learning_session_id']),
        ('motivation_measurement_runs', row['study_cycle_id']),
      ]) {
        final before = await ownerMigrationRows(database);
        await expectLater(
          database.customStatement('DELETE FROM ${parent.$1} WHERE id = ?', [
            parent.$2,
          ]),
          throwsException,
        );
        expect(await ownerMigrationRows(database), before, reason: parent.$1);
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
        await populateOwnerMigrationFacts(source);
        checkedAt = source.participation.clock.now;
        token = await source.participation.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'delete:synthetic-assessment-v17-migration',
        );
        await source.participation.ownerWrites.markPending(token);
        oldRows = (await ownerMigrationRows(source.database))
          ..remove('assessment_runs')
          ..remove('saved_words');
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
      expect(database.schemaVersion, 19);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        19,
      );
      expect(database.allTables, hasLength(36));
      expect(before, oldRows);
      final after = await ownerMigrationRows(database);
      expect(
        after['assessment_runs'],
        isEmpty,
        reason:
            'A migration cannot fabricate Assessment runs, responses or grants',
      );
      expect(
        Map<String, List<Map<String, Object?>>>.of(after)
          ..remove('assessment_runs')
          ..remove('saved_words'),
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
      expect(await ownerMigrationRows(database), after);
      await database.close();
      closed = true;
      final secondOpen = AppDatabase(NativeDatabase(file));
      reopened = secondOpen;
      expect(
        await ownerMigrationRows(secondOpen),
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
