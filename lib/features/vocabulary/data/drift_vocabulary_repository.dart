import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../domain/vocabulary_category.dart';
import '../domain/vocabulary_failure.dart';
import '../domain/vocabulary_repository.dart';
import '../domain/vocabulary_word.dart';

final class DriftVocabularyRepository implements VocabularyRepository {
  DriftVocabularyRepository(this.database, {this.contentManifests});

  static const int categoryWordLimit = 50;

  final db.AppDatabase database;
  final ContentManifestRepository? contentManifests;

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) {
    final query = database.select(database.vocabularyCategories)
      ..where(
        (row) => row.ownerId.equals(ownerId) & row.isDeleted.equals(false),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.normalizedName),
      ]);
    return query.watch().map(
      (rows) => rows.map(_categoryToDomain).toList(growable: false),
    );
  }

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) {
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            row.ownerId.equals(ownerId) &
            row.categoryId.equals(categoryId) &
            row.isDeleted.equals(false),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.normalizedSpelling)]);
    return query.watch().map(
      (rows) => rows.map(_wordToDomain).toList(growable: false),
    );
  }

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async {
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) => row.ownerId.equals(ownerId) & row.isDeleted.equals(false),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.normalizedSpelling)]);
    final rows = await query.get();
    return rows.map(_wordToDomain).toList(growable: false);
  }

  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> wordIds) async {
    final ids = <String>[];
    final seen = <String>{};
    for (final rawId in wordIds) {
      if (!_isCanonicalId(rawId) || !seen.add(rawId)) {
        throw const VocabularyNotFoundFailure();
      }
      ids.add(rawId);
    }
    if (ids.isEmpty) return const <VocabularyWord>[];

    final rows = await (database.select(
      database.vocabularyWords,
    )..where((row) => row.id.isIn(ids) & row.isDeleted.equals(false))).get();
    final byId = <String, db.VocabularyWord>{
      for (final row in rows) row.id: row,
    };
    if (byId.length != ids.length || ids.any((id) => !byId.containsKey(id))) {
      throw const VocabularyNotFoundFailure();
    }
    final words = <VocabularyWord>[];
    for (final id in ids) {
      final core = _wordToDomain(byId[id]!);
      words.add(await _withVerifiedRichMetadata(core));
    }
    return List.unmodifiable(words);
  }

  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory category) async {
    _requireUtc(category.createdAtUtc);
    _requireUtc(category.updatedAtUtc);
    return database.transaction(() async {
      final existingById = await _categoryById(category.id);
      if (existingById != null) {
        if (existingById.ownerId == category.ownerId &&
            existingById.normalizedName == category.normalizedName &&
            !existingById.isDeleted) {
          return _categoryToDomain(existingById);
        }
        throw const DuplicateVocabularyFailure();
      }
      if (await _categoryNaturalKeyExists(
        category.ownerId,
        category.normalizedName,
      )) {
        throw const DuplicateVocabularyFailure();
      }

      await database
          .into(database.vocabularyCategories)
          .insert(
            db.VocabularyCategoriesCompanion.insert(
              id: category.id,
              ownerId: category.ownerId,
              name: category.name,
              normalizedName: category.normalizedName,
              sortOrder: Value(category.sortOrder),
              localRevision: const Value(1),
              createdAtUtcMs: category.createdAtUtc.millisecondsSinceEpoch,
              updatedAtUtcMs: category.updatedAtUtc.millisecondsSinceEpoch,
            ),
          );
      await _appendOutbox(
        entityType: 'category',
        entityId: category.id,
        ownerId: category.ownerId,
        operationKind: 'upsert',
        revision: 1,
        nowUtc: category.updatedAtUtc,
      );
      return category.copyWith(localRevision: 1);
    });
  }

  @override
  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required String normalizedName,
    required DateTime nowUtc,
  }) async {
    _requireUtc(nowUtc);
    return database.transaction(() async {
      final current = await _activeCategory(ownerId, categoryId);
      if (current == null) {
        throw const VocabularyNotFoundFailure();
      }
      final duplicate =
          await (database.select(database.vocabularyCategories)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.normalizedName.equals(normalizedName) &
                    row.id.equals(categoryId).not(),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        throw const DuplicateVocabularyFailure();
      }

      final revision = current.localRevision + 1;
      await (database.update(
        database.vocabularyCategories,
      )..where((row) => row.id.equals(categoryId))).write(
        db.VocabularyCategoriesCompanion(
          name: Value(name),
          normalizedName: Value(normalizedName),
          localRevision: Value(revision),
          updatedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
        ),
      );
      await _appendOutbox(
        entityType: 'category',
        entityId: categoryId,
        ownerId: ownerId,
        operationKind: 'upsert',
        revision: revision,
        nowUtc: nowUtc,
      );
      return _categoryToDomain(
        current.copyWith(
          name: name,
          normalizedName: normalizedName,
          localRevision: revision,
          updatedAtUtcMs: nowUtc.millisecondsSinceEpoch,
        ),
      );
    });
  }

  @override
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  }) async {
    _requireUtc(nowUtc);
    await database.transaction(() async {
      final current = await _activeCategory(ownerId, categoryId);
      if (current == null) {
        throw const VocabularyNotFoundFailure();
      }
      final revision = current.localRevision + 1;
      await (database.update(
        database.vocabularyCategories,
      )..where((row) => row.id.equals(categoryId))).write(
        db.VocabularyCategoriesCompanion(
          isDeleted: const Value(true),
          localRevision: Value(revision),
          updatedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
        ),
      );
      await (database.update(database.vocabularyWords)..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.categoryId.equals(categoryId) &
                row.isDeleted.equals(false),
          ))
          .write(
            db.VocabularyWordsCompanion(
              isDeleted: const Value(true),
              updatedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
            ),
          );
      await _appendOutbox(
        entityType: 'category',
        entityId: categoryId,
        ownerId: ownerId,
        operationKind: 'delete',
        revision: revision,
        nowUtc: nowUtc,
      );
    });
  }

  @override
  Future<VocabularyWord> createWord(VocabularyWord word) async {
    _requireUtc(word.createdAtUtc);
    _requireUtc(word.updatedAtUtc);
    return database.transaction(() async {
      if (await _activeCategory(word.ownerId, word.categoryId) == null) {
        throw const VocabularyNotFoundFailure();
      }
      final existingById = await _wordById(word.id);
      if (existingById != null) {
        if (existingById.ownerId == word.ownerId &&
            existingById.normalizedSpelling == word.normalizedSpelling &&
            existingById.normalizedMeaning == word.normalizedMeaning &&
            !existingById.isDeleted) {
          return _wordToDomain(existingById);
        }
        throw const DuplicateVocabularyFailure();
      }
      if (await _wordNaturalKeyExists(word)) {
        throw const DuplicateVocabularyFailure();
      }
      final activeCount = await _activeWordCount(word.ownerId, word.categoryId);
      if (activeCount >= categoryWordLimit) {
        throw const CategoryWordLimitFailure(categoryWordLimit);
      }

      await database
          .into(database.vocabularyWords)
          .insert(
            db.VocabularyWordsCompanion.insert(
              id: word.id,
              ownerId: word.ownerId,
              categoryId: word.categoryId,
              spelling: word.spelling,
              normalizedSpelling: word.normalizedSpelling,
              meaning: word.meaning,
              normalizedMeaning: word.normalizedMeaning,
              partOfSpeech: word.partOfSpeech,
              cefrLevel: Value(word.cefrLevel),
              source: Value(word.source),
              isGlobal: Value(word.isGlobal),
              contentRevision: const Value(1),
              contentChecksumSha256: Value(_contentChecksum(word)),
              contentProvenance: const Value('userAuthored'),
              contentReviewState: const Value('unreviewed'),
              contentPublicationState: const Value('private'),
              localRevision: const Value(1),
              createdAtUtcMs: word.createdAtUtc.millisecondsSinceEpoch,
              updatedAtUtcMs: word.updatedAtUtc.millisecondsSinceEpoch,
            ),
          );
      await _appendOutbox(
        entityType: 'word',
        entityId: word.id,
        ownerId: word.ownerId,
        operationKind: 'upsert',
        revision: 1,
        nowUtc: word.updatedAtUtc,
      );
      return _wordToDomain((await _wordById(word.id))!);
    });
  }

  @override
  Future<VocabularyWord> updateWord(VocabularyWord word) async {
    _requireUtc(word.updatedAtUtc);
    return database.transaction(() async {
      final current = await _activeWord(word.ownerId, word.id);
      if (current == null) {
        throw const VocabularyNotFoundFailure();
      }
      if (await _activeCategory(word.ownerId, word.categoryId) == null) {
        throw const VocabularyNotFoundFailure();
      }
      if (await _wordNaturalKeyExists(word, excludingId: word.id)) {
        throw const DuplicateVocabularyFailure();
      }
      final revision = current.localRevision + 1;
      final contentRevision = current.contentRevision + 1;
      await (database.update(
        database.vocabularyWords,
      )..where((row) => row.id.equals(word.id))).write(
        db.VocabularyWordsCompanion(
          categoryId: Value(word.categoryId),
          spelling: Value(word.spelling),
          normalizedSpelling: Value(word.normalizedSpelling),
          meaning: Value(word.meaning),
          normalizedMeaning: Value(word.normalizedMeaning),
          partOfSpeech: Value(word.partOfSpeech),
          cefrLevel: Value(word.cefrLevel),
          source: Value(word.source),
          isGlobal: Value(word.isGlobal),
          contentRevision: Value(contentRevision),
          contentChecksumSha256: Value(_contentChecksum(word)),
          contentProvenance: const Value('userAuthored'),
          contentReviewState: const Value('unreviewed'),
          contentPublicationState: const Value('private'),
          localRevision: Value(revision),
          updatedAtUtcMs: Value(word.updatedAtUtc.millisecondsSinceEpoch),
        ),
      );
      await _appendOutbox(
        entityType: 'word',
        entityId: word.id,
        ownerId: word.ownerId,
        operationKind: 'upsert',
        revision: revision,
        nowUtc: word.updatedAtUtc,
      );
      return _wordToDomain((await _wordById(word.id))!);
    });
  }

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) async {
    _requireUtc(nowUtc);
    await database.transaction(() async {
      final current = await _activeWord(ownerId, wordId);
      if (current == null) {
        throw const VocabularyNotFoundFailure();
      }
      final revision = current.localRevision + 1;
      await (database.update(
        database.vocabularyWords,
      )..where((row) => row.id.equals(wordId))).write(
        db.VocabularyWordsCompanion(
          isDeleted: const Value(true),
          localRevision: Value(revision),
          updatedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
        ),
      );
      await _appendOutbox(
        entityType: 'word',
        entityId: wordId,
        ownerId: ownerId,
        operationKind: 'delete',
        revision: revision,
        nowUtc: nowUtc,
      );
    });
  }

  Future<void> _appendOutbox({
    required String entityType,
    required String entityId,
    required String ownerId,
    required String operationKind,
    required int revision,
    required DateTime nowUtc,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: '$entityType:$entityId:$revision',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: operationKind,
            baseRevision: Value(revision - 1),
            createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<db.VocabularyCategory?> _categoryById(String categoryId) {
    return (database.select(
      database.vocabularyCategories,
    )..where((row) => row.id.equals(categoryId))).getSingleOrNull();
  }

  Future<db.VocabularyCategory?> _activeCategory(
    String ownerId,
    String categoryId,
  ) {
    return (database.select(database.vocabularyCategories)..where(
          (row) =>
              row.id.equals(categoryId) &
              row.ownerId.equals(ownerId) &
              row.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<bool> _categoryNaturalKeyExists(
    String ownerId,
    String normalizedName,
  ) async {
    final row =
        await (database.select(database.vocabularyCategories)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.normalizedName.equals(normalizedName),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<db.VocabularyWord?> _wordById(String wordId) {
    return (database.select(
      database.vocabularyWords,
    )..where((row) => row.id.equals(wordId))).getSingleOrNull();
  }

  Future<db.VocabularyWord?> _activeWord(String ownerId, String wordId) {
    return (database.select(database.vocabularyWords)..where(
          (row) =>
              row.id.equals(wordId) &
              row.ownerId.equals(ownerId) &
              row.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<bool> _wordNaturalKeyExists(
    VocabularyWord word, {
    String? excludingId,
  }) async {
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            row.ownerId.equals(word.ownerId) &
            row.categoryId.equals(word.categoryId) &
            row.normalizedSpelling.equals(word.normalizedSpelling) &
            row.normalizedMeaning.equals(word.normalizedMeaning) &
            (excludingId == null
                ? const Constant(true)
                : row.id.equals(excludingId).not()),
      );
    return await query.getSingleOrNull() != null;
  }

  Future<int> _activeWordCount(String ownerId, String categoryId) async {
    final count = database.vocabularyWords.id.count();
    final query = database.selectOnly(database.vocabularyWords)
      ..addColumns([count])
      ..where(
        database.vocabularyWords.ownerId.equals(ownerId) &
            database.vocabularyWords.categoryId.equals(categoryId) &
            database.vocabularyWords.isDeleted.equals(false),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  VocabularyCategory _categoryToDomain(db.VocabularyCategory row) {
    return VocabularyCategory(
      id: row.id,
      ownerId: row.ownerId,
      name: row.name,
      normalizedName: row.normalizedName,
      sortOrder: row.sortOrder,
      localRevision: row.localRevision,
      isDeleted: row.isDeleted,
      createdAtUtc: _fromEpoch(row.createdAtUtcMs),
      updatedAtUtc: _fromEpoch(row.updatedAtUtcMs),
    );
  }

  VocabularyWord _wordToDomain(db.VocabularyWord row) {
    return VocabularyWord(
      id: row.id,
      ownerId: row.ownerId,
      categoryId: row.categoryId,
      spelling: row.spelling,
      normalizedSpelling: row.normalizedSpelling,
      meaning: row.meaning,
      normalizedMeaning: row.normalizedMeaning,
      partOfSpeech: row.partOfSpeech,
      cefrLevel: row.cefrLevel,
      source: row.source,
      isGlobal: row.isGlobal,
      localRevision: row.localRevision,
      isDeleted: row.isDeleted,
      createdAtUtc: _fromEpoch(row.createdAtUtcMs),
      updatedAtUtc: _fromEpoch(row.updatedAtUtcMs),
      contentRevision: row.contentRevision,
      contentChecksumSha256: row.contentChecksumSha256,
      contentProvenance: _provenance(row.contentProvenance),
      contentReviewState: _reviewState(row.contentReviewState),
      contentPublicationState: _publicationState(row.contentPublicationState),
    );
  }

  Future<VocabularyWord> _withVerifiedRichMetadata(VocabularyWord core) async {
    final manifests = contentManifests;
    if (manifests == null || !_isRichMetadataEligible(core)) return core;
    final identity = ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: core.id,
      revision: core.contentRevision,
    );
    try {
      final verified = await manifests.requireVerified(identity);
      final manifest = verified.manifest;
      if (manifest.identity != identity ||
          manifest.provenance != ContentProvenance.packaged ||
          manifest.reviewState != ContentReviewState.approved ||
          manifest.publicationState != ContentPublicationState.published) {
        return core;
      }
      return core.copyWith(
        richMetadata: RichLexicalMetadata.fromVerifiedArtifact(
          bytes: verified.bytes,
          wordId: core.id,
          contentRevision: core.contentRevision,
          verifiedArtifactChecksumSha256: manifest.checksumSha256,
        ),
      );
    } on Object {
      // Rich metadata is optional presentation context. Any failed quality or
      // parse check quarantines only that optional artifact, never core words.
      return core;
    }
  }

  bool _isRichMetadataEligible(VocabularyWord word) {
    final checksum = word.contentChecksumSha256;
    return word.isGlobal &&
        word.contentRevision > 0 &&
        checksum != null &&
        word.contentProvenance == ContentProvenance.packaged &&
        word.contentReviewState == ContentReviewState.approved &&
        word.contentPublicationState == ContentPublicationState.published &&
        checksum == _contentChecksum(word);
  }

  ContentProvenance _provenance(String raw) => switch (raw) {
    'packaged' => ContentProvenance.packaged,
    _ => ContentProvenance.userAuthored,
  };

  ContentReviewState _reviewState(String raw) => switch (raw) {
    'approved' => ContentReviewState.approved,
    'rejected' => ContentReviewState.rejected,
    _ => ContentReviewState.unreviewed,
  };

  ContentPublicationState _publicationState(String raw) => switch (raw) {
    'published' => ContentPublicationState.published,
    'retired' => ContentPublicationState.retired,
    _ => ContentPublicationState.private,
  };

  DateTime _fromEpoch(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  String _contentChecksum(VocabularyWord word) =>
      ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: word.categoryId,
        spelling: word.spelling,
        normalizedSpelling: word.normalizedSpelling,
        meaning: word.meaning,
        normalizedMeaning: word.normalizedMeaning,
        partOfSpeech: word.partOfSpeech,
        cefrLevel: word.cefrLevel,
        source: word.source,
        isGlobal: word.isGlobal,
      );

  void _requireUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'timestamp', 'must be UTC');
    }
  }

  bool _isCanonicalId(String value) =>
      value.isNotEmpty && value == value.trim() && value.runes.length <= 256;
}
