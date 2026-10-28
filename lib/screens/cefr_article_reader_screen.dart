import 'package:flutter/material.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class CefrArticleReaderScreen extends StatefulWidget {
  final String title;
  final String content;
  final String cefrLevel;
  final VoiceProvider? voiceProvider;

  const CefrArticleReaderScreen({
    super.key,
    required this.title,
    required this.content,
    required this.cefrLevel,
    this.voiceProvider,
  });

  @override
  State<CefrArticleReaderScreen> createState() =>
      _CefrArticleReaderScreenState();
}

class _CefrArticleReaderScreenState extends State<CefrArticleReaderScreen> {
  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  String? _selectedWord;

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

  Future<void> _speakWord(String word) async {
    setState(() {
      _selectedWord = word;
    });
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: word,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: word,
          contentType: 'article_reader',
        ),
      );
    } catch (_) {}
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
    final words = widget.content.split(RegExp(r'\s+'));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'บทความ CEFR (${widget.cefrLevel})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'แตะที่คำศัพท์เพื่อฟังเสียงอ่าน AI:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  children: words.map((w) {
                    final cleanWord = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
                    final isSelected =
                        _selectedWord == cleanWord && cleanWord.isNotEmpty;

                    return GestureDetector(
                      onTap: cleanWord.isNotEmpty
                          ? () => _speakWord(cleanWord)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.amber.shade200
                              : Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          w,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_selectedWord != null && _selectedWord!.isNotEmpty) ...[
              const Divider(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'คำศัพท์ที่เลือก: "$_selectedWord"',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.volume_up,
                      color: Colors.indigo,
                      size: 30,
                    ),
                    onPressed: () => _speakWord(_selectedWord!),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
