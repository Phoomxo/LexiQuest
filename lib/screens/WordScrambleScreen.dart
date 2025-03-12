import 'package:flutter/material.dart';
import 'dart:math';
import 'FillInTheBlanksScreen.dart'; // ✅ นำเข้าไฟล์หน้าถัดไป

class WordScrambleScreen extends StatefulWidget {
  final String word;

  const WordScrambleScreen({super.key, required this.word});

  @override
  _WordScrambleScreenState createState() => _WordScrambleScreenState();
}

class _WordScrambleScreenState extends State<WordScrambleScreen> {
  List<String> scrambledLetters = [];
  List<String?> userAnswer = [];
  Set<String> usedLetters = {}; // ✅ เก็บตัวอักษรที่ถูกใช้แล้ว

  @override
  void initState() {
    super.initState();
    _scrambleWord();
  }

  /// ✅ สุ่มตัวอักษร
  void _scrambleWord() {
    scrambledLetters = widget.word.split('');
    scrambledLetters.shuffle(Random());
    userAnswer = List.filled(scrambledLetters.length, null);
    usedLetters.clear();
  }

  /// ✅ ตรวจสอบคำตอบและเปลี่ยนหน้า
void _checkAnswer() {
  if (userAnswer.join() == widget.word) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ คำตอบถูกต้อง! กำลังไปเติมคำในช่องว่าง...")),
    );

    // ✅ ถ้าเรียงคำถูกต้อง → ไป FillInTheBlanksScreen
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
      const SnackBar(content: Text("❌ คำตอบผิด! กลับไปแบบทดสอบ...")),
    );

    // ❌ ถ้าเรียงคำผิด → กลับไป QuizScreen
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }
}


  /// ✅ รีเซ็ตเกม (เริ่มใหม่)
  void _resetGame() {
    setState(() {
      _scrambleWord();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("เกมเรียงตัวอักษร")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Wrap(
            children: List.generate(scrambledLetters.length, (index) {
              return DragTarget<String>(
                onWillAccept: (letter) => userAnswer[index] == null, // ✅ ป้องกันการวางซ้ำ
                onAccept: (letter) {
                  setState(() {
                    userAnswer[index] = letter;
                    usedLetters.add(letter);
                  });
                },
                builder: (context, candidateData, rejectedData) {
                  return Container(
                    margin: const EdgeInsets.all(5),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: userAnswer[index] != null ? Colors.green.shade200 : Colors.grey.shade300,
                      border: Border.all(color: Colors.black),
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
            children: scrambledLetters.map((letter) {
              return Visibility(
                visible: !usedLetters.contains(letter), // ✅ ซ่อนตัวอักษรที่ถูกใช้ไปแล้ว
                child: Draggable<String>(
                  data: letter,
                  child: _buildLetterTile(letter),
                  feedback: Material(
                    child: _buildLetterTile(letter, isDragging: true),
                  ),
                  childWhenDragging: Opacity(opacity: 0.0, child: _buildLetterTile(letter)), // ✅ ป้องกันการลดขนาด
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          ElevatedButton(onPressed: _checkAnswer, child: const Text("ตรวจสอบคำตอบ")),
          ElevatedButton(onPressed: _resetGame, child: const Text("เริ่มใหม่")),
        ],
      ),
    );
  }

  /// 🎨 สร้างปุ่มตัวอักษร
  Widget _buildLetterTile(String letter, {bool isDragging = false}) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDragging ? Colors.blue.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black),
      ),
      child: Text(
        letter,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
