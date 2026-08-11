import 'package:flutter/material.dart';

class BossBattleScreen extends StatefulWidget {
  BossBattleScreen({
    super.key,
    this.bossName = 'Vocabulary Challenge',
    required this.questions,
  }) {
    if (questions.isEmpty) {
      throw ArgumentError.value(
        questions,
        'questions',
        'at least one owned question is required',
      );
    }
  }

  final String bossName;
  final List<Map<String, String>> questions;

  @override
  State<BossBattleScreen> createState() => _BossBattleScreenState();
}

class _BossBattleScreenState extends State<BossBattleScreen> {
  late int _remainingQuestions;
  int _currentIndex = 0;
  bool _isVictory = false;
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _remainingQuestions = widget.questions.length;
  }

  void _attackBoss() {
    if (_isVictory || _currentIndex >= widget.questions.length) return;

    final currentQuestion = widget.questions[_currentIndex];
    final targetWord = (currentQuestion['word'] ?? '').toLowerCase().trim();
    final userInput = _inputController.text.toLowerCase().trim();

    if (targetWord.isNotEmpty && userInput == targetWord) {
      setState(() {
        _remainingQuestions -= 1;
        _inputController.clear();
        if (_remainingQuestions == 0) {
          _isVictory = true;
        } else {
          _currentIndex += 1;
        }
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('สะกดคำไม่ถูกต้อง! บอสป้องกันไว้ได้')),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalQuestions = widget.questions.length;
    final currentQuestion = _currentIndex < totalQuestions
        ? widget.questions[_currentIndex]
        : const <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '⚔️ Vocabulary Challenge',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.red.shade900,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              elevation: 6,
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.bossName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'HP: $_remainingQuestions / $totalQuestions',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _remainingQuestions / totalQuestions,
                      color: Colors.red,
                      backgroundColor: Colors.grey.shade300,
                      minHeight: 12,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            if (_isVictory) ...[
              const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
              const SizedBox(height: 12),
              const Text(
                '🎉 ชัยชนะ! คุณปราบบอสสำเร็จ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ] else ...[
              Text(
                'คำแปล: "${currentQuestion['translation'] ?? ''}"',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  labelText: 'พิมพ์สะกดคำศัพท์เพื่อโจมตีบอส',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _attackBoss,
                icon: const Icon(Icons.flash_on),
                label: const Text('โจมตีบอส!'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
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
