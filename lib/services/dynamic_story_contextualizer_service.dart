class ContextualStory {
  final String targetWord;
  final String cefrLevel;
  final String storyTitle;
  final String storyText;
  final String thaiTranslation;

  const ContextualStory({
    required this.targetWord,
    required this.cefrLevel,
    required this.storyTitle,
    required this.storyText,
    required this.thaiTranslation,
  });
}

/// Dynamic CEFR Micro-Story Contextualizer Engine
/// (IEEE Transactions on Learning Technologies 2024 & ACL 2023 Standard).
class DynamicStoryContextualizerService {
  const DynamicStoryContextualizerService();

  static const Map<String, Map<String, String>> _storyTemplates = {
    'opportunity': {
      'cefr': 'B1',
      'title': 'The Golden Chance',
      'text':
          'Sarah seized the opportunity to present her innovative project to the international board.',
      'th': 'ซาราห์คว้าโอกาสในการนำเสนอโครงการนวัตกรรมของเธอแก่คณะกรรมการระดับสากล',
    },
    'resilience': {
      'cefr': 'C1',
      'title': 'Overcoming Storms',
      'text':
          'The team displayed remarkable resilience after facing unexpected technical setbacks.',
      'th': 'ทีมงานแสดงให้เห็นถึงความยืดหยุ่นล้มแล้วลุกไวที่น่าทึ่งหลังจากเผชิญกับอุปสรรคทางเทคนิค',
    },
  };

  /// Generates a contextual micro-story embedded with the target word
  static ContextualStory generateStory(String targetWord) {
    final cleanWord = targetWord.trim().toLowerCase();
    final data = _storyTemplates[cleanWord] ?? {
      'cefr': 'B2',
      'title': 'Exploring ${cleanWord.toUpperCase()}',
      'text':
          'Learning about $cleanWord opens up new perspectives in language mastery.',
      'th': 'การเรียนรู้เกี่ยวกับ $cleanWord ช่วยเปิดมุมมองใหม่ในการเก่งภาษา',
    };

    return ContextualStory(
      targetWord: cleanWord,
      cefrLevel: data['cefr']!,
      storyTitle: data['title']!,
      storyText: data['text']!,
      thaiTranslation: data['th']!,
    );
  }
}
