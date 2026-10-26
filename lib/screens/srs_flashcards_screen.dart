import 'dart:math';

import 'package:flutter/foundation.dart';
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
    this.sourceWordIds,
    this.voice,
    this.learning,
  }) : assert(wordList == null || sourceWordIds == null);

  /// Compatibility-only fixture input. Production loads due words from Drift.
  final List<Map<String, String>>? wordList;
  final List<String>? sourceWordIds;
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
  String? _attemptId;
  DateTime? _submittedAtUtc;
  int? _responseTimeMs;
  bool? _submittedRating;
  bool _saved = false;
  int _correctCount = 0;
  final Set<String> _mistakeWordIds = {};
  bool _resultContextValid = true;

  bool get _isCompatibilityDeck => widget.wordList != null;
  bool get _isSourcePractice => widget.sourceWordIds != null;

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
  void didUpdateWidget(covariant SrsFlashcardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.learning, widget.learning) ||
        !listEquals(oldWidget.sourceWordIds, widget.sourceWordIds)) {
      _resultContextValid = false;
    }
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
          : _isSourcePractice
          ? learning.startSourcePracticeForWords(wordIds: widget.sourceWordIds!)
          : learning.startDueReview();
    }
    _load!.then((session) {
      if (!mounted || session.isEmpty) return;
      _session = session;
      _questionStartedAt = DateTime.now();
      _playAudio();
    }, onError: (_) {});
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
    if (_saving || _saved || _attemptId != null) return;
    if (_isFlipped) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  Future<void> _rateItem(bool isCorrect) async {
    if (_saving ||
        _saved ||
        (_submittedRating != null && _submittedRating != isCorrect)) {
      return;
    }
    setState(() => _saving = true);
    _submittedRating ??= isCorrect;
    try {
      if (_isCompatibilityDeck) {
        // Legacy compatibility deck — SrsService removed (Phase 0 Week 14-15).
        // SharedPreferences-backed SRS recording is deprecated; no-op here.
        // SRS state for real words is tracked via LearningUseCases + Drift.
      } else {
        _submittedAtUtc ??= DateTime.now().toUtc();
        _responseTimeMs ??= DateTime.now()
            .difference(_questionStartedAt ?? DateTime.now())
            .inMilliseconds;
        _attemptId ??= 'attempt:srs:${_session!.id}:$_currentIndex';
        await _learning!.recordAnswer(
          sessionId: _session!.id,
          wordId: _currentQuestion.word.id,
          promptMode: 'srsRecall',
          isCorrect: _submittedRating!,
          responseTimeMs: _responseTimeMs,
          attemptNumber: _currentIndex + 1,
          attemptId: _attemptId,
          occurredAtUtc: _submittedAtUtc,
        );
      }
      if (!mounted) return;
      setState(() {
        if (_submittedRating!) {
          _correctCount++;
        } else {
          _mistakeWordIds.add(_currentQuestion.word.id);
        }
        _saved = true;
        _saving = false;
      });
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
    if (!_saved || _saving) return;
    setState(() => _saving = true);
    if (_currentIndex < _session!.questions.length - 1) {
      if (_isFlipped) _controller.reverse();
      setState(() {
        _isFlipped = false;
        _currentIndex++;
        _saving = false;
        _questionStartedAt = DateTime.now();
        _attemptId = null;
        _submittedAtUtc = null;
        _responseTimeMs = null;
        _submittedRating = null;
        _saved = false;
      });
      await _playAudio();
      return;
    }
    LearningSessionSummary? summary;
    try {
      if (!_isCompatibilityDeck) {
        summary = await _learning!.finishSession(_session!.id);
        if (!_isValidSummary(summary)) {
          throw StateError('invalid flashcards summary');
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ปิดการทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isSourcePractice
              ? 'ฝึกบัตรคำจากเนื้อหานี้ครบแล้ว'
              : 'ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว',
        ),
      ),
    );
    Navigator.of(context).pop(
      _isSourcePractice && summary != null && _resultContextValid
          ? LearningSessionResult(
              summary: summary,
              mistakeWordIds: _mistakeWordIds,
            )
          : null,
    );
  }

  bool _isValidSummary(LearningSessionSummary summary) {
    final session = _session;
    if (!_resultContextValid || session == null) return false;
    final total = session.questions.length;
    final wrong = total - _correctCount;
    final score = total == 0 ? 0 : ((_correctCount * 100) / total).round();
    return summary.id == session.id &&
        summary.state == 'completed' &&
        summary.correctCount == _correctCount &&
        summary.wrongCount == wrong &&
        summary.score == score &&
        _mistakeWordIds.length == wrong;
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
      appBar: AppBar(
        title: Text(
          _isSourcePractice ? 'บัตรคำจากเนื้อหานี้' : 'ทบทวนคำที่ถึงกำหนด',
        ),
      ),
      body: FutureBuilder<QuizSession>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _SrsMessage('เปิดข้อมูลทบทวนในเครื่องไม่สำเร็จ');
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'กำลังเตรียมคำศัพท์สำหรับทบทวน',
              ),
            );
          }
          if (snapshot.data!.isEmpty) {
            return _SrsMessage(
              _isSourcePractice
                  ? 'ไม่พบคำศัพท์จากแหล่งเรียนสำหรับฝึก'
                  : 'ยังไม่มีคำศัพท์ที่ถึงกำหนดทบทวน',
            );
          }
          _session ??= snapshot.data;
          return _buildCard();
        },
      ),
    );
  }

  Widget _buildCard() {
    final word = _currentQuestion.word;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_currentIndex + 1}/${_session!.questions.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _saving || _saved || _attemptId != null ? null : _flipCard,
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
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 280),
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
            const SizedBox(height: 20),
            if (_saving)
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังบันทึกผลทบทวน',
              ),
            if (_saved) ...[
              Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isCompatibilityDeck
                          ? 'ชุดตัวอย่างนี้ไม่บันทึกผล'
                          : 'บันทึกแล้ว',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'ผลที่คุณเลือก: ${_submittedRating! ? 'จำได้แล้ว' : 'จำไม่ได้'}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _nextCard,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(
                  _currentIndex == _session!.questions.length - 1
                      ? _isSourcePractice
                            ? 'จบการฝึก'
                            : 'จบการทบทวน'
                      : 'คำถัดไป',
                ),
              ),
            ] else if (!_saving && _isFlipped)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    onPressed: _submittedRating == true
                        ? null
                        : () => _rateItem(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('ยังจำไม่ได้'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _submittedRating == false
                        ? null
                        : () => _rateItem(true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('จำได้แล้ว'),
                  ),
                ],
              )
            else if (!_saving)
              TextButton(
                onPressed: _flipCard,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('ดูคำแปล'),
              ),
          ],
        ),
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
        child: Semantics(
          liveRegion: true,
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
