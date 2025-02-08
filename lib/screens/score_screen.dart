import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  return FutureBuilder<DocumentSnapshot>(
    future: FirebaseFirestore.instance
        .collection('state') // แก้จาก users เป็น state
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final userData = snapshot.data!.data() as Map<String, dynamic>;
      final totalPoints = userData['totalPoints'] ?? 0;
      final totalCorrectAnswers = userData['totalCorrectAnswers'] ?? 0;
      final totalWrongAnswers = userData['totalWrongAnswers'] ?? 0;
      final gamesPlayed = userData['gamesPlayed'] ?? 0;

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
              Text(
                'แต้มรวม: $totalPoints',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'จำนวนครั้งที่เล่น: $gamesPlayed',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                'ตอบถูกทั้งหมด: $totalCorrectAnswers',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                'ตอบผิดทั้งหมด: $totalWrongAnswers',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ResultScreen(score: totalCorrectAnswers),
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
    },
  );
}





}
