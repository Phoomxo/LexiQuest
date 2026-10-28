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
