import '../data/cefr_editorial_catalog.dart';
import '../data/cefr_vocabulary_catalog.dart';
import 'vocabulary_use_cases.dart' show normalizeVocabularyText;

/// Optional presentation support, never a lexical artifact or scoring authority.
abstract final class CefrPracticeExamples {
  static Future<CefrVocabularyCatalog>? _cached;
  static Future<CefrVocabularyCatalog> load() =>
      _cached ??= CefrVocabularyCatalog.load();

  static CefrEditorialEntry? resolve(
    CefrVocabularyCatalog catalog, {
    required String spelling,
    required String meaning,
    required String partOfSpeech,
    required String? cefrLevel,
  }) {
    final normalized = normalizeVocabularyText(spelling);
    final word = catalog.words
        .where((w) => normalizeVocabularyText(w.word) == normalized)
        .firstOrNull;
    final entry = word?.editorial;
    if (word == null ||
        entry == null ||
        word.cefrLevel != cefrLevel?.trim().toUpperCase() ||
        (entry.partOfSpeechOverride ?? word.partOfSpeech) !=
            partOfSpeech.trim().toLowerCase()) {
      return null;
    }
    final selected = normalizeVocabularyText(meaning);
    final index = entry.sourceMeaningIndex;
    if (selected != normalizeVocabularyText(entry.meaning) &&
        (index == null ||
            selected != normalizeVocabularyText(word.meanings[index]))) {
      return null;
    }
    return entry;
  }
}
