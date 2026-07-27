import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class GlobalWordService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔎 **ค้นหาคำศัพท์ใน Firestore (global_words)**
  Future<Map<String, dynamic>?> findWordInDatabase(String word) async {
    DocumentSnapshot doc = await _firestore.collection('global_words').doc(word).get();

    if (doc.exists) {
      print('✅ พบคำศัพท์ใน Firestore: $word');
      return doc.data() as Map<String, dynamic>;
    }
    return null;
  }

  /// ➕ **เพิ่มคำศัพท์ลง Firestore ถ้ายังไม่มี**
  Future<Map<String, dynamic>> addWordToDatabase(String word) async {
    // 1️⃣ ลองค้นหาคำศัพท์ก่อน
    final existingWord = await findWordInDatabase(word);
    if (existingWord != null) {
      return existingWord; // ถ้ามีอยู่แล้ว ใช้คำนี้เลย
    }

    // 2️⃣ ถ้าไม่มี → เรียก API
    final url = Uri.parse('https://api.datamuse.com/words?sp=$word*');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List data = json.decode(response.body);

      if (data.isNotEmpty) {
        String meaning = "ไม่พบความหมาย"; // ค่าเริ่มต้น
        String partOfSpeech = "unknown";

        // 🔹 ดึงข้อมูลจาก Dictionary API
        final dictUrl = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
        final dictResponse = await http.get(dictUrl);

        if (dictResponse.statusCode == 200) {
          final List<dynamic> dictData = json.decode(dictResponse.body);
          if (dictData.isNotEmpty) {
            meaning = dictData[0]['meanings'][0]['definitions'][0]['definition'];
            partOfSpeech = dictData[0]['meanings'][0]['partOfSpeech'];
          }
        }

        // 🔹 บันทึกคำศัพท์ลง `global_words`
        await _firestore.collection('global_words').doc(word).set({
          'word': word,
          'meaning': meaning,
          'partOfSpeech': partOfSpeech,
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('✅ เพิ่มคำศัพท์ลง Firestore: $word');
        return {
          'word': word,
          'meaning': meaning,
          'partOfSpeech': partOfSpeech,
        };
      }
    }

    throw Exception('ไม่สามารถดึงข้อมูลคำศัพท์ได้');
  }
}
