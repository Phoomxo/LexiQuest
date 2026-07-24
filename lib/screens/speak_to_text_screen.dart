import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';
import 'word_scramble_screen.dart';

class SpeakToTextScreen extends StatefulWidget {
  final String correctWord;
  final VoiceProvider? voiceProvider;

  const SpeakToTextScreen({
    super.key,
    required this.correctWord,
    this.voiceProvider,
  });

  @override
  State<SpeakToTextScreen> createState() => _SpeakToTextScreenState();
}

class _SpeakToTextScreenState extends State<SpeakToTextScreen> {
  late stt.SpeechToText _speech;
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  bool isListening = false;
  String spokenText = ''; // ข้อความที่ผู้ใช้พูด
  bool isCorrect = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    if (widget.voiceProvider != null) {
      _voiceProvider = widget.voiceProvider!;
      _ownsVoiceProvider = false;
    } else {
      _voiceProvider = VoiceServiceFactory.create();
      _ownsVoiceProvider = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakWord(); // พูดคำศัพท์ทันทีเมื่อเริ่มหน้าจอ
    });
  }

  Future<void> _speakWord() async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: widget.correctWord,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: widget.correctWord,
          contentType: 'vocabulary_word',
        ),
      );
    } catch (e) {
      debugPrint('Error speaking word: $e');
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) => debugPrint('Speech status: $status'),
      onError: (error) => debugPrint('Speech error: $error'),
    );
    if (available) {
      setState(() {
        isListening = true;
        spokenText = ''; // ล้างข้อความก่อนเริ่มพูดใหม่
      });
      _speech.listen(
        onResult: (result) {
          setState(() {
            spokenText = result.recognizedWords; // อัปเดตข้อความที่ผู้ใช้พูด
            isCorrect =
                spokenText.toLowerCase() ==
                widget.correctWord.toLowerCase(); // ตรวจสอบความถูกต้อง
          });
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: 'en-US',
          listenFor: const Duration(seconds: 10),
          partialResults: true,
        ),
      );
    } else {
      setState(() {
        isListening = false;
      });
    }
  }

  void _stopListening() {
    setState(() {
      isListening = false;
    });
    _speech.stop();
  }

  @override
  void dispose() {
    _speech.stop();
    _voiceProvider.stop();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ฝึกพูดคำศัพท์',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple, Colors.indigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 📢 แสดงคำศัพท์ที่ต้องพูด
              const Text(
                'พูดคำว่า:',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _speakWord, // แตะเพื่อให้พูดคำศัพท์ซ้ำ
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.correctWord,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.yellowAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.volume_up,
                      color: Colors.yellowAccent,
                      size: 32,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // 🗣️ แสดงผลคำที่ผู้ใช้พูด
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      spokenText.isEmpty ? 'พูดอะไรบางอย่าง...' : spokenText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    if (spokenText.isNotEmpty)
                      Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        color: isCorrect ? Colors.green : Colors.red,
                        size: 40,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 🎙️ ปุ่มเริ่มและหยุดพูด
              GestureDetector(
                onTapDown: (_) => _startListening(),
                onTapUp: (_) => _stopListening(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isListening ? Colors.green : Colors.red,
                    boxShadow: [
                      BoxShadow(
                        color: isListening
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        blurRadius: isListening ? 10 : 5,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.transparent,
                    child: Icon(Icons.mic, color: Colors.white, size: 40),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ✅ ปุ่มไปต่อ
              ElevatedButton(
                onPressed: () {
                  if (isCorrect) {
                    // ✅ ถ้าพูดถูก ให้ไป WordScrambleScreen
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            WordScrambleScreen(word: widget.correctWord),
                      ),
                    );
                  } else {
                    // ❌ ถ้าพูดผิด ให้กลับไป QuizScreen
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCorrect
                      ? Colors.green
                      : Colors.red, // ✅ สีปุ่มเปลี่ยนตามเงื่อนไข
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isCorrect ? 'ไปเกมเรียงคำ' : 'กลับไปแบบทดสอบ',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
