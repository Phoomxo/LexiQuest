import 'package:drift/drift.dart';

class ModelDownloads extends Table {
  TextColumn get id => text()();
  TextColumn get modelVersion => text()();
  TextColumn get sourceUrl => text()();
  TextColumn get expectedChecksum => text()();
  IntColumn get expectedBytes => integer()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('notStarted'))();
  TextColumn get localPath => text().nullable()();
  TextColumn get failureCode => text().nullable()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {modelVersion},
  ];
}
