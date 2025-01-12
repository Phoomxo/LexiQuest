import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vocab_model.dart';

class VocabService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

      allVocab.shuffle();
      return allVocab.take(limit).toList();
    } catch (e) {
      throw Exception('Failed to fetch vocabulary: $e');
    }
  }

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