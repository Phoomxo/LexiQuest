import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuizService {
  final CollectionReference _quizCollection =
      FirebaseFirestore.instance.collection('quiz');

  /// บันทึกคำถามลง Firestore
  Future<void> saveQuestionToFirestore({
    required String word,
    required List<String> options,
    required String correctAnswer,
  }) async {
    await _quizCollection.add({
      'word': word,
      'options': options,
      'correctAnswer': correctAnswer,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// บันทึกคะแนนของผู้ใช้ลง Firestore
  Future<void> savePointsToFirestore(int points) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'points': points});
    }
  }

  /// สุ่มตัวเลือก
  List<String> shuffleOptions({
    required String correctAnswer,
    required List<String> allMeanings,
    int numberOfFakes = 3,
  }) {
    final fakeOptions = allMeanings
        .where((meaning) => meaning != correctAnswer)
        .toList()
      ..shuffle();
    final options = [correctAnswer, ...fakeOptions.take(numberOfFakes)];
    options.shuffle();
    return options;
  }

  /// ดึงคำศัพท์จาก Firestore และสร้างคำถามแบบสุ่ม
  Future<void> generateQuizQuestions(int numberOfQuestions) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not signed in');
      }

      // ดึงคำศัพท์ทั้งหมดจาก collection 'vocabulary'
      final querySnapshot = await FirebaseFirestore.instance
          .collection('vocabulary')
          .where('uid', isEqualTo: user.uid)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('No vocabulary found for the user.');
      }

      // สร้างรายการคำศัพท์จากเอกสารที่ดึงมา
      final vocabList = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'word': data['word'],
          'meaning': data['meaning'],
        };
      }).toList();

      // สุ่มเลือกคำถามจำนวนที่ต้องการ
      vocabList.shuffle();
      final selectedVocabList = vocabList.take(numberOfQuestions).toList();

      // สร้างคำถามและบันทึกลง Firestore
      for (var vocab in selectedVocabList) {
        final correctAnswer = vocab['meaning'] as String;
        final options = shuffleOptions(
          correctAnswer: correctAnswer,
          allMeanings: vocabList.map((v) => v['meaning'] as String).toList(),
          numberOfFakes: 3,
        );

        // บันทึกคำถามลง Firestore
        await saveQuestionToFirestore(
          word: vocab['word'] as String,
          options: options,
          correctAnswer: correctAnswer,
        );
      }

      print('Quiz questions generated and saved successfully.');
    } catch (e) {
      print('Failed to generate quiz questions: $e');
    }
  }
}
