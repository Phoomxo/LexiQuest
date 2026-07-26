import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';

class ResultScreen extends StatelessWidget {
  final int score;

  const ResultScreen({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ได้รับคะแนน'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.blue,
              child: Text(
                '$score',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MainNavigationScreen(),
                  ), // เปลี่ยนเป็นหน้าหลักของคุณ
                  (Route<dynamic> route) => false, // ลบ Stack ทั้งหมด
                );
              },
              child: const Text('กลับหน้าหลัก'),
            ),
          ],
        ),
      ),
    );
  }
}
