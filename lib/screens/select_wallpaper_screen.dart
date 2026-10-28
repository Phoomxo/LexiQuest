import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../shop/product_artwork.dart';

class SelectWallpaperScreen extends StatefulWidget {
  const SelectWallpaperScreen({super.key});

  @override
  State<SelectWallpaperScreen> createState() => _SelectWallpaperScreenState();
}

class _SelectWallpaperScreenState extends State<SelectWallpaperScreen> {
  List<ProductArtwork> purchasedWallpapers = const [DefaultProductArtwork()];
  ProductArtwork selectedWallpaper = const DefaultProductArtwork();

  @override
  void initState() {
    super.initState();
    _fetchPurchasedWallpapers();
  }

  Future<void> _fetchPurchasedWallpapers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final purchasedSnapshot = await FirebaseFirestore.instance
        .collection('purchased_items')
        .where('user_id', isEqualTo: user.uid)
        .get();

    final wallpapers = <ProductArtwork>[const DefaultProductArtwork()];
    for (final doc in purchasedSnapshot.docs) {
      final productId = doc.data()['product_id'];
      if (productId is! String || productId.isEmpty) continue;

      final productDoc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();
      final product = productDoc.data();
      if (product == null) continue;

      final artwork = resolveProductArtwork(Map<String, Object?>.from(product));
      if (artwork is NetworkProductArtwork) {
        wallpapers.add(artwork);
      }
    }

    if (!mounted) return;
    setState(() {
      purchasedWallpapers = wallpapers;
    });
  }

  Future<void> _setWallpaper(ProductArtwork artwork) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('state').doc(user.uid).update({
      'selectedWallpaper': artwork.storageValue,
    });
    if (!mounted) return;
    setState(() {
      selectedWallpaper = artwork;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เปลี่ยนวอลเปเปอร์เรียบร้อยแล้ว')),
    );
  }

  Widget _buildArtwork(ProductArtwork artwork) {
    return switch (artwork) {
      DefaultProductArtwork() => const ColoredBox(
        color: Color(0xFFE8ECF3),
        child: Center(child: Icon(Icons.wallpaper_outlined, size: 48)),
      ),
      NetworkProductArtwork(:final uri) => Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xFFE8ECF3),
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    };
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
                  final artwork = purchasedWallpapers[index];
                  final isSelected = selectedWallpaper == artwork;

                  return GestureDetector(
                    onTap: () => _setWallpaper(artwork),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 5,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: isSelected
                              ? Colors.blueAccent
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildArtwork(artwork),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
