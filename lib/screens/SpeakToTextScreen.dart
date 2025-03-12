import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'WordScrambleScreen.dart';

class SpeakToTextScreen extends StatefulWidget {
  final String correctWord;

  const SpeakToTextScreen({super.key, required this.correctWord});

  @override
  _SpeakToTextScreenState createState() => _SpeakToTextScreenState();
}

class _SpeakToTextScreenState extends State<SpeakToTextScreen> {
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool isListening = false;
  String spokenText = ''; // ข้อความที่ผู้ใช้พูด
  bool isCorrect = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _speakWord(); // พูดคำศัพท์ทันทีเมื่อเริ่มหน้าจอ
  }

  Future<void> _speakWord() async {
    await _flutterTts.setLanguage("en-US"); // ตั้งค่าภาษา
    await _flutterTts.setSpeechRate(0.5); // ตั้งค่าความเร็ว
    await _flutterTts.setVolume(1.0); // ตั้งค่าความดัง
    await _flutterTts.setPitch(1.0); // ตั้งค่าโทนเสียง
    await _flutterTts.speak(widget.correctWord); // เรียกให้พูดคำศัพท์
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
            isCorrect = spokenText.toLowerCase() == widget.correctWord.toLowerCase(); // ตรวจสอบความถูกต้อง
          });
        },
        localeId: "en-US", // ตั้งค่าการรับเสียงเป็นภาษาอังกฤษแบบอเมริกัน
      );
    }
  }

  void _stopListening() {
    setState(() {
      isListening = false;
    });
    _speech.stop();
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _speakWord, // แตะเพื่อให้พูดคำศัพท์ซ้ำ
                child: Text(
                  widget.correctWord,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.yellowAccent,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // 🗣️ แสดงผลคำที่ผู้ใช้พูด
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      spokenText.isEmpty ? 'พูดอะไรบางอย่าง...' : spokenText,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
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
                        color: isListening ? Colors.greenAccent : Colors.redAccent,
                        blurRadius: isListening ? 10 : 5,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.transparent,
                    child: Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: 40,
                    ),
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
          builder: (context) => WordScrambleScreen(word: widget.correctWord),
        ),
      );
    } else {
      // ❌ ถ้าพูดผิด ให้กลับไป QuizScreen
      Navigator.pop(context);
    }
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: isCorrect ? Colors.green : Colors.red, // ✅ สีปุ่มเปลี่ยนตามเงื่อนไข
    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  child: Text(
    isCorrect ? 'ไปเกมเรียงคำ' : 'กลับไปแบบทดสอบ',
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
  ),
),


            ],
          ),
        ),
      ),
    );
  }
}
