import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';

class VocabListScreen extends StatelessWidget {
  final String categoryId; // หมวดหมู่ที่เลือก
  final String categoryName; // ชื่อหมวดหมู่

  VocabListScreen({required this.categoryId, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    // อ้างอิงไปยัง Subcollection `words` ของหมวดหมู่ที่เลือก
    final CollectionReference wordsCollection = FirebaseFirestore.instance
        .collection('categories')
        .doc(categoryId)
        .collection('words');

    // ฟังก์ชันลบคำศัพท์
    Future<void> _deleteWord(String wordId) async {
      await wordsCollection.doc(wordId).delete();
    }

    return Scaffold(
    appBar: AppBar(
  title: Text('Words in $categoryName'),
  leading: IconButton(
    icon: Icon(Icons.arrow_back),
    onPressed: () => Navigator.pop(context),
  ),
),



      body: StreamBuilder<QuerySnapshot>(
        stream: wordsCollection.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading words.'));
          }
          final words = snapshot.data!.docs; // เอกสารของคำศัพท์ทั้งหมด
          return ListView.builder(
            itemCount: words.length,
            itemBuilder: (context, index) {
              final word = words[index];
              return GestureDetector(
                onLongPress: () {
                  // แสดง AlertDialog ยืนยันการลบ
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Delete Word'),
                      content: Text('Are you sure you want to delete "${word['word']}"?'),
                      actions: [
                        TextButton(
                          child: Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        TextButton(
                          child: Text('Delete'),
                          onPressed: () async {
                            await _deleteWord(word.id);
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
                onTap: () {
                  // เปิดหน้าแก้ไขคำศัพท์ใน `AddVocabScreen`
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddVocabScreen(
                        categoryId: categoryId,
                        vocab: word, // ส่งเอกสารคำศัพท์เพื่อแก้ไข
                      ),
                    ),
                  );
                },
                child: Card(
                  margin: EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(word['word']),
                    subtitle: Text('${word['meaning']} (${word['part_of_speech']})'),
                    trailing: Icon(Icons.edit), // ไอคอนแก้ไข
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // ไปหน้าเพิ่มคำศัพท์ใหม่
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddVocabScreen(categoryId: categoryId),
            ),
          );
        },
        child: Icon(Icons.add), // ไอคอนเพิ่มคำศัพท์
      ),
    );
  }
}
