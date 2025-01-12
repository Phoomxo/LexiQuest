import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ShopPage extends StatefulWidget {
  @override
  _ShopPageState createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  int userPoints = 0; // เก็บแต้มของผู้ใช้
  List<String> imageUrls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserPoints();
    _fetchImages();
  }

  // ฟังก์ชันดึงแต้มผู้ใช้จาก Firestore
  Future<void> _fetchUserPoints() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('state')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            userPoints = doc.data()!['totalPoints'] ?? 0;
          });
        }
      }
    } catch (e) {
      print('Error fetching user points: $e');
    }
  }

  // ฟังก์ชันดึงรูปภาพจาก Supabase
  Future<void> _fetchImages() async {
    try {
      final response = await _supabase.storage.from('Image').list();
      final urls = response.map((file) {
        return _supabase.storage.from('Image').getPublicUrl(file.name);
      }).toList();

      setState(() {
        imageUrls = urls;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching images: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ร้านค้า'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // แสดงแต้มของผู้ใช้
                  Text(
                    'แต้มของคุณ: $userPoints',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // แสดงรูปภาพสินค้าในรูปแบบ GridView
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, // จำนวนคอลัมน์
                        crossAxisSpacing: 10, // ระยะห่างระหว่างคอลัมน์
                        mainAxisSpacing: 10, // ระยะห่างระหว่างแถว
                        childAspectRatio: 1, // อัตราส่วนความกว้างต่อความสูงของแต่ละช่อง
                      ),
                      itemCount: imageUrls.length,
                      itemBuilder: (context, index) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[300],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              imageUrls[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
