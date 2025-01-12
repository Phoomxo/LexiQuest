import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'quiz_screen.dart';
import 'CategoriesPage.dart';
import 'SelectCategoryForQuiz.dart';

class ChooseModeScreen extends StatelessWidget {
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
                final CollectionReference vocabCollection =
                    FirebaseFirestore.instance.collection('vocabulary');
                final querySnapshot = await vocabCollection.get();

                if (querySnapshot.docs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ไม่มีคำศัพท์ในคลัง!')),
                  );
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
                // เปิดหน้า SelectCategoryForQuiz เพื่อเลือกหมวดหมู่ที่มีคำศัพท์มากกว่า 5 คำ
                final selectedCategory = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SelectCategoryForQuiz(),
                  ),
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

                  // นำทางไปยัง QuizScreen พร้อมส่งคำศัพท์ที่เลือก
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuizScreen(vocabList: vocabList),
                    ),
                  );
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