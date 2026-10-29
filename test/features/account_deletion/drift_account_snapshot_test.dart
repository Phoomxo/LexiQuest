import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/measurement_opportunity_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

void main() {
  late AppDatabase database;
  late SeededMotivationMeasurement measurementA;
  late SeededMeasurementOpportunity opportunityA;
  final now = DateTime.utc(2026, 10, 24, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement(
      "INSERT INTO local_owners "
      "(id, firebase_uid, account_state, is_active, created_at_utc_ms) "
      "VALUES ('owner-a', 'uid-a', 'registered', 1, 1), "
      "('owner-b', 'uid-b', 'registered', 0, 2)",
    );
    await database.customStatement(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, sort_order, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('cat-a', 'owner-a', 'A', 'a', 0, 0, 1, 1), "
      "('cat-b', 'owner-b', 'B', 'b', 0, 0, 1, 1)",
    );
    await database.customStatement(
      "INSERT INTO research_consents "
      "(id, owner_id, consent_version, consent_state, decided_at_utc_ms) "
      "VALUES ('consent-research-a', 'owner-a', 1, 'accepted', 1), "
      "('consent-research-b', 'owner-b', 1, 'accepted', 2)",
    );
    final assignmentA = await seedOwnerAssignment(database, 'owner-a');
    final assignmentB = await seedOwnerAssignment(database, 'owner-b');
    final permitA = await insertOwnerParticipation(
      database,
      'owner-a',
      assignmentId: assignmentA,
    );
    final permitB = await insertOwnerParticipation(
      database,
      'owner-b',
      assignmentId: assignmentB,
    );
    measurementA = await insertOwnerMotivationMeasurement(database, permitA);
    final measurementB = await insertOwnerMotivationMeasurement(
      database,
      permitB,
    );
    opportunityA = await insertOwnerMeasurementOpportunity(
      database,
      permit: permitA,
      measurement: measurementA,
    );
    await insertOwnerMeasurementOpportunity(
      database,
      permit: permitB,
      measurement: measurementB,
    );
    await database.customStatement('''
      INSERT INTO events_v2 (
        event_id, event_type, event_version, occurred_at_utc, recorded_at_utc,
        actor_identity, owner_id, aggregate_type, aggregate_id,
        idempotency_key, consent_context_json, app_version, build_id,
        privacy_classification, payload_json
      ) VALUES
        ('event-research-a', 'research.synthetic', 1, 1, 1,
         'owner-a', 'owner-a', 'research', 'study-a', 'research-key-a',
         '{"consentVersion":1}', '1', 'build', 'ownerOnly',
         '{"marker":"research-a"}'),
        ('event-research-b', 'research.synthetic', 1, 2, 2,
         'owner-b', 'owner-b', 'research', 'study-b', 'research-key-b',
         '{"consentVersion":1}', '1', 'build', 'ownerOnly',
         '{"marker":"research-b"}')
      ''');
    await database.customStatement(
      "INSERT INTO outbox_operations "
      "(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) "
      "VALUES ('outbox-research-a', 'owner-a', 'event_v2', "
      "'event-research-a', 'upsert', 1), "
      "('outbox-research-b', 'owner-b', 'event_v2', "
      "'event-research-b', 'upsert', 2)",
    );
  });

  tearDown(() => database.close());

  test(
    'covers every required local scope and isolates the requested owner',
    () async {
      final snapshot = await DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => now,
      ).build(ownerId: 'owner-a');

      expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
      expect(snapshot.sha256, sha256.convert(snapshot.bytes).toString());
      final json =
          jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
      expect(json['schemaVersion'], 18);
      expect(json['ownerId'], 'owner-a');
      final data = json['data'] as Map<String, dynamic>;
      expect(data.keys.toSet(), requiredFullAccountExportScopes);
      expect(data['assessment_runs'], isEmpty);
      expect((data['vocabulary_categories'] as List).single['id'], 'cat-a');
      final assignment = (data['experiment_assignments'] as List).single as Map;
      expect(assignment['owner_id'], 'owner-a');
      expect(assignment['experiment_id'], 'synthetic-study');
      expect(assignment['experiment_version'], 1);
      expect(assignment['cohort'], 'standard');
      expect(assignment['protocol_version'], 'synthetic-protocol-v1');
      expect(assignment['assigned_at_utc_ms'], 1);
      final permit =
          (data['research_participation_permits'] as List).single as Map;
      expect(permit, hasLength(20));
      expect(permit['owner_id'], 'owner-a');
      expect(permit['assignment_id'], assignment['id']);
      expect(permit['local_revision'], 1);
      expect(permit['cloud_revision'], 1);
      expect(permit['signature'], isNotEmpty);
      final run = (data['motivation_measurement_runs'] as List).single as Map;
      final response = (data['motivation_responses'] as List).single as Map;
      expect(run, hasLength(30));
      expect(response, hasLength(9));
      expect(run, measurementA.run);
      expect(response, measurementA.response);
      expect(run['permit_id'], permit['id']);
      expect(run['permit_payload_sha256'], permit['payload_sha256']);
      expect(response['run_id'], run['id']);
      expect(response['ordinal_value'], 100);
      final opportunity =
          (data['measurement_opportunities'] as List).single as Map;
      expect(opportunity, hasLength(19));
      expect(opportunity['last_switch_ordinal'], 0);
      expect(opportunity['suppressed_switch_count'], 0);
      expect(opportunity['started_effective_presentation'], isNull);
      expect(opportunity['pending_presentation_change_json'], isNull);
      expect(opportunity, opportunityA.opportunity);
      expect(opportunity['measurement_run_id'], run['id']);
      expect(opportunity['learning_session_id'], isNull);
      final events = data['events_v2'] as List;
      expect(events, hasLength(2));
      final presented =
          events.singleWhere((row) => row['event_id'] == opportunityA.eventId)
              as Map;
      expect(presented, hasLength(22));
      expect(presented, opportunityA.event);
      expect(jsonDecode(presented['payload_json'] as String), hasLength(4));
      expect(
        (data['research_consents'] as List).single['id'],
        'consent-research-a',
      );
      expect(
        events.singleWhere(
          (row) => row['event_id'] == 'event-research-a',
        )['event_id'],
        'event-research-a',
      );
      expect(
        (data['outbox_operations'] as List).single['operation_id'],
        'outbox-research-a',
      );
      final encoded = utf8.decode(snapshot.bytes);
      expect(encoded, contains('research-a'));
      expect(encoded, isNot(contains('research-b')));
      expect(encoded, isNot(contains('cat-b')));
      expect(encoded, isNot(contains('uid-b')));
      expect(encoded, isNot(contains('synthetic-permit:owner-b')));
    },
  );
}
