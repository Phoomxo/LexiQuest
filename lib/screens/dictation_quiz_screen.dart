import 'package:flutter/material.dart';

import '../features/accessibility/domain/accessibility_policy.dart';
import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/domain/answer_feedback.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import 'media_dependency_unavailable.dart';

class DictationQuizScreen extends StatefulWidget
    implements AccessibilityModeFeedbackSurface {
  final String targetWord;
  final VoiceUseCases? voice;
  final String? ownerId;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final DictationModeAdapter modeAdapter;

  const DictationQuizScreen({
    super.key,
    required this.targetWord,
    this.voice,
    this.ownerId,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
    this.evidenceAdapter,
    this.modeAdapter = const DictationModeAdapter(),
  });

  @override
  Widget withShellFeedback(Widget? feedback) =>
      AccessibilityModeFeedbackSlot(feedback: feedback, child: this);

  @override
  State<DictationQuizScreen> createState() => _DictationQuizScreenState();
}

class _DictationQuizScreenState extends State<DictationQuizScreen>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<DictationQuizScreen> {
  VoiceUseCases? _voiceProvider;
  bool _initialPlaybackScheduled = false;
  final TextEditingController _textController = TextEditingController();
  bool? _isCorrect;
  bool _supportUsed = false;
  DateTime? _startedAtUtc;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  LearningUseCases? _learning;
  UnifiedLessonSessionLifecycle? _lifecycle;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  bool _sessionCompleted = false;
  late int _nextAttemptNumber;

  DictationModeAdapter get _modeAdapter => widget.modeAdapter;
  bool get _persistenceLocked =>
      _pendingEvidence != null || _pendingSessionClose != null;
  bool get _sessionCloseRetryRequired =>
      (_pendingSessionClose?.requiresRetry ?? false) ||
      (_lifecycle?.sessionCompletionRetryRequired ?? false);
  bool get _interactionLocked => _persistenceLocked || _sessionCompleted;

  @override
  VoiceUseCases? get routeVoiceUseCases => _voiceProvider;

  @override
  void initState() {
    super.initState();
    _nextAttemptNumber = widget.attemptNumber;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _voiceProvider = widget.voice ?? dependencies?.voice;
    _learning = dependencies?.learning;
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    _evidenceAdapter =
        widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    _startedAtUtc ??= DateTime.now().toUtc();
    refreshRouteVoiceSession();
    if (_voiceProvider != null && !_initialPlaybackScheduled) {
      _initialPlaybackScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playAudio(speed: 1.0);
      });
    }
  }

  Future<void> _playAudio({required double speed}) async {
    if (_interactionLocked || !(_lifecycle?.acceptsOperations ?? true)) {
      return;
    }
    if (speed < 1) _supportUsed = true;
    final session = routeVoiceSession;
    if (session == null) return;
    try {
      await session.speak(
        VoiceRequest.create(
          text: widget.targetWord,
          language: 'en',
          voiceId: 'teacher_female',
          speed: speed,
          mode: VoiceMode.practice,
          contentId: widget.targetWord,
          contentType: 'dictation_quiz',
        ),
      );
    } catch (e) {
      debugPrint('Error playing dictation audio: $e');
    }
  }

  Future<void> _checkAnswer() async {
    if (_interactionLocked || !(_lifecycle?.acceptsOperations ?? true)) {
      return;
    }
    final evaluation = _modeAdapter.evaluate(
      target: widget.targetWord,
      response: _textController.text,
      supportUsed: _supportUsed,
    );
    final evidence = _evidenceAdapter;
    final sessionId = widget.sessionId;
    final wordId = widget.wordId;
    if (evidence == null || sessionId == null || wordId == null) {
      if (_lifecycle == null && mounted) {
        setState(() => _isCorrect = evaluation.isCorrect);
      }
      return;
    }
    final captured = _modeAdapter.capture(
      evidence: evidence,
      ownerId: widget.ownerId,
      sessionId: sessionId,
      wordId: wordId,
      target: widget.targetWord,
      response: _textController.text,
      supportUsed: _supportUsed,
      responseTimeMs: DateTime.now()
          .toUtc()
          .difference(_startedAtUtc!)
          .inMilliseconds,
      attemptNumber: _nextAttemptNumber,
    );
    final pending = _pendingEvidence = captured.pending;
    setState(() {});
    try {
      final lifecycle = _lifecycle;
      final result =
          await (lifecycle?.recordCapturedEvidence(
                pending,
                feedbackContext: AnswerFeedbackContext(
                  canonicalCorrectAnswer: widget.targetWord,
                ),
              ) ??
              pending.record());
      if (identical(_pendingEvidence, pending)) {
        if (lifecycle == null && mounted) {
          setState(() => _isCorrect = result.isCorrect);
        }
        await _afterEvidenceCommitted(result.isCorrect);
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _retryEvidence() async {
    final pending = _pendingEvidence;
    if (pending == null ||
        !pending.requiresRetry ||
        !(_lifecycle?.acceptsOperations ?? true)) {
      return;
    }
    try {
      final lifecycle = _lifecycle;
      final result =
          await (lifecycle?.recordCapturedEvidence(
                pending,
                feedbackContext: AnswerFeedbackContext(
                  canonicalCorrectAnswer: widget.targetWord,
                ),
              ) ??
              pending.retry());
      if (identical(_pendingEvidence, pending)) {
        if (lifecycle == null && mounted) {
          setState(() => _isCorrect = result.isCorrect);
        }
        await _afterEvidenceCommitted(result.isCorrect);
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _afterEvidenceCommitted(bool shouldComplete) async {
    _pendingEvidence = null;
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
    if (close == null ||
        !_sessionCloseRetryRequired ||
        !(_lifecycle?.acceptsOperations ?? true)) {
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
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_voiceProvider == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.voice,
      );
    }
    final shellFeedback = AccessibilityModeFeedbackSlot.maybeOf(context);
    final appBar = AppBar(
      toolbarHeight: AccessibilityScope.of(context).textScale >= 2 ? 96 : null,
      title: const Text(
        'แบบฝึกฟังคำศัพท์ (Dictation Quiz)',
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      centerTitle: true,
      backgroundColor: Colors.indigo,
    );
    return PopScope(
      canPop: !_persistenceLocked,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            SizedBox(
              height:
                  appBar.preferredSize.height +
                  MediaQuery.of(context).padding.top,
              child: AccessibilityNavigationBar(child: appBar),
            ),
            Expanded(
              child: AccessibilityModeContentGroup(
                child: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stackedAudioControls =
                          constraints.maxWidth < 520 ||
                          AccessibilityScope.of(context).textScale >= 2;
                      final normalAudioButton = ElevatedButton.icon(
                        onPressed: _interactionLocked
                            ? null
                            : () => _playAudio(speed: 1.0),
                        icon: const Icon(Icons.volume_up),
                        label: const Text(
                          'ความเร็วปกติ (1.0x)',
                          textAlign: TextAlign.center,
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      );
                      final slowAudioButton = OutlinedButton.icon(
                        onPressed: _interactionLocked
                            ? null
                            : () => _playAudio(speed: 0.75),
                        icon: const Icon(Icons.slow_motion_video),
                        label: const Text(
                          'ฟังแบบช้า (0.75x)',
                          textAlign: TextAlign.center,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      );
                      final audioControls = stackedAudioControls
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                normalAudioButton,
                                const SizedBox(height: 12),
                                slowAudioButton,
                              ],
                            )
                          : Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 16,
                              runSpacing: 12,
                              children: <Widget>[
                                normalAudioButton,
                                slowAudioButton,
                              ],
                            );

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight > 48
                                ? constraints.maxHeight - 48
                                : 0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              AccessibilitySemanticRegion(
                                role: AccessibilitySemanticRole.prompt,
                                child: const Text(
                                  'ฟังเสียงแล้วพิมพ์คำศัพท์ให้ถูกต้อง:',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 30),
                              AccessibilitySemanticRegion(
                                role:
                                    AccessibilitySemanticRole.responseAndInput,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    audioControls,
                                    const SizedBox(height: 40),
                                    TextField(
                                      controller: _textController,
                                      enabled: !_interactionLocked,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'พิมพ์คำศัพท์ที่คุณได้ยิน...',
                                        prefixIcon: Icon(Icons.edit),
                                      ),
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _checkAnswer(),
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton(
                                      onPressed: _interactionLocked
                                          ? null
                                          : _checkAnswer,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        minimumSize: const Size(
                                          double.infinity,
                                          50,
                                        ),
                                      ),
                                      child: const Text(
                                        'ตรวจคำตอบ',
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    if (_pendingEvidence?.requiresRetry ??
                                        false)
                                      TextButton(
                                        onPressed: _retryEvidence,
                                        child: const Text(
                                          'ลองบันทึกผลอีกครั้ง',
                                        ),
                                      ),
                                    if (_sessionCloseRetryRequired)
                                      TextButton(
                                        onPressed: _retrySessionClose,
                                        child: const Text(
                                          'ลองปิดเซสชันอีกครั้ง',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              ?shellFeedback,
                              if (_lifecycle == null && _isCorrect != null)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _isCorrect!
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Icon(
                                        _isCorrect!
                                            ? Icons.check_circle
                                            : Icons.cancel,
                                        color: _isCorrect!
                                            ? Colors.green.shade800
                                            : Colors.red.shade800,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _isCorrect!
                                              ? 'ถูกต้อง! ($widget.targetWord)'
                                              : 'ลองใหม่อีกครั้ง!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _isCorrect!
                                                ? Colors.green.shade900
                                                : Colors.red.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
