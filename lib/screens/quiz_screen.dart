import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'score_screen.dart';
import 'SpeakToTextScreen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuizScreen extends StatefulWidget {
  final List<Map<String, dynamic>> vocabList;
  final String? selectedCategoryId;

  QuizScreen({required this.vocabList, this.selectedCategoryId});

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int currentQuestionIndex = 0;
  int correctAnswers = 0;
  bool isAnswered = false;
  bool isCorrect = false;
  List<String> shuffledOptions = [];
  int userPoints = 0; // แต้มของผู้ใช้

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _initializeOptions();
  }

  void _initializeOptions() {
    final currentQuestion = widget.vocabList[currentQuestionIndex];
    final correctAnswer = currentQuestion['meaning'];

    final fakeOptions = widget.vocabList
        .where((vocab) => vocab['meaning'] != correctAnswer)
        .map((vocab) => vocab['meaning'])
        .toList()
      ..shuffle();

    shuffledOptions = [correctAnswer, ...fakeOptions.take(3)]..shuffle();
  }

  void _checkAnswer(String selectedAnswer) {
    final correctAnswer = widget.vocabList[currentQuestionIndex]['meaning'];

    setState(() {
      isAnswered = true;
      if (selectedAnswer == correctAnswer) {
        isCorrect = true;
        correctAnswers++;
        userPoints++; // เพิ่มแต้มเมื่อผู้ใช้ตอบถูก

        // นำทางไปยังหน้า SpeakToTextScreen เพื่อฝึกออกเสียง
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SpeakToTextScreen(
              correctWord: widget.vocabList[currentQuestionIndex]['word'],
            ),
          ),
        ).then((_) {
          // เมื่อกลับมาจาก SpeakToTextScreen ให้ไปคำถามถัดไป
          _nextQuestion();
        });

        HapticFeedback.lightImpact(); // สั่นเบาเมื่อถูก
      } else {
        isCorrect = false;
        HapticFeedback.vibrate(); // สั่นเมื่อผิด
      }
    });
  }

  void _nextQuestion() {
    if (currentQuestionIndex < widget.vocabList.length - 1) {
      setState(() {
        currentQuestionIndex++;
        isAnswered = false;
        isCorrect = false;
        _initializeOptions();
      });
    } else {
      _savePointsToFirestore().then((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ScoreScreen(
              correctAnswers: correctAnswers,
              wrongAnswers: widget.vocabList.length - correctAnswers,
            ),
          ),
        );
      });
    }
  }

 Future<void> _savePointsToFirestore() async {
  final userRef = FirebaseFirestore.instance.collection('users').doc(_auth.currentUser!.uid);

  // สร้างเอกสารใหม่ใน subcollection "sessions" สำหรับบันทึกรอบการเล่น
  final sessionRef = userRef.collection('sessions').doc();
  await sessionRef.set({
    'points': userPoints,
    'correctAnswers': correctAnswers,
    'wrongAnswers': widget.vocabList.length - correctAnswers,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // อัปเดตแต้มรวมและจำนวนครั้งที่เล่นในเอกสารหลักของผู้ใช้
  await userRef.set({
    'totalPoints': FieldValue.increment(userPoints),
    'gamesPlayed': FieldValue.increment(1),
  }, SetOptions(merge: true));

  // สร้าง collection "state" สำหรับเก็บสถิติรวมของผู้ใช้
  final stateRef = FirebaseFirestore.instance.collection('state').doc(_auth.currentUser!.uid);
  await stateRef.set({
    'totalCorrectAnswers': FieldValue.increment(correctAnswers),
    'totalWrongAnswers': FieldValue.increment(widget.vocabList.length - correctAnswers),
    'totalPoints': FieldValue.increment(userPoints),
  }, SetOptions(merge: true));
}


  @override
  Widget build(BuildContext context) {
    final currentQuestion = widget.vocabList[currentQuestionIndex];
    final word = currentQuestion['word'];
    final partOfSpeech = currentQuestion['part_of_speech'];
    final correctAnswer = currentQuestion['meaning'];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('คำศัพท์ ${currentQuestionIndex + 1}/${widget.vocabList.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'คำศัพท์',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              word,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              partOfSpeech,
              style: TextStyle(fontSize: 18, color: Colors.grey[700]),
            ),
            SizedBox(height: 20),
            ...shuffledOptions.map((option) {
              final isSelected = isAnswered && option == correctAnswer;
              final isIncorrect = isAnswered &&
                  option != correctAnswer &&
                  option == shuffledOptions.firstWhere((o) => o != correctAnswer, orElse: () => "");

              return GestureDetector(
                onTap: isAnswered
                    ? null
                    : () {
                        _checkAnswer(option);
                      },
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  padding: EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.green
                        : isIncorrect
                            ? Colors.red
                            : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isSelected || isIncorrect ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
              );
            }),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isAnswered ? _nextQuestion : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isAnswered
                    ? (isCorrect ? Colors.green : Colors.red)
                    : Colors.grey,
                padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'ไปต่อ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}