import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'AddMultipleWordsScreen.dart';
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

  /// 🔥 ฟังก์ชันแสดง Dialog ยืนยันการลบคำศัพท์
  void showDeleteConfirmationDialog(BuildContext context, Word word) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('ลบคำศัพท์', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('คุณต้องการลบ "${word.word}" ใช่หรือไม่?', textAlign: TextAlign.center),
        actions: [
          TextButton(
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('ลบ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () async {
              await wordService.deleteWord(word.id!);
              Navigator.pop(context);
              setState(() {}); // รีโหลดหน้าหลังจากลบคำศัพท์
            },
          ),
        ],
      ),
    );
  }

  /// 🔥 ฟังก์ชันลบคำศัพท์ทั้งหมดในหมวดหมู่
  void showDeleteAllWordsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('ลบคำศัพท์ทั้งหมด', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('คุณต้องการลบคำศัพท์ทั้งหมดในหมวดหมู่นี้ใช่หรือไม่?', textAlign: TextAlign.center),
        actions: [
          TextButton(
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('ลบทั้งหมด', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () async {
              await wordService.deleteAllWords();
              Navigator.pop(context);
              setState(() {}); // รีโหลดหน้าหลังจากลบทั้งหมด
            },
          ),
        ],
      ),
    );
  }

  /// 🔥 UI ปุ่มเพิ่มคำศัพท์แบบ Speed Dial
  Widget _buildFloatingActionButton() {
    return SpeedDial(
      animatedIcon: AnimatedIcons.menu_close,
      backgroundColor: Colors.deepPurple,
      foregroundColor: Colors.white,
      overlayColor: Colors.black,
      overlayOpacity: 0.3,
      spacing: 12,
      spaceBetweenChildren: 10,

      children: [
        SpeedDialChild(
          child: const Icon(Icons.add, color: Colors.white),
          backgroundColor: Colors.blue,
          label: 'เพิ่มคำศัพท์',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddWordScreen(categoryId: widget.categoryId),
              ),
            );
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.playlist_add, color: Colors.white),
          backgroundColor: Colors.green,
          label: 'เพิ่มหลายคำ (Datamuse)',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddMultipleWordsScreen(
                  categoryId: widget.categoryId,
                  categoryName: widget.categoryName,
                ),
              ),
            );
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.delete_forever, color: Colors.white),
          backgroundColor: Colors.red,
          label: 'ลบคำศัพท์ทั้งหมด',
          onTap: () {
            showDeleteAllWordsDialog(context);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName, style: const TextStyle(color: Colors.white)),
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
                if (words.isEmpty) {
                  return const Center(child: Text('ยังไม่มีคำศัพท์ในหมวดนี้'));
                }

                return ListView.builder(
                  itemCount: words.length,
                  itemBuilder: (context, index) {
                    final word = words[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        title: Text(word.word, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${word.meaning} (${word.partOfSpeech})'),
                            if (word.userId == '') 
                              const Text(
                                '🔗 คำศัพท์นี้ถูกเพิ่มจาก Datamuse API',
                                style: TextStyle(color: Colors.blue, fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => showDeleteConfirmationDialog(context, word),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: _buildFloatingActionButton(),
    );
  }
}
