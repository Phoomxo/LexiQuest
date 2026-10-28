import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/accessibility/presentation/accessibility_scope.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

typedef MatchingSessionLoader = Future<QuizSession> Function();

class LegacyMatchingModeScreen extends StatefulWidget {
  const LegacyMatchingModeScreen({
    super.key,
    this.categoryId,
    this.learning,
    this.evidenceAdapter,
    this.modeAdapter,
    this.loadSession,
    this.timeLimit = const Duration(minutes: 2),
    this.sessionConfiguration,
    this.showCountdown = true,
    this.shellFeedback,
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final MatchingModeAdapter? modeAdapter;
  final MatchingSessionLoader? loadSession;
  final Duration? timeLimit;
  final SessionConfiguration? sessionConfiguration;
  final bool showCountdown;
  final Widget? shellFeedback;

  @override
  State<LegacyMatchingModeScreen> createState() =>
      _LegacyMatchingModeScreenState();
}

class _LegacyMatchingModeScreenState extends State<LegacyMatchingModeScreen> {
  final Stopwatch _responseStopwatch = Stopwatch();
  LearningUseCases? _learning;
  CurrentActivityEvidenceAdapter? _evidence;
  MatchingModeAdapter? _adapter;
  UnifiedLessonSessionLifecycle? _lifecycle;
  Future<QuizSession>? _load;
  QuizSession? _session;
  MatchingPreparedSession? _recovery;
  MatchingReviewController? _review;
  Timer? _timeoutTimer;
  Future<void>? _timeoutContinuation;
  Duration? _announcedTimeRemaining;
  bool _loadSettled = false;
  bool _completionCommitted = false;
  bool _abandoning = false;

  bool get _persistenceLocked =>
      _abandoning || (_review?.persistenceLocked ?? false);
  bool get _actionLocked =>
      _abandoning ||
      _completionCommitted ||
      _lifecycle?.acceptsOperations == false ||
      (_review?.actionLocked ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    if (widget.timeLimit != null && widget.timeLimit! <= Duration.zero) {
      _load = Future<QuizSession>.error(
        ArgumentError.value(widget.timeLimit, 'timeLimit', 'must be positive'),
      );
      return;
    }
    final dependencies = AppDependenciesScope.maybeOf(context);
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    _learning = widget.learning ?? dependencies?.learning;
    final learning = _learning;
    if (learning != null) {
      _evidence =
          widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    }
    final registeredAdapter = dependencies?.lessonModes
        ?.resolve(LessonMode.matching)
        ?.adapter;
    _adapter =
        widget.modeAdapter ??
        (registeredAdapter is MatchingModeAdapter
            ? registeredAdapter
            : dependencies == null
            ? const MatchingModeAdapter()
            : null);
    final rawLoad = learning == null
        ? Future<QuizSession>.error(
            StateError('local learning dependency unavailable'),
          )
        : _evidence == null
        ? Future<QuizSession>.error(
            StateError('current activity evidence dependency unavailable'),
          )
        : _adapter == null
        ? Future<QuizSession>.error(
            StateError('matching mode adapter dependency unavailable'),
          )
        : !identical(_evidence!.learning, learning)
        ? Future<QuizSession>.error(
            StateError('matching learning authority mismatch'),
          )
        : widget.loadSession?.call() ??
              _adapter!
                  .prepareSession(
                    learning: learning,
                    evidence: _evidence!,
                    categoryId: widget.categoryId,
                    timeLimit: widget.timeLimit,
                    itemCount: widget.sessionConfiguration?.itemCount ?? 6,
                    sessionConfiguration: widget.sessionConfiguration,
                  )
                  .then((prepared) {
                    _recovery = prepared;
                    return prepared.session;
                  });
    final lifecycle = _lifecycle;
    _load = _prepareSession(
      lifecycle == null
          ? rawLoad
          : lifecycle.initializeSession(
              rawLoad,
              recoveredClose: () => _recovery?.pendingClose,
            ),
      dependencies?.vocabulary?.readPinnedByIds,
    );
  }

  Future<QuizSession> _prepareSession(
    Future<QuizSession> load,
    Future<List<VocabularyWord>> Function(Iterable<String> ids)?
    loadLexicalWords,
  ) async {
    QuizSession? session;
    try {
      session = await load;
      if (!mounted || session.isEmpty) return session;
      final lifecycle = _lifecycle;
      final recovery = _recovery;
      if (lifecycle?.acceptsOperations == false &&
          recovery?.requiresRecovery != true) {
        return session;
      }
      final restoredSummary = recovery?.completedSummary == null
          ? null
          : await recovery!.reconcileCompleted(
              completeSession: lifecycle == null
                  ? (close) =>
                        close.requiresRetry ? close.retry() : close.finish()
                  : lifecycle.completeRecovery,
            );
      final lexicalWords = loadLexicalWords == null
          ? const <VocabularyWord>[]
          : await loadLexicalWords(
              session.questions.map((question) => question.word.id),
            );
      if (!mounted) return session;
      final review = _adapter!.createReview(
        session: session,
        learning: _learning!,
        evidence: _evidence!,
        recovery: _recovery,
        hintUsage: () =>
            lifecycle?.snapshotHintUsage() ??
            const HintUsageSnapshot.unavailable(),
        resetHintsAfterCommit: () =>
            lifecycle?.resetHintsAfterCommittedEvidence(),
        lexicalWords: lexicalWords,
        completeSession: lifecycle == null
            ? null
            : (close) => lifecycle.completeRecovery(close),
        ownClose: lifecycle?.ownRecoveryClose,
        runAdmittedOperation: lifecycle?.runAdmittedOperation,
        runRecoveryOperation: lifecycle?.runRecoveryOperation,
        acceptsOperation: () => lifecycle?.acceptsOperations ?? true,
      )..addListener(_onReviewChanged);
      _review = review;
      _session = session;
      final completedSummary = restoredSummary ?? review.completedSummary;
      if (completedSummary != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showScore(completedSummary));
        });
        if (mounted) setState(() {});
        return session;
      }
      _responseStopwatch
        ..reset()
        ..start();
      final remaining = _recovery?.remainingTime(_learning!.nowUtc());
      _announcedTimeRemaining = remaining;
      if (remaining == null) {
        // Untimed accessibility sessions are bounded only by the shell's
        // persisted active-effort authority, never by a wall-clock timer.
      } else if (review.timeoutRequested || remaining == Duration.zero) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_timeOut());
        });
      } else {
        _timeoutTimer = Timer(remaining, _startTimeoutContinuation);
      }
      if (mounted) setState(() {});
      return session;
    } catch (_) {
      if (session != null &&
          !session.isEmpty &&
          _recovery?.completedSummary == null) {
        final lifecycle = _lifecycle;
        if (lifecycle != null) {
          await lifecycle.abandon();
        } else {
          await _learning!.abandonSession(
            ownerId: session.ownerId,
            sessionId: session.id,
            abandonedAtUtc: DateTime.now().toUtc(),
          );
        }
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _loadSettled = true);
    }
  }

  void _onReviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !_persistenceLocked &&
          _loadSettled &&
          (_session == null || _session!.isEmpty || _completionCommitted),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _persistenceLocked) return;
        unawaited(_confirmExit());
      },
      child: AccessibilityModeScaffold(
        appBar: AppBar(title: const Text('จับคู่คำศัพท์')),
        body: FutureBuilder<QuizSession>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _MatchingMessage(
                icon: Icons.error_outline,
                message:
                    'กิจกรรมจับคู่ไม่พร้อมใช้งาน ข้อมูลการเรียนไม่เปลี่ยนแปลง',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const _MatchingMessage(
                icon: Icons.library_add_outlined,
                message: 'ยังไม่มีคำศัพท์สำหรับกิจกรรมจับคู่',
              );
            }
            final review = _review;
            if (review == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildBoard(review);
          },
        ),
      ),
    );
  }

  Widget _buildBoard(MatchingReviewController review) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: Localizations.localeOf(context).languageCode == 'th'
                  ? 'จับคู่แล้ว ${review.matchedWordIds.length} จาก ${review.pairSet.pairs.length} คู่'
                  : '${review.matchedWordIds.length} of ${review.pairSet.pairs.length} pairs matched',
              child: LinearProgressIndicator(
                value:
                    review.matchedWordIds.length / review.pairSet.pairs.length,
              ),
            ),
            const SizedBox(height: 12),
            AccessibilitySemanticRegion(
              role: AccessibilitySemanticRole.prompt,
              child: Text(
                widget.showCountdown
                    ? 'จับคู่คำศัพท์กับความหมาย เวลาที่เหลือ: '
                          '${_durationLabel(_announcedTimeRemaining ?? widget.timeLimit!)}.'
                    : 'กิจกรรมแบบไม่แสดงเวลานับถอยหลัง ยังมีขีดจำกัดเวลาเรียนจริง',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 4),
            AccessibilitySemanticRegion(
              role: AccessibilitySemanticRole.responseAndInput,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'คำศัพท์',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final pair in review.pairSet.wordOrder)
                    if (!review.matchedWordIds.contains(pair.word.id))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Semantics(
                          button: true,
                          selected: review.selectedWordId == pair.word.id,
                          label: 'คำศัพท์ ${pair.wordLabel}',
                          child: FilledButton.tonal(
                            key: ValueKey<String>(
                              'matching-word-${pair.word.id}',
                            ),
                            onPressed: _actionLocked
                                ? null
                                : () => _selectWord(pair.word.id),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: Text(
                              pair.wordLabel,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  Text(
                    'ความหมาย',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final pair in review.pairSet.meaningOrder)
                    if (!review.matchedWordIds.contains(pair.word.id))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Semantics(
                          button: true,
                          selected:
                              review.selectedMeaningWordId == pair.word.id,
                          label: 'ความหมาย ${pair.meaningLabel}',
                          child: OutlinedButton(
                            key: ValueKey<String>(
                              'matching-meaning-${pair.word.id}',
                            ),
                            onPressed: _actionLocked
                                ? null
                                : () => _selectMeaning(pair.word.id),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: Text(
                              pair.meaningLabel,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            if (review.phase == MatchingReviewPhase.savingEvidence ||
                review.phase == MatchingReviewPhase.completing)
              const LinearProgressIndicator(),
            if (review.phase == MatchingReviewPhase.evidenceRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: _retryEvidence,
                child: const Text('ลองบันทึกคู่เดิมอีกครั้ง'),
              )
            else if (review.phase ==
                MatchingReviewPhase.completionRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: _retryCompletion,
                child: const Text('ลองจบกิจกรรมอีกครั้ง'),
              ),
            if (review.feedback case final feedback?) ...<Widget>[
              const SizedBox(height: 12),
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.feedback,
                child: AnswerFeedbackPanel(feedback: feedback),
              ),
            ],
            if (widget.shellFeedback != null) widget.shellFeedback!,
            if (review.allMatched && !_completionCommitted) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey<String>('matching-finish'),
                onPressed: _actionLocked ? null : _finish,
                child: const Text('ดูผลการเรียน'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes == 0) return '$seconds sec';
    if (seconds == 0) return '$minutes min';
    return '$minutes min $seconds sec';
  }

  Future<void> _selectWord(String wordId) => _select(
    () => _review!.selectWord(
      wordId,
      responseTimeMs: _responseStopwatch.elapsedMilliseconds,
    ),
  );

  Future<void> _selectMeaning(String wordId) => _select(
    () => _review!.selectMeaning(
      wordId,
      responseTimeMs: _responseStopwatch.elapsedMilliseconds,
    ),
  );

  Future<void> _select(Future<AnswerRecordResult?> Function() operation) async {
    if (_actionLocked) return;
    try {
      final result = await operation();
      if (result != null) {
        final review = _review;
        if (review?.timeoutRequested == true) {
          await _showScore(await review!.timeout());
          return;
        }
        _responseStopwatch
          ..reset()
          ..start();
      }
    } on Object {
      _showFailure('ยังยืนยันการบันทึกคู่คำไม่ได้ กรุณาลองบันทึกอีกครั้ง');
    }
  }

  Future<void> _retryEvidence() async {
    final review = _review;
    if (review == null ||
        review.phase != MatchingReviewPhase.evidenceRetryRequired) {
      return;
    }
    try {
      await review.retryEvidence();
      if (review.timeoutRequested) {
        await _showScore(await review.timeout());
        return;
      }
      _responseStopwatch
        ..reset()
        ..start();
    } on Object {
      _showFailure('ยังยืนยันการบันทึกคู่คำไม่ได้ กรุณาลองบันทึกอีกครั้ง');
    }
  }

  Future<void> _finish() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    _timeoutTimer?.cancel();
    try {
      await _showScore(await review.finish());
    } on Object {
      _showFailure('ยังจบกิจกรรมไม่ได้ กรุณาลองอีกครั้ง');
    }
  }

  Future<void> _timeOut() async {
    final review = _review;
    if (!mounted || review == null || _completionCommitted) return;
    try {
      await _showScore(await review.timeout());
    } on Object {
      _showFailure('ยังจบกิจกรรมเมื่อหมดเวลาไม่ได้ กรุณาลองอีกครั้ง');
    }
  }

  void _startTimeoutContinuation() {
    if (_timeoutContinuation != null) return;
    final continuation = _timeOut();
    _timeoutContinuation = continuation;
    unawaited(
      continuation.whenComplete(() {
        if (identical(_timeoutContinuation, continuation)) {
          _timeoutContinuation = null;
        }
      }),
    );
  }

  Future<void> _retryCompletion() async {
    final review = _review;
    if (review == null) return;
    try {
      await _showScore(await review.retryCompletion());
    } on Object {
      _showFailure('ยังจบกิจกรรมไม่ได้ กรุณาลองอีกครั้ง');
    }
  }

  Future<void> _showScore(LearningSessionSummary summary) async {
    if (!mounted) return;
    _timeoutTimer?.cancel();
    setState(() => _completionCommitted = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/score',
        builder: (_) => _MatchingScoreReceipt(
          onPresented: () async {
            final recovery = _recovery;
            if (recovery != null) {
              await recovery.markSummaryPresented(summary);
            }
          },
          child: ScoreScreen(
            correctAnswers: summary.correctCount,
            wrongAnswers: summary.wrongCount,
            score: summary.score,
          ),
        ),
      ),
      replace: true,
    );
  }

  Future<void> _confirmExit() async {
    if (_persistenceLocked) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากกิจกรรมจับคู่หรือไม่'),
        content: const Text('ระบบจะดำเนินการจบกิจกรรมที่กำลังเรียนอยู่'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('จับคู่ต่อ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ออกจากกิจกรรม'),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted && !_persistenceLocked) {
      await _abandonAndPop();
    }
  }

  Future<void> _abandonAndPop() async {
    final session = _session;
    if (_abandoning || _completionCommitted || session == null) return;
    setState(() => _abandoning = true);
    _timeoutTimer?.cancel();
    try {
      final lifecycle = _lifecycle;
      if (lifecycle != null) {
        await lifecycle.abandon();
      } else {
        await _learning!.abandonSession(
          ownerId: session.ownerId,
          sessionId: session.id,
          abandonedAtUtc: DateTime.now().toUtc(),
        );
      }
    } on Object {
      if (!mounted) return;
      setState(() => _abandoning = false);
      _showFailure('ยังจบกิจกรรมไม่ได้ กรุณาลองอีกครั้ง');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showFailure(String message) {
    if (!mounted || _lifecycle?.acceptsOperations == false) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _responseStopwatch.stop();
    _review?.removeListener(_onReviewChanged);
    _review?.dispose();
    super.dispose();
  }
}

final class _MatchingScoreReceipt extends StatefulWidget {
  const _MatchingScoreReceipt({required this.child, this.onPresented});

  final Widget child;
  final Future<void> Function()? onPresented;

  @override
  State<_MatchingScoreReceipt> createState() => _MatchingScoreReceiptState();
}

final class _MatchingScoreReceiptState extends State<_MatchingScoreReceipt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final onPresented = widget.onPresented;
      if (onPresented == null) return;
      try {
        await onPresented();
      } on Object {
        // A missing presentation receipt deliberately replays this completed
        // summary after restart instead of suppressing a result the learner
        // may never have seen.
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _MatchingMessage extends StatelessWidget {
  const _MatchingMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
