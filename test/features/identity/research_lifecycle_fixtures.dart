import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';

const researchLifecycleTables = [
  'motivation_measurement_runs',
  'motivation_responses',
  'research_participation_permits',
  'measurement_opportunities',
];

Future<void> insertLifecycleRow(
  AppDatabase database,
  String table,
  Map<String, Object?> values,
) => database.customStatement(
  'INSERT INTO $table (${values.keys.join(',')}) '
  'VALUES (${List.filled(values.length, '?').join(',')})',
  values.values.toList(),
);

Future<void> seedLifecycleOwner(
  AppDatabase database,
  String ownerId, {
  bool active = false,
  String? firebaseUid,
}) => insertLifecycleRow(database, 'local_owners', {
  'id': ownerId,
  'firebase_uid': firebaseUid,
  'account_state': firebaseUid == null ? 'localGuest' : 'firebaseBound',
  'is_active': active ? 1 : 0,
  'created_at_utc_ms': 1,
});

Future<void> seedLifecycleResearch(
  AppDatabase database,
  String ownerId, {
  bool run = true,
  bool response = true,
  bool permit = true,
  bool opportunity = true,
  bool deleted = false,
  bool withdrawn = false,
  bool reuseExistingConsent = false,
  String? existingLearningSessionId,
}) async {
  final decidedAt = reuseExistingConsent
      ? (await (database.select(database.researchConsents)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.consentVersion.equals(1),
                ))
                .getSingle())
            .decidedAtUtcMs
      : 1;
  final assignment = DriftExperimentAssignmentRepository.canonicalAssignmentId(
    ownerId: ownerId,
    experimentId: 'motivation',
    experimentVersion: 1,
  );
  await insertLifecycleRow(database, 'experiment_assignments', {
    'id': assignment,
    'owner_id': ownerId,
    'experiment_id': 'motivation',
    'experiment_version': 1,
    'cohort': 'adventure',
    'protocol_version': '1',
    'assigned_at_utc_ms': decidedAt,
  });
  if (!reuseExistingConsent) {
    await insertLifecycleRow(database, 'research_consents', {
      'id': 'consent:$ownerId',
      'owner_id': ownerId,
      'consent_version': 1,
      'consent_state': withdrawn ? 'withdrawn' : 'accepted',
      'decided_at_utc_ms': 1,
      'withdrawn_at_utc_ms': withdrawn ? 2 : null,
    });
  }
  if (run) {
    await insertLifecycleRow(database, 'motivation_measurement_runs', {
      'id': 'run:$ownerId',
      'owner_id': ownerId,
      'assignment_id': assignment,
      'consent_version': 1,
      'consent_decided_at_utc_ms': decidedAt,
      'protocol_id': 'motivation',
      'protocol_version': '1',
      'treatment': 'adventure',
      'instrument_id': 'fixture',
      'instrument_version': '1',
      'form_id': 'paired',
      'form_version': '1',
      'app_version': '1',
      'build_id': 'fixture',
      'database_schema_version': 24,
      'content_revision': '1',
      'evidence_policy_version': '1',
      'state': withdrawn ? 'withdrawn' : 'started',
      'started_at_utc_ms': decidedAt,
      'closed_at_utc_ms': withdrawn ? decidedAt + 4 : null,
      'is_deleted': deleted ? 1 : 0,
    });
  }
  if (response) {
    await insertLifecycleRow(database, 'motivation_responses', {
      'id': 'response:$ownerId',
      'owner_id': ownerId,
      'run_id': 'run:$ownerId',
      'item_id': 'baseline.interest',
      'item_catalog_version': '1',
      'response_code': 'agree',
      'ordinal_value': 3,
      'answered_at_utc_ms': decidedAt + 1,
      'is_deleted': deleted ? 1 : 0,
    });
  }
  if (permit) {
    await insertLifecycleRow(database, 'research_participation_permits', {
      'id': 'permit:$ownerId',
      'owner_id': ownerId,
      'assignment_id': assignment,
      'participant_class': 'minor',
      'age_band_code': 'adolescent',
      'assigned_treatment': 'adventure',
      'consent_receipt_id': 'private-consent:$ownerId',
      'guardian_permission_receipt_ref': 'private-guardian:$ownerId',
      'learner_assent_receipt_ref': 'private-assent:$ownerId',
      'protocol_id': 'motivation',
      'protocol_version': '1',
      'issued_at_utc_ms': decidedAt,
      'expires_at_utc_ms': decidedAt + 9999,
      'revoked_at_utc_ms': withdrawn ? decidedAt + 4 : null,
      'issuer_key_id': 'private-issuer',
      'payload_sha256': 'a' * 64,
      'signature': 'private-signature:$ownerId',
      'local_revision': 3,
      'cloud_revision': 2,
      'is_deleted': deleted ? 1 : 0,
    });
  }
  if (opportunity) {
    if (existingLearningSessionId == null) {
      await insertLifecycleRow(database, 'learning_sessions', {
        'id': 'session:$ownerId',
        'owner_id': ownerId,
        'activity_type': 'quiz',
        'started_at_utc_ms': decidedAt + 1,
        'ended_at_utc_ms': decidedAt + 3,
        'state': 'completed',
        'app_version': '1',
        'build_id': 'fixture',
      });
    }
    await insertLifecycleRow(database, 'measurement_opportunities', {
      'id': 'opportunity:$ownerId',
      'owner_id': ownerId,
      'measurement_run_id': 'run:$ownerId',
      'permit_id': 'permit:$ownerId',
      'entry_attempt_id': '11111111-1111-4111-8111-111111111111',
      'assigned_treatment': 'adventure',
      'effective_presentation': 'standard',
      'presented_event_id': 'event:presented:$ownerId',
      'learning_session_id': existingLearningSessionId ?? 'session:$ownerId',
      'started_event_id': 'event:start:$ownerId',
      'completed_event_id': 'event:complete:$ownerId',
      'last_switch_ordinal': 2,
      'suppressed_switch_count': 1,
      'opened_at_utc_ms': decidedAt + 1,
      'closed_at_utc_ms': decidedAt + 3,
      'is_deleted': deleted ? 1 : 0,
    });
  }
}

Future<List<Map<String, Object?>>> lifecycleRows(
  AppDatabase database,
  String table,
  String ownerId,
) async => [
  for (final row
      in await database
          .customSelect(
            'SELECT * FROM $table WHERE ${table == 'local_owners' ? 'id' : 'owner_id'} = ? ORDER BY 1',
            variables: [Variable<String>(ownerId)],
          )
          .get())
    Map<String, Object?>.from(row.data),
];

Future<Map<String, Object?>> lifecycleSnapshot(
  AppDatabase database,
  String ownerId,
) async => {
  for (final table in [
    'local_owners',
    'research_consents',
    'experiment_assignments',
    'learning_sessions',
    'outbox_operations',
    'sync_conflicts',
    ...researchLifecycleTables,
  ])
    table: await lifecycleRows(database, table, ownerId),
};
