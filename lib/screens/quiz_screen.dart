import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class QuizScreen extends StatefulWidget {
  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final CollectionReference _vocabCollection =
      FirebaseFirestore.instance.collection('vocab');

  List<DocumentSnapshot> _vocabList = [];
  String _question = "";
  String _correctAnswer = "";
  List<String> _options = [];
  bool _isLoading = true;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _loadVocab();
  }

  Future<void> _loadVocab() async {
    try {
      QuerySnapshot querySnapshot = await _vocabCollection.get();
      if (querySnapshot.docs.isEmpty) {
        // ตรวจสอบกรณีไม่มีข้อมูลคำศัพท์
        setState(() {
          _isLoading = false;
          _question = "No vocabulary available. Please add some!";
        });
      } else {
        setState(() {
          _vocabList = querySnapshot.docs;
          _isLoading = false;
          _generateQuestion();
        });
      }
    } catch (e) {
      // จัดการข้อผิดพลาดในการเชื่อมต่อกับ Firestore
      setState(() {
        _isLoading = false;
        _question = "Failed to load vocabulary: $e";
      });
    }
  }

  void _generateQuestion() {
    if (_vocabList.isEmpty) return;

    final random = Random();
    final vocab = _vocabList[random.nextInt(_vocabList.length)];
    _question = vocab['meaning'];
    _correctAnswer = vocab['word'];

    // สุ่มตัวเลือกคำตอบ
    _options = [_correctAnswer];
    while (_options.length < 4) {
      final option = _vocabList[random.nextInt(_vocabList.length)]['word'];
      if (!_options.contains(option)) {
        _options.add(option);
      }
    }
    _options.shuffle();
  }

  void _checkAnswer(String selectedAnswer) {
    if (selectedAnswer == _correctAnswer) {
      setState(() {
        _score++;
      });
    }
    _generateQuestion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vocabulary Quiz'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Score: $_score',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 30),
                  Text(
                    _question,
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  ..._options.map((option) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ElevatedButton(
                          onPressed: () => _checkAnswer(option),
                          child: Text(option),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
