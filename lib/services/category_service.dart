import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/category_model.dart' as models;

class CategoryService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference get _categoriesCollection {
    return FirebaseFirestore.instance.collection('categories');
  }

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
      'uid': user.uid,
    });

    debugPrint('Category added with ID: ${categoryRef.id}');
  }

  /// ฟังก์ชันเพิ่มคำศัพท์ในหมวดหมู่
  Future<void> addWord(
    String categoryId,
    String word,
    String meaning,
    String partOfSpeech,
  ) async {
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

    debugPrint('Word added with ID: ${wordRef.id}');
  }

  /// เพิ่มหมวดหมู่พร้อมคำศัพท์ให้ผู้ใช้
  Future<void> addCategoryForUser(
    String categoryName,
    String uid,
    List<Map<String, String>> words,
  ) async {
    final categoryRef = _firestore.collection('categories').doc();
    await categoryRef.set({
      'category_name': categoryName,
      'created_at': Timestamp.now(),
      'uid': uid,
    });

    for (var wordData in words) {
      final wordRef = categoryRef.collection('words').doc();
      await wordRef.set({
        'word': wordData["word"] ?? '',
        'meaning': wordData["meaning"] ?? '',
        'part_of_speech': wordData["part_of_speech"] ?? '',
        'user_id': uid,
        'is_global': false,
        'created_at': Timestamp.now(),
      });
    }

    debugPrint("✅ Category and words added: $categoryName");
  }

  /// ลบหมวดหมู่
  Future<void> deleteCategory(String categoryId) async {
    try {
      await _categoriesCollection.doc(categoryId).delete();
      debugPrint('Category deleted successfully');
    } catch (_) {
      debugPrint('Category deletion failed.');
      throw Exception('Category deletion failed.');
    }
  }

  /// ดึงหมวดหมู่เฉพาะของผู้ใช้ปัจจุบัน
  Stream<List<models.Category>> getCategoriesStream() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const Stream.empty();
      }

      return _categoriesCollection
          .where('uid', isEqualTo: user.uid)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => models.Category.fromDocumentSnapshot(doc))
                .toList(),
          );
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// เพิ่มหมวดหมู่เริ่มต้นให้กับผู้ใช้ใหม่ (เรียกใช้ได้จาก UI)
  Future<void> addDefaultCategoriesForNewUser(String uid) async {
    List<Map<String, dynamic>> defaultCategories = [
      {
        'category_name': 'สัตว์ (Animals)',
        'words': [
          {"word": "Dog", "meaning": "หมา", "part_of_speech": "Noun"},
          {"word": "Cat", "meaning": "แมว", "part_of_speech": "Noun"},
          {"word": "Elephant", "meaning": "ช้าง", "part_of_speech": "Noun"},
          {"word": "Tiger", "meaning": "เสือ", "part_of_speech": "Noun"},
          {"word": "Lion", "meaning": "สิงโต", "part_of_speech": "Noun"},
          {"word": "Monkey", "meaning": "ลิง", "part_of_speech": "Noun"},
          {"word": "Zebra", "meaning": "ม้าลาย", "part_of_speech": "Noun"},
          {"word": "Bear", "meaning": "หมี", "part_of_speech": "Noun"},
          {"word": "Rabbit", "meaning": "กระต่าย", "part_of_speech": "Noun"},
          {"word": "Horse", "meaning": "ม้า", "part_of_speech": "Noun"},
        ],
      },
      {
        'category_name': 'อาหาร (Food)',
        'words': [
          {"word": "Rice", "meaning": "ข้าว", "part_of_speech": "Noun"},
          {"word": "Apple", "meaning": "แอปเปิ้ล", "part_of_speech": "Noun"},
          {"word": "Bread", "meaning": "ขนมปัง", "part_of_speech": "Noun"},
          {"word": "Milk", "meaning": "นม", "part_of_speech": "Noun"},
          {"word": "Egg", "meaning": "ไข่", "part_of_speech": "Noun"},
          {"word": "Fish", "meaning": "ปลา", "part_of_speech": "Noun"},
          {"word": "Chicken", "meaning": "ไก่", "part_of_speech": "Noun"},
          {"word": "Banana", "meaning": "กล้วย", "part_of_speech": "Noun"},
          {"word": "Orange", "meaning": "ส้ม", "part_of_speech": "Noun"},
          {"word": "Soup", "meaning": "ซุป", "part_of_speech": "Noun"},
        ],
      },
      {
        'category_name': 'อาชีพ (Jobs)',
        'words': [
          {"word": "Teacher", "meaning": "ครู", "part_of_speech": "Noun"},
          {"word": "Doctor", "meaning": "หมอ", "part_of_speech": "Noun"},
          {"word": "Engineer", "meaning": "วิศวกร", "part_of_speech": "Noun"},
          {"word": "Nurse", "meaning": "พยาบาล", "part_of_speech": "Noun"},
          {"word": "Police", "meaning": "ตำรวจ", "part_of_speech": "Noun"},
          {"word": "Farmer", "meaning": "ชาวนา", "part_of_speech": "Noun"},
          {
            "word": "Chef",
            "meaning": "พ่อครัว / แม่ครัว",
            "part_of_speech": "Noun",
          },
          {
            "word": "Firefighter",
            "meaning": "นักดับเพลิง",
            "part_of_speech": "Noun",
          },
          {"word": "Driver", "meaning": "คนขับรถ", "part_of_speech": "Noun"},
          {"word": "Singer", "meaning": "นักร้อง", "part_of_speech": "Noun"},
        ],
      },
      {
        'category_name': 'กีฬา (Sports)',
        'words': [
          {"word": "Football", "meaning": "ฟุตบอล", "part_of_speech": "Noun"},
          {
            "word": "Basketball",
            "meaning": "บาสเกตบอล",
            "part_of_speech": "Noun",
          },
          {"word": "Tennis", "meaning": "เทนนิส", "part_of_speech": "Noun"},
          {
            "word": "Badminton",
            "meaning": "แบดมินตัน",
            "part_of_speech": "Noun",
          },
          {
            "word": "Volleyball",
            "meaning": "วอลเลย์บอล",
            "part_of_speech": "Noun",
          },
          {
            "word": "Swimming",
            "meaning": "การว่ายน้ำ",
            "part_of_speech": "Noun",
          },
          {"word": "Running", "meaning": "การวิ่ง", "part_of_speech": "Noun"},
          {
            "word": "Cycling",
            "meaning": "การปั่นจักรยาน",
            "part_of_speech": "Noun",
          },
          {"word": "Boxing", "meaning": "มวย", "part_of_speech": "Noun"},
          {"word": "Golf", "meaning": "กอล์ฟ", "part_of_speech": "Noun"},
        ],
      },
      {
        'category_name': 'การท่องเที่ยว (Travel)',
        'words': [
          {
            "word": "Passport",
            "meaning": "หนังสือเดินทาง",
            "part_of_speech": "Noun",
          },
          {"word": "Ticket", "meaning": "ตั๋ว", "part_of_speech": "Noun"},
          {
            "word": "Luggage",
            "meaning": "กระเป๋าเดินทาง",
            "part_of_speech": "Noun",
          },
          {"word": "Hotel", "meaning": "โรงแรม", "part_of_speech": "Noun"},
          {"word": "Flight", "meaning": "เที่ยวบิน", "part_of_speech": "Noun"},
          {"word": "Map", "meaning": "แผนที่", "part_of_speech": "Noun"},
          {
            "word": "Destination",
            "meaning": "จุดหมายปลายทาง",
            "part_of_speech": "Noun",
          },
          {
            "word": "Tourist",
            "meaning": "นักท่องเที่ยว",
            "part_of_speech": "Noun",
          },
          {
            "word": "Travel agency",
            "meaning": "บริษัททัวร์",
            "part_of_speech": "Noun",
          },
          {
            "word": "Adventure",
            "meaning": "การผจญภัย",
            "part_of_speech": "Noun",
          },
        ],
      },
    ];

    for (var category in defaultCategories) {
      final categoryRef = _firestore.collection('categories').doc();
      await categoryRef.set({
        'category_name': category['category_name'] ?? '',
        'created_at': Timestamp.now(),
        'uid': uid,
      });

      for (var wordData in category['words']) {
        final wordRef = categoryRef.collection('words').doc();
        await wordRef.set({
          'word': wordData["word"] ?? '',
          'meaning': wordData["meaning"] ?? '',
          'part_of_speech': wordData["part_of_speech"] ?? '',
          'user_id': uid,
          'is_global': false,
          'created_at': Timestamp.now(),
        });
      }
    }

    debugPrint("✅ Default categories and words added.");
  }
}
