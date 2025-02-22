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
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchUserPoints(),
      _fetchProducts(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchUserPoints() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('state').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            userPoints = (doc.data()?['totalPoints'] ?? 0) as int;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching user points: $e');
    }
  }

  Future<void> _fetchProducts() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('products')
          .get()
          .timeout(const Duration(seconds: 10));

      if (querySnapshot.docs.isEmpty) {
        debugPrint("❌ ไม่พบสินค้าใน Firestore!");
        return;
      }

      final List<Map<String, dynamic>> productList = [];

      for (var doc in querySnapshot.docs) {
        final productData = doc.data();

        if (!productData.containsKey('image_name') || !productData.containsKey('name') || !productData.containsKey('price')) {
          continue;
        }

        final imageName = productData['image_name'];
        if (imageName == null || imageName.isEmpty) {
          continue;
        }

        final imageUrl = _supabase.storage.from('Image').getPublicUrl(imageName);
        debugPrint("✅ ดึง URL รูปภาพสำเร็จ: $imageUrl");

        productList.add({
          'id': doc.id,
          'name': productData['name'],
          'image_url': imageUrl,
          'price': productData['price'],
        });
      }

      if (mounted) {
        setState(() {
          products = productList;
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching products: $e');
    }
  }

  Future<void> _buyProduct(Map<String, dynamic> product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final int productPrice = (product['price'] as num).toInt();

    if (userPoints < productPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('แต้มของคุณไม่เพียงพอ!')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final stateRef = FirebaseFirestore.instance.collection('state').doc(userId);
        final stateSnapshot = await transaction.get(stateRef);

        if (!stateSnapshot.exists) return;

        final currentPoints = stateSnapshot.data()?['totalPoints'] ?? 0;
        if (currentPoints < productPrice) return;

        transaction.update(stateRef, {'totalPoints': FieldValue.increment(-productPrice)});
        transaction.set(
          FirebaseFirestore.instance.collection('purchased_items').doc(),
          {
            'user_id': userId,
            'product_id': product['id'],
            'total_price': productPrice,
            'created_at': Timestamp.now(),
          },
        );
      });

      if (mounted) {
        setState(() {
          userPoints -= productPrice;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ซื้อ "${product['name']}" สำเร็จ!')),
      );
    } catch (e) {
      debugPrint("❌ Error purchasing product: $e");
    }
  }

  Widget _buildProductImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const Icon(Icons.image_not_supported, size: 50, color: Colors.grey);
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.broken_image, size: 50, color: Colors.red);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ร้านค้า'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.stars, color: Colors.amber, size: 30),
                          const SizedBox(width: 10),
                          Text(
                            'แต้มของคุณ: $userPoints',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];

                        return Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(15),
                                    topRight: Radius.circular(15),
                                  ),
                                  child: _buildProductImage(product['image_url']),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  children: [
                                    Text(
                                      product['name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                    Text('${product['price']} แต้ม', style: TextStyle(color: Colors.deepOrange, fontSize: 16)),
                                    const SizedBox(height: 10),
                                    ElevatedButton.icon(
                                      onPressed: () => _buyProduct(product),
                                      icon: const Icon(Icons.shopping_cart, color: Colors.white),
                                      label: const Text('ซื้อ', style: TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
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
