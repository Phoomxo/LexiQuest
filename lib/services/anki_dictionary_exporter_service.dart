import 'dart:convert';

class VocabularyCardExport {
  final String word;
  final String ipa;
  final String translation;
  final String exampleSentence;

  const VocabularyCardExport({
    required this.word,
    required this.ipa,
    required this.translation,
    required this.exampleSentence,
  });
}

/// Anki & JSON Dictionary Exporter Engine for LexiQuest.
class AnkiDictionaryExporterService {
  const AnkiDictionaryExporterService();

  /// Exports cards into Anki tab-delimited text format (Word \t IPA \t Translation \t Example)
  static String exportToAnkiTxt(List<VocabularyCardExport> cards) {
    if (cards.isEmpty) return '';
    final buffer = StringBuffer();
    for (final card in cards) {
      buffer.writeln(
        '${card.word}\t${card.ipa}\t${card.translation}\t${card.exampleSentence}',
      );
    }
    return buffer.toString();
  }

  /// Exports cards into standard JSON Dictionary Package format
  static String exportToJsonPackage(List<VocabularyCardExport> cards) {
    final list = cards
        .map(
          (c) => {
            'word': c.word,
            'ipa': c.ipa,
            'translation': c.translation,
            'exampleSentence': c.exampleSentence,
          },
        )
        .toList();

    return const JsonEncoder.withIndent('  ').convert({'cards': list});
  }
}
