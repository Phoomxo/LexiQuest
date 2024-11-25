import 'package:flutter/material.dart';

class SettingScreen extends StatelessWidget {
  // ตัวอย่างข้อมูลโปรไฟล์ (สมมุติว่าดึงมาจากฐานข้อมูล)
  final Map<String, dynamic> profileData = {
    'name': 'วัดสิริ',
    'nickname': 'สุขหวาน',
    'age': 'อายุ 1 ขวบ',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'โปรไฟล์',
          style: TextStyle(color: Colors.black),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // รูปโปรไฟล์
                const CircleAvatar(
                  radius: 60,
                  backgroundImage: AssetImage('assets/profile_placeholder.png'),
                ),
                const SizedBox(height: 20),
                // ชื่อโปรไฟล์
                const Text(
                  'โปรไฟล์',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                // ข้อมูลที่ดึงมาจากฐานข้อมูล
                _buildProfileItem(profileData['name']),
                const SizedBox(height: 10),
                _buildProfileItem(profileData['nickname']),
                const SizedBox(height: 10),
                _buildProfileItem(profileData['age']),
                const SizedBox(height: 40),
                // ปุ่มออกจากระบบ
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  ),
                  onPressed: () {
                    // Action สำหรับปุ่มออกจากระบบ
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('ออกจากระบบ'),
                        content: const Text('คุณต้องการออกจากระบบหรือไม่?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('ยกเลิก'),
                          ),
                          TextButton(
                            onPressed: () {
                              // การทำงานหลังออกจากระบบ
                              Navigator.pop(context); // ปิด Dialog
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => Placeholder()), // หน้าหลัก (เปลี่ยนตามต้องการ)
                              );
                            },
                            child: const Text(
                              'ยืนยัน',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text(
                    'ออกจากระบบ',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget สำหรับสร้างกล่องข้อมูลโปรไฟล์
  Widget _buildProfileItem(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
