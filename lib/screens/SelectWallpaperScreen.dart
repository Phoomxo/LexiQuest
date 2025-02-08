import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectWallpaperScreen extends StatefulWidget {
  @override
  _SelectWallpaperScreenState createState() => _SelectWallpaperScreenState();
}

class _SelectWallpaperScreenState extends State<SelectWallpaperScreen> {
  List<String> purchasedWallpapers = [];
  String? selectedWallpaper;

  @override
  void initState() {
    super.initState();
    _fetchPurchasedWallpapers();
  }

  // ฟังก์ชันดึง URL ของรูปจาก Supabase Storage
  String _getSupabaseImageUrl(String imageName) {
  final supabase = Supabase.instance.client;
  final imageUrl = supabase.storage.from('Image').getPublicUrl(imageName);
  print("🔗 Supabase Image URL: $imageUrl");
  return imageUrl;
}


  // ฟังก์ชันดึงวอลเปเปอร์ที่ผู้ใช้ซื้อจาก Firestore
  Future<void> _fetchPurchasedWallpapers() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  print("🔍 กำลังดึงข้อมูลวอลเปเปอร์ของผู้ใช้ ${user.uid}");

  final purchasedSnapshot = await FirebaseFirestore.instance
      .collection('purchased_items')
      .where('user_id', isEqualTo: user.uid)
      .get();

  print("🛒 จำนวนวอลเปเปอร์ที่ซื้อ: ${purchasedSnapshot.docs.length}");

  List<String> wallpapers = [];

   // ✅ เพิ่ม "Default Wallpaper" (วอลเปเปอร์สีขาว)
  wallpapers.add("default"); // ใช้เป็นค่าพิเศษสำหรับสีขาว

  for (var doc in purchasedSnapshot.docs) {
    final productId = doc.data()['product_id'];
    print("🔍 ตรวจสอบ product_id: $productId");

    if (productId != null) {
      final productDoc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();

      if (productDoc.exists && productDoc.data()?['image_name'] != null) {
        final imageName = productDoc.data()?['image_name'];
        print("🖼️ พบ image_name: $imageName");

        // ใช้ Supabase Storage เพื่อสร้าง URL
        final imageUrl = _getSupabaseImageUrl(imageName);
        print("✅ พบวอลเปเปอร์: $imageUrl");

        wallpapers.add(imageUrl);
      } else {
        print("⚠️ ไม่พบ image_name สำหรับ product_id: $productId");
      }
    }
  }

  setState(() {
    purchasedWallpapers = wallpapers;
  });

  print("🎯 วอลเปเปอร์ที่จะแสดง: ${purchasedWallpapers.length}");
}




  // ฟังก์ชันเปลี่ยนวอลเปเปอร์ที่เลือก
  Future<void> _setWallpaper(String wallpaperUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('state').doc(user.uid).update({
        'selectedWallpaper': wallpaperUrl == "default" ? null : wallpaperUrl, // ✅ ถ้าเลือก "default" ให้ตั้งค่าเป็น `null`
      });

      setState(() {
        selectedWallpaper = wallpaperUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปลี่ยนวอลเปเปอร์สำเร็จ!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกวอลเปเปอร์')),
      body: purchasedWallpapers.isEmpty
          ? const Center(child: Text('คุณยังไม่มีวอลเปเปอร์ที่ซื้อ'))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: purchasedWallpapers.length,
              itemBuilder: (context, index) {
  final wallpaper = purchasedWallpapers[index];

  return GestureDetector(
    onTap: () => _setWallpaper(wallpaper),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: selectedWallpaper == wallpaper ? Colors.green : Colors.transparent,
          width: 3,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: wallpaper == "default"
            ? Container(color: Colors.white) // ✅ ใช้สีขาวเป็น Default Wallpaper
            : Image.network(
                wallpaper,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(Icons.error, color: Colors.red),
              ),
      ),
    ),
  );
},

            ),
    );
  }
}
