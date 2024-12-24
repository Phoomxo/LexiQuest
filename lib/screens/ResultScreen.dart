import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  final int totalQuestions;
  final int correctAnswers;
  final int duration;
  final String userId;

  ResultScreen({
    required this.totalQuestions,
    required this.correctAnswers,
    required this.duration,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final int wrongAnswers = totalQuestions - correctAnswers;
    final int score = correctAnswers * 10; // คำนวณคะแนน

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ผลลัพธ์'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'คุณตอบถูก $correctAnswers/$totalQuestions ข้อ',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'ระยะเวลา: $duration วินาที',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('กลับไปหน้าแรก'),
            ),
          ],
        ),
      ),
    );
  }
}
