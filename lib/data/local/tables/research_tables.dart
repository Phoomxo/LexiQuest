import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'event_tables.dart';
import 'learning_tables.dart';

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

@DataClassName('ResearchParticipationPermitRow')
class ResearchParticipationPermits extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
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
  Set<Column<Object>> get primaryKey => {id};

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

@DataClassName('MotivationMeasurementRunRow')
class MotivationMeasurementRuns extends Table {
  TextColumn get id => text().withLength(min: 1, max: 128)();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  TextColumn get permitId =>
      text().references(ResearchParticipationPermits, #id)();
  TextColumn get permitPayloadSha256 => text().withLength(min: 64, max: 64)();
  TextColumn get assignmentId =>
      text().references(ExperimentAssignments, #id)();
  IntColumn get assignmentRevision => integer()();
  IntColumn get consentVersion => integer()();
  IntColumn get consentDecidedAtUtcMs => integer()();
  TextColumn get protocolId => text().withLength(min: 1, max: 128)();
  TextColumn get protocolVersion => text().withLength(min: 1, max: 128)();
  IntColumn get protocolRevision => integer()();
  TextColumn get treatment => text()();
  TextColumn get instrumentId => text().withLength(min: 1, max: 128)();
  TextColumn get instrumentVersion => text().withLength(min: 1, max: 128)();
  IntColumn get instrumentRevision => integer()();
  TextColumn get instrumentChecksumSha256 =>
      text().withLength(min: 64, max: 64)();
  TextColumn get formId => text().withLength(min: 1, max: 128)();
  TextColumn get formVersion => text().withLength(min: 1, max: 128)();
  TextColumn get itemCatalogVersion => text().withLength(min: 1, max: 128)();
  TextColumn get scoringRuleVersion => text().withLength(min: 1, max: 128)();
  TextColumn get appVersion => text().withLength(min: 1, max: 128)();
  TextColumn get buildId => text().withLength(min: 1, max: 128)();
  IntColumn get databaseSchemaVersion => integer()();
  TextColumn get contentRevision => text().withLength(min: 1, max: 128)();
  TextColumn get evidencePolicyVersion => text().withLength(min: 1, max: 128)();
  TextColumn get catalogVersion => text().withLength(min: 1, max: 128)();
  TextColumn get state => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get closedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, assignmentId, protocolId, protocolVersion},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (local_revision > 0 AND assignment_revision > 0 AND protocol_revision > 0 AND instrument_revision > 0)',
    'CHECK (consent_version > 0 AND consent_decided_at_utc_ms >= 0 AND database_schema_version > 0)',
    "CHECK (length(permit_payload_sha256) = 64 AND permit_payload_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(instrument_checksum_sha256) = 64 AND instrument_checksum_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (treatment IN ('standard', 'adventure'))",
    "CHECK (scoring_rule_version = 'normalized-score-v1')",
    "CHECK (state IN ('started', 'completed', 'skipped', 'abandoned', 'withdrawn'))",
    'CHECK (started_at_utc_ms >= consent_decided_at_utc_ms)',
    "CHECK ((state = 'started' AND closed_at_utc_ms IS NULL) OR (state <> 'started' AND closed_at_utc_ms >= started_at_utc_ms AND closed_at_utc_ms IS NOT NULL))",
  ];
}

@DataClassName('AssessmentRunRow')
class AssessmentRuns extends Table {
  TextColumn get id => text().withLength(min: 1, max: 128)();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get learningSessionId =>
      text().references(LearningSessions, #id)();
  TextColumn get studyCycleId =>
      text().references(MotivationMeasurementRuns, #id)();
  TextColumn get phase => text()();
  TextColumn get state => text()();
  TextColumn get protocolId => text().withLength(min: 1, max: 128)();
  TextColumn get protocolVersion => text().withLength(min: 1, max: 128)();
  TextColumn get experimentId => text().withLength(min: 1, max: 128)();
  IntColumn get experimentVersion => integer()();
  TextColumn get assignmentId =>
      text().references(ExperimentAssignments, #id)();
  TextColumn get cohort => text()();
  IntColumn get consentVersion => integer()();
  IntColumn get consentDecidedAtUtcMs => integer()();
  TextColumn get instrumentId => text().withLength(min: 1, max: 128)();
  TextColumn get instrumentVersion => text().withLength(min: 1, max: 128)();
  TextColumn get formId => text().withLength(min: 1, max: 128)();
  TextColumn get formVersion => text().withLength(min: 1, max: 128)();
  TextColumn get instrumentChecksumSha256 =>
      text().withLength(min: 64, max: 64)();
  TextColumn get formChecksumSha256 => text().withLength(min: 64, max: 64)();
  TextColumn get appVersion => text().withLength(min: 1, max: 128)();
  TextColumn get buildId => text().withLength(min: 1, max: 128)();
  IntColumn get databaseSchemaVersion => integer()();
  TextColumn get contentRevision => text().withLength(min: 1, max: 128)();
  TextColumn get evidencePolicyVersion => text().withLength(min: 1, max: 128)();
  TextColumn get featureContractRevision =>
      text().withLength(min: 1, max: 128)();
  TextColumn get featureContractHash => text().withLength(min: 64, max: 64)();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get completedAtUtcMs => integer().nullable()();
  IntColumn get abandonedAtUtcMs => integer().nullable()();
  IntColumn get assignmentRevision => integer()();
  IntColumn get protocolRevision => integer()();
  IntColumn get instrumentRevision => integer()();
  IntColumn get formContentRevision => integer()();
  TextColumn get participationPermitId =>
      text().references(ResearchParticipationPermits, #id)();
  IntColumn get participationPermitRevision => integer()();
  TextColumn get participationPermitPayloadSha256 =>
      text().withLength(min: 64, max: 64)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {learningSessionId},
    {ownerId, studyCycleId, phase},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (phase IN ('pre', 'post'))",
    "CHECK (state IN ('active', 'completed', 'abandoned'))",
    "CHECK (cohort IN ('standard', 'adventure'))",
    'CHECK (experiment_version > 0 AND consent_version > 0 AND database_schema_version > 0 AND assignment_revision > 0 AND protocol_revision > 0 AND instrument_revision > 0 AND form_content_revision > 0 AND participation_permit_revision > 0)',
    'CHECK (consent_decided_at_utc_ms >= 0 AND started_at_utc_ms >= consent_decided_at_utc_ms)',
    "CHECK ((state = 'active' AND completed_at_utc_ms IS NULL AND abandoned_at_utc_ms IS NULL) OR (state = 'completed' AND completed_at_utc_ms IS NOT NULL AND completed_at_utc_ms >= started_at_utc_ms AND abandoned_at_utc_ms IS NULL) OR (state = 'abandoned' AND abandoned_at_utc_ms IS NOT NULL AND abandoned_at_utc_ms >= started_at_utc_ms AND completed_at_utc_ms IS NULL))",
    "CHECK (length(instrument_checksum_sha256) = 64 AND instrument_checksum_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(form_checksum_sha256) = 64 AND form_checksum_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(feature_contract_hash) = 64 AND feature_contract_hash NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(participation_permit_payload_sha256) = 64 AND participation_permit_payload_sha256 NOT GLOB '*[^0-9a-f]*')",
  ];
}

@DataClassName('MotivationResponseRow')
class MotivationResponses extends Table {
  TextColumn get id => text().withLength(min: 1, max: 128)();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  TextColumn get runId => text().references(
    MotivationMeasurementRuns,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get itemId => text().withLength(min: 1, max: 128)();
  TextColumn get itemCatalogVersion => text().withLength(min: 1, max: 128)();
  TextColumn get responseCode => text().withLength(min: 1, max: 128)();
  IntColumn get ordinalValue => integer()();
  IntColumn get answeredAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, runId, itemId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (local_revision > 0 AND answered_at_utc_ms >= 0)',
    'CHECK (ordinal_value BETWEEN 0 AND 100)',
  ];
}

@DataClassName('MeasurementOpportunityRow')
class MeasurementOpportunities extends Table {
  TextColumn get id => text().withLength(min: 1, max: 128)();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
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
  IntColumn get openedAtUtcMs => integer()();
  TextColumn get presentedEventId =>
      text().references(EventsV2, #eventId).nullable()();
  IntColumn get presentedAtUtcMs => integer().nullable()();
  TextColumn get learningSessionId =>
      text().references(LearningSessions, #id).nullable()();
  IntColumn get learningSessionStartedAtUtcMs => integer().nullable()();
  BoolColumn get isIndexSession =>
      boolean().withDefault(const Constant(false))();
  IntColumn get closedAtUtcMs => integer().nullable()();
  IntColumn get lastSwitchOrdinal => integer()
      .withDefault(const Constant(0))
      .check(
        const CustomExpression<bool>('last_switch_ordinal BETWEEN 0 AND 10'),
      )();
  IntColumn get suppressedSwitchCount => integer()
      .withDefault(const Constant(0))
      .check(
        const CustomExpression<bool>(
          'suppressed_switch_count >= 0 AND (suppressed_switch_count = 0 OR last_switch_ordinal = 10)',
        ),
      )();
  TextColumn get startedEffectivePresentation => text().nullable().check(
    const CustomExpression<bool>(
      "started_effective_presentation IS NULL OR started_effective_presentation IN ('standard', 'adventure')",
    ),
  )();
  TextColumn get pendingPresentationChangeJson => text().nullable().check(
    const CustomExpression<bool>(
      'pending_presentation_change_json IS NULL OR length(CAST(pending_presentation_change_json AS BLOB)) BETWEEN 2 AND 2048',
    ),
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, measurementRunId, permitId, entryAttemptId},
    {ownerId, learningSessionId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (local_revision > 0 AND opened_at_utc_ms >= 0)',
    "CHECK (assigned_treatment IN ('standard', 'adventure') AND effective_presentation IN ('standard', 'adventure'))",
    'CHECK ((presented_event_id IS NULL AND presented_at_utc_ms IS NULL) OR (presented_event_id IS NOT NULL AND presented_at_utc_ms IS NOT NULL AND presented_at_utc_ms >= opened_at_utc_ms))',
    'CHECK ((learning_session_id IS NULL AND learning_session_started_at_utc_ms IS NULL) OR (learning_session_id IS NOT NULL AND learning_session_started_at_utc_ms IS NOT NULL AND presented_event_id IS NOT NULL AND learning_session_started_at_utc_ms >= presented_at_utc_ms))',
    'CHECK (is_index_session = 0 OR learning_session_id IS NOT NULL)',
    'CHECK (closed_at_utc_ms IS NULL OR (closed_at_utc_ms >= opened_at_utc_ms AND (presented_at_utc_ms IS NULL OR closed_at_utc_ms >= presented_at_utc_ms) AND (learning_session_started_at_utc_ms IS NULL OR closed_at_utc_ms >= learning_session_started_at_utc_ms)))',
  ];
}
