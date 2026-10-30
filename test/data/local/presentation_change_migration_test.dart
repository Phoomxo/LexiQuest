import 'dart:convert';
import 'dart:io';

import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';

import '../../support/measurement_opportunity_harness.dart';
import '../../support/research_participation_harness.dart'
    show ParticipationFixture;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  test(
    'fresh v18 has35 tables and retains the four bounded v17 opportunity fields',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      expect(database.schemaVersion, 20);
      final columns = await database
          .customSelect('PRAGMA table_info(measurement_opportunities)')
          .get();
      expect(database.allTables, hasLength(37));
      expect(
        await database.customSelect('SELECT * FROM word_reports').get(),
        isEmpty,
      );
      expect(columns, hasLength(19));
      final byName = {for (final row in columns) row.read<String>('name'): row};
      for (final name in ['last_switch_ordinal', 'suppressed_switch_count']) {
        expect(byName[name]?.read<String>('type'), 'INTEGER', reason: name);
        expect(byName[name]?.read<int>('notnull'), 1, reason: name);
        expect(byName[name]?.read<String>('dflt_value'), '0', reason: name);
      }
      for (final name in [
        'started_effective_presentation',
        'pending_presentation_change_json',
      ]) {
        expect(byName[name]?.read<String>('type'), 'TEXT', reason: name);
        expect(byName[name]?.read<int>('notnull'), 0, reason: name);
        expect(
          byName[name]?.readNullable<String>('dflt_value'),
          isNull,
          reason: name,
        );
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
  for (final startedKind in ['valid', 'missing', 'tampered', 'unlinked']) {
    test(
      'v16 DDL with $startedKind Started retains canonical synthetic facts and fences',
      () async {
        final schema = File('test/fixtures/schema_v16.sql').readAsStringSync();
        expect(
          RegExp(r'^CREATE TABLE', multiLine: true).allMatches(schema),
          hasLength(34),
        );
        expect(schema, contains('accepted_plan_json'));
        for (final column in _newColumns) {
          expect(schema, isNot(contains(column)));
        }
        final source = await OpportunityFixture.open(
          treatment: TodayExperiencePresentation.adventure,
        );
        late Map<String, List<Map<String, Object?>>> oldRows;
        late MotivationMeasurementRun historicalRun;
        late DeletionIntentToken token;
        late String opportunityId;
        String? indexId;
        late DateTime checkedAt;
        try {
          // The DDL is genuine v16. These facts are explicitly current canonical
          // synthetic data projected to its old columns, not a claim of collection
          // under a historical v16 runtime or of continuing collection permission.
          final pending = await source.accept(
            id: 'synthetic-pending-before-exposure',
            at: participationStart,
          );
          final assistance = QuizAssistance()
              .showHint(participationStart.millisecondsSinceEpoch + 10)
              .hideHint();
          await source.learning.saveQuizCheckpoint(
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
                attemptId: 'synthetic-unsubmitted-before-exposure',
                questionOrdinal: 0,
                selectedOptionOrdinal: 1,
                revealed: false,
                assistance: assistance,
                occurredAtUtcMs: participationStart.millisecondsSinceEpoch + 20,
                responseTimeMs: null,
              ),
            ),
          );
          await source.accept(
            id: 'synthetic-history-before-exposure',
            at: participationStart.add(const Duration(milliseconds: 100)),
          );
          await source.finish(
            id: 'synthetic-history-before-exposure',
            at: participationStart.add(const Duration(seconds: 1)),
          );
          final exposure = await source.ready(
            at: participationStart.add(const Duration(minutes: 1)),
          );
          opportunityId = exposure.id;
          if (startedKind != 'unlinked') {
            indexId = (await source.accept()).sessionId;
          }
          historicalRun = (await source.measurements.load(
            'owner-a',
            source.runId,
          ))!;
          checkedAt = source.participation.clock.now;
          token = await source.participation.ownerWrites.beginDeletion(
            ownerId: 'owner-a',
            firebaseUid: 'uid-a',
            idempotencyKey: 'synthetic-v16-ddl-migration-$startedKind',
          );
          await source.participation.ownerWrites.markPending(token);
          oldRows = await _allRows(source.database);
          expect(oldRows.remove('assessment_runs'), isEmpty);
          expect(oldRows.remove('saved_words'), isEmpty);
          expect(oldRows.remove('word_reports'), isEmpty);
          expect(oldRows, hasLength(34));
        } finally {
          await source.database.close();
        }
        for (final opportunity in oldRows['measurement_opportunities']!) {
          for (final name in _newColumns) {
            opportunity.remove(name);
          }
        }
        final startedRows = oldRows['events_v2']!
            .where(
              (row) => row['event_type'] == 'TodayExperienceMissionStarted',
            )
            .toList();
        if (startedKind == 'missing') {
          expect(startedRows, hasLength(1));
          oldRows['events_v2']!.remove(startedRows.single);
        } else if (startedKind == 'tampered') {
          expect(startedRows, hasLength(1));
          final payload = Map<String, dynamic>.from(
            jsonDecode(startedRows.single['payload_json']! as String) as Map,
          );
          payload['planId'] = 'quiz-plan:${'0' * 64}';
          startedRows.single['payload_json'] = jsonEncode(payload);
        }
        final before = <String, List<Map<String, Object?>>>{};
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-v16-migration-',
        );
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
              for (final table in sqlite.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
              )) {
                final name = table['name'] as String;
                before[name] = [
                  for (final row in sqlite.select(
                    'SELECT * FROM "$name" ORDER BY rowid',
                  ))
                    Map<String, Object?>.from(row),
                ];
              }
              sqlite.execute('PRAGMA user_version = 16');
            },
          ),
        );
        var closed = false;
        AppDatabase? reopened;
        addTearDown(() async {
          await reopened?.close();
          if (!closed) await database.close();
          await directory.delete(recursive: true);
        });
        expect(
          (await database.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          20,
        );
        expect(before, hasLength(34));
        expect(database.allTables, hasLength(37));
        expect(
          await database.customSelect('SELECT * FROM word_reports').get(),
          isEmpty,
        );
        final after = await _allRows(database);
        expect(after['assessment_runs'], isEmpty);
        expect(after['saved_words'], isEmpty);
        expect(after['word_reports'], isEmpty);
        for (final table in before.entries) {
          final retained = after[table.key]!.map((row) {
            final old = Map<String, Object?>.from(row);
            if (table.key == 'measurement_opportunities') {
              for (final name in _newColumns) {
                old.remove(name);
              }
            }
            return old;
          }).toList();
          expect(retained, table.value, reason: table.key);
        }
        final opportunity = after['measurement_opportunities']!.single;
        expect(opportunity['last_switch_ordinal'], 0);
        expect(opportunity['suppressed_switch_count'], 0);
        expect(opportunity['pending_presentation_change_json'], isNull);
        expect(
          opportunity['started_effective_presentation'],
          startedKind == 'unlinked' ? null : 'adventure',
        );
        expect(
          after['events_v2'],
          before['events_v2'],
          reason:
              'Backfill must not create or repair a missing/tampered Started',
        );
        final pendingRow = after['learning_sessions']!.singleWhere(
          (row) => row['id'] == 'synthetic-pending-before-exposure',
        );
        final plan = AcceptedQuizPlan.parse(
          id: pendingRow['accepted_plan_id']! as String,
          json: pendingRow['accepted_plan_json']! as String,
        );
        final checkpoint = QuizCheckpoint.parse(
          pendingRow['checkpoint_json']! as String,
          plan: plan,
        );
        expect(checkpoint, isA<PendingQuizAnswer>());
        expect(checkpoint.answer!.capturedOwnerId, 'owner-a');
        expect(
          checkpoint.assistance.hintFirstShownAtUtcMs,
          participationStart.millisecondsSinceEpoch + 10,
        );
        expect(after['answer_attempts'], hasLength(1));
        expect(after['outbox_operations'], hasLength(3));
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );

        // Inspect historical facts only. No admission/import or fresh collection.
        final participant = await ParticipationFixture.open(
          database: database,
          seed: false,
        );
        final timing = DriftMotivationMeasurementTimingReader(database);
        final measurements = DriftMotivationMeasurementRepository(
          database,
          participation: participant.repository,
          timing: timing,
          consentNowUtc: () => checkedAt,
        );
        final opportunities = DriftMeasurementOpportunityRepository(
          database,
          measurements: measurements,
          timing: timing,
        );
        final migratedOpportunity = (await opportunities.load(
          'owner-a',
          opportunityId,
        ))!;
        if (indexId != null) {
          final recovered =
              await DriftLearningRepository(
                database,
                ownerWrites: participant.ownerWrites,
              ).inspectConfiguredQuiz(
                sessionId: indexId,
                expectedOwnerId: 'owner-a',
              );
          final proof = opportunities.inspectIndexFacts(
            run: historicalRun,
            opportunity: migratedOpportunity,
            index: recovered,
            nowUtc: checkedAt,
          );
          if (startedKind == 'valid') {
            expect(
              await proof,
              isFalse,
              reason:
                  'Valid active Started passed full proof; no completion yet',
            );
          } else {
            await expectLater(proof, throwsA(isA<ResearchCaptureDenied>()));
          }
        } else {
          expect(migratedOpportunity.indexLink, isNull);
          expect(
            after['events_v2']!.where(
              (row) => row['event_type'] == 'TodayExperienceMissionStarted',
            ),
            isEmpty,
          );
        }
        final coordinator = DriftOwnerWriteCoordinator(
          database,
          nowUtc: () => checkedAt,
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
        expect(
          await _allRows(database),
          after,
          reason: 'Historical proof checking cannot mutate old or new facts',
        );
        await database.close();
        closed = true;
        final secondOpen = AppDatabase(NativeDatabase(file));
        reopened = secondOpen;
        expect(
          await _allRows(secondOpen),
          after,
          reason: 'A second open cannot reset counters, pins, events or fence',
        );
      },
    );
  }
}

const _newColumns = {
  'last_switch_ordinal',
  'suppressed_switch_count',
  'started_effective_presentation',
  'pending_presentation_change_json',
};

Future<Map<String, List<Map<String, Object?>>>> _allRows(
  AppDatabase database,
) async {
  final rows = <String, List<Map<String, Object?>>>{};
  for (final table in database.allTables) {
    rows[table.actualTableName] = [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        Map<String, Object?>.from(row.data),
    ];
  }
  return rows;
}
