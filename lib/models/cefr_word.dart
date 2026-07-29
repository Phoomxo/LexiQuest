class CefrWord {
  final String word;
  final String cefrLevel; // A1, A2, B1, B2, C1, C2
  final String
  category; // Daily Life, Animals, Food, Travel, Work/Business, Academic, Science, Technology, Philosophy
  final String meaning;
  final String partOfSpeech;
  final String exampleSentence;
  final List<String> tags; // toeic, ielts, toefl, daily

  const CefrWord({
    required this.word,
    required this.cefrLevel,
    required this.category,
    required this.meaning,
    required this.partOfSpeech,
    required this.exampleSentence,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'cefrLevel': cefrLevel,
    'category': category,
    'meaning': meaning,
    'partOfSpeech': partOfSpeech,
    'exampleSentence': exampleSentence,
    'tags': tags,
  };

  factory CefrWord.fromJson(Map<String, dynamic> json) => CefrWord(
    word: json['word'] as String? ?? '',
    cefrLevel: json['cefrLevel'] as String? ?? 'A1',
    category: json['category'] as String? ?? 'General',
    meaning: json['meaning'] as String? ?? '',
    partOfSpeech: json['partOfSpeech'] as String? ?? '',
    exampleSentence: json['exampleSentence'] as String? ?? '',
    tags:
        (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        const [],
  );
}
