import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'quiz_screen.dart';

class ChooseModeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกรูปแบบ'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
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
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              ),
              onPressed: () {
                // คุณสามารถสร้าง CategorySelectionScreen หรือหน้าที่เกี่ยวข้องได้
              },
              child: const Text(
                'เริ่มด้วยคำศัพท์ที่เพิ่มเข้ามา',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
