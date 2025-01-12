import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/category_model.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CollectionReference _categoriesCollection =
      FirebaseFirestore.instance.collection('categories');

  /// เพิ่ม Category ใหม่ พร้อมบันทึก uid ของผู้ใช้
  Future<void> addCategory(String categoryName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    final categoryRef = _categoriesCollection.doc();
    await categoryRef.set({
      'category_name': categoryName,
      'created_at': Timestamp.now(),
      'uid': user.uid, // บันทึก uid ของผู้ใช้ที่สร้าง Category
    });

    print('Category added with ID: ${categoryRef.id}');
  }

  Future<void> addWord(String categoryId, String word, String meaning, String partOfSpeech) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception('User not logged in');
  }

  final wordRef = FirebaseFirestore.instance
      .collection('categories')
      .doc(categoryId)
      .collection('words')
      .doc();

  await wordRef.set({
    'word': word,
    'meaning': meaning,
    'part_of_speech': partOfSpeech,
    'user_id': user.uid,
    'is_global': false,
    'created_at': Timestamp.now(),
  });

  print('Word added with ID: ${wordRef.id}');
}

  /// ดึง Category ของผู้ใช้ปัจจุบันเท่านั้น
 Stream<List<Category>> getCategoriesStream() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    print('No user is logged in'); // กรณีที่ไม่มีผู้ใช้ล็อกอิน
    return const Stream.empty();
  }

  print('Current user UID: ${user.uid}'); // เพิ่ม log เพื่อตรวจสอบ UID ของผู้ใช้

  return _categoriesCollection
      .where('uid', isEqualTo: user.uid) // ตรวจสอบให้ uid ตรงกัน
      .snapshots()
      .map((snapshot) {
    return snapshot.docs
        .map((doc) => Category.fromDocumentSnapshot(doc))
        .toList();
  });
}



  /// ลบ Category ตาม categoryId
  Future<void> deleteCategory(String categoryId) async {
    try {
      await _categoriesCollection.doc(categoryId).delete();
      print('Category deleted successfully');
    } catch (e) {
      print('Failed to delete category: $e');
      throw Exception('Failed to delete category: $e');
    }
  }
}
