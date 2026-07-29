class StorybookChapter {
  final String title;
  final String cefrLevel;
  final String contentText;
  final Map<String, String> vocabularyIpaMap;

  const StorybookChapter({
    required this.title,
    required this.cefrLevel,
    required this.contentText,
    required this.vocabularyIpaMap,
  });
}

/// Delivers Dual-Coding CEFR Interactive Storybook chapters with phonetic annotations (Mayer 2014).
class CefrInteractiveStorybookService {
  const CefrInteractiveStorybookService();

  static const List<StorybookChapter> _sampleChapters = [
    StorybookChapter(
      title: 'The Smart Journey',
      cefrLevel: 'A2',
      contentText:
          'Alex walked into the library to find a rare book about ancient discovery.',
      vocabularyIpaMap: {
        'library': '/ˈlaɪbrəri/',
        'discovery': '/dɪˈskʌvəri/',
        'ancient': '/ˈeɪnʃənt/',
      },
    ),
    StorybookChapter(
      title: 'Future Horizons',
      cefrLevel: 'B2',
      contentText:
          'Engineers analyze statistical models to optimize spaced repetition retention.',
      vocabularyIpaMap: {
        'analyze': '/ˈænəlaɪz/',
        'statistical': '/stəˈtɪstɪkl/',
        'retention': '/rɪˈtenʃn/',
      },
    ),
  ];

  /// Gets available storybook chapters filtered by CEFR level
  List<StorybookChapter> getChapters({String? level}) {
    if (level == null || level.isEmpty) return _sampleChapters;
    return _sampleChapters
        .where((ch) => ch.cefrLevel.toUpperCase() == level.toUpperCase())
        .toList();
  }

  /// Extracts annotated target words in a chapter text
  List<String> getAnnotatedWords(StorybookChapter chapter) {
    return chapter.vocabularyIpaMap.keys.toList();
  }
}
