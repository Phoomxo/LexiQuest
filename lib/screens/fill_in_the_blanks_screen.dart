import 'package:flutter/material.dart';
import '../models/sentence_model.dart';
import '../services/sentence_service.dart';

class FillInTheBlanksScreen extends StatefulWidget {
  final String word;

  const FillInTheBlanksScreen({super.key, required this.word});

  @override
  State<FillInTheBlanksScreen> createState() => _FillInTheBlanksScreenState();
}

class _FillInTheBlanksScreenState extends State<FillInTheBlanksScreen> {
  SentenceModel? sentenceModel;
  List<String> userSentence = [];

  @override
  void initState() {
    super.initState();
    _loadSentence();
  }

  void _loadSentence() async {
    SentenceModel? model = await SentenceService.fetchSentence(widget.word);
    if (model != null) {
      setState(() {
        sentenceModel = model;
        userSentence = List.filled(model.words.length, "");
      });
    }
  }

  void _checkAnswer() {
    if (sentenceModel == null) return;
    String correctSentence = sentenceModel!.sentence;
    String userInput = userSentence.join(" ");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userInput == correctSentence ? "✅ คำตอบถูกต้อง!" : "❌ คำตอบผิด!",
        ),
        backgroundColor: userInput == correctSentence
            ? Colors.green
            : Colors.red,
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("เติมคำในช่องว่าง"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7E57C2), Color(0xFF9575CD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        // เพิ่ม SingleChildScrollView เพื่อให้สามารถเลื่อนหน้าจอได้
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7E57C2), Color(0xFF9575CD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "ลากคำศัพท์ไปวางให้เป็นประโยคที่ถูกต้อง",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 5,
                          color: Colors.black26,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: List.generate(userSentence.length, (index) {
                      return DragTarget<String>(
                        onAcceptWithDetails: (details) {
                          setState(() {
                            if (sentenceModel!.words.contains(details.data)) {
                              userSentence[index] =
                                  details.data; // ให้แค่คำที่ถูกต้อง
                            }
                          });
                        },
                        builder: (context, candidateData, rejectedData) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 110,
                            height: 55,
                            alignment: Alignment.center,
                            margin: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: userSentence[index].isEmpty
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.greenAccent.shade200,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(2, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              userSentence[index],
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 30),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children:
                        sentenceModel?.words.map((word) {
                          return Draggable<String>(
                            data: word,
                            feedback: Material(
                              color: Colors.transparent,
                              child: _buildWordTile(word, isDragging: true),
                            ),
                            child: _buildWordTile(word),
                          );
                        }).toList() ??
                        [],
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _checkAnswer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 50,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      elevation: 6,
                    ),
                    child: const Text(
                      "ตรวจสอบคำตอบ",
                      style: TextStyle(fontSize: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordTile(String word, {bool isDragging = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDragging ? Colors.deepPurple.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          if (!isDragging)
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(2, 3),
            ),
        ],
      ),
      child: Text(
        word,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}
