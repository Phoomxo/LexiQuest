class Vocab {
  final String? id;
  final String word;
  final String meaning;
  final String partOfSpeech;
  final String uid; // เพิ่ม uid ของผู้ใช้

  Vocab({
    this.id,
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.uid,
  });

  // Factory method สำหรับสร้าง Vocab object จาก Map
  factory Vocab.fromMap(Map<String, dynamic> data, [String? id]) {
    return Vocab(
      id: id,
      word: data['word'] ?? '',
      meaning: data['meaning'] ?? '',
      partOfSpeech: data['part_of_speech'] ?? '',
      uid: data['uid'] ?? '',
    );
  }

  // แปลง Vocab object เป็น Map เพื่อบันทึกลง Firestore
  Map<String, dynamic> toMap() {
    return {
      'word': word,
      'meaning': meaning,
      'part_of_speech': partOfSpeech,
      'uid': uid, // บันทึก uid ของผู้ใช้
    };
  }
}
