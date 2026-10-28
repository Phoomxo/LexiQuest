import 'local_reading_catalog.dart';

class GeneratedPassage {
  final String contentId;
  final String cefrLevel;
  final String passageText;
  final List<String> targetWords;
  final bool isFallback;

  GeneratedPassage({
    required this.contentId,
    required this.cefrLevel,
    required this.passageText,
    required this.targetWords,
    this.isFallback = false,
  });
}

class AiReadingContentAdapter {
  Future<GeneratedPassage> generatePassage({
    required String cefrLevel,
    required List<String> targetWords,
    bool forceOffline = false,
  }) async {
    // This adapter has no remote provider. Connectivity cannot turn local
    // authored text into AI output; retain the parameter for API compatibility.
    return _getCuratedFallback(cefrLevel, targetWords);
  }

  GeneratedPassage _getCuratedFallback(
    String cefrLevel,
    List<String> targetWords,
  ) {
    final lesson = LocalReadingCatalog.forLevel(cefrLevel);
    final text = lesson.text;
    final tokens = RegExp(
      r"[a-z]+(?:'[a-z]+)?",
    ).allMatches(text.toLowerCase()).map((match) => match.group(0)!).toSet();
    return GeneratedPassage(
      contentId: lesson.id,
      cefrLevel: lesson.level,
      passageText: text,
      targetWords: targetWords
          .where((word) => tokens.contains(word.trim().toLowerCase()))
          .toSet()
          .toList(),
      isFallback: true,
    );
  }
}
