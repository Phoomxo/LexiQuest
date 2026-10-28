import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import 'motivation_measurement_fixture.dart';

final class SeededMeasurementOpportunity {
  SeededMeasurementOpportunity({
    required Map<String, Object?> opportunity,
    Map<String, Object?>? event,
  }) : opportunity = Map.unmodifiable(opportunity),
       event = event == null ? null : Map.unmodifiable(event);

  final Map<String, Object?> opportunity;
  final Map<String, Object?>? event;
  String get id => opportunity['id']! as String;
  String? get eventId => event?['event_id'] as String?;
}

// Historical synthetic facts only. No collection grant or learning row is created.
Future<SeededMeasurementOpportunity> insertOwnerMeasurementOpportunity(
  AppDatabase database, {
  required ResearchParticipationPermit permit,
  required SeededMotivationMeasurement measurement,
  bool presented = true,
  String entryAttemptId = '00000000-0000-4000-8000-000000000001',
  String? learningSessionId,
}) async {
  requireMeasurementEntryId(entryAttemptId);
  final run = measurement.run;
  if (run['owner_id'] != permit.ownerId ||
      run['permit_id'] != permit.id ||
      run['permit_payload_sha256'] != permit.payloadSha256 ||
      run['assignment_id'] != permit.assignmentId ||
      (!presented && learningSessionId != null)) {
    throw StateError('invalid synthetic opportunity pins');
  }
  final assignment = await database
      .customSelect(
        'SELECT * FROM experiment_assignments WHERE id = ? AND owner_id = ?',
        variables: [
          Variable<String>(permit.assignmentId),
          Variable<String>(permit.ownerId),
        ],
      )
      .getSingle();
  final id = measurementOpportunityId(
    ownerId: permit.ownerId,
    measurementRunId: measurement.runId,
    permitId: permit.id,
    entryAttemptId: entryAttemptId,
  );
  final openedMs = (run['started_at_utc_ms']! as int) + 1;
  final presentedMs = openedMs + 1;
  final occurred = DateTime.fromMillisecondsSinceEpoch(
    presentedMs,
    isUtc: true,
  );
  Map<String, Object?>? event;
  if (presented) {
    final identity = measurementPresentedIdentity(id);
    final payload = <String, Object?>{
      'assignedTreatment': permit.assignedTreatment.name,
      'effectivePresentation': permit.assignedTreatment.name,
      'entryAttemptId': entryAttemptId,
      'catalogVersion': run['catalog_version'],
    };
    validateMeasurementPresentedPayload(payload);
    final consent = ConsentContext(
      researchConsentVersion: run['consent_version']! as int,
      aiConsentGranted: false,
      voiceConsentGranted: false,
      socialConsentGranted: false,
    );
    final experiment = ExperimentContext(
      experimentId: assignment.read<String>('experiment_id'),
      variantId: assignment.read<String>('cohort'),
      assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        assignment.read<int>('assigned_at_utc_ms'),
        isUtc: true,
      ),
    );
    event = {
      'event_id': researchEventId(identity, occurred),
      'event_type': measurementPresentedEventType,
      'event_version': measurementPresentedEventVersion,
      'occurred_at_utc': presentedMs ~/ 1000,
      'recorded_at_utc': presentedMs ~/ 1000,
      'actor_identity': permit.ownerId,
      'owner_id': permit.ownerId,
      'tenant_context_json': null,
      'aggregate_type': 'MeasurementOpportunity',
      'aggregate_id': id,
      'correlation_id': id,
      'causation_id': null,
      'idempotency_key': identity,
      'consent_context_json': jsonEncode(consent.toJson()),
      'experiment_context_json': jsonEncode(experiment.toJson()),
      'content_revision': run['content_revision'],
      'policy_version': run['evidence_policy_version'],
      'app_version': run['app_version'],
      'build_id': run['build_id'],
      'provider_provenance_json': null,
      'privacy_classification': PrivacyClassification.ownerOnly.name,
      'payload_json': jsonEncode(payload),
    };
  }
  int? sessionStart;
  int? closedAt;
  if (learningSessionId != null) {
    final session = await database
        .customSelect(
          'SELECT * FROM learning_sessions WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(learningSessionId),
            Variable<String>(permit.ownerId),
          ],
        )
        .getSingle();
    sessionStart = session.read<int>('started_at_utc_ms');
    if (sessionStart < presentedMs) throw StateError('index precedes exposure');
    closedAt = session.readNullable<int>('ended_at_utc_ms');
  }
  final opportunity = <String, Object?>{
    'id': id,
    'owner_id': permit.ownerId,
    'local_revision': 1,
    'measurement_run_id': measurement.runId,
    'permit_id': permit.id,
    'entry_attempt_id': entryAttemptId,
    'assigned_treatment': permit.assignedTreatment.name,
    'effective_presentation': permit.assignedTreatment.name,
    'opened_at_utc_ms': openedMs,
    'presented_event_id': event?['event_id'],
    'presented_at_utc_ms': presented ? presentedMs : null,
    'learning_session_id': learningSessionId,
    'learning_session_started_at_utc_ms': sessionStart,
    'is_index_session': learningSessionId == null ? 0 : 1,
    'closed_at_utc_ms': closedAt,
  };
  final presentedEvent = event;
  await database.transaction(() async {
    if (presentedEvent != null) {
      await database.customStatement(
        'INSERT INTO events_v2 (${presentedEvent.keys.join(', ')}) '
        'VALUES (${List.filled(presentedEvent.length, '?').join(', ')})',
        presentedEvent.values.toList(),
      );
    }
    await database.customStatement(
      'INSERT INTO measurement_opportunities (${opportunity.keys.join(', ')}) '
      'VALUES (${List.filled(opportunity.length, '?').join(', ')})',
      opportunity.values.toList(),
    );
  });
  return SeededMeasurementOpportunity(opportunity: opportunity, event: event);
}
