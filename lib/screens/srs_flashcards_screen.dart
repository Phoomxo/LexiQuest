import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/flashcard_mode_adapter.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/evidence_context.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../voice/voice_models.dart';

/// Owner-scoped gateway for historical transient decks.
///
/// These rows have no stable vocabulary identity, so only the canonical
/// Legacy evidence rollout may enter the nonpersistent compatibility screen.
/// Shadow and Enforced must use the typed production adapter instead.
final class SrsFlashcardCompatibilityRoute extends StatefulWidget {
  const SrsFlashcardCompatibilityRoute({
    super.key,
    required this.wordList,
    this.voice,
  });

  final List<Map<String, String>> wordList;
  final VoiceUseCases? voice;

  @override
  State<SrsFlashcardCompatibilityRoute> createState() =>
      _SrsFlashcardCompatibilityRouteState();
}

final class _SrsFlashcardCompatibilityRouteState
    extends State<SrsFlashcardCompatibilityRoute> {
  AppDependencies? _dependencies;
  Future<EvidencePolicyRolloutMode>? _rollout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (identical(dependencies, _dependencies)) return;
    _dependencies = dependencies;
    _rollout = _resolveRollout(dependencies);
  }

  Future<EvidencePolicyRolloutMode> _resolveRollout(
    AppDependencies? dependencies,
  ) async {
    final learning = dependencies?.learning;
    final rollout = dependencies?.evidencePolicyRolloutModeProvider;
    if (learning == null || rollout == null) {
      throw StateError('flashcard compatibility authority unavailable');
    }
    final owner = await learning.owners.getOrCreateActiveOwner();
    final ownerId = owner.id.trim();
    if (ownerId.isEmpty) {
      throw StateError('active owner identity unavailable');
    }
    return rollout.resolve(ownerId: ownerId, evidenceContext: null);
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    return ProductionFeatureGate(
      feature: Feature.srs,
      registry: dependencies?.features,
      builder: (_) => FutureBuilder<EvidencePolicyRolloutMode>(
        future: _rollout,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Scaffold(
              appBar: AppBar(title: const Text('ทบทวน SRS')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError ||
              snapshot.data != EvidencePolicyRolloutMode.legacy) {
            return ProductionFeatureUnavailable(
              feature: Feature.srs,
              reason: snapshot.hasError
                  ? ProductionFeatureUnavailableReason.missingDependency
                  : ProductionFeatureUnavailableReason.incompatibleRollout,
              state: dependencies?.features.stateOf(Feature.srs),
            );
          }
          return _LegacyFlashcardCompatibilityScope(
            child: SrsFlashcardsScreen(
              wordList: widget.wordList,
              voice: widget.voice,
            ),
          );
        },
      ),
    );
  }
}

final class _LegacyFlashcardCompatibilityScope extends InheritedWidget {
  const _LegacyFlashcardCompatibilityScope({required super.child});

  static bool authorized(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            _LegacyFlashcardCompatibilityScope
          >() !=
      null;

  @override
  bool updateShouldNotify(_LegacyFlashcardCompatibilityScope oldWidget) =>
      false;
}

class SrsFlashcardsScreen extends StatefulWidget {
  const SrsFlashcardsScreen({
    super.key,
    this.wordList,
    this.voice,
    this.learning,
    this.evidenceAdapter,
    this.modeAdapter,
  });

  /// Compatibility-only fixture input. Production loads due words from Drift.
  final List<Map<String, String>>? wordList;
  final VoiceUseCases? voice;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final FlashcardModeAdapter? modeAdapter;

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
  FlashcardReviewController? _review;
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _abandoning = false;
  final Stopwatch _responseStopwatch = Stopwatch();
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  FlashcardModeAdapter? _modeAdapter;
  UnifiedLessonSessionLifecycle? _lessonLifecycle;
  bool _compatibilityCompleted = false;
  bool _loadSettled = false;

  bool get _isCompatibilityDeck => widget.wordList != null;
  bool get _persistenceLocked => _review?.persistenceLocked ?? false;
  bool get _completionCommitted =>
      _compatibilityCompleted || (_review?.isCompleted ?? false);
  bool get _saving => _abandoning || (_review?.isSaving ?? false);
  bool get _actionLocked =>
      _abandoning ||
      (!_isCompatibilityDeck && _lessonLifecycle?.acceptsOperations == false) ||
      (!_isCompatibilityDeck && (_review?.actionLocked ?? true)) ||
      _completionCommitted;

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
      _load = _LegacyFlashcardCompatibilityScope.authorized(context)
          ? Future.value(_compatibilitySession(widget.wordList!))
          : Future<QuizSession>.error(
              StateError('Legacy flashcard compatibility is unauthorized'),
            );
    } else {
      _learning = widget.learning ?? dependencies?.learning;
      final registeredAdapter = dependencies?.lessonModes
          ?.find(LessonMode.flashcard)
          ?.adapter;
      _modeAdapter =
          widget.modeAdapter ??
          (registeredAdapter is FlashcardModeAdapter
              ? registeredAdapter
              : null);
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
          : _modeAdapter == null
          ? Future<QuizSession>.error(
              StateError('flashcard mode adapter dependency unavailable'),
            )
          : !identical(_evidenceAdapter!.learning, learning)
          ? Future<QuizSession>.error(
              StateError('flashcard learning authority mismatch'),
            )
          : learning.startDueReview();
      final lifecycle = _lessonLifecycle;
      _load = lifecycle == null
          ? _startLifecycle(load)
          : lifecycle.initializeSession(load);
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
      if (!_isCompatibilityDeck) {
        final lifecycle = _lessonLifecycle;
        _review = _modeAdapter!.createReview(
          session: session,
          learning: _learning!,
          evidence: _evidenceAdapter!,
          completeSession: lifecycle == null
              ? null
              : (close) => lifecycle.complete(close),
          recordInteraction: () => _lessonLifecycle?.recordInteraction(),
          acceptsOperation: () => _lessonLifecycle?.acceptsOperations ?? true,
        )..addListener(_onReviewChanged);
      }
      _responseStopwatch
        ..reset()
        ..start();
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

  QuizQuestion get _currentQuestion => _isCompatibilityDeck
      ? _session!.questions[_currentIndex]
      : _review!.currentQuestion;

  int get _visibleIndex =>
      _isCompatibilityDeck ? _currentIndex : _review!.index;

  bool get _visibleFlipped =>
      _isCompatibilityDeck ? _isFlipped : (_review?.isRevealed ?? false);

  void _onReviewChanged() {
    if (mounted) setState(() {});
  }

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
    if (!_isCompatibilityDeck) {
      unawaited(_revealAnswer());
      return;
    }
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
    if (_isCompatibilityDeck) {
      await _nextCompatibilityCard();
      return;
    }
    final review = _review!;
    final previousIndex = review.index;
    try {
      await review.rate(
        remembered: isCorrect,
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
      await _afterReviewAction(previousIndex: previousIndex);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _revealAnswer() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      await review.reveal(
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
      if (!mounted) return;
      await _controller.forward();
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _advanceAfterReveal() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    final previousIndex = review.index;
    try {
      await review.advanceAfterReveal();
      await _afterReviewAction(previousIndex: previousIndex);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _retryReview() async {
    final review = _review;
    if (review == null || !review.requiresRetry || review.isSaving) return;
    final previousIndex = review.index;
    final wasRevealed = review.isRevealed;
    try {
      await review.retry();
      if (!mounted) return;
      if (!wasRevealed && review.isRevealed) {
        await _controller.forward();
      }
      await _afterReviewAction(previousIndex: previousIndex);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _afterReviewAction({required int previousIndex}) async {
    if (!mounted) return;
    final review = _review!;
    if (review.isCompleted) {
      await _completeReview();
      return;
    }
    if (review.index != previousIndex) {
      if (_controller.value != 0) await _controller.reverse();
      _responseStopwatch
        ..reset()
        ..start();
      await _playAudio();
    }
  }

  Future<void> _nextCompatibilityCard() async {
    _lessonLifecycle?.recordInteraction();
    if (_currentIndex < _session!.questions.length - 1) {
      if (_isFlipped) _controller.reverse();
      setState(() {
        _isFlipped = false;
        _currentIndex++;
      });
      _responseStopwatch
        ..reset()
        ..start();
      await _playAudio();
      return;
    }
    await _completeReview();
  }

  Future<void> _completeReview() async {
    if (!mounted) return;
    if (_isCompatibilityDeck) {
      setState(() => _compatibilityCompleted = true);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว')),
    );
    Navigator.of(context).pop();
  }

  void _showSaveFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง')),
    );
  }

  @override
  void dispose() {
    _responseStopwatch.stop();
    _review
      ?..removeListener(_onReviewChanged)
      ..dispose();
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
    setState(() => _abandoning = true);
    try {
      await _lessonLifecycle?.abandon();
    } catch (_) {
      if (mounted) setState(() => _abandoning = false);
      _showSaveFailure();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildCard() {
    final word = _currentQuestion.word;
    final actionLocked = _actionLocked;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: max(0, constraints.maxHeight - 48),
            ),
            child: Column(
              children: [
                Text(
                  '${_visibleIndex + 1}/${_session!.questions.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: max(180, constraints.maxHeight * 0.52),
                  child: Semantics(
                    button: !_visibleFlipped,
                    enabled: !actionLocked,
                    label: _visibleFlipped
                        ? 'Answer for ${word.spelling}'
                        : 'Reveal answer for ${word.spelling}',
                    child: GestureDetector(
                      key: !_isCompatibilityDeck && !_visibleFlipped
                          ? const ValueKey<String>('flashcard-reveal-answer')
                          : null,
                      onTap: actionLocked || _visibleFlipped ? null : _flipCard,
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
                                          transform: Matrix4.identity()
                                            ..rotateY(pi),
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
                ),
                const SizedBox(height: 20),
                if (_saving)
                  const LinearProgressIndicator()
                else if (_review?.requiresRetry ?? false)
                  FilledButton(
                    key: const ValueKey<String>('current-evidence-retry'),
                    onPressed: _retryReview,
                    child: Text(
                      _review!.requiresCompletionRetry
                          ? 'Retry session completion'
                          : 'Retry saved review',
                    ),
                  )
                else if (_completionCommitted)
                  const SizedBox.shrink()
                else if (_isCompatibilityDeck && _visibleFlipped)
                  _ratingControls()
                else if (!_isCompatibilityDeck && _visibleFlipped)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey<String>('flashcard-continue'),
                      onPressed: _advanceAfterReveal,
                      child: const Text('Continue'),
                    ),
                  )
                else if (!_isCompatibilityDeck)
                  _ratingControls(includeRevealInstruction: true)
                else
                  const Text('แตะการ์ดเพื่อดูคำแปล'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ratingControls({bool includeRevealInstruction = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          key: const ValueKey<String>('flashcard-not-remembered'),
          onPressed: () => _rateItem(false),
          child: const Text('จำไม่ได้ (Again)'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey<String>('flashcard-remembered'),
          onPressed: () => _rateItem(true),
          child: const Text('จำได้แล้ว (Good)'),
        ),
        if (includeRevealInstruction) ...[
          const SizedBox(height: 8),
          const Text(
            'แตะการ์ดเพื่อดูคำแปล (ไม่นับเป็นการจำได้ด้วยตนเอง)',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _front(QuizWord word) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.spelling,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 16),
            IconButton(
              onPressed: _actionLocked ? null : _playAudio,
              icon: const Icon(Icons.volume_up_outlined),
              iconSize: 40,
              tooltip: 'ฟังเสียง',
            ),
          ],
        ),
      ),
    );
  }

  Widget _back(QuizWord word) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.spelling,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              word.meaning,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (word.partOfSpeech.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(word.partOfSpeech, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
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
