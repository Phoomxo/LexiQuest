import 'package:drift/drift.dart';

import 'identity_tables.dart';

class VocabularyCategories extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAcknowledgedAtUtcMs => integer().nullable()();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, normalizedName},
  ];
}

class VocabularyWords extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get categoryId => text().references(VocabularyCategories, #id)();
  TextColumn get spelling => text()();
  TextColumn get normalizedSpelling => text()();
  TextColumn get meaning => text()();
  TextColumn get normalizedMeaning => text()();
  TextColumn get partOfSpeech => text()();
  TextColumn get cefrLevel => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  BoolColumn get isGlobal => boolean().withDefault(const Constant(false))();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAcknowledgedAtUtcMs => integer().nullable()();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, categoryId, normalizedSpelling, normalizedMeaning},
  ];
}

class SavedWords extends Table {
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  TextColumn get wordId =>
      text().references(VocabularyWords, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isSaved => boolean()();
  IntColumn get localRevision => integer()();
  IntColumn get firstSavedAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();
  TextColumn get lastMutationId => text()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, wordId};

  @override
  List<String> get customConstraints => [
    "CHECK (typeof(local_revision) = 'integer' AND local_revision > 0)",
    "CHECK (typeof(first_saved_at_utc_ms) = 'integer' AND first_saved_at_utc_ms >= 0)",
    "CHECK (typeof(updated_at_utc_ms) = 'integer' AND updated_at_utc_ms >= 0)",
    'CHECK (length(CAST(last_mutation_id AS BLOB)) BETWEEN 1 AND 256 '
        'AND length(trim(last_mutation_id)) > 0)',
  ];
}

class VocabularyImports extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get categoryId => text().references(VocabularyCategories, #id)();
  TextColumn get sourceType => text()();
  TextColumn get sourceName => text()();
  TextColumn get sourceHash => text()();
  TextColumn get status => text()();
  IntColumn get acceptedCount => integer().withDefault(const Constant(0))();
  IntColumn get duplicateCount => integer().withDefault(const Constant(0))();
  IntColumn get rejectedCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get completedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, categoryId, sourceHash},
  ];
}

class VocabularyImportRows extends Table {
  TextColumn get id => text()();
  TextColumn get importId =>
      text().references(VocabularyImports, #id, onDelete: KeyAction.cascade)();
  IntColumn get rowNumber => integer()();
  TextColumn get payloadHash => text()();
  TextColumn get status => text()();
  TextColumn get failureCode => text().nullable()();
  TextColumn get wordId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {importId, rowNumber},
  ];
}
