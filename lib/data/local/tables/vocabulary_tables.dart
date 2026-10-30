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

@DataClassName('WordReportRow')
class WordReports extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  TextColumn get wordId => text()();
  TextColumn get categoryId => text()();
  IntColumn get wordRevision => integer()();
  TextColumn get snapshotJson => text()();
  TextColumn get snapshotSha256 => text()();
  TextColumn get reason => text()();
  TextColumn get comment => text().nullable()();
  IntColumn get queuedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (substr(id, 1, 12) = 'word-report:' "
        'AND length(CAST(id AS BLOB)) BETWEEN 13 AND 256 '
        'AND length(trim(substr(id, 13))) > 0)',
    'CHECK (length(word_id) BETWEEN 1 AND 256 AND length(trim(word_id)) > 0)',
    'CHECK (length(category_id) BETWEEN 1 AND 256 AND length(trim(category_id)) > 0)',
    "CHECK (typeof(word_revision) = 'integer' AND word_revision > 0)",
    'CHECK (length(CAST(snapshot_json AS BLOB)) BETWEEN 1 AND 8192)',
    'CHECK (length(snapshot_sha256) = 64 '
        "AND snapshot_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (reason IN ('incorrectMeaning','spelling','partOfSpeech','inappropriate','other'))",
    'CHECK (comment IS NULL OR (length(comment) BETWEEN 1 AND 500 '
        'AND length(CAST(comment AS BLOB)) <= 2048 '
        'AND length(trim(comment)) > 0 AND comment = trim(comment)))',
    "CHECK (reason <> 'other' OR comment IS NOT NULL)",
    "CHECK (typeof(queued_at_utc_ms) = 'integer' "
        'AND queued_at_utc_ms BETWEEN 0 AND 8640000000000000)',
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
