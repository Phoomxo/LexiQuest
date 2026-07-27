import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ShopPage extends StatefulWidget {
  @override
  _ShopPageState createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  int userPoints = 0; // เก็บแต้มของผู้ใช้

  @override
  void initState() {
    super.initState();
    _fetchUserPoints(); // ดึงแต้มเมื่อเริ่มต้นหน้า
  }

  Future<void> _fetchUserPoints() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        userPoints = doc.data()?['points'] ?? 0; // กำหนดแต้มของผู้ใช้
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
              child: Text(
                'แต้ม: $userPoints',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Text(
          'ร้านค้าสำหรับซื้อวอลเปเปอร์ (อยู่ระหว่างการพัฒนา)',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
