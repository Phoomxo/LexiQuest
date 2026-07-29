class SentenceModel {
  final String sentence;
  final List<String> words;

  SentenceModel({required this.sentence, required this.words});

  factory SentenceModel.fromJson(String sentenceText) {
    List<String> words = sentenceText.split(" ");
    words.shuffle(); // ✅ สุ่มเรียงคำเพื่อใช้ในการลากวาง

    return SentenceModel(sentence: sentenceText, words: words);
  }
}
