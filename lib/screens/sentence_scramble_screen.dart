import 'package:flutter/material.dart';
import '../voice/voice_models.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';

class SentenceScrambleScreen extends StatefulWidget {
  final String targetSentence;
  final String translation;
  final VoiceUseCases? voice;

  const SentenceScrambleScreen({
    super.key,
    required this.targetSentence,
    this.translation = '',
    this.voice,
  });

  @override
  State<SentenceScrambleScreen> createState() => _SentenceScrambleScreenState();
}

class _SentenceScrambleScreenState extends State<SentenceScrambleScreen>
    with
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<SentenceScrambleScreen> {
  VoiceUseCases? _voice;
  late List<String> _originalWords;
  late List<String> _scrambledWords;
  final List<String> _userSelection = [];
  bool? _isCorrect;

  @override
  void initState() {
    super.initState();
    _originalWords = widget.targetSentence.trim().split(RegExp(r'\s+'));
    _scrambledWords = List<String>.from(_originalWords)..shuffle();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAudio();
    });
  }

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice = widget.voice ?? AppDependenciesScope.maybeOf(context)?.voice;
    refreshRouteVoiceSession();
  }

  Future<void> _playAudio() async {
    try {
      await routeVoiceSession?.speak(
        VoiceRequest.create(
          text: widget.targetSentence,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: widget.targetSentence,
          contentType: 'sentence_scramble',
        ),
      );
    } catch (e) {
      debugPrint('Sentence audio error: $e');
    }
  }

  void _selectWord(int index) {
    setState(() {
      final word = _scrambledWords.removeAt(index);
      _userSelection.add(word);
      _isCorrect = null;
    });
  }

  void _deselectWord(int index) {
    setState(() {
      final word = _userSelection.removeAt(index);
      _scrambledWords.add(word);
      _isCorrect = null;
    });
  }

  void _checkSentence() {
    final userSentence = _userSelection.join(' ');
    setState(() {
      _isCorrect = userSentence == widget.targetSentence;
    });
  }

  void _reset() {
    setState(() {
      _userSelection.clear();
      _scrambledWords = List<String>.from(_originalWords)..shuffle();
      _isCorrect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เรียงประโยคภาษาอังกฤษ',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            if (widget.translation.isNotEmpty) ...[
              Text(
                widget.translation,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
            IconButton(
              icon: const Icon(
                Icons.volume_up,
                size: 36,
                color: Colors.deepPurple,
              ),
              onPressed: _playAudio,
            ),
            const SizedBox(height: 20),
            // User selection area
            Container(
              constraints: const BoxConstraints(minHeight: 80),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_userSelection.length, (index) {
                  return ActionChip(
                    label: Text(
                      _userSelection[index],
                      style: const TextStyle(fontSize: 16),
                    ),
                    onPressed: () => _deselectWord(index),
                    backgroundColor: Colors.indigo.shade100,
                  );
                }),
              ),
            ),
            const SizedBox(height: 30),
            // Scrambled pool area
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_scrambledWords.length, (index) {
                return ChoiceChip(
                  label: Text(
                    _scrambledWords[index],
                    style: const TextStyle(fontSize: 16),
                  ),
                  selected: false,
                  onSelected: (_) => _selectWord(index),
                );
              }),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reset,
                    child: const Text('เริ่มใหม่'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _userSelection.isNotEmpty
                        ? _checkSentence
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                    ),
                    child: const Text(
                      'ตรวจประโยค',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            if (_isCorrect != null) ...[
              const SizedBox(height: 16),
              Text(
                _isCorrect!
                    ? 'ถูกต้อง! (Great job)'
                    : 'เรียงยังไม่ถูกต้อง ลองใหม่อีกครั้ง',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _isCorrect! ? Colors.green : Colors.red,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
