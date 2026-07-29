import 'package:flutter/material.dart';

class CefrDiagnosticTestScreen extends StatefulWidget {
  const CefrDiagnosticTestScreen({super.key});

  @override
  State<CefrDiagnosticTestScreen> createState() =>
      _CefrDiagnosticTestScreenState();
}

class _CefrDiagnosticTestScreenState extends State<CefrDiagnosticTestScreen> {
  int _currentIndex = 0;
  int _score = 0;

  static const List<Map<String, dynamic>> _questions = [
    {
      'question': 'What is the meaning of "apple"?',
      'options': ['แอปเปิ้ล', 'กล้วย', 'ส้ม', 'มะม่วง'],
      'answerIndex': 0,
      'cefr': 'A1',
    },
    {
      'question': 'Choose the synonym for "journey":',
      'options': ['Trip', 'Food', 'House', 'Book'],
      'answerIndex': 0,
      'cefr': 'A2',
    },
    {
      'question': 'What does "achieve" mean?',
      'options': ['บรรลุเป้าหมาย', 'ล้มเหลว', 'ปฏิเสธ', 'ละทิ้ง'],
      'answerIndex': 0,
      'cefr': 'B1',
    },
    {
      'question': 'Choose the correct meaning of "innovative":',
      'options': ['ที่เป็นนวัตกรรมใหม่', 'โบราณ', 'ธรรมดา', 'น่าเบื่อ'],
      'answerIndex': 0,
      'cefr': 'B2',
    },
    {
      'question': 'Select the definition of "ubiquitous":',
      'options': ['Present everywhere', 'Rare', 'Hidden', 'Ancient'],
      'answerIndex': 0,
      'cefr': 'C1',
    },
  ];

  void _answerQuestion(int index) {
    if (index == _questions[_currentIndex]['answerIndex']) {
      _score++;
    }
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      _showResult();
    }
  }

  String _evaluatedCefrLevel() {
    final percent = (_score / _questions.length) * 100.0;
    if (percent >= 90) return 'C1 / C2 Advanced';
    if (percent >= 70) return 'B2 Upper-Intermediate';
    if (percent >= 50) return 'B1 Intermediate';
    if (percent >= 30) return 'A2 Elementary';
    return 'A1 Beginner';
  }

  void _showResult() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ผลการวัดระดับ CEFR ของคุณ'),
        content: Text(
          'คุณทำได้ $_score/${_questions.length} คะแนน\nระดับที่ประเมินได้: ${_evaluatedCefrLevel()}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentQ = _questions[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'แบบทดสอบวัดระดับ CEFR (${_currentIndex + 1}/${_questions.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              backgroundColor: Colors.indigo.shade100,
              color: Colors.indigo,
            ),
            const SizedBox(height: 30),
            Text(
              currentQ['question'],
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ...List.generate(
              (currentQ['options'] as List).length,
              (optIndex) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: ElevatedButton(
                  onPressed: () => _answerQuestion(optIndex),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                  ),
                  child: Text(
                    currentQ['options'][optIndex],
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
