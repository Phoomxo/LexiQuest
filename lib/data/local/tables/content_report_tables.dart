import 'package:drift/drift.dart';

import 'identity_tables.dart';

@DataClassName('ContentReportRow')
class ContentReports extends Table {
  TextColumn get id => text().withLength(min: 1, max: 256)();
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  TextColumn get reportJson => text()();
  TextColumn get reportSha256 => text().withLength(min: 64, max: 64)();
  IntColumn get queuedAtUtcMs => integer()();
  TextColumn get deliveryState =>
      text().withDefault(const Constant('queued'))();
  TextColumn get acknowledgementJson => text().nullable()();
  TextColumn get acknowledgedFirebaseUid => text().nullable()();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (length(CAST(report_json AS BLOB)) BETWEEN 1 AND 32768)',
    "CHECK (report_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (typeof(queued_at_utc_ms) = 'integer' AND queued_at_utc_ms BETWEEN 0 AND 8640000000000000)",
    "CHECK (delivery_state IN ('queued','unconfirmed','received'))",
    "CHECK ((delivery_state = 'received') = (acknowledgement_json IS NOT NULL))",
    'CHECK ((acknowledgement_json IS NOT NULL) = (acknowledged_firebase_uid IS NOT NULL))',
    'CHECK (acknowledgement_json IS NULL OR length(CAST(acknowledgement_json AS BLOB)) BETWEEN 1 AND 16384)',
    'CHECK (acknowledged_firebase_uid IS NULL OR length(trim(acknowledged_firebase_uid)) BETWEEN 1 AND 128)',
    "CHECK (typeof(local_revision) = 'integer' AND local_revision BETWEEN 1 AND 9007199254740991)",
  ];
}
