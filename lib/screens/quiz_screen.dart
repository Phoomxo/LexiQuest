import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/m3_theme.dart';
import '../features/account_deletion/domain/account_deletion_contracts.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/accepted_quiz_plan.dart';
import '../features/learning/domain/learning_models.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import 'score_screen.dart';
import '../navigation/app_routes.dart';

enum QuizWordSelectionMode { weakness, sourcePractice }

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    this.categoryId,
    this.learning,
    this.wordIds,
    this.selectionMode = QuizWordSelectionMode.weakness,
    this.resumeSessionId,
    this.expectedOwnerId,
    this.ownerChanges,
    this.onCanonicalFinished,
    this.onScoreRouteChanged,
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final List<String>? wordIds;
  final QuizWordSelectionMode selectionMode;
  final String? resumeSessionId;
  final String? expectedOwnerId;
  final Stream<String?>? ownerChanges;
  final Future<void> Function(ConfiguredQuizFinishResult result)?
  onCanonicalFinished;
  final void Function(Route<dynamic>? route, bool current)? onScoreRouteChanged;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _QuizOperation { hint, answer, advance, finish }

typedef _AnswerIntent = ({
  int revision,
  int? optionOrdinal,
  bool reveal,
  int? latencyMs,
});

bool _ownerChangedFailure(Object? error) =>
    (error is ConfiguredQuizUnavailable &&
        error.reason == ConfiguredQuizUnavailableReason.ownerChanged) ||
    (error is AccountDeletionException &&
        error.code == AccountDeletionFailureCode.ownerChanged);

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  LearningUseCases? _learning;
  Future<ConfiguredQuizLaunch>? _launch;
  String? _acceptedSessionId;
  String? _boundOwnerId;
  Future<ConfiguredQuizState?>? _load;
  ConfiguredQuizState? _quiz;
  StreamSubscription<String?>? _ownerSubscription;
  Object? _ownerSource;
  final _ownerToken = ValueNotifier<String?>(null);
  ConfiguredQuizUnavailable? _unavailable;
  bool _ownerKnown = false;
  ModalRoute<dynamic>? _route;
  bool _foreground = true;
  bool _visible = false;
  int _generation = 0;
  int _binding = 0;
  bool _saving = false;
  _QuizOperation? _failedOperation;
  Future<void> Function()? _retryAction;
  _AnswerIntent? _answerIntent;
  Stopwatch? _questionClock;
  ConfiguredQuizFinishResult? _finished;
  bool _finishDelivered = false;
  bool _scoreOpen = false;
  bool _practicingMistakes = false;

  int get _index => _quiz!.checkpoint.questionOrdinal;
  bool get _answered => _quiz!.checkpoint is AnsweredQuizQuestion;
  bool get _hintVisible => _quiz!.checkpoint.assistance.hintVisible;
  bool get _pendingAnswer =>
      _quiz!.checkpoint is PendingQuizAnswer ||
      _failedOperation == _QuizOperation.answer;
  bool get _blocked => _saving || _retryAction != null || _pendingAnswer;
  bool get _revealed =>
      _quiz?.checkpoint.answer?.revealed ?? _answerIntent?.reveal ?? false;
  String? get _selected {
    final ordinal =
        _quiz?.checkpoint.answer?.selectedOptionOrdinal ??
        _answerIntent?.optionOrdinal;
    return ordinal == null
        ? null
        : _quiz!.plan.questions[_index].options[ordinal];
  }

  bool get _ownerCurrent =>
      !_ownerKnown ||
      _boundOwnerId == null ||
      _ownerToken.value == _boundOwnerId;

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _visible &&
      _foreground &&
      (_route?.isCurrent ?? true) &&
      _ownerCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    _acceptedSessionId = widget.resumeSessionId;
    _boundOwnerId = widget.expectedOwnerId;
  }

  @override
  void didUpdateWidget(covariant QuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.learning != widget.learning ||
        oldWidget.categoryId != widget.categoryId ||
        !listEquals(oldWidget.wordIds, widget.wordIds) ||
        oldWidget.selectionMode != widget.selectionMode ||
        oldWidget.resumeSessionId != widget.resumeSessionId ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId) {
      _binding++;
      _generation++;
      _launch = null;
      _acceptedSessionId = widget.resumeSessionId;
      _boundOwnerId = widget.expectedOwnerId;
      _quiz = null;
      _load = null;
      _finished = null;
      _unavailable = null;
      _finishDelivered = false;
      _scoreOpen = false;
      _clearPendingUi();
    }
    _configure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  void _configure() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final learning = widget.learning ?? dependencies?.learning;
    if (!identical(_learning, learning)) {
      _binding++;
      _generation++;
      _learning = learning;
      _load = null;
      _launch = null;
      _acceptedSessionId = widget.resumeSessionId;
      _boundOwnerId = widget.expectedOwnerId;
      _quiz = null;
      _finished = null;
      _unavailable = null;
      _finishDelivered = false;
      _scoreOpen = false;
      _clearPendingUi();
    }
    final ownerSource = widget.ownerChanges ?? dependencies?.progress;
    if (!identical(_ownerSource, ownerSource)) {
      _ownerSource = ownerSource;
      _ownerKnown = false;
      unawaited(_ownerSubscription?.cancel());
      _ownerSubscription =
          (widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId())
              ?.listen(
                (owner) {
                  if (identical(_ownerSource, ownerSource)) {
                    _ownerChanged(owner);
                  }
                },
                onError: (Object _) {
                  if (identical(_ownerSource, ownerSource)) _ownerChanged(null);
                },
              );
    }
    _route = ModalRoute.of(context);
    _updateVisibility();
    if (_visible && _load == null) {
      _load = _open(_generation, _binding);
    }
  }

  void _ownerChanged(String? owner) {
    if (!mounted) return;
    _ownerToken.value = owner;
    _ownerKnown = true;
    if (!_ownerCurrent) {
      _generation++;
      setState(() {
        _quiz = null;
        _finished = null;
        _clearPendingUi();
        _load = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(_updateVisibility);
  }

  void _updateVisibility() {
    final visible = _foreground && (_route?.isCurrent ?? true);
    if (_visible == visible) return;
    _visible = visible;
    _generation++;
    _quiz = null;
    _load = null;
    _clearPendingUi();
    if (_visible) _load = _open(_generation, _binding);
  }

  void _clearPendingUi() {
    _saving = false;
    _retryAction = null;
    _failedOperation = null;
    _answerIntent = null;
    _questionClock?.stop();
    _questionClock = null;
  }

  Future<ConfiguredQuizState?> _open(int generation, int binding) async {
    final learning = _learning;
    if (learning == null) {
      throw StateError('local learning dependency unavailable');
    }
    if (widget.resumeSessionId != null &&
        (widget.expectedOwnerId == null ||
            widget.expectedOwnerId!.trim().isEmpty)) {
      throw ArgumentError('exact quiz resume requires its expected owner');
    }
    ConfiguredQuizState saved;
    final sessionId = _acceptedSessionId;
    if (sessionId != null) {
      saved = await learning.resumeQuiz(
        sessionId: sessionId,
        expectedOwnerId: _boundOwnerId!,
      );
    } else {
      if (widget.wordIds?.isEmpty ?? false) return null;
      final configuration = widget.wordIds == null
          ? QuizConfiguration.category(categoryId: widget.categoryId)
          : widget.selectionMode == QuizWordSelectionMode.sourcePractice
          ? QuizConfiguration.sourcePractice(wordIds: widget.wordIds!)
          : QuizConfiguration.weaknessPractice(wordIds: widget.wordIds!);
      final launchFuture = _launch ??= learning.prepareConfiguredQuiz(
        configuration: configuration,
        expectedOwnerId: widget.expectedOwnerId,
      );
      final ConfiguredQuizLaunch launch;
      try {
        launch = await launchFuture;
      } on Object {
        if (binding == _binding && identical(_launch, launchFuture)) {
          _launch = null;
        }
        rethrow;
      }
      if (!_current(generation) || binding != _binding) {
        throw StateError('quiz route no longer current');
      }
      _boundOwnerId = launch.session.ownerId;
      try {
        saved = await learning.startConfiguredQuiz(launch);
      } on ConfiguredQuizUnavailable catch (error) {
        if (error.reason != ConfiguredQuizUnavailableReason.emptySelection) {
          rethrow;
        }
        return null;
      }
    }
    if (binding == _binding) {
      _acceptedSessionId = saved.sessionId;
      _boundOwnerId = saved.ownerId;
      if (!_ownerKnown) _ownerToken.value = saved.ownerId;
    }
    if (_current(generation) && binding == _binding) {
      setState(() {
        _quiz = saved;
        if (!saved.restored && saved.checkpoint is AwaitingQuizAnswer) {
          _questionClock = Stopwatch()..start();
        }
      });
    }
    return saved;
  }

  @override
  void dispose() {
    _generation++;
    _binding++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ownerSubscription?.cancel());
    _questionClock?.stop();
    _ownerToken.dispose();
    super.dispose();
  }

  void _retryLoad() {
    _generation++;
    setState(() {
      _quiz = null;
      _clearPendingUi();
      _load = _open(_generation, _binding);
    });
  }

  @override
  Widget build(BuildContext context) {
    final usesAdaptiveTitle =
        _title.runes.length > 18 ||
        MediaQuery.textScalerOf(context).scale(1) >= 2;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: usesAdaptiveTitle
            ? M3Theme.appBarToolbarHeight(context)
            : null,
        title: usesAdaptiveTitle
            ? M3Theme.appBarTitle(context, _title)
            : Text(_title),
      ),
      body: AdaptiveContentPane(
        child: !_visible
            ? const SizedBox.shrink()
            : !_ownerCurrent || _unavailable != null
            ? _QuizMessage(
                icon: Icons.error_outline,
                message:
                    !_ownerCurrent ||
                        _unavailable?.reason ==
                            ConfiguredQuizUnavailableReason.ownerChanged
                    ? 'บัญชีเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'
                    : 'ไม่สามารถเล่นรอบเดิมต่อได้ กรุณากลับไปเลือกกิจกรรม',
                liveRegion: true,
                actionLabel: 'กลับไปเลือกกิจกรรม',
                onAction: () => Navigator.maybePop(context),
              )
            : FutureBuilder<ConfiguredQuizState?>(
                future: _load,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    final ownerChanged = _ownerChangedFailure(error);
                    return _QuizMessage(
                      icon: Icons.error_outline,
                      message: ownerChanged
                          ? 'บัญชีเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'
                          : 'เปิดแบบทดสอบไม่สำเร็จ กรุณาลองอีกครั้งหรือกลับไปเลือกกิจกรรม',
                      liveRegion: true,
                      actionLabel: 'กลับไปเลือกกิจกรรม',
                      onAction: () => Navigator.maybePop(context),
                      onRetry: ownerChanged ? null : _retryLoad,
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'กำลังเตรียมแบบทดสอบ',
                      ),
                    );
                  }
                  if (snapshot.data == null) {
                    return const _QuizMessage(
                      icon: Icons.library_add_outlined,
                      message:
                          'ยังไม่มีคำศัพท์สำหรับแบบทดสอบ กรุณาเพิ่มคำศัพท์ก่อน',
                    );
                  }
                  final quiz = _quiz;
                  if (quiz == null || !_ownerCurrent) {
                    return const SizedBox.shrink();
                  }
                  final checkpoint = quiz.checkpoint;
                  if (checkpoint is AbandonedQuizSession) {
                    return _QuizMessage(
                      icon: Icons.history,
                      message: 'รอบการฝึกนี้จบแล้ว กรุณาเลือกกิจกรรมใหม่',
                      actionLabel: 'กลับไปเลือกกิจกรรม',
                      onAction: () => Navigator.maybePop(context),
                    );
                  }
                  if (checkpoint is ClosingQuizSession ||
                      checkpoint is CompletedQuizSession) {
                    return _QuizMessage(
                      icon: Icons.check_circle_outline,
                      message: checkpoint is CompletedQuizSession
                          ? 'บันทึกผลรอบนี้แล้ว'
                          : 'คำตอบครบแล้ว พร้อมบันทึกผลรอบนี้',
                      liveRegion: true,
                      actionLabel: _saving || _scoreOpen
                          ? null
                          : 'ดูผลการเรียน',
                      onAction: _saving || _scoreOpen ? null : _next,
                    );
                  }
                  return _buildQuestion(quiz.asQuizSession);
                },
              ),
      ),
    );
  }

  String get _title {
    final activity = _quiz?.activityType;
    if (activity == 'sourcePractice' ||
        (activity == null &&
            widget.wordIds != null &&
            widget.selectionMode == QuizWordSelectionMode.sourcePractice)) {
      return 'แบบทดสอบจากเนื้อหานี้';
    }
    if (activity == 'weaknessPractice' ||
        (activity == null && widget.wordIds != null)) {
      return 'ฝึกคำที่ผิด';
    }
    return 'แบบทดสอบคำศัพท์';
  }

  Widget _buildQuestion(QuizSession session) {
    final question = session.questions[_index];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'คำถาม ${_index + 1} จาก ${session.questions.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'คำถาม ${_index + 1} จาก ${session.questions.length}',
              child: LinearProgressIndicator(
                value: (_index + 1) / session.questions.length,
              ),
            ),
            const SizedBox(height: 24),
            const Text('เลือกคำแปลที่ตรงกับคำศัพท์'),
            const SizedBox(height: 12),
            Text(
              question.word.spelling,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            if (_hintVisible || _answered)
              Text(
                question.word.partOfSpeech,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (!_answered) ...[
              if (question.word.partOfSpeech.isNotEmpty)
                TextButton(
                  onPressed: _blocked ? null : _toggleHint,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(_hintVisible ? 'ซ่อนคำใบ้' : 'ดูคำใบ้'),
                ),
              TextButton(
                onPressed: _blocked
                    ? null
                    : () => _record(question, null, reveal: true),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('เฉลยคำตอบ'),
              ),
            ],
            const SizedBox(height: 24),
            ...question.options.map((option) {
              final feedbackColors = _answerColors(question, option);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.tonal(
                  onPressed: _answered || _blocked
                      ? null
                      : () => _record(question, option),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: feedbackColors?.background,
                    foregroundColor: feedbackColors?.foreground,
                  ),
                  child: Text(option),
                ),
              );
            }),
            const SizedBox(height: 16),
            if (_saving)
              const LinearProgressIndicator(semanticsLabel: 'กำลังบันทึกคำตอบ'),
            if (!_answered && !_saving && _pendingAnswer)
              FilledButton.icon(
                onPressed: () =>
                    _record(question, _selected, reveal: _revealed),
                icon: const Icon(Icons.refresh),
                label: const Text('ลองบันทึกอีกครั้ง'),
              ),
            if (_answered) ...[
              Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _selected == question.correctAnswer
                          ? 'ถูกต้อง'
                          : 'ยังไม่ถูก ลองดูคำแปลอีกครั้ง',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'คำตอบของคุณ: ${_revealed ? 'ไม่ได้ตอบ (ขอเฉลย)' : _selected}',
                    ),
                    Text(
                      '${question.word.spelling} — ${question.correctAnswer}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!_saving &&
                _retryAction != null &&
                _failedOperation != _QuizOperation.answer)
              OutlinedButton.icon(
                onPressed: _retryAction,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองบันทึกอีกครั้ง'),
              ),
            if (_answered)
              FilledButton(
                onPressed: _blocked ? null : _next,
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

  ({Color background, Color foreground})? _answerColors(
    QuizQuestion question,
    String option,
  ) {
    if (!_answered) return null;
    final colors = Theme.of(context).colorScheme;
    if (option == question.correctAnswer) {
      if (colors.brightness == Brightness.light) {
        return (
          background: Colors.green.shade100,
          foreground: colors.onSecondaryContainer,
        );
      }
      return (
        background: colors.tertiaryContainer,
        foreground: colors.onTertiaryContainer,
      );
    }
    if (option == _selected) {
      if (colors.brightness == Brightness.light) {
        return (
          background: Colors.red.shade100,
          foreground: colors.onSecondaryContainer,
        );
      }
      return (
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
      );
    }
    return null;
  }

  bool _apply(
    ConfiguredQuizState saved,
    int generation, {
    bool freshQuestion = false,
  }) {
    if (!_current(generation)) return false;
    setState(() {
      _quiz = saved;
      _answerIntent = null;
      _retryAction = null;
      _failedOperation = null;
      if (freshQuestion) {
        _questionClock?.stop();
        _questionClock = Stopwatch()..start();
      }
    });
    return true;
  }

  Future<void> _run(
    _QuizOperation operation,
    Future<void> Function(int generation) action,
  ) async {
    if (_saving || !_current(_generation)) return;
    final generation = _generation;
    setState(() => _saving = true);
    try {
      await action(generation);
    } on ConfiguredQuizUnavailable catch (error) {
      if (_current(generation)) {
        setState(() {
          _quiz = null;
          _unavailable = error;
          _clearPendingUi();
        });
        if (error.reason == ConfiguredQuizUnavailableReason.ownerChanged) {
          _ownerKnown = true;
          _ownerToken.value = null;
        }
      }
    } on Object catch (error) {
      if (mounted && _current(generation)) {
        if (_ownerChangedFailure(error)) {
          _ownerKnown = true;
          _ownerToken.value = null;
          setState(() {
            _quiz = null;
            _finished = null;
            _clearPendingUi();
          });
          return;
        }
        setState(() {
          _failedOperation = operation;
          _retryAction = () => _run(operation, action);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              operation == _QuizOperation.finish
                  ? 'จบรอบการฝึกไม่สำเร็จ กรุณาลองอีกครั้ง'
                  : operation == _QuizOperation.hint
                  ? 'บันทึกคำใบ้ไม่สำเร็จ กรุณาลองอีกครั้ง'
                  : operation == _QuizOperation.advance
                  ? 'เปิดคำถามถัดไปไม่สำเร็จ กรุณาลองอีกครั้ง'
                  : 'บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง',
            ),
          ),
        );
      }
    } finally {
      if (_current(generation)) setState(() => _saving = false);
    }
  }

  Future<void> _toggleHint() async {
    final quiz = _quiz;
    if (quiz == null || _blocked || quiz.checkpoint is! AwaitingQuizAnswer) {
      return;
    }
    final visible = !quiz.checkpoint.assistance.hintVisible;
    await _run(_QuizOperation.hint, (generation) async {
      final saved = await _learning!.setQuizHint(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
        visible: visible,
      );
      _apply(saved, generation);
    });
  }

  Future<void> _record(
    QuizQuestion question,
    String? option, {
    bool reveal = false,
  }) async {
    if (_saving || _answered) return;
    final retry = _retryAction;
    if (retry != null) {
      if (_failedOperation == _QuizOperation.answer) await retry();
      return;
    }
    final quiz = _quiz!;
    if (quiz.checkpoint is PendingQuizAnswer) {
      await _run(
        _QuizOperation.answer,
        (generation) => _commitAnswer(quiz, generation),
      );
      return;
    }
    if (quiz.checkpoint is! AwaitingQuizAnswer) return;
    final ordinal = option == null ? null : question.options.indexOf(option);
    if (!reveal && (ordinal == null || ordinal < 0)) return;
    final intent = (
      revision: quiz.checkpointRevision,
      optionOrdinal: ordinal,
      reveal: reveal,
      latencyMs: _questionClock?.elapsedMilliseconds,
    );
    _answerIntent = intent;
    await _run(_QuizOperation.answer, (generation) async {
      final prepared = await _learning!.prepareQuizAnswer(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: intent.revision,
        selectedOptionOrdinal: intent.optionOrdinal,
        revealed: intent.reveal,
        responseTimeMs: intent.latencyMs,
      );
      if (!_apply(prepared, generation)) return;
      if (prepared.checkpoint is PendingQuizAnswer ||
          prepared.checkpoint is AnsweredQuizQuestion) {
        await _commitAnswer(prepared, generation);
      }
    });
  }

  Future<void> _commitAnswer(ConfiguredQuizState quiz, int generation) async {
    final result = await _learning!.commitQuizAnswer(
      sessionId: quiz.sessionId,
      expectedOwnerId: quiz.ownerId,
      expectedRevision: quiz.checkpointRevision,
    );
    if (!_apply(result.state, generation) || !result.record.inserted) return;
    unawaited(_answerFeedback(result.state.checkpoint.answer!.isCorrect));
  }

  Future<void> _answerFeedback(bool correct) async {
    try {
      if (correct) {
        await HapticFeedback.lightImpact();
      } else {
        await HapticFeedback.vibrate();
      }
    } on Object {
      // Device feedback cannot turn a committed answer into a retry.
    }
  }

  Future<void> _next() async {
    if (_saving || _scoreOpen) return;
    final retry = _retryAction;
    if (retry != null) {
      await retry();
      return;
    }
    final finished = _finished;
    if (finished != null) {
      await _showScore(finished);
      return;
    }
    final quiz = _quiz!;
    final checkpoint = quiz.checkpoint;
    if (checkpoint is AnsweredQuizQuestion &&
        checkpoint.questionOrdinal < quiz.plan.questions.length - 1) {
      await _run(_QuizOperation.advance, (generation) async {
        final next = await _learning!.advanceQuiz(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
        );
        _apply(next, generation, freshQuestion: true);
      });
      return;
    }
    await _run(_QuizOperation.finish, (generation) async {
      var closing = quiz;
      if (closing.checkpoint is AnsweredQuizQuestion) {
        closing = await _learning!.prepareQuizFinish(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
        );
        if (!_apply(closing, generation)) return;
      }
      if (closing.checkpoint is! ClosingQuizSession &&
          closing.checkpoint is! CompletedQuizSession) {
        throw StateError('quiz has not reached its final answer');
      }
      final result = await _learning!.finishConfiguredQuiz(
        sessionId: closing.sessionId,
        expectedOwnerId: closing.ownerId,
        expectedRevision: closing.checkpointRevision,
      );
      if (!_apply(result.state, generation)) return;
      _finished = result;
      await _showScore(result);
    });
  }

  Future<void> _showScore(ConfiguredQuizFinishResult result) async {
    if (_scoreOpen || !_current(_generation)) return;
    final binding = _binding;
    setState(() => _scoreOpen = true);
    if (!_finishDelivered) {
      _finishDelivered = true;
      try {
        await widget.onCanonicalFinished?.call(result);
      } on Object {
        // An optional post-study offer cannot prevent the ordinary score.
      }
    }
    if (!mounted || binding != _binding || !_current(_generation)) {
      if (mounted && binding == _binding) setState(() => _scoreOpen = false);
      return;
    }
    final mistakes = result.state.mistakeWords;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/score',
          builder: (scoreContext) {
            widget.onScoreRouteChanged?.call(
              ModalRoute.of(scoreContext),
              ModalRoute.isCurrentOf(scoreContext) == true,
            );
            return ValueListenableBuilder<String?>(
              valueListenable: _ownerToken,
              builder: (context, owner, _) => owner == result.state.ownerId
                  ? ScoreScreen(
                      correctAnswers: result.summary.correctCount,
                      wrongAnswers: result.summary.wrongCount,
                      score: result.summary.score,
                      mistakes: mistakes,
                      onPracticeMistakes: mistakes.isEmpty
                          ? null
                          : () => _practiceMistakes(scoreContext, mistakes),
                    )
                  : Scaffold(
                      body: _QuizMessage(
                        icon: Icons.account_circle_outlined,
                        message: 'บัญชีเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม',
                        actionLabel: 'กลับไปเลือกกิจกรรม',
                        onAction: () => Navigator.maybePop(scoreContext),
                      ),
                    ),
            );
          },
        ),
        onRouteCreated: (route) =>
            widget.onScoreRouteChanged?.call(route, true),
      );
      if (mounted &&
          binding == _binding &&
          _ownerCurrent &&
          _route?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } finally {
      widget.onScoreRouteChanged?.call(null, false);
      if (mounted && binding == _binding) setState(() => _scoreOpen = false);
    }
  }

  Future<void> _practiceMistakes(
    BuildContext scoreContext,
    List<QuizWord> mistakes,
  ) async {
    if (_practicingMistakes || !_ownerCurrent) return;
    final scoreRoute = ModalRoute.of(scoreContext);
    _practicingMistakes = true;
    try {
      await AppNavigator.pushPage<void>(
        scoreContext,
        AppPage<void>(
          name: 'learning/mistake-practice',
          builder: (_) => QuizScreen(
            wordIds: mistakes.map((word) => word.id).toSet().toList(),
            learning: _learning,
            expectedOwnerId: _boundOwnerId,
            ownerChanges: widget.ownerChanges,
          ),
        ),
      );
      if (scoreContext.mounted && scoreRoute?.isCurrent == true) {
        Navigator.of(scoreContext).pop();
      }
    } finally {
      _practicingMistakes = false;
    }
  }
}

class _QuizMessage extends StatelessWidget {
  const _QuizMessage({
    required this.icon,
    required this.message,
    this.liveRegion = false,
    this.actionLabel,
    this.onAction,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final bool liveRegion;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onRetry;

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
            Semantics(
              liveRegion: liveRegion,
              child: Text(message, textAlign: TextAlign.center),
            ),
            if (onRetry != null)
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('ลองอีกครั้ง'),
              ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
