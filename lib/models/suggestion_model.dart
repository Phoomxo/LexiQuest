class SuggestedWord {
  final String word;
  final String meaning;
  final String partOfSpeech;

  SuggestedWord({
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
  });

  // แปลงเป็น JSON
  Map<String, dynamic> toMap() {
    return {'word': word, 'meaning': meaning, 'partOfSpeech': partOfSpeech};
  }

  // โหลดจาก JSON
  factory SuggestedWord.fromMap(Map<String, dynamic> map) {
    return SuggestedWord(
      word: map['word'],
      meaning: map['meaning'],
      partOfSpeech: map['partOfSpeech'],
    );
  }
}
