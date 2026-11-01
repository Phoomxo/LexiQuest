import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'vocabulary_tables.dart';

@DataClassName('LearningPackVersion')
class LearningPackVersions extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  TextColumn get packId => text()();
  TextColumn get packVersion => text()();
  TextColumn get manifestJson => text()();
  TextColumn get manifestSha256 => text()();
  TextColumn get packageSha256 => text()();
  IntColumn get packageByteCount => integer()();
  BlobColumn get packageBytes => blob().nullable()();
  TextColumn get retainedMediaJson => text()();
  TextColumn get retainedMediaSha256 => text()();
  TextColumn get sourceDescriptorJson => text()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  TextColumn get categoryId => text().nullable().references(
    VocabularyCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get importId => text().nullable().references(
    VocabularyImports,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get installedAtUtcMs => integer().nullable()();
  IntColumn get revision => integer()();
  TextColumn get lastMutationId => text()();
  TextColumn get lastMutationSha256 => text()();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, packId, packVersion, packageSha256},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (length(CAST(id AS BLOB)) BETWEEN 1 AND 256 AND length(trim(id)) > 0)',
    'CHECK (length(CAST(pack_id AS BLOB)) BETWEEN 1 AND 256 AND length(trim(pack_id)) > 0)',
    'CHECK (length(CAST(pack_version AS BLOB)) BETWEEN 1 AND 256 AND length(trim(pack_version)) > 0)',
    'CHECK (length(CAST(last_mutation_id AS BLOB)) BETWEEN 1 AND 256 AND length(trim(last_mutation_id)) > 0)',
    "CHECK (length(manifest_sha256) = 64 AND manifest_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(package_sha256) = 64 AND package_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(retained_media_sha256) = 64 AND retained_media_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(last_mutation_sha256) = 64 AND last_mutation_sha256 NOT GLOB '*[^0-9a-f]*')",
    'CHECK (length(CAST(manifest_json AS BLOB)) BETWEEN 1 AND 65536)',
    'CHECK (length(CAST(retained_media_json AS BLOB)) BETWEEN 1 AND 8388608)',
    'CHECK (length(CAST(source_descriptor_json AS BLOB)) BETWEEN 1 AND 4096)',
    "CHECK (typeof(package_byte_count) = 'integer' AND package_byte_count BETWEEN 1 AND 8388608)",
    "CHECK (package_bytes IS NULL OR (typeof(package_bytes) = 'blob' AND length(package_bytes) = package_byte_count))",
    'CHECK (is_pinned = 0 OR package_bytes IS NOT NULL)',
    'CHECK ((category_id IS NULL AND import_id IS NULL AND installed_at_utc_ms IS NULL) OR '
        '(category_id IS NOT NULL AND import_id IS NOT NULL AND installed_at_utc_ms IS NOT NULL))',
    "CHECK (typeof(revision) = 'integer' AND revision BETWEEN 1 AND 9007199254740991)",
    "CHECK (installed_at_utc_ms IS NULL OR (typeof(installed_at_utc_ms) = 'integer' AND installed_at_utc_ms BETWEEN 0 AND 8640000000000000))",
    "CHECK (typeof(created_at_utc_ms) = 'integer' AND created_at_utc_ms BETWEEN 0 AND 8640000000000000)",
    "CHECK (typeof(updated_at_utc_ms) = 'integer' AND updated_at_utc_ms BETWEEN 0 AND 8640000000000000)",
  ];
}

@DataClassName('LexicalContentSnapshot')
class LexicalContentSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  TextColumn get packVersionId => text().references(
    LearningPackVersions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get wordId =>
      text().references(VocabularyWords, #id, onDelete: KeyAction.restrict)();
  IntColumn get boundWordRevision => integer()();
  TextColumn get boundWordSha256 => text()();
  TextColumn get entryCode => text()();
  TextColumn get lexicalJson => text()();
  TextColumn get lexicalSha256 => text()();
  IntColumn get createdAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (length(CAST(id AS BLOB)) BETWEEN 1 AND 256 AND length(trim(id)) > 0)',
    'CHECK (length(CAST(entry_code AS BLOB)) BETWEEN 1 AND 256 AND length(trim(entry_code)) > 0)',
    "CHECK (length(bound_word_sha256) = 64 AND bound_word_sha256 NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(lexical_sha256) = 64 AND lexical_sha256 NOT GLOB '*[^0-9a-f]*')",
    'CHECK (length(CAST(lexical_json AS BLOB)) BETWEEN 1 AND 65536)',
    "CHECK (typeof(bound_word_revision) = 'integer' AND bound_word_revision BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(created_at_utc_ms) = 'integer' AND created_at_utc_ms BETWEEN 0 AND 8640000000000000)",
  ];
}
