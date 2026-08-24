import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../runtime/app_dependencies.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../voice/voice_models.dart';

class SrsFlashcardsScreen extends StatefulWidget {
  const SrsFlashcardsScreen({
    super.key,
    this.wordList,
    this.voice,
    this.learning,
    this.evidenceAdapter,
  });

  /// Compatibility-only fixture input. Production loads due words from Drift.
  final List<Map<String, String>>? wordList;
  final VoiceUseCases? voice;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;

  @override
  State<SrsFlashcardsScreen> createState() => _SrsFlashcardsScreenState();
}

class _SrsFlashcardsScreenState extends State<SrsFlashcardsScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<SrsFlashcardsScreen> {
  VoiceUseCases? _voice;
  late final AnimationController _controller;
  late final Animation<double> _animation;
  LearningUseCases? _learning;
  Future<QuizSession>? _load;
  QuizSession? _session;
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _saving = false;
  DateTime? _questionStartedAt;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  UnifiedLessonSessionLifecycle? _lessonLifecycle;
  bool _completionCommitted = false;
  bool _loadSettled = false;

  bool get _isCompatibilityDeck => widget.wordList != null;
  bool get _persistenceLocked =>
      _pendingEvidence != null || _pendingSessionClose != null;
  bool get _actionLocked =>
      _saving || _persistenceLocked || _completionCommitted;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _lessonLifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    _voice = widget.voice ?? dependencies?.voice;
    refreshRouteVoiceSession();
    if (_load != null) return;
    if (_isCompatibilityDeck) {
      _load = Future.value(_compatibilitySession(widget.wordList!));
    } else {
      _learning = widget.learning ?? dependencies?.learning;
      final learning = _learning;
      if (learning != null) {
        _evidenceAdapter =
            widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
      }
      final load = learning == null
          ? Future<QuizSession>.error(
              StateError('local learning dependency unavailable'),
            )
          : _evidenceAdapter == null
          ? Future<QuizSession>.error(
              StateError('current activity evidence dependency unavailable'),
            )
          : learning.startDueReview();
      _load = _startLifecycle(load);
    }
    unawaited(_primeLoadedSession(_load!));
  }

  Future<QuizSession> _startLifecycle(Future<QuizSession> load) async {
    final session = await load;
    final startedAtUtc = session.startedAtUtc;
    if (!_isCompatibilityDeck && !session.isEmpty && startedAtUtc != null) {
      await _lessonLifecycle?.start(
        sessionId: session.id,
        startedAtUtc: startedAtUtc,
        itemCount: session.questions.length,
      );
    }
    return session;
  }

  Future<void> _primeLoadedSession(Future<QuizSession> load) async {
    try {
      final session = await load;
      if (!mounted) return;
      _loadSettled = true;
      if (session.isEmpty) return;
      _session = session;
      _questionStartedAt = DateTime.now();
      await _playAudio();
    } on Object {
      // FutureBuilder renders the typed local-unavailable state from the
      // original load future. This observer must not create an unhandled
      // derived Future when loading fails.
      if (mounted) setState(() => _loadSettled = true);
    }
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
    if (_actionLocked) return;
    final word = _currentQuestion.word.spelling;
    if (word.isEmpty) return;
    try {
      await routeVoiceSession?.speak(
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
    if (_actionLocked) return;
    _lessonLifecycle?.recordInteraction();
    if (_isFlipped) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  Future<void> _rateItem(bool isCorrect) async {
    if (_actionLocked) return;
    _lessonLifecycle?.recordInteraction();
    PendingCurrentActivityEvidence? pending;
    if (!_isCompatibilityDeck) {
      final existing = _pendingEvidence;
      if (existing != null) return;
      final elapsed = DateTime.now().difference(
        _questionStartedAt ?? DateTime.now(),
      );
      pending = _evidenceAdapter!.capture(
        input: CurrentActivityInput.srsRecall,
        sessionId: _session!.id,
        wordId: _currentQuestion.word.id,
        isCorrect: isCorrect,
        responseTimeMs: elapsed.inMilliseconds,
        attemptNumber: _currentIndex + 1,
      );
      _pendingEvidence = pending;
    }
    setState(() => _saving = true);
    try {
      if (_isCompatibilityDeck) {
        // Legacy compatibility deck — SrsService removed (Phase 0 Week 14-15).
        // SharedPreferences-backed SRS recording is deprecated; no-op here.
        // SRS state for real words is tracked via LearningUseCases + Drift.
      } else {
        await pending!.record();
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

  Future<void> _retryEvidence() async {
    final pending = _pendingEvidence;
    if (pending == null || !pending.requiresRetry || _saving) return;
    setState(() => _saving = true);
    try {
      await pending.retry();
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

  Future<void> _retrySessionClose() async {
    final pending = _pendingSessionClose;
    if (pending == null || _saving) return;
    setState(() => _saving = true);
    try {
      final lifecycle = _lessonLifecycle;
      if (lifecycle == null) {
        if (pending.requiresRetry) {
          await pending.retry();
        } else {
          await pending.finish();
        }
      } else {
        await lifecycle.complete(pending);
      }
      _pendingSessionClose = null;
      await _completeReview();
    } catch (_) {
      _showSaveFailure();
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
        _pendingEvidence = null;
      });
      await _playAudio();
      return;
    }
    if (!_isCompatibilityDeck) {
      await _finishFinalSession();
      return;
    }
    await _completeReview();
  }

  Future<void> _finishFinalSession() async {
    try {
      final pending = _pendingSessionClose ??= _learning!.captureSessionClose(
        sessionId: _session!.id,
      );
      _pendingEvidence = null;
      final lifecycle = _lessonLifecycle;
      if (lifecycle == null) {
        await pending.finish();
      } else {
        await lifecycle.complete(pending);
      }
      _pendingSessionClose = null;
      await _completeReview();
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _completeReview() async {
    if (!mounted) return;
    setState(() {
      _completionCommitted = true;
      _saving = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว')),
    );
    Navigator.of(context).pop();
  }

  void _showSaveFailure() {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !_persistenceLocked &&
          (_isCompatibilityDeck ||
              (_loadSettled &&
                  (_session == null ||
                      _session!.isEmpty ||
                      _completionCommitted))),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _persistenceLocked || _isCompatibilityDeck) return;
        unawaited(_abandonAndPop());
      },
      child: Scaffold(
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
      ),
    );
  }

  Future<void> _abandonAndPop() async {
    if (_saving || _completionCommitted) return;
    setState(() => _saving = true);
    try {
      await _lessonLifecycle?.abandon();
    } catch (_) {
      _showSaveFailure();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildCard() {
    final word = _currentQuestion.word;
    final actionLocked = _actionLocked;
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
              onTap: actionLocked ? null : _flipCard,
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
          else if (_pendingEvidence?.requiresRetry ?? false)
            FilledButton(
              key: const ValueKey<String>('current-evidence-retry'),
              onPressed: _retryEvidence,
              child: const Text('Retry saved review'),
            )
          else if (_pendingSessionClose != null)
            FilledButton(
              key: const ValueKey<String>('current-evidence-retry'),
              onPressed: _retrySessionClose,
              child: const Text('Retry session completion'),
            )
          else if (_completionCommitted)
            const SizedBox.shrink()
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
          onPressed: _actionLocked ? null : _playAudio,
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
