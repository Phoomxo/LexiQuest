import 'package:flutter/material.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class ChatMessage {
  final String sender;
  final String text;
  final bool isUser;

  const ChatMessage({
    required this.sender,
    required this.text,
    required this.isUser,
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

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(sender: 'You', text: text, isUser: true));
      _inputController.clear();
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _messages.add(
            const ChatMessage(
              sender: 'AI Tutor',
              text:
                  'That sounds impressive! What would you say is your greatest strength in team collaboration?',
              isUser: false,
            ),
          );
        });
        _speakAiResponse(
          'That sounds impressive! What would you say is your greatest strength in team collaboration?',
        );
      }
    });
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
          'จำลองบทสนทนากับ AI Tutor',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: InputDecoration(
                      hintText: 'ตอบกลับภาษาอังกฤษ...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.indigo),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
