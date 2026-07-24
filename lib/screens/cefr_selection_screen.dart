import 'package:flutter/material.dart';
import '../services/cefr_service.dart';
import 'srs_flashcards_screen.dart';

class CefrSelectionScreen extends StatefulWidget {
  final CefrService? cefrService;

  const CefrSelectionScreen({
    super.key,
    this.cefrService,
  });

  @override
  State<CefrSelectionScreen> createState() => _CefrSelectionScreenState();
}

class _CefrSelectionScreenState extends State<CefrSelectionScreen> {
  late final CefrService _cefrService;

  @override
  void initState() {
    super.initState();
    _cefrService = widget.cefrService ?? CefrService();
  }

  static const List<Map<String, dynamic>> cefrLevels = [
    {
      'level': 'A1',
      'name': 'A1 - Beginner (ผู้เริ่มต้น)',
      'color': Colors.blue,
    },
    {'level': 'A2', 'name': 'A2 - Elementary (พื้นฐาน)', 'color': Colors.teal},
    {
      'level': 'B1',
      'name': 'B1 - Intermediate (ปานกลาง)',
      'color': Colors.green,
    },
    {
      'level': 'B2',
      'name': 'B2 - Upper-Intermediate (ปานกลางสูง)',
      'color': Colors.orange,
    },
    {
      'level': 'C1',
      'name': 'C1 - Advanced (ก้าวหน้า)',
      'color': Colors.deepOrange,
    },
    {
      'level': 'C2',
      'name': 'C2 - Proficiency (เชี่ยวชาญ)',
      'color': Colors.purple,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'คลังคำศัพท์มาตรฐาน CEFR (A1 - C2)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: cefrLevels.length,
        itemBuilder: (context, index) {
          final levelInfo = cefrLevels[index];
          final String levelCode = levelInfo['level'];
          final String levelName = levelInfo['name'];
          final Color badgeColor = levelInfo['color'];
          final words = _cefrService.getWordsByLevel(levelCode);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16.0),
              leading: CircleAvatar(
                backgroundColor: badgeColor,
                child: Text(
                  levelCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                levelName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text('คำศัพท์ประจำระดับ: ${words.length} คำ'),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                color: Colors.indigo,
              ),
              onTap: () {
                final wordMaps = words
                    .map(
                      (w) => {
                        'word': w.word,
                        'translation': w.meaning,
                        'example': w.exampleSentence,
                      },
                    )
                    .toList();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SrsFlashcardsScreen(wordList: wordMaps),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
