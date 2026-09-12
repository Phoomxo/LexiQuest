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
  // Cross-row guards accept canonical sessions or an exact historical proof.
  TextColumn get learningSessionId => text().nullable()();
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

/// Historical transport mirror only. Importing this record creates no playable
/// session, checkpoint, answer or reward authority.
@DataClassName('ResearchSessionProofRow')
class ResearchSessionProofs extends ResearchOwnedRecord {
  TextColumn get measurementRunId =>
      text().references(MotivationMeasurementRuns, #id)();
  TextColumn get permitId =>
      text().references(ResearchParticipationPermits, #id)();
  TextColumn get learningSessionId => text().withLength(min: 1, max: 128)();
  IntColumn get proofRevision => integer()();
  TextColumn get activityType => text().withLength(min: 1, max: 128)();
  TextColumn get sessionState => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get endedAtUtcMs => integer().nullable()();
  TextColumn get appVersion => text().withLength(min: 1, max: 128)();
  TextColumn get buildId => text().withLength(min: 1, max: 128)();
  TextColumn get sessionConfigurationIdentity => text().nullable()();
  TextColumn get sessionConfigurationJson => text().nullable()();
  TextColumn get pairStartOperation => text().nullable()();
  IntColumn get pairCheckpointEventVersion => integer().nullable()();
  TextColumn get pairOwnerLineageJson => text().nullable()();
  TextColumn get permitPayloadSha256 => text()();
  IntColumn get permitRevision => integer()();

  // The phase tuple is enforced by the single named v26 unique index.
  @override
  List<String> get customConstraints => [
    "CHECK (typeof(proof_revision) = 'integer' AND proof_revision IN (1, 2))",
    "CHECK (typeof(started_at_utc_ms) = 'integer' AND started_at_utc_ms >= 0)",
    "CHECK ((proof_revision = 1 AND session_state = 'active' AND ended_at_utc_ms IS NULL) OR (proof_revision = 2 AND session_state = 'completed' AND ended_at_utc_ms IS NOT NULL AND typeof(ended_at_utc_ms) = 'integer' AND ended_at_utc_ms >= started_at_utc_ms))",
    'CHECK ((session_configuration_identity IS NULL AND session_configuration_json IS NULL) OR (session_configuration_identity IS NOT NULL AND session_configuration_json IS NOT NULL))',
    "CHECK ((activity_type = 'matching' AND pair_start_operation IS NOT NULL AND pair_checkpoint_event_version IS NOT NULL AND typeof(pair_checkpoint_event_version) = 'integer' AND pair_checkpoint_event_version IN (1, 2) AND pair_owner_lineage_json IS NOT NULL) OR (activity_type <> 'matching' AND pair_start_operation IS NULL AND pair_checkpoint_event_version IS NULL AND pair_owner_lineage_json IS NULL))",
    "CHECK (typeof(permit_payload_sha256) = 'text' AND length(permit_payload_sha256) = 64 AND instr(permit_payload_sha256, char(0)) = 0 AND permit_payload_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (typeof(permit_revision) = 'integer' AND permit_revision > 0)",
  ];
}
