import 'package:flutter/material.dart';
import '../services/custom_wordbook_importer.dart';
import 'srs_flashcards_screen.dart';

class WordbookImportScreen extends StatefulWidget {
  final CustomWordbookImporter? importer;

  const WordbookImportScreen({super.key, this.importer});

  @override
  State<WordbookImportScreen> createState() => _WordbookImportScreenState();
}

class _WordbookImportScreenState extends State<WordbookImportScreen> {
  late final CustomWordbookImporter _importer;
  final TextEditingController _textController = TextEditingController();
  List<Map<String, String>> _parsedWords = [];
  bool _isJsonMode = false;

  @override
  void initState() {
    super.initState();
    _importer = widget.importer ?? CustomWordbookImporter();
  }

  void _processImport() {
    final rawText = _textController.text.trim();
    if (rawText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาใส่ข้อความคำศัพท์ CSV หรือ JSON')),
      );
      return;
    }

    try {
      final results = _isJsonMode
          ? _importer.parseJson(rawText)
          : _importer.parseCsv(rawText);

      setState(() {
        _parsedWords = results;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('นำเข้าคำศัพท์สำเร็จ ${results.length} คำ!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('รูปแบบไฟล์ไม่ถูกต้อง: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'นำเข้าสมุดคำศัพท์ส่วนตัว (Import Wordbook)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.teal,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'รูปแบบข้อมูล:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                ToggleButtons(
                  isSelected: [!_isJsonMode, _isJsonMode],
                  onPressed: (index) {
                    setState(() {
                      _isJsonMode = index == 1;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.white,
                  fillColor: Colors.teal,
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('CSV'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('JSON'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isJsonMode
                  ? 'ตัวอย่าง: [{"word": "apple", "translation": "แอปเปิ้ล"}]'
                  : 'ตัวอย่าง CSV: word,translation,example\napple,แอปเปิ้ล,Red apple',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'วางข้อความคำศัพท์ที่นี่...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _processImport,
              icon: const Icon(Icons.file_upload),
              label: const Text('ประมวลผลนำเข้าคำศัพท์'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 20),
            if (_parsedWords.isNotEmpty) ...[
              Text(
                'รายการคำศัพท์ที่นำเข้า (${_parsedWords.length} คำ):',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _parsedWords.length,
                  itemBuilder: (context, index) {
                    final item = _parsedWords[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(
                        item['word'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(item['translation'] ?? ''),
                    );
                  },
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SrsFlashcardsScreen(wordList: _parsedWords),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('เริ่มเรียนรู้คำศัพท์ชุดนี้ทันที'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
