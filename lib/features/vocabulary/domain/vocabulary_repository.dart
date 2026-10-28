import 'vocabulary_category.dart';
import 'vocabulary_word.dart';

abstract interface class VocabularyRepository {
  Stream<List<VocabularyCategory>> watchCategories(String ownerId);

  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId);

  /// Returns all non-deleted words for [ownerId] across all categories.
  Future<List<VocabularyWord>> listAllWords(String ownerId);

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
