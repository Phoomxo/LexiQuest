import 'package:flutter/material.dart';
import 'ResultScreen.dart';

class ScoreScreen extends StatelessWidget {
  final int correctAnswers;
  final int wrongAnswers;
  final bool isFromFirestore; // เช็คว่าเริ่มจาก Firestore หรือไม่
  final String? selectedCategoryId; // ถ้ามาจากหมวดหมู่ จะมีค่า categoryId

  const ScoreScreen({super.key, 
    required this.correctAnswers,
    required this.wrongAnswers,
    this.isFromFirestore = true,
    this.selectedCategoryId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ความคืบหน้า'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // วงกลมแสดงจำนวนข้อที่ตอบถูก
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.green,
                      child: Text(
                        '$correctAnswers',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Icon(Icons.check, color: Colors.green, size: 32),
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.red,
                      child: Text(
                        '$wrongAnswers',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Icon(Icons.close, color: Colors.red, size: 32),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),
            // ปุ่มลองใหม่อีกครั้ง
            ElevatedButton(
              onPressed: () {
                if (isFromFirestore) {
                  // ถ้ามาจาก Firestore ให้สุ่มคำใหม่
                  Navigator.pop(context, 'retry_firestore');
                } else if (selectedCategoryId != null) {
                  // ถ้ามาจากหมวดหมู่ ให้ฝึกซ้ำหมวดหมู่เดิม
                  Navigator.pop(context, selectedCategoryId);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'ลองใหม่อีกครั้ง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            // ปุ่มออก
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ResultScreen(score: correctAnswers),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'ออก',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
