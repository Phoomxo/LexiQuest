import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
    await _flutterTts.setLanguage("en-US"); // ตั้งค่าให้พูดเป็นภาษาอังกฤษแบบอเมริกัน
  }

  void _startListening() async {
  bool available = await _speech.initialize(
    onStatus: (status) => print('Speech status: $status'),
    onError: (error) => print('Speech error: $error'),
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
      localeId: "en", // ตั้งค่าการรับเสียงเป็นภาษาอังกฤษแบบอเมริกัน
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
        title: const Text('ฝึกพูดคำศัพท์'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'พูดคำว่า:',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            // เพิ่ม GestureDetector ให้สามารถแตะที่คำศัพท์เพื่อฟังการออกเสียงซ้ำได้
            GestureDetector(
              onTap: _speakWord, // ฟังก์ชันพูดซ้ำเมื่อแตะที่คำศัพท์
              child: Text(
                widget.correctWord,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 20),
            // กล่องข้อความแสดงสิ่งที่ผู้ใช้พูด
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                spokenText.isEmpty ? 'พูดอะไรบางอย่าง...' : spokenText,
                style: const TextStyle(fontSize: 18, color: Colors.black),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTapDown: (_) => _startListening(),
              onTapUp: (_) => _stopListening(),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: isCorrect ? Colors.green : Colors.red,
                child: const Icon(
                  Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // ไปยังหน้าถัดไป
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isCorrect ? Colors.green : Colors.grey,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'ไปต่อ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
