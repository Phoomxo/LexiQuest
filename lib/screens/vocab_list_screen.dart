import 'package:flutter/material.dart';
import '../models/word_model.dart';
import '../services/word_service.dart';
import 'add_vocab_screen.dart';

class VocabListScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const VocabListScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
  }) : super(key: key);

  @override
  _VocabListScreenState createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late WordService wordService;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    wordService = WordService(categoryId: widget.categoryId);
  }

  void showDeleteConfirmationDialog(BuildContext context, Word word) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบคำศัพท์'),
        content: Text('คุณต้องการลบ "${word.word}" ใช่หรือไม่?'),
        actions: [
          TextButton(
            child: const Text('ยกเลิก'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'ลบ',
              style: TextStyle(color: Colors.red),
            ),
            onPressed: () async {
              await wordService.deleteWord(word.id!);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: Text(
    widget.categoryName,
    style: const TextStyle(color: Colors.white),
  ),
  centerTitle: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  flexibleSpace: Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.deepPurple, Colors.indigo],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ),
),

      body: Column(
        children: [
          // 🔎 แถบค้นหาคำศัพท์
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "ค้นหาคำศัพท์...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onChanged: (query) {
                setState(() {
                  searchQuery = query.toLowerCase();
                });
              },
            ),
          ),

          // 📋 รายการคำศัพท์
          Expanded(
            child: StreamBuilder<List<Word>>(
              stream: wordService.getWordsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดคำศัพท์'));
                }

                final words = snapshot.data ?? [];
                final filteredWords = words
                    .where((word) =>
                        word.word.toLowerCase().contains(searchQuery) ||
                        word.meaning.toLowerCase().contains(searchQuery))
                    .toList();

                if (filteredWords.isEmpty) {
                  return const Center(child: Text('ยังไม่มีคำศัพท์ในหมวดนี้'));
                }

                return ListView.builder(
                  itemCount: filteredWords.length,
                  itemBuilder: (context, index) {
                    final word = filteredWords[index];
                    return Card(
  color: Colors.white.withOpacity(0.9), // ✅ ทำให้การ์ดโปร่งใสเล็กน้อย
  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(15),
  ),
  elevation: 3,
  child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        title: Text(
                          word.word,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${word.meaning} (${word.partOfSpeech})',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Text(
                            word.word[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        trailing: const Icon(Icons.edit, color: Colors.deepPurple), // เปลี่ยนสีเป็นม่วง
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddWordScreen(
                                categoryId: widget.categoryId,
                                word: word,
                              ),
                            ),
                          );
                          setState(() {}); // รีโหลดหน้าหลังจากอัปเดตคำศัพท์
                        },
                        onLongPress: () => showDeleteConfirmationDialog(context, word),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // ➕ ปุ่มเพิ่มคำศัพท์
      floatingActionButton: FloatingActionButton.extended(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddWordScreen(categoryId: widget.categoryId),
      ),
    );
  },
  label: const Text(
    'เพิ่มคำศัพท์',
    style: TextStyle(color: Colors.white), // ✅ เปลี่ยนสีตัวอักษรเป็นสีขาว
  ),
  icon: const Icon(Icons.add, color: Colors.white), // ✅ เปลี่ยนไอคอนเป็นสีขาว
  backgroundColor: Colors.deepPurple, // ✅ ใช้โทนสีม่วงให้ตรงกับธีม
),

    );
  }
}
