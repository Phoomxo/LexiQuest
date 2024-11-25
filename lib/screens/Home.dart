import 'package:flutter/material.dart';
import 'ChooseModeScreen.dart';



class Home extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'แบบฝึกหัด',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            // ปุ่ม "เรียนรู้คำศัพท์"
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[300], // สีเขียวสำหรับปุ่มแรก
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              ),
              onPressed: () {
                // เชื่อมไปยัง ChooseModeScreen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChooseModeScreen(),
                  ),
                );
              },
              child: const Text(
                'เรียนรู้คำศัพท์',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[400], // สีส้มสำหรับปุ่มที่สอง
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              ),
              onPressed: () {
                // ยังไม่มีการเชื่อมโยง (คุณสามารถเพิ่มได้ภายหลัง)
              },
              child: const Text(
                'เพิ่มคำศัพท์',
                style: TextStyle(
                  color: Colors.white,
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
