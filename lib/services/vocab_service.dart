import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vocab_model.dart';

class VocabService {
  final CollectionReference _vocabCollection =
      FirebaseFirestore.instance.collection('vocabulary');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Add new vocabulary to the general collection
  Future<void> addVocab(Vocab vocab) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('Error: No user is signed in');
      return;
    }

    await _vocabCollection.add({
      ...vocab.toMap(),
      'uid': user.uid, // บันทึก uid ของผู้ใช้
    });
  }

  /// Update existing vocabulary in the general collection
  Future<void> updateVocab(Vocab vocab) async {
    if (vocab.id == null) {
      throw Exception('Vocabulary ID cannot be null for updating.');
    }

    try {
      await _vocabCollection.doc(vocab.id).update(vocab.toMap());
    } catch (e) {
      throw Exception('Failed to update vocabulary: $e');
    }
  }

  /// Fetch vocabulary list from the general collection
  Future<List<Vocab>> getVocabFromAppCollection() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final querySnapshot = await _vocabCollection
        .where('uid', isEqualTo: user.uid) // กรองข้อมูลด้วย uid
        .get();

    return querySnapshot.docs.map((doc) {
      return Vocab.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }

  /// Fetch vocabulary list from a specific category
  Future<List<Vocab>> getVocabFromCategory(String categoryId) async {
    try {
      final querySnapshot = await _firestore
          .collection('categories')
          .doc(categoryId)
          .collection('words')
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('No vocabulary found in the selected category.');
      }

      return querySnapshot.docs.map((doc) {
        return Vocab.fromMap(doc.data(), doc.id);
      }).toList()
        ..shuffle();
    } catch (e) {
      throw Exception('Failed to fetch vocabulary from category: $e');
    }
  }
}
