import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/hint_policy.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/answer_feedback_panel.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import 'score_screen.dart';

typedef ClozeLexicalLoader =
    Future<List<VocabularyWord>> Function(Iterable<String> wordIds);

/// Presents typed cloze state without owning scoring or evidence policy.
class FillInTheBlanksScreen extends StatefulWidget {
  const FillInTheBlanksScreen({
    super.key,
    this.categoryId,
    this.learning,
    this.evidenceAdapter,
    this.modeAdapter,
    this.loadLexicalWords,
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final ClozeModeAdapter? modeAdapter;
  final ClozeLexicalLoader? loadLexicalWords;

  @override
  State<FillInTheBlanksScreen> createState() => _FillInTheBlanksScreenState();
}

class _FillInTheBlanksScreenState extends State<FillInTheBlanksScreen> {
  final Stopwatch _responseStopwatch = Stopwatch();
  final TextEditingController _typedAnswer = TextEditingController();
  LearningUseCases? _learning;
  CurrentActivityEvidenceAdapter? _evidence;
  ClozeModeAdapter? _adapter;
  UnifiedLessonSessionLifecycle? _lifecycle;
  Future<QuizSession>? _load;
  QuizSession? _session;
  ClozeReviewController? _review;
  ClozeInputMode? _inputMode;
  bool _loadSettled = false;
  bool _completionCommitted = false;
  bool _abandoning = false;

  bool get _persistenceLocked =>
      _abandoning || (_review?.persistenceLocked ?? false);
  bool get _actionLocked =>
      _abandoning ||
      _lifecycle?.acceptsOperations == false ||
      (_review?.actionLocked ?? true) ||
      _completionCommitted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    _learning = widget.learning ?? dependencies?.learning;
    final learning = _learning;
    if (learning != null) {
      _evidence =
          widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    }
    final registered = dependencies?.lessonModes
        ?.find(LessonMode.cloze)
        ?.adapter;
    _adapter =
        widget.modeAdapter ??
        (registered is ClozeModeAdapter
            ? registered
            : dependencies == null
            ? const ClozeModeAdapter()
            : null);
    final loader =
        widget.loadLexicalWords ?? dependencies?.vocabulary?.readPinnedByIds;
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
            StateError('cloze mode adapter dependency unavailable'),
          )
        : loader == null
        ? Future<QuizSession>.error(
            StateError('reviewed lexical metadata dependency unavailable'),
          )
        : !identical(_evidence!.learning, learning)
        ? Future<QuizSession>.error(
            StateError('cloze learning authority mismatch'),
          )
        : learning.startQuiz(categoryId: widget.categoryId);
    final lifecycle = _lifecycle;
    _load = _prepareSession(
      lifecycle == null ? rawLoad : lifecycle.initializeSession(rawLoad),
      loader,
    );
  }

  Future<QuizSession> _prepareSession(
    Future<QuizSession> load,
    ClozeLexicalLoader? loader,
  ) async {
    QuizSession? session;
    try {
      session = await load;
      if (!mounted || session.isEmpty) return session;
      final words = await loader!(
        session.questions.map((question) => question.word.id),
      );
      if (!mounted) return session;
      final lifecycle = _lifecycle;
      if (lifecycle?.acceptsOperations == false) return session;
      _review = _adapter!.createReview(
        session: session,
        lexicalWords: words,
        learning: _learning!,
        evidence: _evidence!,
        hintUsage: () =>
            lifecycle?.snapshotHintUsage() ??
            const HintUsageSnapshot.unavailable(),
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
      _responseStopwatch
        ..reset()
        ..start();
      if (mounted) setState(() => _session = session);
      return session;
    } catch (_) {
      if (session != null && !session.isEmpty) {
        final lifecycle = _lifecycle;
        if (lifecycle != null) {
          await lifecycle.abandon();
        } else {
          await _learning!.abandonSession(
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
      child: Scaffold(
        appBar: AppBar(title: const Text('Cloze Test')),
        body: FutureBuilder<QuizSession>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _ClozeMessage(
                icon: Icons.error_outline,
                message: 'Cloze Test is unavailable. No learning data changed.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const _ClozeMessage(
                icon: Icons.library_add_outlined,
                message: 'No vocabulary is available for Cloze Test.',
              );
            }
            final review = _review;
            if (review == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildItem(review);
          },
        ),
      ),
    );
  }

  Widget _buildItem(ClozeReviewController review) {
    final item = review.currentItem;
    final question = item.question;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              label: 'Question ${review.index + 1} of ${review.items.length}',
              child: LinearProgressIndicator(
                value: (review.index + 1) / review.items.length,
              ),
            ),
            const SizedBox(height: 24),
            if (question == null) ...<Widget>[
              Semantics(
                container: true,
                liveRegion: true,
                excludeSemantics: true,
                label: item.semanticAnnouncement,
                child: Text(
                  item.semanticAnnouncement,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey<String>('cloze-skip'),
                onPressed: _actionLocked ? null : _advance,
                child: const Text('Continue'),
              ),
            ] else ...<Widget>[
              Text(
                question.prompt,
                key: const ValueKey<String>('cloze-prompt'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              if (_inputMode == null)
                Wrap(
                  key: const ValueKey<String>('cloze-input-mode'),
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>('cloze-mode-selected'),
                      onPressed: _actionLocked
                          ? null
                          : () => setState(
                              () => _inputMode = ClozeInputMode.selected,
                            ),
                      icon: const Icon(Icons.touch_app_outlined),
                      label: const Text('Choose'),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>('cloze-mode-typed'),
                      onPressed: _actionLocked
                          ? null
                          : () => setState(
                              () => _inputMode = ClozeInputMode.typed,
                            ),
                      icon: const Icon(Icons.keyboard_outlined),
                      label: const Text('Type'),
                    ),
                  ],
                )
              else
                Semantics(
                  key: const ValueKey<String>('cloze-input-mode'),
                  label: _inputMode == ClozeInputMode.selected
                      ? 'Selected response mode: Choose'
                      : 'Selected response mode: Type',
                  child: Text(
                    _inputMode == ClozeInputMode.selected
                        ? 'Choose the missing word'
                        : 'Type the missing word',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              if (_inputMode == ClozeInputMode.selected)
                for (final option in question.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.tonal(
                      key: ValueKey<String>(
                        'cloze-option-${question.wordId}-$option',
                      ),
                      onPressed: review.isAnswered || _actionLocked
                          ? null
                          : () => _recordSelected(option),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(option),
                    ),
                  )
              else if (_inputMode == ClozeInputMode.typed) ...<Widget>[
                TextField(
                  key: const ValueKey<String>('cloze-typed-answer'),
                  controller: _typedAnswer,
                  enabled: !review.isAnswered && !_actionLocked,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Type the missing word',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _recordTyped(),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  key: const ValueKey<String>('cloze-submit-typed'),
                  onPressed: review.isAnswered || _actionLocked
                      ? null
                      : _recordTyped,
                  child: const Text('Check answer'),
                ),
              ],
              if (review.isSaving) const LinearProgressIndicator(),
              if (review.phase == ClozeReviewPhase.evidenceRetryRequired)
                FilledButton(
                  key: const ValueKey<String>('current-evidence-retry'),
                  onPressed: review.isSaving ? null : _retryEvidence,
                  child: const Text('Retry saved answer'),
                )
              else if (review.phase == ClozeReviewPhase.completionRetryRequired)
                FilledButton(
                  key: const ValueKey<String>('current-evidence-retry'),
                  onPressed: review.isSaving ? null : _retryCompletion,
                  child: const Text('Retry session completion'),
                ),
              if (review.feedback case final feedback?) ...<Widget>[
                const SizedBox(height: 12),
                AnswerFeedbackPanel(feedback: feedback),
              ],
              if (review.isAnswered) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey<String>('cloze-next'),
                  onPressed: _actionLocked ? null : _advance,
                  child: Text(
                    review.index == review.items.length - 1
                        ? 'View results'
                        : 'Next question',
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _recordSelected(String option) async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      await review.answerSelected(
        option: option,
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
    } on Object {
      _showFailure('Could not save the answer. Please retry.');
    }
  }

  Future<void> _recordTyped() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      await review.answerTyped(
        text: _typedAnswer.text,
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
    } on Object {
      _showFailure('Could not save the answer. Please retry.');
    }
  }

  Future<void> _retryEvidence() async {
    final review = _review;
    if (review == null || !review.requiresRetry || review.isSaving) return;
    try {
      await review.retryEvidence();
    } on Object {
      _showFailure('Could not save the answer. Please retry.');
    }
  }

  Future<void> _advance() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      final summary = await review.advance();
      if (summary != null) {
        await _showScore(summary);
        return;
      }
      _typedAnswer.clear();
      _inputMode = null;
      _responseStopwatch
        ..reset()
        ..start();
    } on Object {
      _showFailure('Could not close the session. Please retry.');
    }
  }

  Future<void> _retryCompletion() async {
    final review = _review;
    if (review == null || review.isSaving) return;
    try {
      await _showScore(await review.retryCompletion());
    } on Object {
      _showFailure('Could not close the session. Please retry.');
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

  Future<void> _confirmExit() async {
    if (_persistenceLocked) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave Cloze Test?'),
        content: const Text('The active session will be closed safely.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep learning'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
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
    try {
      final lifecycle = _lifecycle;
      if (lifecycle != null) {
        await lifecycle.abandon();
      } else {
        await _learning!.abandonSession(
          sessionId: session.id,
          abandonedAtUtc: DateTime.now().toUtc(),
        );
      }
    } on Object {
      if (!mounted) return;
      setState(() => _abandoning = false);
      _showFailure('Could not close the session. Please retry.');
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
    _responseStopwatch.stop();
    _typedAnswer.dispose();
    _review?.removeListener(_onReviewChanged);
    _review?.dispose();
    super.dispose();
  }
}

final class _ClozeMessage extends StatelessWidget {
  const _ClozeMessage({required this.icon, required this.message});

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
