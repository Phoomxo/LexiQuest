import 'package:flutter/material.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class ShadowingChallengeScreen extends StatefulWidget {
  final String referenceSentence;
  final VoiceProvider? voiceProvider;

  const ShadowingChallengeScreen({
    super.key,
    required this.referenceSentence,
    this.voiceProvider,
  });

  @override
  State<ShadowingChallengeScreen> createState() =>
      _ShadowingChallengeScreenState();
}

class _ShadowingChallengeScreenState extends State<ShadowingChallengeScreen> {
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  bool _isRecording = false;
  bool _hasRecorded = false;

  @override
  void initState() {
    super.initState();
    if (widget.voiceProvider != null) {
      _voiceProvider = widget.voiceProvider!;
      _ownsVoiceProvider = false;
    } else {
      _voiceProvider = VoiceServiceFactory.create();
      _ownsVoiceProvider = true;
    }
  }

  Future<void> _playReference({required double speed}) async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: widget.referenceSentence,
          language: 'en',
          voiceId: 'teacher_female',
          speed: speed,
          mode: VoiceMode.practice,
          contentId: widget.referenceSentence,
          contentType: 'shadowing_reference',
        ),
      );
    } catch (e) {
      debugPrint('Shadowing audio error: $e');
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (!_isRecording) {
        _hasRecorded = true;
      }
    });
  }

  @override
  void dispose() {
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
          'Shadowing Practice (พูดตามจังหวะ AI)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '1. ฟังเสียงต้นแบบ AI -> 2. กดอัดเสียงพูดตามทันที',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Text(
                widget.referenceSentence,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _playReference(speed: 1.0),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('ฟังเสียง AI (1.0x)'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _playReference(speed: 0.8),
                  icon: const Icon(Icons.slow_motion_video),
                  label: const Text('ฟังชะลอ (0.8x)'),
                ),
              ],
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? Colors.red : Colors.deepPurple,
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isRecording
                  ? 'กำลังอัดเสียงพูดตาม...'
                  : 'กดไอคอนเพื่อเริ่มฝึก Shadowing',
              style: TextStyle(
                color: _isRecording ? Colors.red : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_hasRecorded) ...[
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.greenAccent,
                child: Text(
                  'บันทึกการฝึกพูดเรียบร้อย! ลองฟังเทียบจังหวะเสียงได้เลย',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
