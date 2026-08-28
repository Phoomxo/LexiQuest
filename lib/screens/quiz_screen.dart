import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/meaning_quiz_mode_adapter.dart';
import '../features/learning/application/typed_recall_mode_adapter.dart';
import '../features/learning/domain/answer_feedback.dart';
import '../features/learning/domain/hint_policy.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/answer_feedback_panel.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../features/learning/presentation/session_configuration_sheet.dart';
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
    this.sessionConfiguration,
  }) : typedRecallModeAdapter = null,
       typedRecall = false;

  const QuizScreen.typedRecall({
    super.key,
    this.categoryId,
    this.learning,
    this.evidenceAdapter,
    TypedRecallModeAdapter? modeAdapter,
    this.sessionConfiguration,
  }) : modeAdapter = null,
       typedRecallModeAdapter = modeAdapter,
       typedRecall = true;

  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final MeaningQuizModeAdapter? modeAdapter;
  final TypedRecallModeAdapter? typedRecallModeAdapter;
  final bool typedRecall;
  final SessionConfiguration? sessionConfiguration;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Stopwatch _responseStopwatch = Stopwatch();
  final TextEditingController _typedResponseController =
      TextEditingController();
  LearningUseCases? _learning;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  MeaningQuizModeAdapter? _modeAdapter;
  TypedRecallModeAdapter? _typedRecallAdapter;
  UnifiedLessonSessionLifecycle? _lessonLifecycle;
  SessionConfiguration? _sessionConfiguration;
  Future<QuizSession>? _load;
  QuizSession? _session;
  MeaningQuizReviewController? _meaningReview;
  TypedRecallQuizReviewController? _typedReview;
  bool _completionCommitted = false;
  bool _loadSettled = false;
  bool _abandoning = false;

  bool get _persistenceLocked =>
      _abandoning ||
      (_typedReview?.persistenceLocked ??
          _meaningReview?.persistenceLocked ??
          false);
  bool get _actionLocked =>
      _abandoning ||
      _lessonLifecycle?.acceptsOperations == false ||
      (_typedReview?.actionLocked ?? _meaningReview?.actionLocked ?? true) ||
      _completionCommitted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _lessonLifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    final lifecycleConfiguration = _lessonLifecycle?.configuration;
    if (widget.sessionConfiguration != null &&
        lifecycleConfiguration != null &&
        widget.sessionConfiguration != lifecycleConfiguration) {
      _load = Future<QuizSession>.error(
        const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        ),
      );
      return;
    }
    _sessionConfiguration =
        lifecycleConfiguration ?? widget.sessionConfiguration;
    _learning = widget.learning ?? dependencies?.learning;
    final learning = _learning;
    if (learning != null) {
      _evidenceAdapter =
          widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    }
    if (widget.typedRecall) {
      final supplied = widget.typedRecallModeAdapter;
      final registered = dependencies?.lessonModes
          ?.resolveTypedRecall()
          ?.adapter;
      _typedRecallAdapter = supplied is TypedRecallModeAdapter
          ? supplied
          : registered ??
                (dependencies == null ? const TypedRecallModeAdapter() : null);
    } else {
      final supplied = widget.modeAdapter;
      final registered = dependencies?.lessonModes
          ?.find(LessonMode.meaningQuiz)
          ?.adapter;
      _modeAdapter = supplied is MeaningQuizModeAdapter
          ? supplied
          : registered is MeaningQuizModeAdapter
          ? registered
          : dependencies == null
          ? const MeaningQuizModeAdapter()
          : null;
    }
    final rawLoad = learning == null
        ? Future<QuizSession>.error(
            StateError('local learning dependency unavailable'),
          )
        : _evidenceAdapter == null
        ? Future<QuizSession>.error(
            StateError('current activity evidence dependency unavailable'),
          )
        : !widget.typedRecall && _modeAdapter == null
        ? Future<QuizSession>.error(
            StateError('meaning quiz mode adapter dependency unavailable'),
          )
        : widget.typedRecall && _typedRecallAdapter == null
        ? Future<QuizSession>.error(
            StateError('typed recall mode adapter dependency unavailable'),
          )
        : !identical(_evidenceAdapter!.learning, learning)
        ? Future<QuizSession>.error(
            StateError('meaning quiz learning authority mismatch'),
          )
        : _loadConfiguredQuiz(learning, dependencies);
    final lifecycle = _lessonLifecycle;
    _load = _prepareSession(
      lifecycle == null ? rawLoad : lifecycle.initializeSession(rawLoad),
      dependencies?.vocabulary?.readPinnedByIds,
    );
  }

  Future<QuizSession> _loadConfiguredQuiz(
    LearningUseCases learning,
    AppDependencies? dependencies,
  ) async {
    final configuration = _sessionConfiguration;
    if (configuration == null) {
      return learning.startQuiz(categoryId: widget.categoryId);
    }
    if (configuration.mode !=
            (widget.typedRecall
                ? LessonMode.typedRecall
                : LessonMode.meaningQuiz) ||
        configuration.difficulty != SessionDifficulty.standard) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    final pack = configuration.packIdentity;
    if (pack == null) {
      return learning.startQuiz(
        categoryId: widget.categoryId,
        limit: configuration.itemCount,
        sessionConfiguration: configuration,
      );
    }
    if (widget.typedRecall || widget.categoryId != null) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    final planning = dependencies?.studyPlanning;
    if (planning == null) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.packDrift,
      );
    }
    try {
      final detail = await planning.loadPinnedVersion(pack);
      if (detail.vocabularyWordIds.length < configuration.itemCount) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.packDrift,
        );
      }
      final session = await learning.startQuiz(
        limit: configuration.itemCount,
        pinnedWordIds: detail.vocabularyWordIds,
        sessionConfiguration: configuration,
      );
      if (session.questions.length != configuration.itemCount) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.packDrift,
        );
      }
      return session;
    } on SessionConfigurationResetRequired {
      rethrow;
    } catch (_) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.packDrift,
      );
    }
  }

  Future<QuizSession> _prepareSession(
    Future<QuizSession> load,
    Future<List<VocabularyWord>> Function(Iterable<String> ids)?
    loadLexicalWords,
  ) async {
    try {
      final session = await load;
      if (!mounted) return session;
      if (!session.isEmpty) {
        final lifecycle = _lessonLifecycle;
        if (widget.typedRecall) {
          _typedReview = _typedRecallAdapter!.createQuizReview(
            session: session,
            learning: _learning!,
            evidence: _evidenceAdapter!,
            supportUsage: () => TypedRecallSupport(
              hint:
                  lifecycle?.snapshotHintUsage() ??
                  const HintUsageSnapshot.unavailable(),
            ),
            resetHintsAfterCommit: () =>
                lifecycle?.resetHintsAfterCommittedEvidence(),
            completeSession: lifecycle == null
                ? null
                : (close) => lifecycle.complete(close),
            recordInteraction: () => lifecycle?.recordInteraction(),
            acceptsOperation: () => lifecycle?.acceptsOperations ?? true,
            runEvidenceOperation: lifecycle == null
                ? null
                : (operation) => lifecycle.runAcceptedOperation(operation),
          )..addListener(_onReviewChanged);
        } else {
          final lexicalWords = loadLexicalWords == null
              ? const <VocabularyWord>[]
              : await loadLexicalWords(
                  session.questions.map((question) => question.word.id),
                );
          if (!mounted) return session;
          _meaningReview = _modeAdapter!.createReview(
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
            direction:
                _sessionConfiguration?.direction ?? SessionDirection.mixed,
            lexicalWords: lexicalWords,
          )..addListener(_onReviewChanged);
        }
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

  MeaningQuizQuestion get _currentQuestion =>
      _typedReview?.currentQuestion ?? _meaningReview!.currentQuestion;
  int get _reviewIndex => _typedReview?.index ?? _meaningReview!.index;
  int get _questionCount =>
      _typedReview?.questions.length ?? _meaningReview!.questions.length;
  MeaningQuizReviewPhase get _reviewPhase =>
      _typedReview?.phase ?? _meaningReview!.phase;
  AnswerFeedback? get _reviewFeedback =>
      _typedReview?.feedback ?? _meaningReview?.feedback;
  String? get _selectedOption =>
      _typedReview?.selectedOption ?? _meaningReview?.selectedOption;
  bool get _expectsTypedResponse => _typedReview?.expectsTypedResponse ?? false;
  bool get _isAnswered =>
      _typedReview?.isAnswered ?? _meaningReview?.isAnswered ?? false;
  bool get _isSaving =>
      _typedReview?.isSaving ?? _meaningReview?.isSaving ?? false;
  bool get _requiresRetry =>
      _typedReview?.requiresRetry ?? _meaningReview?.requiresRetry ?? false;

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
              final error = snapshot.error;
              if (error is SessionConfigurationResetRequired) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: SessionConfigurationResetPrompt(
                    error: error,
                    onReset: () => Navigator.of(context).maybePop(),
                  ),
                );
              }
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
            if (_typedReview == null && _meaningReview == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildQuestion();
          },
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final question = _currentQuestion;
    final actionLocked = _actionLocked;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: 'คำถาม ${_reviewIndex + 1} จาก $_questionCount',
              child: LinearProgressIndicator(
                value: (_reviewIndex + 1) / _questionCount,
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
            if (_expectsTypedResponse) ...<Widget>[
              TextField(
                key: const ValueKey<String>('typed-recall-input'),
                controller: _typedResponseController,
                enabled: !_isAnswered && !actionLocked,
                maxLength: TypedRecallModeAdapter.maxAnswerScalars,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  _lessonLifecycle?.recordInteraction();
                  setState(() {});
                },
                onSubmitted: (_) {
                  if (_typedResponseController.text.trim().isNotEmpty &&
                      !actionLocked) {
                    _recordTyped();
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Type the vocabulary word',
                  hintText: 'Enter the spelling from memory',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey<String>('typed-recall-submit'),
                onPressed:
                    _isAnswered ||
                        actionLocked ||
                        _typedResponseController.text.trim().isEmpty
                    ? null
                    : _recordTyped,
                child: const Text('Check answer'),
              ),
            ] else
              ...question.options.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.tonal(
                    key: ValueKey<String>(
                      'meaning-quiz-option-${question.word.id}-$option',
                    ),
                    onPressed: _isAnswered || actionLocked
                        ? null
                        : () => _recordChoice(option),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: _answerColor(option),
                    ),
                    child: Text(option),
                  ),
                ),
              ),
            if (_isSaving) const LinearProgressIndicator(),
            if (_reviewPhase == MeaningQuizReviewPhase.evidenceRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: _isSaving ? null : _retryEvidence,
                child: const Text('Retry saved answer'),
              )
            else if (_reviewPhase ==
                MeaningQuizReviewPhase.completionRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: _isSaving ? null : _retrySessionClose,
                child: const Text('Retry session completion'),
              ),
            if (_reviewFeedback case final feedback?) ...<Widget>[
              const SizedBox(height: 12),
              AnswerFeedbackPanel(feedback: feedback),
            ],
            if (_isAnswered) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey<String>('meaning-quiz-next'),
                onPressed: actionLocked ? null : _next,
                child: Text(
                  _reviewIndex == _questionCount - 1
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

  Color? _answerColor(String option) {
    if (!_isAnswered) return null;
    if (option == _currentQuestion.correctOption) {
      return Colors.green.shade100;
    }
    if (option == _selectedOption) return Colors.red.shade100;
    return null;
  }

  Future<void> _recordChoice(String option) async {
    if ((_typedReview == null && _meaningReview == null) || _actionLocked) {
      return;
    }
    try {
      final result = _typedReview != null
          ? await _typedReview!.answerChoice(
              option: option,
              responseTimeMs: _responseStopwatch.elapsedMilliseconds,
            )
          : await _meaningReview!.answer(
              option: option,
              responseTimeMs: _responseStopwatch.elapsedMilliseconds,
            );
      await _haptic(result);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _recordTyped() async {
    final review = _typedReview;
    if (review == null || _actionLocked) return;
    try {
      final result = await review.answerTyped(
        response: _typedResponseController.text,
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
      await _haptic(result);
    } catch (_) {
      _showSaveFailure();
    }
  }

  Future<void> _retryEvidence() async {
    if (!_requiresRetry || _isSaving) return;
    try {
      final result = _typedReview != null
          ? await _typedReview!.retryEvidence()
          : await _meaningReview!.retryEvidence();
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
    if ((_typedReview == null && _meaningReview == null) || _actionLocked) {
      return;
    }
    try {
      final summary = _typedReview != null
          ? await _typedReview!.advance()
          : await _meaningReview!.advance();
      if (summary != null) {
        await _showScore(summary);
        return;
      }
      _typedResponseController.clear();
      _responseStopwatch
        ..reset()
        ..start();
    } catch (_) {
      _showSessionCloseFailure();
    }
  }

  Future<void> _retrySessionClose() async {
    if (_isSaving) return;
    try {
      final summary = _typedReview != null
          ? await _typedReview!.retryCompletion()
          : await _meaningReview!.retryCompletion();
      await _showScore(summary);
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
          ownerId: session.ownerId,
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
    _typedResponseController.dispose();
    _typedReview?.removeListener(_onReviewChanged);
    _typedReview?.dispose();
    _meaningReview?.removeListener(_onReviewChanged);
    _meaningReview?.dispose();
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
