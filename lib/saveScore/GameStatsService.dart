import 'package:cloud_firestore/cloud_firestore.dart';

class GameStatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ฟังก์ชันบันทึก game_stats
  Future<void> saveGameStats({
    required String userId,
    required int score,
    required int correctAnswers,
    required int wrongAnswers,
    required int duration,
  }) async {
    try {
      // เพิ่มข้อมูลลงใน collection 'game_stats'
      await _firestore.collection('game_stats').add({
        'user_id': userId,
        'score': score,
        'correct_answers': correctAnswers,
        'wrong_answers': wrongAnswers,
        'duration': duration,
        'created_at': Timestamp.now(),
      });
      print('Game stats saved successfully!');
    } catch (e) {
      print('Error saving game stats: $e');
    }
  }
}
