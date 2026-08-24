import 'package:drift/drift.dart';

import 'content_tables.dart';

@DataClassName('ContentDownloadStateRow')
class ContentDownloadStates extends Table {
  TextColumn get id => text()();
  TextColumn get manifestId => text().references(ContentManifests, #id)();
  TextColumn get state => text().withDefault(const Constant('notDownloaded'))();
  TextColumn get localPath => text().nullable()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  TextColumn get verifiedChecksumSha256 => text().nullable()();
  TextColumn get failureCode => text().nullable()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {manifestId},
  ];
}
