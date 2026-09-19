import 'dart:async';

import 'package:flutter/material.dart';

import '../features/accessibility/domain/accessibility_policy.dart';
import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/hint_policy.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/answer_feedback_panel.dart';
import '../features/learning/presentation/sentence_practice_panel.dart';
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
    this.sessionConfiguration,
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final ClozeModeAdapter? modeAdapter;
  final ClozeLexicalLoader? loadLexicalWords;
  final SessionConfiguration? sessionConfiguration;

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
  String? _selectedAnswer;
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

  bool get _typedAnswerReady {
    final value = _typedAnswer.value;
    return value.text.trim().isNotEmpty &&
        value.text.runes.length <= 160 &&
        !(value.composing.isValid && !value.composing.isCollapsed);
  }

  @override
  void initState() {
    super.initState();
    _typedAnswer.addListener(_typedAnswerChanged);
  }

  void _typedAnswerChanged() {
    setState(() {});
  }

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
        : learning.startQuiz(
            categoryId: widget.categoryId,
            limit: widget.sessionConfiguration?.itemCount ?? 10,
            sessionConfiguration: widget.sessionConfiguration,
          );
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
        appBar: AppBar(title: const Text('เติมคำในประโยค')),
        body: FutureBuilder<QuizSession>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _ClozeMessage(
                icon: Icons.error_outline,
                message:
                    'กิจกรรมเติมคำไม่พร้อมใช้งาน ข้อมูลการเรียนไม่เปลี่ยนแปลง',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const _ClozeMessage(
                icon: Icons.library_add_outlined,
                message: 'ยังไม่มีคำศัพท์สำหรับกิจกรรมเติมคำ',
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
              label: 'ข้อ ${review.index + 1} จาก ${review.items.length}',
              child: LinearProgressIndicator(
                value: (review.index + 1) / review.items.length,
              ),
            ),
            const SizedBox(height: 24),
            if (question == null) ...<Widget>[
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.prompt,
                child: Semantics(
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
              ),
              const SizedBox(height: 20),
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.responseAndInput,
                child: FilledButton(
                  key: const ValueKey<String>('cloze-skip'),
                  onPressed: _actionLocked ? null : _advance,
                  child: const Text('ดำเนินต่อ'),
                ),
              ),
            ] else ...<Widget>[
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.prompt,
                child: Card.filled(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: <Widget>[
                        const Icon(Icons.chat_bubble_outline, size: 32),
                        const SizedBox(height: 12),
                        const Text('เติมคำให้ประโยคสมบูรณ์'),
                        const SizedBox(height: 20),
                        Text(
                          question.prompt,
                          key: const ValueKey<String>('cloze-prompt'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.responseAndInput,
                child: _inputMode == null
                    ? Wrap(
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
                            label: const Text('เลือกคำตอบ'),
                          ),
                          FilledButton.tonalIcon(
                            key: const ValueKey<String>('cloze-mode-typed'),
                            onPressed: _actionLocked
                                ? null
                                : () => setState(
                                    () => _inputMode = ClozeInputMode.typed,
                                  ),
                            icon: const Icon(Icons.keyboard_outlined),
                            label: const Text('พิมพ์คำตอบ'),
                          ),
                        ],
                      )
                    : Semantics(
                        key: const ValueKey<String>('cloze-input-mode'),
                        label: _inputMode == ClozeInputMode.selected
                            ? 'รูปแบบคำตอบที่เลือก: เลือกคำตอบ'
                            : 'รูปแบบคำตอบที่เลือก: พิมพ์คำตอบ',
                        child: Text(
                          _inputMode == ClozeInputMode.selected
                              ? 'เลือกคำที่หายไป'
                              : 'พิมพ์คำที่หายไป',
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              if (_inputMode == ClozeInputMode.selected)
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          for (final option in question.options)
                            FilledButton.tonal(
                              key: ValueKey<String>(
                                'cloze-option-${question.wordId}-$option',
                              ),
                              onPressed: review.isAnswered || _actionLocked
                                  ? null
                                  : () => _chooseOption(option, question),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(80, 52),
                                backgroundColor: _selectedAnswer == option
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : null,
                                side: _selectedAnswer == option
                                    ? BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Semantics(
                                selected: _selectedAnswer == option,
                                child: Text(option),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedAnswer == null
                            ? 'แตะเลือกคำ แล้วกดตรวจคำตอบ'
                            : 'คำที่เลือก: $_selectedAnswer',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey<String>('cloze-submit-selected'),
                        onPressed:
                            review.isAnswered ||
                                _actionLocked ||
                                _selectedAnswer == null
                            ? null
                            : () => _confirmSelected(question),
                        child: const Text('ตรวจคำตอบ'),
                      ),
                    ],
                  ),
                )
              else if (_inputMode == ClozeInputMode.typed)
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        key: const ValueKey<String>('cloze-typed-answer'),
                        controller: _typedAnswer,
                        enabled: !review.isAnswered && !_actionLocked,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'พิมพ์คำที่หายไป',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _recordTyped(),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        key: const ValueKey<String>('cloze-submit-typed'),
                        onPressed:
                            review.isAnswered ||
                                _actionLocked ||
                                !_typedAnswerReady
                            ? null
                            : _recordTyped,
                        child: const Text('ตรวจคำตอบ'),
                      ),
                    ],
                  ),
                ),
              if (review.isSaving) const LinearProgressIndicator(),
              if (review.phase == ClozeReviewPhase.evidenceRetryRequired)
                FilledButton(
                  key: const ValueKey<String>('current-evidence-retry'),
                  onPressed: review.isSaving ? null : _retryEvidence,
                  child: const Text('ลองบันทึกคำตอบเดิมอีกครั้ง'),
                ),

              if (review.feedback case final feedback?) ...<Widget>[
                const SizedBox(height: 12),
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.feedback,
                  child: AnswerFeedbackPanel(feedback: feedback),
                ),
              ],
              if (review.isAnswered) ...<Widget>[
                const SizedBox(height: 20),
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.feedback,
                  child: SentencePracticePanel(
                    key: ValueKey<String>(
                      'sentence-${question.contentRevision}',
                    ),
                    identity:
                        '${_session!.ownerId}/${_session!.id}/${question.wordId}/${question.contentRevision}',
                    text: question.completeSentence,
                    canInteract: () =>
                        mounted &&
                        identical(_review?.currentItem.question, question) &&
                        _review?.isAnswered == true &&
                        !_actionLocked,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey<String>('cloze-next'),
                  onPressed: _actionLocked ? null : _advance,
                  child: Text(
                    review.index == review.items.length - 1
                        ? 'ดูผลการเรียน'
                        : 'ข้อถัดไป',
                  ),
                ),
              ],
            ],
            if (review.phase == ClozeReviewPhase.completionRetryRequired)
              FilledButton(
                key: const ValueKey<String>('current-evidence-retry'),
                onPressed: review.isSaving ? null : _retryCompletion,
                child: const Text('ลองจบกิจกรรมอีกครั้ง'),
              ),
          ],
        ),
      ),
    );
  }

  void _chooseOption(String option, ClozeQuestion question) {
    if (!mounted ||
        _actionLocked ||
        _review?.isAnswered == true ||
        !identical(_review?.currentItem.question, question)) {
      return;
    }
    setState(() => _selectedAnswer = option);
  }

  Future<void> _confirmSelected(ClozeQuestion question) async {
    if (!mounted ||
        _actionLocked ||
        _review?.isAnswered == true ||
        !identical(_review?.currentItem.question, question)) {
      return;
    }
    final option = _selectedAnswer;
    if (option != null) await _recordSelected(option);
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
      _showFailure('ยังยืนยันการบันทึกคำตอบไม่ได้ กรุณาลองบันทึกอีกครั้ง');
    }
  }

  Future<void> _recordTyped() async {
    final review = _review;
    if (review == null || _actionLocked || !_typedAnswerReady) return;
    try {
      await review.answerTyped(
        text: _typedAnswer.text,
        responseTimeMs: _responseStopwatch.elapsedMilliseconds,
      );
    } on Object {
      _showFailure('ยังยืนยันการบันทึกคำตอบไม่ได้ กรุณาลองบันทึกอีกครั้ง');
    }
  }

  Future<void> _retryEvidence() async {
    final review = _review;
    if (review == null || !review.requiresRetry || review.isSaving) return;
    try {
      await review.retryEvidence();
    } on Object {
      _showFailure('ยังยืนยันการบันทึกคำตอบไม่ได้ กรุณาลองบันทึกอีกครั้ง');
    }
  }

  Future<void> _advance() async {
    final review = _review;
    if (review == null || _actionLocked) return;
    try {
      if (review.isSkipped) _lifecycle?.noteSkippedItem();
      final summary = await review.advance();
      if (summary != null) {
        await _showScore(summary);
        return;
      }
      _typedAnswer.clear();
      _inputMode = null;
      _selectedAnswer = null;
      _responseStopwatch
        ..reset()
        ..start();
    } on Object {
      _showFailure('ยังจบกิจกรรมไม่ได้ กรุณาลองอีกครั้ง');
    }
  }

  Future<void> _retryCompletion() async {
    final review = _review;
    if (review == null || review.isSaving) return;
    try {
      await _showScore(await review.retryCompletion());
    } on Object {
      _showFailure('ยังจบกิจกรรมไม่ได้ กรุณาลองอีกครั้ง');
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
        title: const Text('ออกจากกิจกรรมเติมคำหรือไม่'),
        content: const Text('ระบบจะดำเนินการจบกิจกรรมที่กำลังเรียนอยู่'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('เรียนต่อ'),
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
    _responseStopwatch.stop();
    _typedAnswer.removeListener(_typedAnswerChanged);
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
