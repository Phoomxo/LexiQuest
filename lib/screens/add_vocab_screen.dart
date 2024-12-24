import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddVocabScreen extends StatefulWidget {
  final String categoryId; // หมวดหมู่ที่เลือก
  final QueryDocumentSnapshot? vocab; // เอกสารคำศัพท์ (ถ้ามี)

  AddVocabScreen({required this.categoryId, this.vocab});

  @override
  _AddVocabScreenState createState() => _AddVocabScreenState();
}

class _AddVocabScreenState extends State<AddVocabScreen> {
  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _meaningController = TextEditingController();
  final TextEditingController _partOfSpeechController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // หาก vocab มีค่าจะเติมข้อมูลใน TextField
    if (widget.vocab != null) {
      _wordController.text = widget.vocab!['word'];
      _meaningController.text = widget.vocab!['meaning'];
      _partOfSpeechController.text = widget.vocab!['part_of_speech'];
    }
  }

  Future<void> _saveVocab() async {
    final CollectionReference wordsCollection = FirebaseFirestore.instance
        .collection('categories')
        .doc(widget.categoryId)
        .collection('words');

    if (widget.vocab == null) {
      // เพิ่มคำศัพท์ใหม่
      await wordsCollection.add({
        'word': _wordController.text.trim(),
        'meaning': _meaningController.text.trim(),
        'part_of_speech': _partOfSpeechController.text.trim(),
        'created_at': Timestamp.now(),
      });
    } else {
      // แก้ไขคำศัพท์ที่มีอยู่
      await wordsCollection.doc(widget.vocab!.id).update({
        'word': _wordController.text.trim(),
        'meaning': _meaningController.text.trim(),
        'part_of_speech': _partOfSpeechController.text.trim(),
      });
    }
    Navigator.pop(context); // กลับไปหน้า VocabListScreen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vocab == null ? 'Add Vocabulary' : 'Edit Vocabulary'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _wordController,
              decoration: InputDecoration(
                labelText: 'Word',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _meaningController,
              decoration: InputDecoration(
                labelText: 'Meaning',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _partOfSpeechController,
              decoration: InputDecoration(
                labelText: 'Part of Speech',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _saveVocab,
              child: Text('Save', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
