import 'package:drift/drift.dart';

import 'identity_tables.dart';

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
