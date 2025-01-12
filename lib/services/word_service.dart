
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/word_model.dart';

class WordService {
  final String categoryId;
  final CollectionReference _wordsCollection;

  WordService({required this.categoryId})
      : _wordsCollection = FirebaseFirestore.instance
            .collection('categories')
            .doc(categoryId)
            .collection('words') {
    if (categoryId.isEmpty) {
      print('Error: Category ID is empty');
      throw ArgumentError('Error: Category ID cannot be empty');
    }
    print('WordService initialized with categoryId: $categoryId');
  }

  /// ดึงคำศัพท์ทั้งหมดในหมวดหมู่แบบ Stream
  Stream<List<Word>> getWordsStream() {
    stderr.writeln('Fetching words for categoryId: $categoryId');
    if (categoryId.isEmpty) {
      print('Error: Category ID is empty before fetching words');
      return Stream.value([]);
    }
    print('Fetching words for categoryId: $categoryId');
    return _wordsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Word.fromDocumentSnapshot(doc)).toList();
    });
  }

  /// ลบคำศัพท์จากหมวดหมู่
  Future<void> deleteWord(String wordId) async {
    if (categoryId.isEmpty) {
      print('Error: Cannot delete word because category ID is empty');
      return;
    }
    print('Deleting word with ID: $wordId from categoryId: $categoryId');
    await _wordsCollection.doc(wordId).delete();
  }

  /// เพิ่มคำศัพท์ใหม่
  Future<void> addWord(Word word) async {
  if (categoryId.isEmpty) {
    print('Error: Cannot add word because category ID is empty');
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    print('Error: No user is signed in');
    return;
  }

  final wordRef = _wordsCollection.doc();
  await wordRef.set({
    ...word.toMap(),
    'uid': user.uid, // บันทึก uid ของผู้ใช้
  });
  print('Word added with ID: ${wordRef.id} to categoryId: $categoryId');
}


  /// อัปเดตคำศัพท์
  Future<void> updateWord(String wordId, Word word) async {
    if (categoryId.isEmpty) {
      print('Error: Cannot update word because category ID is empty');
      return;
    }
    print('Updating word with ID: $wordId in categoryId: $categoryId');
    await _wordsCollection.doc(wordId).update(word.toMap());
  }
}