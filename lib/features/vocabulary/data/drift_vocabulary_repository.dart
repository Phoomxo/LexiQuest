import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/vocabulary_category.dart';
import '../domain/vocabulary_failure.dart';
import '../domain/vocabulary_repository.dart';
import '../domain/vocabulary_word.dart';

final class DriftVocabularyRepository implements VocabularyRepository {
  DriftVocabularyRepository(this.database);

  static const int categoryWordLimit = 50;

  final db.AppDatabase database;

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
      return word.copyWith(localRevision: 1);
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
      return word.copyWith(
        localRevision: revision,
        updatedAtUtc: word.updatedAtUtc,
      );
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
    );
  }

  DateTime _fromEpoch(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  void _requireUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'timestamp', 'must be UTC');
    }
  }
}
