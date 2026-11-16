import '../data/cefr_vocabulary_catalog.dart';
import '../domain/vocabulary_failure.dart';
import '../domain/vocabulary_word.dart';
import 'vocabulary_use_cases.dart';

/// Adds a learner-selected sense through the existing private vocabulary API.
/// Catalog browsing itself never writes learning, research or reward evidence.
final class CefrCatalogImport {
  const CefrCatalogImport({required this.vocabulary, required this.catalog});
  final VocabularyUseCases vocabulary;
  final CefrVocabularyCatalog catalog;

  Future<VocabularyWord> add({
    required String wordId,
    required int meaningIndex,
    bool useEditorial = false,
    required String categoryId,
    required String expectedOwnerId,
    bool Function()? mutationAllowed,
  }) async {
    final entry = catalog.words.singleWhere((word) => word.id == wordId);
    if (entry.practiceUsageNotice != null) {
      throw StateError('This catalog entry is for recognition only');
    }
    final editorial = entry.editorial;
    if (!useEditorial &&
        (meaningIndex < 0 || meaningIndex >= entry.meanings.length)) {
      throw RangeError.index(meaningIndex, entry.meanings, 'meaningIndex');
    }
    if (!useEditorial &&
        !entry.selectableMeaningIndices.contains(meaningIndex)) {
      throw StateError('This source sense is not available for selection');
    }
    if (useEditorial && editorial == null) {
      throw StateError('This word has no curated sense');
    }
    final meaning = useEditorial
        ? editorial!.meaning
        : entry.meanings[meaningIndex];
    final sourceIndex = useEditorial
        ? editorial!.sourceMeaningIndex
        : meaningIndex;
    final source = sourceIndex == null
        ? 'cefr-editorial-r1/${entry.word}/${editorial!.senseKey}'
        : '${entry.importNamespace}/${entry.word}/$sourceIndex';
    Future<void> checkOwner() async {
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      if (owner.id != expectedOwnerId || mutationAllowed?.call() == false) {
        throw StateError('Catalog owner changed');
      }
    }

    await checkOwner();
    final categories = await vocabulary.watchCategories().first;
    if (!categories.any(
      (category) =>
          category.id == categoryId &&
          category.ownerId == expectedOwnerId &&
          !category.isReadOnly &&
          !category.isDeleted,
    )) {
      throw const VocabularyNotFoundFailure();
    }
    Future<VocabularyWord?> existing() async {
      final rows = await vocabulary.vocabulary.listAllWords(expectedOwnerId);
      return rows
          .where(
            (word) =>
                word.ownerId == expectedOwnerId &&
                word.categoryId == categoryId &&
                (word.source == source ||
                    (word.normalizedSpelling ==
                            normalizeVocabularyText(entry.word) &&
                        word.normalizedMeaning ==
                            normalizeVocabularyText(meaning))),
          )
          .firstOrNull;
    }

    final prior = await existing();
    await checkOwner();
    if (prior != null) return prior;
    try {
      return await vocabulary.createWord(
        CreateWordCommand(
          categoryId: categoryId,
          spelling: entry.word,
          meaning: meaning,
          partOfSpeech: useEditorial
              ? editorial!.partOfSpeechOverride ?? entry.partOfSpeech
              : entry.partOfSpeech,
          cefrLevel: entry.cefrLevel,
          source: source,
        ),
        expectedOwnerId: expectedOwnerId,
        mutationAllowed: mutationAllowed,
        enforceMutationAtCommit: true,
      );
    } on DuplicateVocabularyFailure {
      await checkOwner();
      final concurrent = await existing();
      await checkOwner();
      if (concurrent != null) return concurrent;
      rethrow;
    }
  }
}
