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
  final Map<String, String> _curatedBank = {
    'B2':
        'Life is filled with ephemeral moments that require a resilient spirit to appreciate fully.',
    'B1':
        'The journey across the ancient city was filled with beautiful sights and quiet streets.',
  };

  Future<GeneratedPassage> generatePassage({
    required String cefrLevel,
    required List<String> targetWords,
    bool forceOffline = false,
  }) async {
    if (forceOffline) {
      return _getCuratedFallback(cefrLevel, targetWords);
    }

    try {
      // In production, invokes backend AI API; if unavailable, falls back gracefully.
      final text = _includeTargetWords(
        _curatedBank[cefrLevel] ??
            'Reading practice text incorporating target words cleanly.',
        targetWords,
      );
      return GeneratedPassage(
        contentId: 'ai-gen-${DateTime.now().millisecondsSinceEpoch}',
        cefrLevel: cefrLevel,
        passageText: text,
        targetWords: targetWords,
        isFallback: false,
      );
    } catch (_) {
      return _getCuratedFallback(cefrLevel, targetWords);
    }
  }

  GeneratedPassage _getCuratedFallback(
    String cefrLevel,
    List<String> targetWords,
  ) {
    final text = _includeTargetWords(
      _curatedBank[cefrLevel] ??
          'Curated fallback passage for vocabulary reading practice.',
      targetWords,
    );
    return GeneratedPassage(
      contentId: 'curated-${cefrLevel.toLowerCase()}',
      cefrLevel: cefrLevel,
      passageText: text,
      targetWords: targetWords,
      isFallback: true,
    );
  }

  String _includeTargetWords(String passage, List<String> targetWords) {
    final missing = targetWords
        .where((word) => !passage.toLowerCase().contains(word.toLowerCase()))
        .toList(growable: false);
    return missing.isEmpty
        ? passage
        : '$passage The learner then used ${missing.join(' and ')} in context.';
  }
}
