import '../domain/assessment_models.dart';

AssessmentRun decodeAssessmentRunRow(Map<String, Object?> row) => AssessmentRun(
  id: row['id']! as String,
  ownerId: row['owner_id']! as String,
  learningSessionId: row['learning_session_id']! as String,
  studyCycleId: row['study_cycle_id']! as String,
  phase: AssessmentPhase.values.byName(row['phase']! as String),
  state: AssessmentRunState.values.byName(row['state']! as String),
  protocolId: row['protocol_id']! as String,
  protocolVersion: row['protocol_version']! as String,
  protocolRevision: row['protocol_revision']! as int,
  experimentId: row['experiment_id']! as String,
  experimentVersion: row['experiment_version']! as int,
  assignmentId: row['assignment_id']! as String,
  assignmentRevision: row['assignment_revision']! as int,
  cohort: row['cohort']! as String,
  consentVersion: row['consent_version']! as int,
  consentDecidedAtUtc: _utc(row['consent_decided_at_utc_ms']),
  instrumentId: row['instrument_id']! as String,
  instrumentVersion: row['instrument_version']! as String,
  instrumentRevision: row['instrument_revision']! as int,
  formId: row['form_id']! as String,
  formVersion: row['form_version']! as String,
  formContentRevision: row['form_content_revision']! as int,
  participationPermitId: row['participation_permit_id']! as String,
  participationPermitRevision: row['participation_permit_revision']! as int,
  participationPermitPayloadSha256:
      row['participation_permit_payload_sha256']! as String,
  instrumentChecksumSha256: row['instrument_checksum_sha256']! as String,
  formChecksumSha256: row['form_checksum_sha256']! as String,
  appVersion: row['app_version']! as String,
  buildId: row['build_id']! as String,
  databaseSchemaVersion: row['database_schema_version']! as int,
  contentRevision: row['content_revision']! as String,
  evidencePolicyVersion: row['evidence_policy_version']! as String,
  featureContractRevision: row['feature_contract_revision']! as String,
  featureContractHash: row['feature_contract_hash']! as String,
  startedAtUtc: _utc(row['started_at_utc_ms']),
  completedAtUtc: row['completed_at_utc_ms'] == null
      ? null
      : _utc(row['completed_at_utc_ms']),
  abandonedAtUtc: row['abandoned_at_utc_ms'] == null
      ? null
      : _utc(row['abandoned_at_utc_ms']),
);

DateTime _utc(Object? value) {
  if (value is! int || value < 0 || value > 8640000000000000) {
    throw const FormatException('Invalid Assessment timestamp.');
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
