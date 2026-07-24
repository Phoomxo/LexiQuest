import 'package:flutter/material.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class ChatMessage {
  final String sender;
  final String text;
  final bool isUser;
  final String? grammarRating;

  const ChatMessage({
    required this.sender,
    required this.text,
    required this.isUser,
    this.grammarRating,
  });
}

class AiTutorScreen extends StatefulWidget {
  final VoiceProvider? voiceProvider;

  const AiTutorScreen({super.key, this.voiceProvider});

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  final TextEditingController _inputController = TextEditingController();
  String _selectedScenario = 'Job Interview';
  bool _isListeningMic = false;

  final List<ChatMessage> _messages = [
    const ChatMessage(
      sender: 'AI Tutor',
      text:
          'Hello! Welcome to the interview. Could you please introduce yourself and tell me about your qualifications?',
      isUser: false,
    ),
  ];

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

  void _sendMessage([String? spokenText]) {
    final text = (spokenText ?? _inputController.text).trim();
    if (text.isEmpty) return;

    final grammarRating = text.length > 15
        ? 'Grammar: Excellent (95%)'
        : 'Grammar: Good (80%)';

    setState(() {
      _messages.add(
        ChatMessage(
          sender: 'You',
          text: text,
          isUser: true,
          grammarRating: grammarRating,
        ),
      );
      _inputController.clear();
      _isListeningMic = false;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        const responseText =
            'That sounds impressive! What would you say is your greatest strength in team collaboration?';
        setState(() {
          _messages.add(
            const ChatMessage(
              sender: 'AI Tutor',
              text: responseText,
              isUser: false,
            ),
          );
        });
        _speakAiResponse(responseText);
      }
    });
  }

  void _toggleMicListening() {
    if (_isListeningMic) {
      setState(() => _isListeningMic = false);
    } else {
      setState(() => _isListeningMic = true);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _isListeningMic) {
          _sendMessage(
            'I have three years of experience in software engineering and team leadership.',
          );
        }
      });
    }
  }

  Future<void> _speakAiResponse(String text) async {
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: text,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: 'ai_tutor_response',
          contentType: 'ai_tutor',
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputController.dispose();
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
          'จำลองบทสนทนา AI Tutor (Voice-to-Voice)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.indigo.shade900,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'สถานการณ์:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _selectedScenario,
                  items: const [
                    DropdownMenuItem(
                      value: 'Job Interview',
                      child: Text('💼 Job Interview'),
                    ),
                    DropdownMenuItem(
                      value: 'Hotel Check-in',
                      child: Text('🏨 Hotel Check-in'),
                    ),
                    DropdownMenuItem(
                      value: 'Cafe Ordering',
                      child: Text('☕ Cafe Ordering'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedScenario = val;
                      });
                    }
                  },
                ),
              ],
            ),
            if (_isListeningMic) ...[
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'กำลังฟังเสียงพูดของคุณ... (Speaking)',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? Colors.indigo.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg.sender,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: msg.isUser
                                      ? Colors.indigo
                                      : Colors.grey.shade800,
                                ),
                              ),
                              if (msg.grammarRating != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    msg.grammarRating!,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(msg.text, style: const TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isListeningMic ? Icons.mic : Icons.mic_none,
                    color: _isListeningMic ? Colors.red : Colors.indigo,
                  ),
                  onPressed: _toggleMicListening,
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: InputDecoration(
                      hintText: 'พิมพ์ หรือกดไมค์เพื่อพูดภาษาอังกฤษ...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.indigo),
                  onPressed: () => _sendMessage(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
