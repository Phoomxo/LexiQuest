import 'package:flutter/material.dart';

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
            // ปุ่มสีแดง
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, // สีปุ่ม
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // ความโค้งมนของปุ่ม
                ),
                elevation: 5, // เงาของปุ่ม
              ),
              onPressed: () {
                // กำหนด action เมื่อกดปุ่มนี้
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
            const SizedBox(height: 20), // เว้นระหว่างปุ่ม
            // ปุ่มสีเหลือง
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, // สีปุ่ม
                padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), // ความโค้งมนของปุ่ม
                ),
                elevation: 5, // เงาของปุ่ม
              ),
              onPressed: () {
                // กำหนด action เมื่อกดปุ่มนี้
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
