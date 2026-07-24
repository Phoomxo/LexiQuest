class PhrasalVerb {
  final String phrase;
  final String cefrLevel;
  final String meaning;
  final String exampleSentence;

  const PhrasalVerb({
    required this.phrase,
    required this.cefrLevel,
    required this.meaning,
    required this.exampleSentence,
  });

  Map<String, dynamic> toJson() => {
    'phrase': phrase,
    'cefrLevel': cefrLevel,
    'meaning': meaning,
    'exampleSentence': exampleSentence,
  };

  factory PhrasalVerb.fromJson(Map<String, dynamic> json) => PhrasalVerb(
    phrase: json['phrase'] as String? ?? '',
    cefrLevel: json['cefrLevel'] as String? ?? 'B1',
    meaning: json['meaning'] as String? ?? '',
    exampleSentence: json['exampleSentence'] as String? ?? '',
  );
}
