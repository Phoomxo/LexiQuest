import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ResultScreen.dart';

class QuizScreen extends StatefulWidget {
  final List<Map<String, dynamic>> vocabList;

  QuizScreen({required this.vocabList});

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int currentQuestionIndex = 0;
  int correctAnswers = 0;
  bool isAnswered = false;
  bool isCorrect = false;
  List<String> shuffledOptions = []; // เก็บตัวเลือกในคำถามปัจจุบัน

  @override
  void initState() {
    super.initState();
    _initializeOptions(); // สร้างตัวเลือกครั้งแรก
  }

  void _initializeOptions() {
    final currentQuestion = widget.vocabList[currentQuestionIndex];
    final correctAnswer = currentQuestion['meaning'];

    // ดึงคำแปลหลอกจากคำศัพท์อื่น
    final fakeOptions = widget.vocabList
        .where((vocab) => vocab['meaning'] != correctAnswer)
        .map((vocab) => vocab['meaning'])
        .toList()
      ..shuffle();

    // สร้างตัวเลือกทั้งหมด (คำตอบที่ถูกต้อง + ตัวเลือกหลอก)
    shuffledOptions = [correctAnswer, ...fakeOptions.take(3)]..shuffle();
  }

  void _checkAnswer(String selectedAnswer) {
    final correctAnswer = widget.vocabList[currentQuestionIndex]['meaning'];

    setState(() {
      isAnswered = true;
      if (selectedAnswer == correctAnswer) {
        isCorrect = true;
        correctAnswers++;
        HapticFeedback.lightImpact(); // เสียงตอบถูก
      } else {
        isCorrect = false;
        HapticFeedback.vibrate(); // เสียงตอบผิด
      }
    });
  }

  void _nextQuestion() {
    if (currentQuestionIndex < widget.vocabList.length - 1) {
      setState(() {
        currentQuestionIndex++;
        isAnswered = false;
        isCorrect = false;
        _initializeOptions(); // อัปเดตตัวเลือกเมื่อเปลี่ยนคำถาม
      });
    } else {
      // ไปหน้าสรุปคะแนน
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            totalQuestions: widget.vocabList.length,
            correctAnswers: correctAnswers,
            duration: 300, // ตัวอย่างเวลาเล่น
            userId: 'user123', // User ID (เปลี่ยนตามระบบของคุณ)
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentQuestion = widget.vocabList[currentQuestionIndex];
    final word = currentQuestion['word'];
    final partOfSpeech = currentQuestion['part_of_speech'];
    final correctAnswer = currentQuestion['meaning'];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // ซ่อนปุ่มย้อนกลับ
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
              final isIncorrect = isAnswered && option != correctAnswer && option == shuffledOptions.firstWhere((o) => o != correctAnswer, orElse: () => "");

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
