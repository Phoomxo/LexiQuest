import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'quiz_screen.dart';
import 'CategoriesPage.dart';
import 'SelectCategoryForQuiz.dart';

class ChooseModeScreen extends StatelessWidget {
  const ChooseModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: const Text(
    'เลือกรูปแบบการเรียน',
    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
  ),
  centerTitle: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  flexibleSpace: Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.deepPurple, Colors.indigo],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ),
),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🎯 ปุ่มเริ่มด้วยคำศัพท์ในแอพ
              _buildModeButton(
                context,
                title: "เริ่มด้วยคำศัพท์ในแอพ",
                icon: Icons.play_arrow,
                color: Colors.red,
                onPressed: () async {
                  final CollectionReference vocabCollection =
                      FirebaseFirestore.instance.collection('vocabulary');
                  final querySnapshot = await vocabCollection.get();

                  if (querySnapshot.docs.isEmpty) {
                    _showSnackBar(context, 'ไม่มีคำศัพท์ในคลัง!');
                    return;
                  }

                  final vocabList = querySnapshot.docs.map((doc) {
                    return {
                      'word': doc['word'],
                      'meaning': doc['meaning'],
                      'part_of_speech': doc['part_of_speech'],
                    };
                  }).toList()
                    ..shuffle();

                  final selectedWords = vocabList.take(10).toList();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuizScreen(vocabList: selectedWords),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // 📝 ปุ่มเริ่มด้วยคำศัพท์ที่เพิ่มเข้ามา
              _buildModeButton(
                context,
                title: "เริ่มด้วยคำศัพท์ที่เพิ่มเข้ามา",
                icon: Icons.list_alt,
                color: Colors.orange,
                onPressed: () async {
                  final selectedCategory = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SelectCategoryForQuiz()),
                  );

                  if (selectedCategory != null) {
                    final CollectionReference wordsCollection = FirebaseFirestore
                        .instance
                        .collection('categories')
                        .doc(selectedCategory)
                        .collection('words');

                    final querySnapshot = await wordsCollection.get();

                    final vocabList = querySnapshot.docs.map((doc) {
                      return {
                        'word': doc['word'],
                        'meaning': doc['meaning'],
                        'part_of_speech': doc['part_of_speech'],
                      };
                    }).toList()
                      ..shuffle();

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QuizScreen(vocabList: vocabList),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 📌 ฟังก์ชันสร้างปุ่มแบบกำหนดเอง
  Widget _buildModeButton(BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 250, // ✅ กำหนดความกว้างของปุ่มให้เท่ากัน
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24, color: Colors.white),
        label: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15), // ✅ ปรับความสูงของปุ่มให้เหมาะสม
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 5,
          shadowColor: Colors.black.withOpacity(0.3),
        ),
      ),
    );
  }

  /// 📌 ฟังก์ชันแสดง SnackBar
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
