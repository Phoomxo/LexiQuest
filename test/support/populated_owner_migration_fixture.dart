import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';

import 'experiment_assignment_fixture.dart';
import 'measurement_opportunity_fixture.dart';
import 'measurement_opportunity_harness.dart';
import 'motivation_measurement_fixture.dart';
import 'research_participation_fixture.dart';

Future<Map<String, Object?>> assessmentMigrationRow(
  OpportunityFixture fixture,
) async {
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

Future<void> populateOwnerMigrationFacts(OpportunityFixture fixture) async {
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
    await insertOwnerMigrationRow(database, row.key, row.value);
  }
  if ((await database.customSelect('SELECT * FROM streak_states').get())
      .isEmpty) {
    await insertOwnerMigrationRow(database, 'streak_states', {
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
    await insertOwnerMigrationRow(database, 'learning_day_log', {
      'id': 'synthetic-retained-learning-day',
      'owner_id': 'owner-a',
      'learning_day': '2026-10-29',
      'first_session_at_utc_ms': 20,
    });
  }
}

Future<void> insertOwnerMigrationRow(
  AppDatabase database,
  String table,
  Map<String, Object?> row,
) => database.customStatement(
  'INSERT INTO "$table" (${row.keys.join(',')}) '
  'VALUES (${List.filled(row.length, '?').join(',')})',
  row.values.toList(),
);

Future<Map<String, List<Map<String, Object?>>>> ownerMigrationRows(
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
