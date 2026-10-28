import 'package:cloud_firestore/cloud_firestore.dart';

class Word {
  final String? id;
  final String word;
  final String meaning;
  final String partOfSpeech;
  final String userId;
  final bool isGlobal;
  final DateTime createdAt;

  Word({
    this.id,
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.userId,
    required this.isGlobal,
    required this.createdAt,
  });

  // สร้าง Word object จาก Firestore Document
  factory Word.fromDocumentSnapshot(DocumentSnapshot doc) {
    return Word(
      id: doc.id,
      word: doc['word'],
      meaning: doc['meaning'],
      partOfSpeech: doc['part_of_speech'],
      userId: doc['user_id'],
      isGlobal: doc['is_global'],
      createdAt: (doc['created_at'] as Timestamp).toDate(),
    );
  }

  // แปลง Word object เป็น Map สำหรับบันทึกลง Firestore
  Map<String, dynamic> toMap() {
    return {
      'word': word,
      'meaning': meaning,
      'part_of_speech': partOfSpeech,
      'user_id': userId,
      'is_global': isGlobal,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}
