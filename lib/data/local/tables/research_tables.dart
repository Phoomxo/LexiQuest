import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'learning_tables.dart';

@DataClassName('ExperimentAssignmentRow')
class ExperimentAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get experimentId => text()();
  IntColumn get experimentVersion => integer()();
  TextColumn get cohort => text()();
  TextColumn get protocolVersion => text()();
  IntColumn get assignedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, experimentId, experimentVersion},
  ];
}

@DataClassName('AssessmentRunRow')
class AssessmentRuns extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get learningSessionId =>
      text().references(LearningSessions, #id)();
  TextColumn get studyCycleId => text()();
  TextColumn get phase => text()();
  TextColumn get state => text()();
  TextColumn get protocolId => text()();
  TextColumn get protocolVersion => text()();
  TextColumn get experimentId => text()();
  IntColumn get experimentVersion => integer()();
  TextColumn get assignmentId =>
      text().references(ExperimentAssignments, #id)();
  TextColumn get cohort => text()();
  IntColumn get consentVersion => integer()();
  IntColumn get consentDecidedAtUtcMs => integer()();
  TextColumn get instrumentId => text()();
  TextColumn get instrumentVersion => text()();
  TextColumn get formId => text()();
  TextColumn get formVersion => text()();
  TextColumn get instrumentChecksumSha256 => text()();
  TextColumn get formChecksumSha256 => text()();
  TextColumn get appVersion => text()();
  TextColumn get buildId => text()();
  IntColumn get databaseSchemaVersion => integer()();
  TextColumn get contentRevision => text()();
  TextColumn get evidencePolicyVersion => text()();
  TextColumn get featureContractRevision => text()();
  TextColumn get featureContractHash => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get completedAtUtcMs => integer().nullable()();
  IntColumn get abandonedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {learningSessionId},
    {ownerId, studyCycleId, phase},
  ];
}

/// Shared transport metadata; signed permit fields are preserved by their
/// repository when acknowledgements arrive.
abstract class ResearchOwnedRecord extends Table {
  TextColumn get id => text().withLength(min: 1, max: 128)();
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.cascade)();
  IntColumn get localRevision => integer().customConstraint(
    'NOT NULL DEFAULT 1 CHECK (local_revision > 0)',
  )();
  IntColumn get cloudRevision => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (cloud_revision >= 0)',
  )();
  IntColumn
  get lastAcknowledgedAtUtcMs => integer().nullable().customConstraint(
    'CHECK (last_acknowledged_at_utc_ms IS NULL OR last_acknowledged_at_utc_ms >= 0)',
  )();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable().customConstraint(
    'CHECK (server_updated_at_utc_ms IS NULL OR server_updated_at_utc_ms >= 0)',
  )();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MotivationMeasurementRunRow')
class MotivationMeasurementRuns extends ResearchOwnedRecord {
  TextColumn get assignmentId =>
      text().references(ExperimentAssignments, #id)();
  IntColumn get consentVersion => integer()();
  IntColumn get consentDecidedAtUtcMs => integer()();
  TextColumn get protocolId => text().withLength(min: 1, max: 128)();
  TextColumn get protocolVersion => text().withLength(min: 1, max: 128)();
  TextColumn get treatment => text()();
  TextColumn get instrumentId => text().withLength(min: 1, max: 128)();
  TextColumn get instrumentVersion => text().withLength(min: 1, max: 128)();
  TextColumn get formId => text().withLength(min: 1, max: 128)();
  TextColumn get formVersion => text().withLength(min: 1, max: 128)();
  TextColumn get appVersion => text().withLength(min: 1, max: 128)();
  TextColumn get buildId => text().withLength(min: 1, max: 128)();
  IntColumn get databaseSchemaVersion => integer()();
  TextColumn get contentRevision => text().withLength(min: 1, max: 128)();
  TextColumn get evidencePolicyVersion => text().withLength(min: 1, max: 128)();
  TextColumn get state => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get closedAtUtcMs => integer().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (consent_version > 0 AND consent_decided_at_utc_ms >= 0 AND database_schema_version > 0)',
    "CHECK (treatment IN ('standard', 'adventure'))",
    "CHECK (state IN ('started', 'completed', 'skipped', 'abandoned', 'withdrawn'))",
    'CHECK (started_at_utc_ms >= consent_decided_at_utc_ms)',
    "CHECK ((state = 'started' AND closed_at_utc_ms IS NULL) OR (state <> 'started' AND closed_at_utc_ms >= started_at_utc_ms AND closed_at_utc_ms IS NOT NULL))",
  ];
}

@DataClassName('MotivationResponseRow')
class MotivationResponses extends ResearchOwnedRecord {
  TextColumn get runId => text().references(
    MotivationMeasurementRuns,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get itemId => text().withLength(min: 1, max: 128)();
  TextColumn get itemCatalogVersion => text().withLength(min: 1, max: 128)();
  TextColumn get responseCode => text().withLength(min: 1, max: 128)();
  IntColumn get ordinalValue => integer().nullable()();
  IntColumn get answeredAtUtcMs => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, runId, itemId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (answered_at_utc_ms >= 0)',
    'CHECK (ordinal_value IS NULL OR ordinal_value BETWEEN 0 AND 100)',
  ];
}

@DataClassName('ResearchParticipationPermitRow')
class ResearchParticipationPermits extends ResearchOwnedRecord {
  TextColumn get participantClass => text()();
  TextColumn get ageBandCode => text().withLength(min: 1, max: 128)();
  TextColumn get assignmentId =>
      text().references(ExperimentAssignments, #id)();
  TextColumn get assignedTreatment => text()();
  TextColumn get consentReceiptId => text().withLength(min: 1, max: 128)();
  TextColumn get guardianPermissionReceiptRef =>
      text().withLength(min: 1, max: 128).nullable()();
  TextColumn get learnerAssentReceiptRef =>
      text().withLength(min: 1, max: 128).nullable()();
  TextColumn get protocolId => text().withLength(min: 1, max: 128)();
  TextColumn get protocolVersion => text().withLength(min: 1, max: 128)();
  IntColumn get issuedAtUtcMs => integer()();
  IntColumn get expiresAtUtcMs => integer()();
  IntColumn get revokedAtUtcMs => integer().nullable()();
  TextColumn get issuerKeyId => text().withLength(min: 1, max: 128)();
  TextColumn get payloadSha256 => text().withLength(min: 64, max: 64)();
  TextColumn get signature => text().withLength(min: 1, max: 256)();

  @override
  List<String> get customConstraints => [
    "CHECK (participant_class IN ('adult', 'minor'))",
    "CHECK (assigned_treatment IN ('standard', 'adventure'))",
    "CHECK (participant_class = 'adult' OR (guardian_permission_receipt_ref IS NOT NULL AND learner_assent_receipt_ref IS NOT NULL))",
    'CHECK (issued_at_utc_ms >= 0 AND expires_at_utc_ms > issued_at_utc_ms)',
    'CHECK (revoked_at_utc_ms IS NULL OR revoked_at_utc_ms >= issued_at_utc_ms)',
    "CHECK (length(payload_sha256) = 64 AND payload_sha256 NOT GLOB '*[^0-9a-f]*')",
  ];
}

@DataClassName('MeasurementOpportunityRow')
class MeasurementOpportunities extends ResearchOwnedRecord {
  TextColumn get measurementRunId => text().references(
    MotivationMeasurementRuns,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get permitId =>
      text().references(ResearchParticipationPermits, #id)();
  TextColumn get entryAttemptId => text().withLength(min: 36, max: 36)();
  TextColumn get assignedTreatment => text()();
  TextColumn get effectivePresentation => text()();
  TextColumn get presentedEventId => text().nullable()();
  TextColumn get learningSessionId =>
      text().references(LearningSessions, #id).nullable()();
  TextColumn get startedEventId => text().nullable()();
  TextColumn get completedEventId => text().nullable()();
  IntColumn get lastSwitchOrdinal => integer().withDefault(const Constant(0))();
  IntColumn get suppressedSwitchCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get openedAtUtcMs => integer()();
  IntColumn get closedAtUtcMs => integer().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, measurementRunId, permitId, entryAttemptId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (assigned_treatment IN ('standard', 'adventure'))",
    "CHECK (effective_presentation IN ('standard', 'adventure'))",
    'CHECK (last_switch_ordinal BETWEEN 0 AND 10 AND suppressed_switch_count >= 0)',
    'CHECK (opened_at_utc_ms >= 0 AND (closed_at_utc_ms IS NULL OR closed_at_utc_ms >= opened_at_utc_ms))',
    'CHECK (started_event_id IS NULL OR learning_session_id IS NOT NULL)',
    'CHECK (completed_event_id IS NULL OR (started_event_id IS NOT NULL AND closed_at_utc_ms IS NOT NULL))',
  ];
}
