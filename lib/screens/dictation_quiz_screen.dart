import 'package:flutter/material.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';

class DictationQuizScreen extends StatefulWidget {
  final String targetWord;
  final VoiceUseCases? voice;

  const DictationQuizScreen({
    super.key,
    required this.targetWord,
    this.voice,
  });

  @override
  State<DictationQuizScreen> createState() => _DictationQuizScreenState();
}

class _DictationQuizScreenState extends State<DictationQuizScreen> {
  late final VoiceUseCases _voiceProvider;
  bool _ownsVoiceProvider = false;
  final TextEditingController _textController = TextEditingController();
  bool? _isCorrect;

  @override
  void initState() {
    super.initState();
    _voiceProvider = widget.voice ?? VoiceUseCases.createDefault();
    _ownsVoiceProvider = widget.voice == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAudio(speed: 1.0);
    });
  }

  Future<void> _playAudio({required double speed}) async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: widget.targetWord,
          language: 'en',
          voiceId: 'teacher_female',
          speed: speed,
          mode: VoiceMode.practice,
          contentId: widget.targetWord,
          contentType: 'dictation_quiz',
        ),
      );
    } catch (e) {
      debugPrint('Error playing dictation audio: $e');
    }
  }

  void _checkAnswer() {
    final userInput = _textController.text.trim().toLowerCase();
    final expected = widget.targetWord.trim().toLowerCase();
    setState(() {
      _isCorrect = userInput == expected;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _voiceProvider.stop();
    _voiceProvider.disposeIfOwned(_ownsVoiceProvider);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'แบบฝึกฟังคำศัพท์ (Dictation Quiz)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ฟังเสียงแล้วพิมพ์คำศัพท์ให้ถูกต้อง:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _playAudio(speed: 1.0),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('ความเร็วปกติ (1.0x)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _playAudio(speed: 0.75),
                  icon: const Icon(Icons.slow_motion_video),
                  label: const Text('ฟังแบบช้า (0.75x)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'พิมพ์คำศัพท์ที่คุณได้ยิน...',
                prefixIcon: Icon(Icons.edit),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _checkAnswer(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkAnswer,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                'ตรวจคำตอบ',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            if (_isCorrect != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isCorrect!
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isCorrect! ? Icons.check_circle : Icons.cancel,
                      color: _isCorrect!
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isCorrect!
                          ? 'ถูกต้อง! ($widget.targetWord)'
                          : 'ลองใหม่อีกครั้ง!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isCorrect!
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
