import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/word_model.dart';
import '../services/word_service.dart';

class AddWordScreen extends StatefulWidget {
  final String categoryId;
  final Word? word;

  const AddWordScreen({super.key, required this.categoryId, this.word});

  @override
  _AddWordScreenState createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  late TextEditingController _wordController;
  late TextEditingController _meaningController;
  late TextEditingController _partOfSpeechController;
  late WordService wordService;

  bool _isLoading = false;
  List<String> _suggestedWords = [];

  @override
  void initState() {
    super.initState();
    wordService = WordService(categoryId: widget.categoryId);
    _wordController = TextEditingController(text: widget.word?.word ?? '');
    _meaningController = TextEditingController(text: widget.word?.meaning ?? '');
    _partOfSpeechController = TextEditingController(text: widget.word?.partOfSpeech ?? '');
  }

  /// 🔎 **ดึงคำศัพท์แนะนำจาก Datamuse API**
  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestedWords = []);
      return;
    }
    final url = Uri.parse('https://api.datamuse.com/words?sp=$query*');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      setState(() {
        _suggestedWords = data.map<String>((word) => word['word']).toList();
      });
    }
  }

  /// 🌍 **แปลคำศัพท์เป็นภาษาไทยโดยใช้ Google Translate (GTX)**
  Future<void> _translateToThai(String word) async {
    final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=th&dt=t&q=$word');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _meaningController.text = data[0][0][0]; // ใส่ค่าที่แปลลงในช่อง "ความหมาย"
      });
    }
  }

  /// 🔥 **ดึงข้อมูล "ประเภทของคำ" อัตโนมัติจาก Dictionary API**
  Future<void> _fetchWordDetails(String word) async {
    final url = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      if (data.isNotEmpty) {
        final firstEntry = data[0];
        final meanings = firstEntry['meanings'] as List<dynamic>;

        if (meanings.isNotEmpty) {
          setState(() {
            _partOfSpeechController.text = meanings[0]['partOfSpeech'] ?? '';
          });
        }
      }
    }
  }

  /// ➕ **เพิ่มหรืออัปเดตคำศัพท์**
  void _addOrUpdateWord() async {
    final wordText = _wordController.text.trim();
    final meaning = _meaningController.text.trim();
    final partOfSpeech = _partOfSpeechController.text.trim();

    if (wordText.isEmpty || meaning.isEmpty || partOfSpeech.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบทุกช่อง')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.word == null) {
        await wordService.addWord(Word(
          word: wordText,
          meaning: meaning,
          partOfSpeech: partOfSpeech,
          userId: '',
          isGlobal: false,
          createdAt: DateTime.now(),
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เพิ่มคำศัพท์สำเร็จ')),
        );
      } else {
        await wordService.updateWord(widget.word!.id!, Word(
          word: wordText,
          meaning: meaning,
          partOfSpeech: partOfSpeech,
          userId: widget.word!.userId,
          isGlobal: widget.word!.isGlobal,
          createdAt: widget.word!.createdAt,
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตคำศัพท์สำเร็จ')),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.word == null ? 'เพิ่มคำศัพท์' : 'แก้ไขคำศัพท์'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🔎 **Autocomplete สำหรับเลือกคำศัพท์**
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                await _fetchSuggestions(textEditingValue.text);
                return _suggestedWords;
              },
              onSelected: (String selection) async {
                setState(() {
                  _wordController.text = selection;
                });

                // ✅ **แปลเป็นภาษาไทย**
                await _translateToThai(selection);

                // ✅ **ดึงข้อมูลประเภทของคำ**
                await _fetchWordDetails(selection);
              },
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  decoration: InputDecoration(
                    labelText: 'คำศัพท์',
                    prefixIcon: const Icon(Icons.translate),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 15),

            // 📖 **ความหมายของคำศัพท์ (ภาษาไทย)**
            TextField(
              controller: _meaningController,
              decoration: InputDecoration(
                labelText: 'ความหมาย (ภาษาไทย)',
                prefixIcon: const Icon(Icons.text_snippet),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 15),

            // 🏷️ **ประเภทของคำ**
            TextField(
              controller: _partOfSpeechController,
              decoration: InputDecoration(
                labelText: 'ประเภทของคำ',
                prefixIcon: const Icon(Icons.category),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

          ],
        ),
      ),

      // ✅ Floating Action Button สำหรับบันทึก
      floatingActionButton: FloatingActionButton.extended(
  onPressed: _addOrUpdateWord,
  icon: const Icon(Icons.check, color: Colors.white), // ✅ เปลี่ยนไอคอนเป็นสีขาว
  label: const Text(
    'เพิ่ม',
    style: TextStyle(color: Colors.white), // ✅ เปลี่ยนสีตัวอักษรเป็นสีขาว
  ),
  backgroundColor: Colors.deepPurple, // ✅ ใช้โทนสีม่วง
),

    );
  }
}
