import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../runtime/app_dependencies.dart';
import 'score_screen.dart';
import '../navigation/app_routes.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    this.categoryId,
    this.learning,
    this.evidenceAdapter,
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  LearningUseCases? _learning;
  Future<QuizSession>? _load;
  QuizSession? _session;
  int _index = 0;
  bool _answered = false;
  bool _saving = false;
  String? _selected;
  DateTime? _questionStartedAt;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  UnifiedLessonSessionLifecycle? _lessonLifecycle;
  bool _completionCommitted = false;
  bool _loadSettled = false;

  bool get _evidencePersistenceLocked {
    final pending = _pendingEvidence;
    return pending != null && !pending.isCommitted;
  }

  bool get _persistenceLocked =>
      _evidencePersistenceLocked ||
      _pendingSessionClose != null ||
      _completionCommitted;
  bool get _actionLocked => _saving || _persistenceLocked;

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
    final load = learning == null
        ? Future<QuizSession>.error(
            StateError('local learning dependency unavailable'),
          )
        : _evidenceAdapter == null
        ? Future<QuizSession>.error(
            StateError('current activity evidence dependency unavailable'),
          )
        : learning.startQuiz(categoryId: widget.categoryId);
    _load = _loadAndStartSession(load);
  }

  Future<QuizSession> _loadAndStartSession(Future<QuizSession> load) async {
    try {
      final session = await load;
      final startedAtUtc = session.startedAtUtc;
      if (!session.isEmpty && startedAtUtc != null) {
        await _lessonLifecycle?.start(
          sessionId: session.id,
          startedAtUtc: startedAtUtc,
          itemCount: session.questions.length,
        );
      }
      if (mounted) {
        setState(() {
          _session = session;
          _questionStartedAt = DateTime.now();
        });
      }
      return session;
    } finally {
      if (mounted) setState(() => _loadSettled = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final persistenceLocked = _persistenceLocked;
    return PopScope(
      canPop:
          !persistenceLocked &&
          _loadSettled &&
          (_session == null || _session!.isEmpty || _completionCommitted),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || persistenceLocked) return;
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
            final session = snapshot.data!;
            if (session.isEmpty) {
              return const _QuizMessage(
                icon: Icons.library_add_outlined,
                message: 'ยังไม่มีคำศัพท์สำหรับ Quiz กรุณาเพิ่มคำศัพท์ก่อน',
              );
            }
            return _buildQuestion(session);
          },
        ),
      ),
    );
  }

  Widget _buildQuestion(QuizSession session) {
    final question = session.questions[_index];
    final actionLocked = _actionLocked;
    final evidenceRetryRequired = _pendingEvidence?.requiresRetry ?? false;
    final sessionCloseRetryRequired = _pendingSessionClose != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'คำถาม ${_index + 1} จาก ${session.questions.length}',
              child: LinearProgressIndicator(
                value: (_index + 1) / session.questions.length,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              question.word.spelling,
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
                  onPressed: _answered || actionLocked
                      ? null
                      : () => _record(question, option),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _answerColor(question, option),
                  ),
                  child: Text(option),
                ),
              ),
            ),
            const Spacer(),
            if (_saving) const LinearProgressIndicator(),
            if (evidenceRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: _saving ? null : _retryEvidence,
                child: const Text('Retry saved answer'),
              )
            else if (sessionCloseRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: _saving ? null : _retrySessionClose,
                child: const Text('Retry session completion'),
              ),
            if (_answered && _pendingSessionClose == null)
              FilledButton(
                onPressed: actionLocked ? null : _next,
                child: Text(
                  _index == session.questions.length - 1
                      ? 'ดูผลการเรียน'
                      : 'คำถามถัดไป',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExit(BuildContext context) async {
    if (_persistenceLocked) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ออกจาก Quiz?'),
        content: const Text('ความคืบหน้าในเซสชันนี้จะไม่ถูกบันทึก'),
        actions: [
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
    if (_saving || _completionCommitted) return;
    setState(() => _saving = true);
    try {
      await _lessonLifecycle?.abandon();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ปิด session ไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Color? _answerColor(QuizQuestion question, String option) {
    if (!_answered) return null;
    if (option == question.correctAnswer) return Colors.green.shade100;
    if (option == _selected) return Colors.red.shade100;
    return null;
  }

  Future<void> _record(QuizQuestion question, String option) async {
    final session = _session;
    if (session == null || _pendingEvidence != null) return;
    _lessonLifecycle?.recordInteraction();
    final correct = option == question.correctAnswer;
    final elapsed = DateTime.now().difference(
      _questionStartedAt ?? DateTime.now(),
    );
    final pending = _evidenceAdapter!.capture(
      input: CurrentActivityInput.meaningMultipleChoice,
      sessionId: session.id,
      wordId: question.word.id,
      isCorrect: correct,
      responseTimeMs: elapsed.inMilliseconds,
      attemptNumber: _index + 1,
    );
    _pendingEvidence = pending;
    setState(() {
      _saving = true;
      _selected = option;
    });
    await _commitPending(pending, retry: false);
  }

  Future<void> _retryEvidence() async {
    final pending = _pendingEvidence;
    if (pending == null || !pending.requiresRetry || _saving) return;
    setState(() => _saving = true);
    await _commitPending(pending, retry: true);
  }

  Future<void> _commitPending(
    PendingCurrentActivityEvidence pending, {
    required bool retry,
  }) async {
    try {
      if (retry) {
        await pending.retry();
      } else {
        await pending.record();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _answered = true;
      _saving = false;
    });
    try {
      if (pending.isCorrect) {
        await HapticFeedback.lightImpact();
      } else {
        await HapticFeedback.vibrate();
      }
    } catch (_) {
      // Evidence is already durable; ornamental feedback is best-effort.
    }
  }

  Future<void> _next() async {
    if (_actionLocked) return;
    final session = _session!;
    if (_index < session.questions.length - 1) {
      setState(() {
        _index++;
        _answered = false;
        _selected = null;
        _questionStartedAt = DateTime.now();
        _pendingEvidence = null;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final pending = _pendingSessionClose ??= _learning!.captureSessionClose(
        sessionId: session.id,
      );
      final lifecycle = _lessonLifecycle;
      final summary = lifecycle == null
          ? await pending.finish()
          : await lifecycle.complete(pending);
      await _showScore(summary);
    } catch (_) {
      _showSessionCloseFailure();
    }
  }

  Future<void> _retrySessionClose() async {
    final pending = _pendingSessionClose;
    if (pending == null || _saving) return;
    setState(() => _saving = true);
    try {
      final lifecycle = _lessonLifecycle;
      final summary = lifecycle == null
          ? pending.requiresRetry
                ? await pending.retry()
                : await pending.finish()
          : await lifecycle.complete(pending);
      await _showScore(summary);
    } catch (_) {
      _showSessionCloseFailure();
    }
  }

  Future<void> _showScore(LearningSessionSummary summary) async {
    if (!mounted) return;
    setState(() {
      _pendingEvidence = null;
      _pendingSessionClose = null;
      _completionCommitted = true;
      _saving = false;
    });
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

  void _showSessionCloseFailure() {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ปิด session ไม่สำเร็จ กรุณาลองอีกครั้ง')),
    );
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
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
