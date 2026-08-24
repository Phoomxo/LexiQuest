import 'package:drift/drift.dart';

import 'identity_tables.dart';

@DataClassName('SavedLearningItemRow')
class SavedLearningItems extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get contentType => text()();
  TextColumn get contentId => text()();
  IntColumn get contentRevision => integer()();
  IntColumn get savedAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAcknowledgedAtUtcMs => integer().nullable()();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, contentType, contentId, contentRevision},
  ];
}

/// Lifecycle reservation for f21. f20 intentionally provides no writer.
@DataClassName('ContentQualityReportRow')
class ContentQualityReports extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get contentType => text()();
  TextColumn get contentId => text()();
  IntColumn get contentRevision => integer()();
  TextColumn get reasonCode => text()();
  TextColumn get comment => text().nullable()();
  IntColumn get submittedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
