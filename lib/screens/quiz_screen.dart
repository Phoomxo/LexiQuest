// import 'dart:nativewrappers/_internal/vm/lib/internal_patch.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/quiz_service.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({Key? key}) : super(key: key);

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final QuizService _quizService = QuizService();
  List<Map<String, dynamic>> _questions = []; // เก็บคำถามที่ดึงมาจาก Firestore
  int _currentQuestionIndex = 0;
  int _score = 0;
  bool _isAnswered = false;

  @override
  void initState() {
    super.initState();
    _loadQuizQuestions();
  }

  /// ฟังก์ชันโหลดคำถามจาก Firestore
  Future<void> _loadQuizQuestions() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('quiz')
          .get();

      final questions = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'word': data['word'],
          'options': List<String>.from(data['options']),
          'correctAnswer': data['correctAnswer'],
        };
      }).toList();

      setState(() {
        _questions = questions;
      });
    } catch (e) {
      print('Failed to load quiz questions: $e');
    }
  }

  /// ฟังก์ชันตรวจสอบคำตอบ
  void _checkAnswer(String selectedAnswer) {
    final correctAnswer = _questions[_currentQuestionIndex]['correctAnswer'];
    setState(() {
      _isAnswered = true;
      if (selectedAnswer == correctAnswer) {
        _score++;
      }
    });
  }

  /// ฟังก์ชันไปยังคำถามถัดไป
  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _isAnswered = false;
      });
    } else {
      _showScoreDialog();
    }
  }

  /// ฟังก์ชันแสดงคะแนนเมื่อจบแบบทดสอบ
  void _showScoreDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('จบแบบทดสอบ'),
        content: Text('คุณได้คะแนน $_score / ${_questions.length}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // กลับไปหน้าหลัก
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final options = currentQuestion['options'] as List<String>;

    return Scaffold(
      appBar: AppBar(
        title: Text('คำถาม ${_currentQuestionIndex + 1} / ${_questions.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentQuestion['word'],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ...options.map((option) => GestureDetector(
                  onTap: _isAnswered
                      ? null
                      : () {
                          _checkAnswer(option);
                        },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isAnswered
                          ? (option == currentQuestion['correctAnswer']
                              ? Colors.green
                              : Colors.red)
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        option,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isAnswered ? _nextQuestion : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
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
