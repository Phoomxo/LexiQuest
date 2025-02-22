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

  String _getSupabaseImageUrl(String imageName) {
    final supabase = Supabase.instance.client;
    return supabase.storage.from('Image').getPublicUrl(imageName);
  }

  Future<void> _fetchPurchasedWallpapers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final purchasedSnapshot = await FirebaseFirestore.instance
        .collection('purchased_items')
        .where('user_id', isEqualTo: user.uid)
        .get();

    List<String> wallpapers = ["default"];
    for (var doc in purchasedSnapshot.docs) {
      final productId = doc.data()['product_id'];
      if (productId != null) {
        final productDoc = await FirebaseFirestore.instance
            .collection('products')
            .doc(productId)
            .get();

        if (productDoc.exists && productDoc.data()?['image_name'] != null) {
          final imageName = productDoc.data()?['image_name'];
          final imageUrl = _getSupabaseImageUrl(imageName);
          wallpapers.add(imageUrl);
        }
      }
    }

    setState(() {
      purchasedWallpapers = wallpapers;
    });
  }

  Future<void> _setWallpaper(String wallpaperUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('state').doc(user.uid).update({
        'selectedWallpaper': wallpaperUrl == "default" ? null : wallpaperUrl,
      });
      setState(() {
        selectedWallpaper = wallpaperUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปลี่ยนวอลเปเปอร์สำเร็จ!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกวอลเปเปอร์')),
      body: purchasedWallpapers.isEmpty
          ? const Center(child: Text('คุณยังไม่มีวอลเปเปอร์ที่ซื้อ'))
          : Padding(
              padding: const EdgeInsets.all(10),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  childAspectRatio: 0.8,
                ),
                itemCount: purchasedWallpapers.length,
                itemBuilder: (context, index) {
                  final wallpaper = purchasedWallpapers[index];
                  final isSelected = selectedWallpaper == wallpaper;

                  return GestureDetector(
                    onTap: () => _setWallpaper(wallpaper),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 5,
                            spreadRadius: 2,
                          )
                        ],
                        border: Border.all(
                          color: isSelected ? Colors.blueAccent : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: wallpaper == "default"
                            ? Container(
                                color: Colors.grey.shade300,
                                child: const Center(
                                  child: Icon(Icons.image, size: 50, color: Colors.grey),
                                ),
                              )
                            : Image.network(
                                wallpaper,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(child: CircularProgressIndicator());
                                },
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
