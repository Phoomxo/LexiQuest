import 'package:flutter/material.dart';
import '../services/vocab_service.dart';
import 'quiz_screen.dart';
import 'SelectCategoryForQuiz.dart';
import '../services/quiz_service.dart';

class ChooseModeScreen extends StatelessWidget {
  final VocabService _vocabService = VocabService();
  final QuizService _quizService = QuizService();

  ChooseModeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'เลือกรูปแบบ',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ปุ่มเริ่มด้วยคำศัพท์ในแอพ
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 5,
              ),
              onPressed: () async {
                try {
                  final vocabList = await _vocabService.getVocabFromAppCollection();
                  await _quizService.generateQuizQuestions(5);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const QuizScreen(),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text(
                'เริ่มด้วยคำศัพท์ในแอพ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ปุ่มเริ่มด้วยคำศัพท์ที่เพิ่มเข้ามา
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 5,
              ),
              onPressed: () async {
                final selectedCategory = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SelectCategoryForQuiz(),
                  ),
                );

                if (selectedCategory != null) {
                  try {
                    final vocabList =
                        await _vocabService.getVocabFromCategory(selectedCategory);

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const QuizScreen(),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text(
                'เริ่มด้วยคำศัพท์ที่เพิ่มเข้ามา',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
