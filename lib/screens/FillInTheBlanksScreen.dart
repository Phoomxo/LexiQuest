import 'package:flutter/material.dart';
import '../models/SentenceModel.dart';
import '../services/SentenceService.dart';
import 'quiz_screen.dart';

class FillInTheBlanksScreen extends StatefulWidget {
  final String word;

  const FillInTheBlanksScreen({Key? key, required this.word}) : super(key: key);

  @override
  _FillInTheBlanksScreenState createState() => _FillInTheBlanksScreenState();
}

class _FillInTheBlanksScreenState extends State<FillInTheBlanksScreen> {
  SentenceModel? sentenceModel;
  List<String> userSentence = [];

  @override
  void initState() {
    super.initState();
    _loadSentence();
  }

  /// ✅ โหลดประโยคจาก API
  void _loadSentence() async {
    SentenceModel? model = await SentenceService.fetchSentence(widget.word);
    if (model != null) {
      setState(() {
        sentenceModel = model;
        userSentence = List.filled(model.words.length, ""); // ✅ ช่องให้ลากคำมาใส่
      });
    }
  }

  /// ✅ ตรวจสอบคำตอบ
void _checkAnswer() {
  if (sentenceModel == null) return;
  String correctSentence = sentenceModel!.sentence;
  String userInput = userSentence.join(" ");

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(userInput == correctSentence ? "✅ คำตอบถูกต้อง! กลับไปแบบทดสอบ..." : "❌ คำตอบผิด! กลับไปแบบทดสอบ...")),
  );

  Future.delayed(const Duration(seconds: 1), () {
    if (mounted) {
      Navigator.pop(context); // ✅ กลับไปหน้า QuizScreen
    }
  });
}




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("เรียงประโยคให้ถูกต้อง")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("ลากคำศัพท์ไปวางให้เป็นประโยคที่ถูกต้อง", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // 🔹 พื้นที่ให้ลากคำมาเรียง
          Wrap(
            children: List.generate(userSentence.length, (index) {
              return DragTarget<String>(
                onAccept: (word) {
                  setState(() {
                    userSentence[index] = word;
                  });
                },
                builder: (context, candidateData, rejectedData) {
                  return Container(
                    width: 80,
                    height: 50,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: userSentence[index].isEmpty ? Colors.grey.shade300 : Colors.green.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(userSentence[index], style: const TextStyle(fontSize: 18)),
                  );
                },
              );
            }),
          ),

          const SizedBox(height: 30),

          // 🔹 คำที่ให้ลาก
          Wrap(
            spacing: 10,
            children: sentenceModel?.words.map((word) {
              return Draggable<String>(
                data: word,
                child: _buildWordTile(word),
                feedback: Material(child: _buildWordTile(word, isDragging: true)),
              );
            }).toList() ?? [],
          ),

          const SizedBox(height: 30),
          ElevatedButton(onPressed: _checkAnswer, child: const Text("ตรวจสอบคำตอบ")),
        ],
      ),
    );
  }

  Widget _buildWordTile(String word, {bool isDragging = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDragging ? Colors.blue.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black),
      ),
      child: Text(word, style: const TextStyle(fontSize: 18)),
    );
  }
}
