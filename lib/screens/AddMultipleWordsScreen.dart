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
    if (numWords <= 0 || numWords > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุจำนวนคำระหว่าง 1-20')),
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
      appBar: AppBar(title: const Text('เพิ่มหลายคำศัพท์')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🔢 กรอกจำนวนคำศัพท์ที่ต้องการเพิ่ม
            TextField(
              controller: _numWordsController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'จำนวนคำศัพท์ (1-20)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),

            // 🔥 ปุ่มเดียวสำหรับดึงและบันทึกทันที
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _fetchAndSaveWords,
              icon: const Icon(Icons.cloud_download),
              label: const Text('ดึงและบันทึกคำศัพท์'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
            const SizedBox(height: 20),

            _isLoading
                ? const CircularProgressIndicator()
                : Expanded(
                    child: suggestedWords.isEmpty
                        ? const Center(child: Text('ยังไม่มีคำศัพท์ กรุณากด "ดึงและบันทึกคำศัพท์"'))
                        : ListView.builder(
                            itemCount: suggestedWords.length,
                            itemBuilder: (context, index) {
                              final word = suggestedWords[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: ListTile(
                                  title: Text(word.word, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  subtitle: Text('${word.meaning} (${word.partOfSpeech})'),
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
