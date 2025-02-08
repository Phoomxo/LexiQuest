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
  int userPoints = 0;
  List<Map<String, dynamic>> products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserPoints();
    _fetchProducts();
  }

  // ดึงแต้มของผู้ใช้จาก Firestore
  Future<void> _fetchUserPoints() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('state').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            userPoints = doc.data()?['totalPoints'] ?? 0;
          });
        }
      }
    } catch (e) {
      print('❌ Error fetching user points: $e');
    }
  }

  // ดึงข้อมูลสินค้า (ชื่อ, รูปภาพ, ราคา) จาก Firestore และ Supabase
  Future<void> _fetchProducts() async {
    try {
      print("📢 กำลังโหลดสินค้า...");

      final querySnapshot = await FirebaseFirestore.instance.collection('products').get();

      if (querySnapshot.docs.isEmpty) {
        print("❌ ไม่พบสินค้าใน Firestore!");
        return;
      }

      final List<Map<String, dynamic>> productList = [];

      for (var doc in querySnapshot.docs) {
        final productData = doc.data();

        if (!productData.containsKey('image_name') || !productData.containsKey('name') || !productData.containsKey('price')) {
          print("⚠️ สินค้า ${doc.id} ขาดข้อมูลที่จำเป็น!");
          continue;
        }

        // ตรวจสอบว่า image_name ไม่เป็นค่าว่าง
        final imageName = productData['image_name'];
        if (imageName == null || imageName.isEmpty) {
          print("⚠️ image_name ของสินค้า ${doc.id} ว่างเปล่า!");
          continue;
        }

        // ดึง URL รูปภาพจาก Supabase Storage
        final imageUrl = _supabase.storage.from('Image').getPublicUrl(imageName);
        print("✅ ดึง URL สำเร็จ: $imageUrl");

        productList.add({
          'id': doc.id,
          'name': productData['name'],
          'image_url': imageUrl,
          'price': productData['price'],
        });
      }

      // ตรวจสอบว่า Widget ยังอยู่ใน Tree หรือไม่ก่อนเรียก setState()
      if (mounted) {
        setState(() {
          products = productList;
          _isLoading = false;
        });
      }

      print("🎯 โหลดสินค้าสำเร็จ ${products.length} รายการ");
    } catch (e) {
      print('❌ Error fetching products: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ฟังก์ชันซื้อสินค้า
  Future<void> _buyProduct(Map<String, dynamic> product) async {
    print("🛒 กำลังซื้อสินค้า: ${product['name']} ราคา: ${product['price']} แต้ม");

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("❌ ไม่พบผู้ใช้");
      return;
    }

    final userId = user.uid;

    // ตรวจสอบว่าสินค้านี้ถูกซื้อไปแล้วหรือยัง
    final checkPurchased = await FirebaseFirestore.instance
        .collection('purchased_items')
        .where('user_id', isEqualTo: userId)
        .where('product_id', isEqualTo: product['id'])
        .get();

    if (checkPurchased.docs.isNotEmpty) {
      print("❌ คุณได้ซื้อสินค้านี้ไปแล้ว!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คุณซื้อสินค้านี้ไปแล้ว!')),
      );
      return;
    }

    if (userPoints < (product['price'] as num).toInt()) {
      print("❌ แต้มไม่พอ! มีแต้ม: $userPoints | ราคาสินค้า: ${product['price']}");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('แต้มของคุณไม่เพียงพอ!')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('state').doc(userId).update({
        'totalPoints': FieldValue.increment(-(product['price'] as num).toInt()),
      });

      await FirebaseFirestore.instance.collection('purchased_items').add({
        'user_id': userId,
        'product_id': product['id'],
        'total_price': (product['price'] as num).toInt(),
        'created_at': Timestamp.now(),
      });

      setState(() {
        userPoints -= (product['price'] as num).toInt();
      });

      print("✅ ซื้อสำเร็จ! แต้มที่เหลือ: $userPoints");

      _showSuccessDialog(product['name']);
    } catch (e) {
      print("❌ Error purchasing product: $e");
    }
  }

  // แสดง Dialog เมื่อซื้อสำเร็จ
  void _showSuccessDialog(String productName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("🎉 การซื้อสำเร็จ!"),
          content: Text("คุณได้ซื้อ $productName เรียบร้อยแล้ว!"),
          actions: [
            TextButton(
              child: const Text("ตกลง"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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
                  Text(
                    'แต้มของคุณ: $userPoints',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
Expanded(
  child: GridView.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.7,
    ),
    itemCount: products.length,
    itemBuilder: (context, index) {
      final product = products[index];

      return Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Image.network(product['image_url'], fit: BoxFit.cover, width: double.infinity),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${product['price']} แต้ม', style: TextStyle(color: Colors.deepOrange, fontSize: 16)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _buyProduct(product),
                    icon: const Icon(Icons.shopping_cart, color: Colors.white),
                    label: const Text('ซื้อ', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, // ปรับสีปุ่ม
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
