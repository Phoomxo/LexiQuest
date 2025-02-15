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
  int userPoints = 0;
  String? backgroundUrl;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _initializeOptions();
    _loadBackground();
  }

  Future<void> _loadBackground() async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('state').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          backgroundUrl = doc.data()?['selectedWallpaper'];
        });
      }
    }
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
        userPoints++;
        HapticFeedback.lightImpact();
      } else {
        isCorrect = false;
        HapticFeedback.vibrate();
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
    final sessionRef = userRef.collection('sessions').doc();
    await sessionRef.set({
      'points': userPoints,
      'correctAnswers': correctAnswers,
      'wrongAnswers': widget.vocabList.length - correctAnswers,
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      await userRef.set({
        'totalPoints': FieldValue.increment(userPoints),
        'gamesPlayed': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving points: $e');
    }

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
      body: Container(
        decoration: BoxDecoration(
          image: backgroundUrl != null
              ? DecorationImage(
                  image: NetworkImage(backgroundUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('คำศัพท์', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text(word, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text(partOfSpeech, style: TextStyle(fontSize: 18, color: Colors.grey[700])),
              SizedBox(height: 20),
              ...shuffledOptions.map((option) {
                return GestureDetector(
                  onTap: isAnswered ? null : () => _checkAnswer(option),
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isAnswered && option == correctAnswer
                          ? Colors.green
                          : isAnswered && option != correctAnswer
                              ? Colors.red
                              : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(option, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: isAnswered
                    ? () {
                        if (isCorrect) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SpeakToTextScreen(
                                correctWord: widget.vocabList[currentQuestionIndex]['word'],
                              ),
                            ),
                          ).then((_) => _nextQuestion());
                        } else {
                          _nextQuestion();
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: isAnswered ? Colors.blue : Colors.grey),
                child: Text('ไปต่อ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
