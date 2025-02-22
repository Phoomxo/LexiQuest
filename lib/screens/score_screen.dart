import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/main.dart';
import 'ResultScreen.dart';
import 'quiz_screen.dart';
import 'ChooseModeScreen.dart';

class ScoreScreen extends StatelessWidget {
  final int correctAnswers;
  final int wrongAnswers;
  final bool isFromFirestore;
  final String? selectedCategoryId;

  const ScoreScreen({
    super.key,
    required this.correctAnswers,
    required this.wrongAnswers,
    this.isFromFirestore = true,
    this.selectedCategoryId,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('กรุณาเข้าสู่ระบบ')),
      );
    }

    // ✅ อัปเดตข้อมูลผู้ใช้ใน Firestore
    _updateUserStats(user.uid, correctAnswers, wrongAnswers);

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('state').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดคะแนน!'));
        }

        if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
          return const Center(child: Text('ไม่พบข้อมูลคะแนน!'));
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final totalPoints = userData['totalPoints'] ?? 0;
        final totalCorrectAnswers = userData['totalCorrectAnswers'] ?? 0;
        final totalWrongAnswers = userData['totalWrongAnswers'] ?? 0;
        final gamesPlayed = userData['gamesPlayed'] ?? 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('ผลลัพธ์ของคุณ'),
            centerTitle: true,
            backgroundColor: Colors.blueAccent,
            elevation: 4,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🏆 แสดงคะแนนรวม
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text(
                          'แต้มสะสมทั้งหมด',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '$totalPoints',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: totalPoints > 50 ? Colors.green : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 📊 แสดงสถิติการเล่น
                _buildStatCard('จำนวนครั้งที่เล่น', gamesPlayed.toString(), Icons.history, Colors.deepPurple),
                _buildStatCard('ตอบถูกทั้งหมด', totalCorrectAnswers.toString(), Icons.check_circle, Colors.green),
                _buildStatCard('ตอบผิดทั้งหมด', totalWrongAnswers.toString(), Icons.cancel, Colors.red),

                const SizedBox(height: 30),

                // 🎮 ปุ่มเล่นใหม่ และกลับหน้าหลัก
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ปุ่มเล่นใหม่ → กลับไปที่ ChooseModeScreen
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const ChooseModeScreen()),
                        );
                      },
                      icon: const Icon(Icons.replay, color: Colors.white),
                      label: const Text('เล่นใหม่', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // ปุ่มกลับหน้าหลัก → ไปที่ MainNavigation และล้าง Stack
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const MainNavigation()),
                          (Route<dynamic> route) => false, // ลบ Stack ทั้งหมด
                        );
                      },
                      icon: const Icon(Icons.home, color: Colors.white),
                      label: const Text('กลับหน้าหลัก', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// ✅ ฟังก์ชันอัปเดตข้อมูลใน Firestore
  Future<void> _updateUserStats(String userId, int correctAnswers, int wrongAnswers) async {
    final userRef = FirebaseFirestore.instance.collection('state').doc(userId);

    try {
      await userRef.set({
        'totalPoints': FieldValue.increment(correctAnswers), // ✅ เพิ่มแต้มสะสม
        'totalCorrectAnswers': FieldValue.increment(correctAnswers), // ✅ บันทึกคำตอบที่ถูก
        'totalWrongAnswers': FieldValue.increment(wrongAnswers), // ✅ บันทึกคำตอบที่ผิด
        'gamesPlayed': FieldValue.increment(1), // ✅ เพิ่มจำนวนครั้งที่เล่น
      }, SetOptions(merge: true));

      print("✅ อัปเดตคะแนนสำเร็จ");
    } catch (e) {
      print("❌ เกิดข้อผิดพลาดในการอัปเดตคะแนน: $e");
    }
  }

  /// 📌 ฟังก์ชันสร้างการ์ดแสดงสถิติ
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
