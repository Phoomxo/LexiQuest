import 'package:drift/drift.dart';

@DataClassName('ContentManifestRow')
class ContentManifests extends Table {
  TextColumn get id => text()();
  TextColumn get contentType => text()();
  TextColumn get contentId => text()();
  IntColumn get revision => integer()();
  TextColumn get checksumSha256 => text()();
  IntColumn get byteLength => integer()();
  TextColumn get provenance => text()();
  TextColumn get sourceUri => text()();
  TextColumn get reviewState => text()();
  TextColumn get publicationState => text()();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get reviewedAtUtcMs => integer().nullable()();
  IntColumn get publishedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {contentType, contentId, revision},
  ];
}

@DataClassName('LearningPackRow')
class LearningPacks extends Table {
  TextColumn get id => text()();
  TextColumn get packId => text()();
  IntColumn get revision => integer()();
  TextColumn get manifestId => text().references(ContentManifests, #id)();
  TextColumn get title => text()();
  TextColumn get cefrLevel => text()();
  TextColumn get topic => text()();
  TextColumn get skill => text()();
  TextColumn get goal => text()();
  IntColumn get createdAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {packId, revision},
    {manifestId},
  ];
}

@DataClassName('LearningPackItemRow')
class LearningPackItems extends Table {
  TextColumn get id => text()();
  TextColumn get learningPackId =>
      text().references(LearningPacks, #id, onDelete: KeyAction.cascade)();
  TextColumn get vocabularyWordId => text()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {learningPackId, position},
    {learningPackId, vocabularyWordId},
  ];
}
