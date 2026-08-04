import 'dart:math';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../runtime/app_dependencies.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';

class SrsFlashcardsScreen extends StatefulWidget {
  const SrsFlashcardsScreen({
    super.key,
    this.wordList,
    this.voice,
    this.learning,
  });

  /// Compatibility-only fixture input. Production loads due words from Drift.
  final List<Map<String, String>>? wordList;
  final VoiceUseCases? voice;
  final LearningUseCases? learning;

  @override
  State<SrsFlashcardsScreen> createState() => _SrsFlashcardsScreenState();
}

class _SrsFlashcardsScreenState extends State<SrsFlashcardsScreen>
    with SingleTickerProviderStateMixin {
  late final VoiceUseCases _voiceProvider;
  late final bool _ownsVoiceProvider;
  late final AnimationController _controller;
  late final Animation<double> _animation;
  LearningUseCases? _learning;
  Future<QuizSession>? _load;
  QuizSession? _session;
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _saving = false;
  DateTime? _questionStartedAt;

  bool get _isCompatibilityDeck => widget.wordList != null;

  @override
  void initState() {
    super.initState();
    _voiceProvider = widget.voice ?? VoiceUseCases.createDefault();
    _ownsVoiceProvider = widget.voice == null;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    if (_isCompatibilityDeck) {
      _load = Future.value(_compatibilitySession(widget.wordList!));
    } else {
      _learning =
          widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
      final learning = _learning;
      _load = learning == null
          ? Future<QuizSession>.error(
              StateError('local learning dependency unavailable'),
            )
          : learning.startDueReview();
    }
    _load!.then((session) {
      if (!mounted || session.isEmpty) return;
      _session = session;
      _questionStartedAt = DateTime.now();
      _playAudio();
    });
  }

  QuizSession _compatibilitySession(List<Map<String, String>> rows) {
    return QuizSession(
      id: 'compatibility',
      startedAtUtc: DateTime.now().toUtc(),
      questions: rows
          .asMap()
          .entries
          .map(
            (entry) => QuizQuestion(
              word: QuizWord(
                id: 'compatibility:${entry.key}',
                categoryId: 'compatibility',
                spelling: entry.value['word'] ?? '',
                meaning: entry.value['translation'] ?? '',
                partOfSpeech: entry.value['example'] ?? '',
              ),
              options: const [],
            ),
          )
          .toList(growable: false),
    );
  }

  QuizQuestion get _currentQuestion => _session!.questions[_currentIndex];

  Future<void> _playAudio() async {
    final word = _currentQuestion.word.spelling;
    if (word.isEmpty) return;
    try {
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: word,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: _currentQuestion.word.id,
          contentType: 'srs_flashcard',
        ),
      );
    } catch (_) {
      // Audio is optional; review evidence remains available without it.
    }
  }

  void _flipCard() {
    if (_isFlipped) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  Future<void> _rateItem(bool isCorrect) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_isCompatibilityDeck) {
        // Legacy compatibility deck — SrsService removed (Phase 0 Week 14-15).
        // SharedPreferences-backed SRS recording is deprecated; no-op here.
        // SRS state for real words is tracked via LearningUseCases + Drift.
      } else {
        final elapsed = DateTime.now().difference(
          _questionStartedAt ?? DateTime.now(),
        );
        await _learning!.recordAnswer(
          sessionId: _session!.id,
          wordId: _currentQuestion.word.id,
          promptMode: 'srsRecall',
          isCorrect: isCorrect,
          responseTimeMs: elapsed.inMilliseconds,
          attemptNumber: _currentIndex + 1,
        );
      }
      if (!mounted) return;
      await _nextCard();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        ),
      );
    }
  }

  Future<void> _nextCard() async {
    if (_currentIndex < _session!.questions.length - 1) {
      if (_isFlipped) _controller.reverse();
      setState(() {
        _isFlipped = false;
        _currentIndex++;
        _saving = false;
        _questionStartedAt = DateTime.now();
      });
      await _playAudio();
      return;
    }
    if (!_isCompatibilityDeck) {
      await _learning!.finishSession(_session!.id);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    _voiceProvider.stop();
    _voiceProvider.disposeIfOwned(_ownsVoiceProvider);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ทบทวน SRS')),
      body: FutureBuilder<QuizSession>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _SrsMessage('เปิดข้อมูลทบทวนในเครื่องไม่สำเร็จ');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const _SrsMessage('ยังไม่มีคำศัพท์ที่ถึงกำหนดทบทวน');
          }
          _session ??= snapshot.data;
          return _buildCard();
        },
      ),
    );
  }

  Widget _buildCard() {
    final word = _currentQuestion.word;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            '${_currentIndex + 1}/${_session!.questions.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : _flipCard,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final angle = _animation.value * pi;
                  final front = angle < pi / 2;
                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    alignment: Alignment.center,
                    child: Card(
                      child: SizedBox.expand(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: front
                              ? _front(word)
                              : Transform(
                                  transform: Matrix4.identity()..rotateY(pi),
                                  alignment: Alignment.center,
                                  child: _back(word),
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
          if (_saving)
            const LinearProgressIndicator()
          else if (_isFlipped)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rateItem(false),
                    child: const Text('จำไม่ได้ (Again)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _rateItem(true),
                    child: const Text('จำได้แล้ว (Good)'),
                  ),
                ),
              ],
            )
          else
            const Text('แตะการ์ดเพื่อดูคำแปล'),
        ],
      ),
    );
  }

  Widget _front(QuizWord word) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(word.spelling, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        IconButton(
          onPressed: _playAudio,
          icon: const Icon(Icons.volume_up_outlined),
          iconSize: 40,
          tooltip: 'ฟังเสียง',
        ),
      ],
    );
  }

  Widget _back(QuizWord word) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(word.spelling, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(word.meaning, style: Theme.of(context).textTheme.headlineMedium),
        if (word.partOfSpeech.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(word.partOfSpeech, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _SrsMessage extends StatelessWidget {
  const _SrsMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
