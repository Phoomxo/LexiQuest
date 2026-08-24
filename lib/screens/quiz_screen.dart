import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/meaning_quiz_mode_adapter.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/answer_feedback_panel.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import 'score_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    this.categoryId,
    this.learning,
    this.evidenceAdapter,
    this.modeAdapter,
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final MeaningQuizModeAdapter? modeAdapter;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Stopwatch _responseStopwatch = Stopwatch();
  LearningUseCases? _learning;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  MeaningQuizModeAdapter? _modeAdapter;
  UnifiedLessonSessionLifecycle? _lessonLifecycle;
  Future<QuizSession>? _load;
  QuizSession? _session;
  MeaningQuizReviewController? _review;
  bool _completionCommitted = false;
  bool _loadSettled = false;
  bool _abandoning = false;

  bool get _persistenceLocked =>
      _abandoning || (_review?.persistenceLocked ?? false);
  bool get _actionLocked =>
      _abandoning ||
      _lessonLifecycle?.acceptsOperations == false ||
      (_review?.actionLocked ?? true) ||
      _completionCommitted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _lessonLifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    _learning = widget.learning ?? dependencies?.learning;
    final learning = _learning;
    if (learning != null) {
      _evidenceAdapter =
          widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    }
    final registeredAdapter = dependencies?.lessonModes
        ?.find(LessonMode.meaningQuiz)
        ?.adapter;
    _modeAdapter =
        widget.modeAdapter ??
        (registeredAdapter is MeaningQuizModeAdapter
            ? registeredAdapter
            : dependencies == null
            ? const MeaningQuizModeAdapter()
            : null);
    final rawLoad = learning == null
        ? Future<QuizSession>.error(
            StateError('local learning dependency unavailable'),
          )
        : _evidenceAdapter == null
        ? Future<QuizSession>.error(
            StateError('current activity evidence dependency unavailable'),
          )
        : _modeAdapter == null
        ? Future<QuizSession>.error(
            StateError('meaning quiz mode adapter dependency unavailable'),
          )
        : !identical(_evidenceAdapter!.learning, learning)
        ? Future<QuizSession>.error(
            StateError('meaning quiz learning authority mismatch'),
          )
        : learning.startQuiz(categoryId: widget.categoryId);
    final lifecycle = _lessonLifecycle;
    _load = _prepareSession(
      lifecycle == null ? rawLoad : lifecycle.initializeSession(rawLoad),
    );
  }

  Future<QuizSession> _prepareSession(Future<QuizSession> load) async {
    try {
      final session = await load;
      if (!mounted) return session;
      if (!session.isEmpty) {
        final lifecycle = _lessonLifecycle;
        _review = _modeAdapter!.createReview(
          session: session,
          learning: _learning!,
          evidence: _evidenceAdapter!,
          completeSession: lifecycle == null
              ? null
              : (close) => lifecycle.complete(close),
          recordInteraction: () => lifecycle?.recordInteraction(),
          acceptsOperation: () => lifecycle?.acceptsOperations ?? true,
          runEvidenceOperation: lifecycle == null
              ? null
              : (operation) => lifecycle.runAcceptedOperation(operation),
        )..addListener(_onReviewChanged);
        _responseStopwatch
          ..reset()
          ..start();
      }
      setState(() => _session = session);
      return session;
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
        unawaited(_confirmExit(context));
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Quiz คำศัพท์')),
        body: FutureBuilder<QuizSession>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _QuizMessage(
                icon: Icons.error_outline,
                message:
                    'เปิด Quiz ไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกเปลี่ยนแปลง',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const _QuizMessage(
                icon: Icons.library_add_outlined,
                message: 'ยังไม่มีคำศัพท์สำหรับ Quiz กรุณาเพิ่มคำศัพท์ก่อน',
              );
            }
            final review = _review;
            if (review == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildQuestion(review);
          },
        ),
      ),
    );
  }

  Widget _buildQuestion(MeaningQuizReviewController review) {
    final question = review.currentQuestion;
    final actionLocked = _actionLocked;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: 'คำถาม ${review.index + 1} จาก ${review.questions.length}',
              child: LinearProgressIndicator(
                value: (review.index + 1) / review.questions.length,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              question.prompt,
              key: const ValueKey<String>('meaning-quiz-prompt'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              question.word.partOfSpeech,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ...question.options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.tonal(
                  key: ValueKey<String>(
                    'meaning-quiz-option-${question.word.id}-$option',
                  ),
                  onPressed: review.isAnswered || actionLocked
                      ? null
                      : () => _record(option),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _answerColor(review, option),
                  ),
                  child: Text(option),
                ),
              ),
            ),
            if (review.isSaving) const LinearProgressIndicator(),
            if (review.phase == MeaningQuizReviewPhase.evidenceRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: review.isSaving ? null : _retryEvidence,
                child: const Text('Retry saved answer'),
              )
            else if (review.phase ==
                MeaningQuizReviewPhase.completionRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: review.isSaving ? null : _retrySessionClose,
                child: const Text('Retry session completion'),
              ),
            if (review.feedback case final feedback?) ...<Widget>[
              const SizedBox(height: 12),
              AnswerFeedbackPanel(feedback: feedback),
            ],
            if (review.isAnswered) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey<String>('meaning-quiz-next'),
                onPressed: actionLocked ? null : _next,
                child: Text(
                  review.index == review.questions.length - 1
                      ? 'ดูผลการเรียน'
                      : 'คำถามถัดไป',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color? _answerColor(MeaningQuizReviewController review, String option) {
    if (!review.isAnswered) return null;
    if (option == review.currentQuestion.correctOption) {
      return Colors.green.shade100;
    }
    if (option == review.selectedOption) return Colors.red.shade100;
    return null;
  }

  Future<void> _record(String option) async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      final result = await review.answer(
        option: option,
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
      await _haptic(result);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _retryEvidence() async {
    final review = _review;
    if (review == null || !review.requiresRetry || review.isSaving) return;
    try {
      final result = await review.retryEvidence();
      await _haptic(result);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _haptic(AnswerRecordResult result) async {
    try {
      if (result.isCorrect) {
        await HapticFeedback.lightImpact();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (_) {
      // Evidence is already durable; ornamental feedback is best-effort.
    }
  }

  Future<void> _next() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      final summary = await review.advance();
      if (summary != null) {
        await _showScore(summary);
        return;
      }
      _responseStopwatch
        ..reset()
        ..start();
    } catch (_) {
      _showSessionCloseFailure();
    }
  }

  Future<void> _retrySessionClose() async {
    final review = _review;
    if (review == null || review.isSaving) return;
    try {
      await _showScore(await review.retryCompletion());
    } catch (_) {
      _showSessionCloseFailure();
    }
  }

  Future<void> _showScore(LearningSessionSummary summary) async {
    if (!mounted) return;
    setState(() => _completionCommitted = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/score',
        builder: (_) => ScoreScreen(
          correctAnswers: summary.correctCount,
          wrongAnswers: summary.wrongCount,
          score: summary.score,
        ),
      ),
      replace: true,
    );
  }

  Future<void> _confirmExit(BuildContext context) async {
    if (_persistenceLocked) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ออกจาก Quiz?'),
        content: const Text('ความคืบหน้าในเซสชันนี้จะไม่ถูกบันทึก'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('เล่นต่อ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ออก'),
          ),
        ],
      ),
    );
    if (shouldExit == true && context.mounted && !_persistenceLocked) {
      await _abandonAndPop();
    }
  }

  Future<void> _abandonAndPop() async {
    final session = _session;
    if (_abandoning || _completionCommitted || session == null) return;
    setState(() => _abandoning = true);
    try {
      final lifecycle = _lessonLifecycle;
      if (lifecycle != null) {
        await lifecycle.abandon();
      } else {
        await _learning!.abandonSession(
          sessionId: session.id,
          abandonedAtUtc: DateTime.now().toUtc(),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _abandoning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ปิด session ไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showSaveFailure() {
    if (!mounted || _lessonLifecycle?.acceptsOperations == false) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง')),
    );
  }

  void _showSessionCloseFailure() {
    if (!mounted || _lessonLifecycle?.acceptsOperations == false) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ปิด session ไม่สำเร็จ กรุณาลองอีกครั้ง')),
    );
  }

  @override
  void dispose() {
    _responseStopwatch.stop();
    _review?.removeListener(_onReviewChanged);
    _review?.dispose();
    super.dispose();
  }
}

class _QuizMessage extends StatelessWidget {
  const _QuizMessage({required this.icon, required this.message});

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
