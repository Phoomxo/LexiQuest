import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  _ShopPageState createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final UserService _userService = UserService(); // เรียกใช้ UserService
  int userPoints = 0; // เก็บแต้มของผู้ใช้
  bool _isLoading = true; // สถานะกำลังโหลดข้อมูล

  @override
  void initState() {
    super.initState();
    _fetchUserPoints(); // ดึงแต้มของผู้ใช้เมื่อเริ่มต้นหน้า
  }

  /// ฟังก์ชันสำหรับดึงข้อมูลผู้ใช้ทั้งหมดและอัปเดตแต้ม
  Future<void> _fetchUserPoints() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเข้าสู่ระบบเพื่อดูแต้มของคุณ')),
        );
        return;
      }

      final userModel = await _userService.getUserData();
      if (userModel != null) {
        setState(() {
          userPoints = userModel.points!;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการดึงแต้ม: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false; // ปิดสถานะกำลังโหลดข้อมูล
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ร้านค้า'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    )
                  : Text(
                      'แต้ม: $userPoints',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // แสดง Loading Indicator ขณะดึงข้อมูล
          : const Center(
              child: Text(
                'ร้านค้าสำหรับซื้อวอลเปเปอร์ (อยู่ระหว่างการพัฒนา)',
                style: TextStyle(fontSize: 18),
              ),
            ),
    );
  }
}
