class CefrWord {
  final String word;
  final String cefrLevel; // A1, A2, B1, B2, C1, C2
  final String meaning;
  final String partOfSpeech;
  final String exampleSentence;

  const CefrWord({
    required this.word,
    required this.cefrLevel,
    required this.meaning,
    required this.partOfSpeech,
    required this.exampleSentence,
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'cefrLevel': cefrLevel,
    'meaning': meaning,
    'partOfSpeech': partOfSpeech,
    'exampleSentence': exampleSentence,
  };

  factory CefrWord.fromJson(Map<String, dynamic> json) => CefrWord(
    word: json['word'] as String? ?? '',
    cefrLevel: json['cefrLevel'] as String? ?? 'A1',
    meaning: json['meaning'] as String? ?? '',
    partOfSpeech: json['partOfSpeech'] as String? ?? '',
    exampleSentence: json['exampleSentence'] as String? ?? '',
  );
}
