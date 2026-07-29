import 'dart:math';
import 'package:flutter/material.dart';
import '../services/srs_service.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class SrsFlashcardsScreen extends StatefulWidget {
  final List<Map<String, String>> wordList;
  final VoiceProvider? voiceProvider;
  final SrsService? srsService;

  const SrsFlashcardsScreen({
    super.key,
    required this.wordList,
    this.voiceProvider,
    this.srsService,
  });

  @override
  State<SrsFlashcardsScreen> createState() => _SrsFlashcardsScreenState();
}

class _SrsFlashcardsScreenState extends State<SrsFlashcardsScreen>
    with SingleTickerProviderStateMixin {
  late final VoiceProvider _voiceProvider;
  late final SrsService _srsService;
  bool _ownsVoiceProvider = false;
  int _currentIndex = 0;
  bool _isFlipped = false;
  late AnimationController _controller;
  late Animation<double> _animation;

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
    _srsService = widget.srsService ?? SrsService();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAudio();
    });
  }

  Map<String, String> get currentItem => widget.wordList[_currentIndex];

  Future<void> _playAudio() async {
    final word = currentItem['word'] ?? '';
    if (word.isEmpty) return;
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: word,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: word,
          contentType: 'srs_flashcard',
        ),
      );
    } catch (e) {
      debugPrint('Flashcard audio error: $e');
    }
  }

  void _flipCard() {
    if (_isFlipped) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  Future<void> _rateItem(bool isCorrect) async {
    final word = currentItem['word'] ?? '';
    await _srsService.recordReview(word, isCorrect);
    _nextCard();
  }

  void _nextCard() {
    if (_currentIndex < widget.wordList.length - 1) {
      if (_isFlipped) {
        _controller.reverse();
      }
      setState(() {
        _isFlipped = false;
        _currentIndex++;
      });
      _playAudio();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คุณทบทวนคำศัพท์ในเซตนี้ครบแล้ว!')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _voiceProvider.stop();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = currentItem['word'] ?? '';
    final translation = currentItem['translation'] ?? '';
    final example = currentItem['example'] ?? 'No example sentence provided.';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SRS Flashcards (${_currentIndex + 1}/${widget.wordList.length})',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _flipCard,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final angle = _animation.value * pi;
                    final isFront = angle < (pi / 2);
                    return Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(angle),
                      alignment: Alignment.center,
                      child: Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: Colors.white,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          child: isFront
                              ? _buildFrontSide(word)
                              : Transform(
                                  transform: Matrix4.identity()..rotateY(pi),
                                  alignment: Alignment.center,
                                  child: _buildBackSide(
                                    word,
                                    translation,
                                    example,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isFlipped)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _rateItem(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      'จำไม่ได้ (Again)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _rateItem(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text(
                      'จำได้แล้ว (Good)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'แตะที่การ์ดเพื่อดูคำแปลและประโยคตัวอย่าง',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontSide(String word) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          word,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 20),
        IconButton(
          icon: const Icon(Icons.volume_up, size: 40, color: Colors.indigo),
          onPressed: _playAudio,
        ),
      ],
    );
  }

  Widget _buildBackSide(String word, String translation, String example) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          word,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          translation,
          style: const TextStyle(
            fontSize: 28,
            color: Colors.deepOrange,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Example:\n"$example"',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
