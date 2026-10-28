import 'package:flutter/material.dart';
import '../features/accessibility/domain/accessibility_policy.dart';
import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../voice/voice_models.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';

class SentenceScrambleScreen extends StatefulWidget {
  final String targetSentence;
  final String translation;
  final VoiceUseCases? voice;
  final String? ownerId;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final SentenceScrambleModeAdapter modeAdapter;

  const SentenceScrambleScreen({
    super.key,
    required this.targetSentence,
    this.translation = '',
    this.voice,
    this.ownerId,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
    this.evidenceAdapter,
    this.modeAdapter = const SentenceScrambleModeAdapter(),
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
  DateTime? _startedAtUtc;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  LearningUseCases? _learning;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  UnifiedLessonSessionLifecycle? _lifecycle;
  bool _pendingWasCorrect = false;
  bool _sessionCompleted = false;
  late int _nextAttemptNumber;

  SentenceScrambleModeAdapter get _modeAdapter => widget.modeAdapter;
  bool get _acceptsModeOperations =>
      mounted && (_lifecycle?.acceptsOperations ?? true);
  bool get _persistenceLocked =>
      _pendingEvidence != null || _pendingSessionClose != null;
  bool get _interactionLocked => _persistenceLocked || _sessionCompleted;

  @override
  void initState() {
    super.initState();
    _originalWords = widget.targetSentence.trim().split(RegExp(r'\s+'));
    _scrambledWords = List<String>.from(_originalWords)..shuffle();
    _startedAtUtc = DateTime.now().toUtc();
    _nextAttemptNumber = widget.attemptNumber;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAudio();
    });
  }

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _voice = widget.voice ?? dependencies?.voice;
    _learning = dependencies?.learning;
    _evidenceAdapter =
        widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    refreshRouteVoiceSession();
  }

  Future<void> _playAudio() async {
    if (_interactionLocked || !_acceptsModeOperations) return;
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
    if (_interactionLocked || !_acceptsModeOperations) return;
    setState(() {
      final word = _scrambledWords.removeAt(index);
      _userSelection.add(word);
      _isCorrect = null;
    });
  }

  void _deselectWord(int index) {
    if (_interactionLocked || !_acceptsModeOperations) return;
    setState(() {
      final word = _userSelection.removeAt(index);
      _scrambledWords.add(word);
      _isCorrect = null;
    });
  }

  Future<void> _checkSentence() async {
    if (_interactionLocked || !_acceptsModeOperations) return;
    final userSentence = _userSelection.join(' ');
    final evaluation = _modeAdapter.evaluate(
      target: widget.targetSentence,
      response: userSentence,
    );
    final evidence = _evidenceAdapter;
    final sessionId = widget.sessionId;
    final wordId = widget.wordId;
    if (evidence == null || sessionId == null || wordId == null) {
      setState(() => _isCorrect = evaluation.isCorrect);
      return;
    }
    final pending = _pendingEvidence = _modeAdapter
        .capture(
          evidence: evidence,
          ownerId: widget.ownerId,
          sessionId: sessionId,
          wordId: wordId,
          target: widget.targetSentence,
          response: userSentence,
          responseTimeMs: DateTime.now()
              .toUtc()
              .difference(_startedAtUtc!)
              .inMilliseconds,
          attemptNumber: _nextAttemptNumber,
        )
        .pending;
    _pendingWasCorrect = evaluation.isCorrect;
    setState(() {});
    try {
      await (_lifecycle?.runAcceptedOperation(pending.record) ??
          pending.record());
      if (identical(_pendingEvidence, pending)) {
        await _afterEvidenceCommitted(_pendingWasCorrect);
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _reset() {
    if (_interactionLocked || !_acceptsModeOperations) return;
    setState(() {
      _userSelection.clear();
      _scrambledWords = List<String>.from(_originalWords)..shuffle();
      _isCorrect = null;
    });
  }

  Future<void> _retryEvidence() async {
    final pending = _pendingEvidence;
    if (pending == null || !pending.requiresRetry || !_acceptsModeOperations) {
      return;
    }
    try {
      await (_lifecycle?.runAcceptedOperation(pending.retry) ??
          pending.retry());
      if (identical(_pendingEvidence, pending)) {
        await _afterEvidenceCommitted(_pendingWasCorrect);
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _afterEvidenceCommitted(bool shouldComplete) async {
    _pendingEvidence = null;
    _isCorrect = shouldComplete;
    final lifecycle = _lifecycle;
    final learning = _learning;
    final sessionId = widget.sessionId;
    if (!shouldComplete ||
        lifecycle == null ||
        learning == null ||
        sessionId == null) {
      if (!shouldComplete) _nextAttemptNumber += 1;
      if (mounted) setState(() {});
      return;
    }
    final close = _pendingSessionClose ??= learning.captureSessionClose(
      sessionId: sessionId,
      ownerId: widget.ownerId,
    );
    if (mounted) setState(() {});
    try {
      await _lifecycle!.complete(close);
      _pendingSessionClose = null;
      _sessionCompleted = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _retrySessionClose() async {
    final close = _pendingSessionClose;
    if (close == null || !close.requiresRetry || !_acceptsModeOperations) {
      return;
    }
    try {
      await _lifecycle!.complete(close);
      _pendingSessionClose = null;
      _sessionCompleted = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_persistenceLocked,
      child: AccessibilityModeScaffold(
        appBar: AppBar(
          title: const Text(
            'เรียงประโยคภาษาอังกฤษ',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: Colors.indigo,
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (widget.translation.isNotEmpty) ...[
                  AccessibilitySemanticRegion(
                    role: AccessibilitySemanticRole.prompt,
                    child: Text(
                      widget.translation,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: IconButton(
                    tooltip: 'ฟังประโยคอีกครั้ง',
                    icon: const Icon(
                      Icons.volume_up,
                      size: 36,
                      color: Colors.deepPurple,
                      semanticLabel: 'ฟังประโยคอีกครั้ง',
                    ),
                    onPressed: _interactionLocked ? null : _playAudio,
                  ),
                ),
                const SizedBox(height: 20),
                // User selection area
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: Container(
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
                ),
                const SizedBox(height: 30),
                // Scrambled pool area
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: Wrap(
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
                ),
                const SizedBox(height: 30),
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _interactionLocked ? null : _reset,
                          child: const Text('เริ่มใหม่'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              _userSelection.isNotEmpty && !_interactionLocked
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
                ),
                if (_isCorrect != null) ...[
                  const SizedBox(height: 16),
                  AccessibilitySemanticRegion(
                    role: AccessibilitySemanticRole.feedback,
                    child: Text(
                      _isCorrect!
                          ? 'ถูกต้อง! (Great job)'
                          : 'เรียงยังไม่ถูกต้อง ลองใหม่อีกครั้ง',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _isCorrect! ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ],
                if (_pendingEvidence?.requiresRetry ?? false)
                  AccessibilitySemanticRegion(
                    role: AccessibilitySemanticRole.responseAndInput,
                    child: TextButton(
                      onPressed: _retryEvidence,
                      child: const Text('ลองบันทึกผลอีกครั้ง'),
                    ),
                  ),
                if (_pendingSessionClose?.requiresRetry ?? false)
                  AccessibilitySemanticRegion(
                    role: AccessibilitySemanticRole.responseAndInput,
                    child: TextButton(
                      onPressed: _retrySessionClose,
                      child: const Text('ลองปิดเซสชันอีกครั้ง'),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
