import 'package:flutter/material.dart';
import '../services/ghost_shadow_duel_service.dart';

class GhostShadowDuelScreen extends StatefulWidget {
  const GhostShadowDuelScreen({super.key});

  @override
  State<GhostShadowDuelScreen> createState() => _GhostShadowDuelScreenState();
}

class _GhostShadowDuelScreenState extends State<GhostShadowDuelScreen> {
  late GhostOpponent _opponent;
  late final GhostSnapshot _ghostSnapshot;

  int _playerHp = 100;
  int _ghostHp = 100;
  int _currentWordIndex = 0;
  final TextEditingController _answerController = TextEditingController();
  final List<String> _battleLog = [];
  bool _isDuelOver = false;
  bool _playerWon = false;
  final Stopwatch _stopwatch = Stopwatch();

  final List<String> _sampleWords = [
    'perseverance',
    'resilience',
    'meticulous',
    'eloquent',
    'paradigm',
  ];

  @override
  void initState() {
    super.initState();
    _ghostSnapshot = GhostSnapshot(
      recordedAt: DateTime.now().subtract(const Duration(days: 7)),
      accuracyRate: 0.85,
      avgResponseTimeMs: 3200,
      weakWords: _sampleWords,
    );

    _opponent = GhostShadowDuelService.generateShadowOpponent(_ghostSnapshot);
    _ghostHp = _opponent.maxHp;
    _battleLog.add('⚔️ การดวลกับร่างเงาในอดีต (Shadow Self) เริ่มต้นขึ้นแล้ว!');
    _stopwatch.start();
  }

  void _submitAnswer() {
    if (_isDuelOver) return;

    final input = _answerController.text.trim().toLowerCase();
    final targetWord = _sampleWords[_currentWordIndex];
    final isCorrect = (input == targetWord);
    final responseTimeMs = _stopwatch.elapsedMilliseconds.toDouble();
    _stopwatch.reset();
    _stopwatch.start();

    final turnResult = GhostShadowDuelService.evaluateTurn(
      playerResponseTimeMs: responseTimeMs,
      isCorrect: isCorrect,
      snapshot: _ghostSnapshot,
    );

    setState(() {
      _answerController.clear();
      if (turnResult.playerHitGhost) {
        _ghostHp = (_ghostHp - turnResult.damageDealt).clamp(0, _opponent.maxHp);
        _battleLog.insert(
          0,
          '💥 [คำว่า "$targetWord"] คุณโจมตีใส่ร่างเงา ${turnResult.damageDealt} DMG! (${turnResult.message})',
        );
      } else {
        _playerHp = (_playerHp - 15).clamp(0, 100);
        _battleLog.insert(
          0,
          '💔 [คำว่า "$targetWord"] คุณตอบผิด โดนร่างเงาสวนกลับ 15 DMG! (${turnResult.message})',
        );
      }

      if (_ghostHp <= 0) {
        _isDuelOver = true;
        _playerWon = true;
        _battleLog.insert(
          0,
          '🎉 ชัยชนะ! คุณสามารถเอาชนะร่างเงาของตนเองในอดีตสำเร็จ (+500 XP, +50 Gems)',
        );
      } else if (_playerHp <= 0) {
        _isDuelOver = true;
        _playerWon = false;
        _battleLog.insert(
          0,
          '☠️ ร่างเงาเอาชนะคุณในรอบนี้! ลองฝึกทบทวนคำศัพท์แล้วกลับมาท้าประลองใหม่',
        );
      } else {
        _currentWordIndex = (_currentWordIndex + 1) % _sampleWords.length;
      }
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentWord = _sampleWords[_currentWordIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0A1A),
      appBar: AppBar(
        title: const Text(
          'Ghost Shadow Duel (ดวลร่างเงาอดีต)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ghost Opponent Card
            Card(
              color: const Color(0xFF1F1538),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.purpleAccent, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.purple,
                          child: Icon(Icons.person_outline, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _opponent.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'เวลาตอบเฉลี่ยในอดีต: ${(_ghostSnapshot.avgResponseTimeMs / 1000).toStringAsFixed(1)}s',
                                style: TextStyle(
                                  color: Colors.purple.shade200,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Chip(
                          backgroundColor: Colors.purple.shade800,
                          label: Text(
                            'HP: $_ghostHp/${_opponent.maxHp}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _ghostHp / _opponent.maxHp,
                      backgroundColor: Colors.purple.shade900,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.pinkAccent,
                      ),
                      minHeight: 10,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Player Status Card
            Card(
              color: Colors.indigo.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'พลังชีวิตของคุณ (Player HP):',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: _playerHp > 30 ? Colors.redAccent : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_playerHp/100',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Target Prompt Card
            if (!_isDuelOver) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'พิมพ์สเปลคำศัพท์ต่อไปนี้ให้ถูกต้องและไวกว่าร่างเงา:',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentWord,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _answerController,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์คำศัพท์ที่ตรงกัน...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onSubmitted: (_) => _submitAnswer(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _submitAnswer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('โจมตี ⚔️'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _playerWon ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _playerWon ? Colors.green : Colors.red,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _playerWon ? Icons.emoji_events : Icons.sentiment_very_dissatisfied,
                      size: 60,
                      color: _playerWon ? Colors.amber : Colors.red,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _playerWon ? 'ชัยชนะเหนือร่างเงา!' : 'พ่ายแพ้ในศึกครั้งนี้',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _playerWon ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _playerHp = 100;
                          _ghostHp = _opponent.maxHp;
                          _isDuelOver = false;
                          _currentWordIndex = 0;
                          _battleLog.clear();
                          _battleLog.add('⚔️ การดวลรอบใหม่เริ่มขึ้นแล้ว!');
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _playerWon ? Colors.green : Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('เล่นอีกครั้ง 🔄'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Battle Log
            const Text(
              'ประวัติการต่อสู้ (Battle Log):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              height: 180,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                itemCount: _battleLog.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _battleLog[index],
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 13,
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
