import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vocab_learning_app/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Seed Firestore products collection with wallpapers', () async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final firestore = FirebaseFirestore.instance;

      final List<Map<String, dynamic>> defaultProducts = [
        {
          'id': 'wallpaper_neon',
          'name': 'วอลเปเปอร์ Neon Cyberpunk',
          'image_name': 'wallpaper_neon.png',
          'image_url':
              'https://images.unsplash.com/photo-1508739773434-c26b3d09e071?auto=format&fit=crop&w=600&q=80',
          'price': 50,
        },
        {
          'id': 'wallpaper_sakura',
          'name': 'วอลเปเปอร์ Sakura Blossom',
          'image_name': 'wallpaper_sakura.png',
          'image_url':
              'https://images.unsplash.com/photo-1522383225653-ed111181a951?auto=format&fit=crop&w=600&q=80',
          'price': 100,
        },
        {
          'id': 'wallpaper_galaxy',
          'name': 'วอลเปเปอร์ Cosmic Galaxy',
          'image_name': 'wallpaper_galaxy.png',
          'image_url':
              'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?auto=format&fit=crop&w=600&q=80',
          'price': 150,
        },
        {
          'id': 'wallpaper_gold',
          'name': 'วอลเปเปอร์ Golden Castle',
          'image_name': 'wallpaper_gold.png',
          'image_url':
              'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=600&q=80',
          'price': 200,
        },
      ];

      for (var item in defaultProducts) {
        await firestore.collection('products').doc(item['id']).set({
          'name': item['name'],
          'image_name': item['image_name'],
          'image_url': item['image_url'],
          'price': item['price'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      // ignore: avoid_print
      print(
        '✅ Successfully seeded 4 wallpaper products into Firebase Firestore DB!',
      );
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ Firestore seed note: $e');
    }
  });
}
