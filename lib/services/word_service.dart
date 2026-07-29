import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
      throw ArgumentError('Error: Category ID cannot be empty');
    }
  }

  /// 🔹 ตรวจสอบว่าหมวดหมู่สามารถเพิ่มคำศัพท์ได้อีกหรือไม่ (สูงสุด 50 คำ)
  Future<bool> canAddMoreWords() async {
    QuerySnapshot wordCountSnapshot = await _wordsCollection.get();
    return wordCountSnapshot.size < 50;
  }

  /// 🔹 ดึงคำศัพท์ทั้งหมดในหมวดหมู่ (Stream)
  Stream<List<Word>> getWordsStream() {
    return _wordsCollection.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Word.fromDocumentSnapshot(doc))
          .toList();
    });
  }

  /// 🔹 ดึงคำศัพท์ทั้งหมดในหมวดหมู่ (Future)
  Future<List<Word>> getAllWords() async {
    QuerySnapshot snapshot = await _wordsCollection.get();
    return snapshot.docs.map((doc) => Word.fromDocumentSnapshot(doc)).toList();
  }

  /// 🔹 เพิ่มคำศัพท์แบบปกติ (จำกัด 50 คำ)
  Future<void> addWord(Word word) async {
    bool canAdd = await canAddMoreWords();
    if (!canAdd) {
      throw Exception('หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว ไม่สามารถเพิ่มได้อีก');
    }

    DocumentReference wordRef = _wordsCollection.doc();
    await wordRef.set(word.toMap());

    debugPrint('✅ เพิ่มคำศัพท์สำเร็จ: ${word.word}');
  }

  /// 🔹 เพิ่มคำศัพท์จาก Datamuse API (จำกัด 50 คำ)
  Future<void> addWordFromDatamuse(Word word) async {
    bool canAdd = await canAddMoreWords();
    if (!canAdd) {
      throw Exception('หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว ไม่สามารถเพิ่มได้อีก');
    }

    // บันทึกคำศัพท์โดยกำหนด `userId` เป็นว่างเปล่า เพื่อให้รู้ว่ามาจาก Datamuse
    DocumentReference wordRef = _wordsCollection.doc();
    await wordRef.set({
      ...word.toMap(),
      "userId": "", // 🔹 บ่งบอกว่ามาจาก Datamuse API
    });

    debugPrint('✅ เพิ่มคำศัพท์จาก Datamuse API: ${word.word}');
  }

  /// 🔹 เพิ่มหลายคำศัพท์พร้อมกัน (Batch Write)
  Future<void> addMultipleWords(
    List<Word> words, {
    bool isFromDatamuse = false,
  }) async {
    QuerySnapshot wordCountSnapshot = await _wordsCollection.get();
    int currentWordCount = wordCountSnapshot.size;

    // คำนวณจำนวนคำที่สามารถเพิ่มได้
    int remainingSlots = 50 - currentWordCount;
    if (remainingSlots <= 0) {
      throw Exception('หมวดหมู่นี้มีคำศัพท์ครบ 50 คำแล้ว ไม่สามารถเพิ่มได้อีก');
    }

    // ถ้าคำศัพท์ที่ผู้ใช้ต้องการเพิ่มเกินจำนวนที่เหลือ → ตัดจำนวนให้พอดี
    List<Word> wordsToAdd = words.take(remainingSlots).toList();

    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var word in wordsToAdd) {
      DocumentReference newDoc = _wordsCollection.doc();
      batch.set(newDoc, {
        ...word.toMap(),
        if (isFromDatamuse) "userId": "", // 🔹 บ่งบอกว่ามาจาก Datamuse API
      });
    }

    await batch.commit();
    debugPrint('✅ เพิ่มคำศัพท์สำเร็จ! (${wordsToAdd.length} คำ)');
  }

  /// 🔹 ลบคำศัพท์จากหมวดหมู่
  Future<void> deleteWord(String wordId) async {
    await _wordsCollection.doc(wordId).delete();
    debugPrint('🗑️ ลบคำศัพท์สำเร็จ!');
  }

  /// 🔹 ลบคำศัพท์ทั้งหมดในหมวดหมู่
  Future<void> deleteAllWords() async {
    QuerySnapshot snapshot = await _wordsCollection.get();
    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    debugPrint('🗑️ ลบคำศัพท์ทั้งหมดสำเร็จ!');
  }

  /// 🔹 อัปเดตคำศัพท์
  Future<void> updateWord(String wordId, Word word) async {
    await _wordsCollection.doc(wordId).update(word.toMap());
    debugPrint('✏️ อัปเดตคำศัพท์สำเร็จ: ${word.word}');
  }
}
