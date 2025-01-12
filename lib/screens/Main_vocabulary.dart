import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MainVocabulary extends StatelessWidget {
  final CollectionReference _vocabularyCollection =
      FirebaseFirestore.instance.collection('vocabulary');

  MainVocabulary({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Main Vocabulary'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            // รายการคำศัพท์ระดับ A1
            final List<Map<String, String>> words = [
              {'word': 'apple', 'meaning': 'แอปเปิล', 'part_of_speech': 'noun'},
              {'word': 'book', 'meaning': 'หนังสือ', 'part_of_speech': 'noun'},
              {'word': 'cat', 'meaning': 'แมว', 'part_of_speech': 'noun'},
              {'word': 'dog', 'meaning': 'สุนัข', 'part_of_speech': 'noun'},
              {'word': 'eat', 'meaning': 'กิน', 'part_of_speech': 'verb'},
              {'word': 'fast', 'meaning': 'เร็ว', 'part_of_speech': 'adjective'},
              {'word': 'go', 'meaning': 'ไป', 'part_of_speech': 'verb'},
              {'word': 'happy', 'meaning': 'มีความสุข', 'part_of_speech': 'adjective'},
              {'word': 'ice', 'meaning': 'น้ำแข็ง', 'part_of_speech': 'noun'},
              {'word': 'jump', 'meaning': 'กระโดด', 'part_of_speech': 'verb'},
              {'word': 'key', 'meaning': 'กุญแจ', 'part_of_speech': 'noun'},
              {'word': 'love', 'meaning': 'รัก', 'part_of_speech': 'verb'},
              {'word': 'man', 'meaning': 'ผู้ชาย', 'part_of_speech': 'noun'},
              {'word': 'night', 'meaning': 'กลางคืน', 'part_of_speech': 'noun'},
              {'word': 'open', 'meaning': 'เปิด', 'part_of_speech': 'verb'},
              {'word': 'quiet', 'meaning': 'เงียบ', 'part_of_speech': 'adjective'},
              {'word': 'run', 'meaning': 'วิ่ง', 'part_of_speech': 'verb'},
              {'word': 'sun', 'meaning': 'ดวงอาทิตย์', 'part_of_speech': 'noun'},
              {'word': 'talk', 'meaning': 'พูด', 'part_of_speech': 'verb'},
              {'word': 'water', 'meaning': 'น้ำ', 'part_of_speech': 'noun'},
              {'word': 'baby', 'meaning': 'ทารก', 'part_of_speech': 'noun'},
              {'word': 'car', 'meaning': 'รถยนต์', 'part_of_speech': 'noun'},
              {'word': 'dance', 'meaning': 'เต้น', 'part_of_speech': 'verb'},
              {'word': 'elephant', 'meaning': 'ช้าง', 'part_of_speech': 'noun'},
              {'word': 'friend', 'meaning': 'เพื่อน', 'part_of_speech': 'noun'},
              {'word': 'garden', 'meaning': 'สวน', 'part_of_speech': 'noun'},
              {'word': 'help', 'meaning': 'ช่วย', 'part_of_speech': 'verb'},
              {'word': 'island', 'meaning': 'เกาะ', 'part_of_speech': 'noun'},
              {'word': 'juice', 'meaning': 'น้ำผลไม้', 'part_of_speech': 'noun'},
              {'word': 'kite', 'meaning': 'ว่าว', 'part_of_speech': 'noun'},
              {'word': 'laugh', 'meaning': 'หัวเราะ', 'part_of_speech': 'verb'},
              {'word': 'monkey', 'meaning': 'ลิง', 'part_of_speech': 'noun'},
              {'word': 'orange', 'meaning': 'สีส้ม', 'part_of_speech': 'noun'},
              {'word': 'pencil', 'meaning': 'ดินสอ', 'part_of_speech': 'noun'},
              {'word': 'queen', 'meaning': 'ราชินี', 'part_of_speech': 'noun'},
              {'word': 'rain', 'meaning': 'ฝน', 'part_of_speech': 'noun'},
              {'word': 'smile', 'meaning': 'ยิ้ม', 'part_of_speech': 'verb'},
              {'word': 'tree', 'meaning': 'ต้นไม้', 'part_of_speech': 'noun'},
              {'word': 'umbrella', 'meaning': 'ร่ม', 'part_of_speech': 'noun'},
              {'word': 'zebra', 'meaning': 'ม้าลาย', 'part_of_speech': 'noun'},
            ];

            // เพิ่มคำศัพท์ลง Firestore
            for (var word in words) {
              await _vocabularyCollection.add(word);
            }

            // แสดงข้อความแจ้งเตือนเมื่อเพิ่มเสร็จ
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Added 20 A1 words successfully!')),
            );
          },
          child: const Text('Add 20 A1 Vocabulary'),
        ),
      ),
    );
  }
}
