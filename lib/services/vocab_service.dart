import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vocab_model.dart';

class VocabService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔹 ดึงคำศัพท์สุ่มจำนวนที่กำหนด (จำกัดจำนวน)
  Future<List<Vocab>> getRandomVocab(int limit) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final querySnapshot = await _firestore
          .collection('vocabulary')
          .where('uid', isEqualTo: user.uid)
          .get();

      final allVocab = querySnapshot.docs.map((doc) {
        return Vocab.fromMap(doc.data(), doc.id);
      }).toList();

      // สุ่มคำศัพท์และจำกัดจำนวน
      allVocab.shuffle();  // Shuffle รายการคำศัพท์
      return allVocab.take(limit).toList(); // เลือกคำศัพท์ตามจำนวนที่ต้องการ
    } catch (e) {
      throw Exception('Failed to fetch vocabulary: $e');
    }
  }

  /// 🔹 ดึงคำศัพท์จากหมวดหมู่ที่กำหนด
  Future<List<Vocab>> getVocabFromCategory(String categoryId) async {
    try {
      final querySnapshot = await _firestore
          .collection('categories')
          .doc(categoryId)
          .collection('words')
          .get();

      if (querySnapshot.docs.isEmpty) {
        // ใช้ exception เมื่อไม่พบคำศัพท์
        throw Exception('No vocabulary found in the selected category.');
      }

      // แปลงเอกสารเป็นคำศัพท์
      final vocabList = querySnapshot.docs.map((doc) {
        return Vocab.fromMap(doc.data(), doc.id);
      }).toList();

      vocabList.shuffle();  // Shuffle รายการคำศัพท์
      return vocabList;  // ส่งผลลัพธ์
    } catch (e) {
      throw Exception('Failed to fetch vocabulary from category: $e');
    }
  }
}
