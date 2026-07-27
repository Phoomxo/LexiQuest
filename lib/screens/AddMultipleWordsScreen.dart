import 'package:flutter/material.dart';
import '../models/suggestion_model.dart';
import '../models/word_model.dart';
import '../services/word_service.dart';
import '../services/suggestion_service.dart';

class AddMultipleWordsScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const AddMultipleWordsScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
  }) : super(key: key);

  @override
  _AddMultipleWordsScreenState createState() => _AddMultipleWordsScreenState();
}

class _AddMultipleWordsScreenState extends State<AddMultipleWordsScreen> {
  final TextEditingController _numWordsController = TextEditingController();
  late WordService wordService;
  late SuggestionService suggestionService;
  bool _isLoading = false;
  List<SuggestedWord> suggestedWords = [];

  @override
  void initState() {
    super.initState();
    wordService = WordService(categoryId: widget.categoryId);
    suggestionService = SuggestionService();
  }

  /// 🔥 ปุ่มเดียวสำหรับดึงคำศัพท์และบันทึกทันที
  Future<void> _fetchAndSaveWords() async {
    int numWords = int.tryParse(_numWordsController.text) ?? 0;
    if (numWords <= 0 || numWords > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุจำนวนคำระหว่าง 1-50')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ ดึงคำศัพท์จาก API
      suggestedWords = await suggestionService.fetchWords(widget.categoryName, numWords);
      setState(() {}); // 🔥 อัปเดต UI แสดงคำศัพท์ที่ดึงมา

      // ✅ แปลงเป็น Word และบันทึกลง Firestore
      List<Word> wordsToAdd = suggestedWords.map((word) {
        return Word(
          word: word.word,
          meaning: word.meaning,
          partOfSpeech: word.partOfSpeech,
          userId: '',
          isGlobal: false,
          createdAt: DateTime.now(),
        );
      }).toList();

      await wordService.addMultipleWords(wordsToAdd);

      // ✅ แสดงข้อความแจ้งเตือน
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เพิ่มคำศัพท์จำนวน ${wordsToAdd.length} คำสำเร็จ!')),
      );

      // ✅ ปิดหน้าหลังจากบันทึกเสร็จ
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เพิ่มหลายคำศัพท์', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🔢 กรอกจำนวนคำศัพท์ที่ต้องการเพิ่ม
            TextField(
              controller: _numWordsController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 18, color: Colors.black),
              decoration: InputDecoration(
                labelText: 'จำนวนคำศัพท์ (1-50)',
                labelStyle: const TextStyle(color: Colors.deepPurple),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.grey, width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 🔥 ปุ่มเดียวสำหรับดึงและบันทึกทันที
            ElevatedButton(
              onPressed: _isLoading ? null : _fetchAndSaveWords,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.deepPurple,
                elevation: 5,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_download, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _isLoading ? 'กำลังโหลด...' : 'ดึงและบันทึกคำศัพท์',
                    style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                : Expanded(
                    child: suggestedWords.isEmpty
                        ? const Center(
                            child: Text('ยังไม่มีคำศัพท์ กรุณากด "ดึงและบันทึกคำศัพท์"',
                                style: TextStyle(fontSize: 16, color: Colors.grey)))
                        : ListView.builder(
                            itemCount: suggestedWords.length,
                            itemBuilder: (context, index) {
                              final word = suggestedWords[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                elevation: 5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(12),
                                  tileColor: Colors.white.withOpacity(0.95),
                                  title: Text(word.word,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                  subtitle: Text(
                                    '${word.meaning} (${word.partOfSpeech})',
                                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.indigo,
                                    child: Text(
                                      word.word[0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ],
        ),
      ),
    );
  }
}
