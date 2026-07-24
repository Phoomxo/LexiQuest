import 'dart:async';
import 'package:flutter/material.dart';
import '../services/rank_service.dart';

class BossBattleScreen extends StatefulWidget {
  final String bossName;
  final int initialBossHp;
  final List<Map<String, String>> questions;
  final RankService? rankService;

  const BossBattleScreen({
    super.key,
    this.bossName = 'บอสคำศัพท์ C1 (Vocab Titan)',
    this.initialBossHp = 100,
    this.questions = const [
      {'word': 'ephemeral', 'translation': 'ชั่วคราว'},
      {'word': 'meticulous', 'translation': 'พิถีพิถัน'},
      {'word': 'sustainable', 'translation': 'ยั่งยืน'},
    ],
    this.rankService,
  });

  @override
  State<BossBattleScreen> createState() => _BossBattleScreenState();
}

class _BossBattleScreenState extends State<BossBattleScreen> {
  late final RankService _rankService;
  late int _bossHp;
  int _currentIndex = 0;
  int _earnedXp = 0;
  int _earnedCoins = 0;
  bool _isVictory = false;
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rankService = widget.rankService ?? const RankService();
    _bossHp = widget.initialBossHp;
  }

  void _attackBoss() {
    if (_currentIndex >= widget.questions.length || _bossHp <= 0) return;

    final currentQuestion = widget.questions[_currentIndex];
    final targetWord = currentQuestion['word']!.toLowerCase().trim();
    final userInput = _inputController.text.toLowerCase().trim();

    if (userInput == targetWord) {
      final damage = 35;
      setState(() {
        _bossHp = (_bossHp - damage).clamp(0, widget.initialBossHp);
        final xpGain = _rankService.calculateXpGain(
          isCorrect: true,
          latencyMs: 1000,
          isBossBattle: true,
        );
        _earnedXp += xpGain;
        _earnedCoins += 30;
        _inputController.clear();

        if (_bossHp <= 0) {
          _isVictory = true;
        } else if (_currentIndex < widget.questions.length - 1) {
          _currentIndex++;
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สะกดคำไม่ถูกต้อง! บอสป้องกันไว้ได้')),
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentQuestion = _currentIndex < widget.questions.length
        ? widget.questions[_currentIndex]
        : {'word': '', 'translation': ''};

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '⚔️ ต่อสู้บอสคำศัพท์ประจำวัน',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.red.shade900,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Boss Status Card
            Card(
              elevation: 6,
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.bossName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          'HP: $_bossHp / ${widget.initialBossHp}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _bossHp / widget.initialBossHp,
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
              const SizedBox(height: 8),
              Text(
                'ได้รับ +$_earnedXp XP และ +$_earnedCoins เหรียญ!',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
            ] else ...[
              Text(
                'คำแปล: "${currentQuestion['translation']}"',
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
