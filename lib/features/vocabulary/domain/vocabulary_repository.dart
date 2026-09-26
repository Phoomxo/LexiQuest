import 'vocabulary_category.dart';
import 'vocabulary_word.dart';

abstract interface class VocabularyRepository {
  Stream<List<VocabularyCategory>> watchCategories(String ownerId);

  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId);

  /// Returns all non-deleted words for [ownerId] across all categories.
  Future<List<VocabularyWord>> listAllWords(String ownerId);

  /// Reads exactly the requested canonical word identities, in request order.
  /// Unknown, deleted, duplicate, or malformed identities fail closed.
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> wordIds);

  Future<VocabularyCategory> createCategory(VocabularyCategory category);

  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required String normalizedName,
    required DateTime nowUtc,
  });

  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  });

  Future<VocabularyWord> createWord(VocabularyWord word);

  Future<VocabularyWord> updateWord(VocabularyWord word);

  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  });
}

/// Atomically creates/reuses an owner category and word with canonical outbox.
abstract interface class AtomicVocabularyCreationRepository {
  Future<VocabularyWord> createOrReuseWordInCategory({
    required VocabularyCategory category,
    required VocabularyWord word,
    required bool Function() mutationAllowed,
  });
}

/// Optional transaction admission for an already selected private category.
/// Uses the same canonical word creation and rolls back its outbox with it.
abstract interface class GuardedVocabularyWordCreationRepository {
  Future<VocabularyWord> createWordWithAdmission({
    required VocabularyWord word,
    required bool Function() mutationAllowed,
    int? expectedCategoryRevision,
  });
}

/// Admission for the existing explicit category commands, within their canonical
/// transaction. Already committed mutations are never revoked.
abstract interface class GuardedVocabularyCategoryRepository {
  Future<VocabularyCategory> createCategoryWithAdmission({
    required VocabularyCategory category,
    required bool Function() mutationAllowed,
  });
  Future<void> deleteCategoryWithAdmission({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
    required bool Function() mutationAllowed,
  });
}

/// Optional lifetime/snapshot checks around the canonical word deletion.
abstract interface class GuardedVocabularyWordDeletionRepository {
  Future<void> deleteWordWithAdmission({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
    required bool Function() mutationAllowed,
    VocabularyWord? expectedWord,
    int? expectedCategoryRevision,
  });
}

/// Snapshot/lifetime admission around the existing canonical update transaction.
abstract interface class GuardedVocabularyWordUpdateRepository {
  Future<VocabularyWord> updateWordWithAdmission({
    required VocabularyWord word,
    required bool Function() mutationAllowed,
    VocabularyWord? expectedWord,
    int? expectedCategoryRevision,
  });
}
