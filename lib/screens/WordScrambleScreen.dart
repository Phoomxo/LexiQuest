import 'package:flutter/material.dart';
import 'dart:math';
import 'FillInTheBlanksScreen.dart';

class WordScrambleScreen extends StatefulWidget {
  final String word;

  const WordScrambleScreen({super.key, required this.word});

  @override
  _WordScrambleScreenState createState() => _WordScrambleScreenState();
}

class _WordScrambleScreenState extends State<WordScrambleScreen> {
  List<String> scrambledLetters = [];
  List<String?> userAnswer = [];
  List<int> usedIndexes = [];

  @override
  void initState() {
    super.initState();
    _scrambleWord();
  }

  void _scrambleWord() {
    scrambledLetters = widget.word.split('');
    scrambledLetters.shuffle(Random());
    userAnswer = List.filled(scrambledLetters.length, null);
    usedIndexes.clear();
  }

  void _checkAnswer() {
    if (userAnswer.join() == widget.word) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ ถูกต้อง! กำลังไปหน้าถัดไป...")),
      );
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => FillInTheBlanksScreen(word: widget.word),
            ),
          );
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ ผิด! ลองอีกครั้ง")),
      );
    }
  }

  void _resetGame() {
    setState(() {
      _scrambleWord();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("เกมเรียงตัวอักษร"),
        centerTitle: true,
        backgroundColor: Colors.purple,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple, Colors.indigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(  // เพิ่ม SingleChildScrollView
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  children: List.generate(scrambledLetters.length, (index) {
                    return DragTarget<int>(
                      onWillAccept: (draggedIndex) => userAnswer[index] == null,
                      onAccept: (draggedIndex) {
                        setState(() {
                          userAnswer[index] = scrambledLetters[draggedIndex];
                          usedIndexes.add(draggedIndex);
                        });
                      },
                      builder: (context, candidateData, rejectedData) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.all(5),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: userAnswer[index] != null
                                ? Colors.greenAccent.shade200
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(2, 2),
                              )
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            userAnswer[index] ?? "",
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    );
                  }),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: List.generate(scrambledLetters.length, (index) {
                    return Visibility(
                      visible: !usedIndexes.contains(index),
                      child: Draggable<int>(
                        data: index,
                        child: _buildLetterTile(scrambledLetters[index]),
                        feedback: Material(
                          child: _buildLetterTile(scrambledLetters[index], isDragging: true),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.0,
                          child: _buildLetterTile(scrambledLetters[index]),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _checkAnswer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text("ตรวจสอบคำตอบ", style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _resetGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text("เริ่มใหม่", style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLetterTile(String letter, {bool isDragging = false}) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDragging ? Colors.blue.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black),
        boxShadow: [
          if (!isDragging)
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(2, 2),
            )
        ],
      ),
      child: Text(
        letter,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
