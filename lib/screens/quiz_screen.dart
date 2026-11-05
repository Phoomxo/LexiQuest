import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/account_deletion/domain/account_deletion_contracts.dart';
import '../features/content_reports/domain/content_report.dart';
import '../features/content_reports/presentation/content_report_button.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/accepted_quiz_plan.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/learning_time_binding.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/learning_packs/presentation/rich_lexical_card.dart';
import '../voice/voice_models.dart';
import '../runtime/app_dependencies.dart';
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
    this.onOwnedRouteChanged,
    this.learningTime,
    this.timeCallerContext = LearningTimeCallerContext.ordinary,
    this.preparedLaunch,
    this.voice,
    this.resultBackLabel,
    this.configureBeforeStart = false,
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
  final void Function(Route<dynamic>? route, bool current)? onOwnedRouteChanged;
  final LearningTimeUseCases? learningTime;
  final LearningTimeCallerContext timeCallerContext;
  final ConfiguredQuizLaunch? preparedLaunch;
  final VoiceUseCases? voice;
  final String? resultBackLabel;
  final bool configureBeforeStart;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _QuizOperation { draft, hint, answer, advance, finish }

typedef _AnswerIntent = ({
  int revision,
  int? optionOrdinal,
  bool reveal,
  int? latencyMs,
  String? typedResponse,
});

bool _ownerChangedFailure(Object? error) =>
    (error is ConfiguredQuizUnavailable &&
        error.reason == ConfiguredQuizUnavailableReason.ownerChanged) ||
    (error is AccountDeletionException &&
        error.code == AccountDeletionFailureCode.ownerChanged);

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  LearningUseCases? _learning;
  Future<ConfiguredQuizLaunch>? _launch;
  bool _setupComplete = false;
  MeaningQuizDirection _direction = MeaningQuizDirection.forward;
  QuizHintPolicy _hints = QuizHintPolicy.optional;
  bool get _needsSetup =>
      widget.configureBeforeStart &&
      !_setupComplete &&
      widget.preparedLaunch == null &&
      widget.resumeSessionId == null &&
      widget.wordIds == null &&
      _acceptedSessionId == null;
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
  LearningTimeUseCases? _time;
  LearningTimeBinding? _timeBinding;
  int _timeRequest = 0;
  final _typed = TextEditingController();
  bool _typedDirty = false;
  bool _restoringTyped = false;
  VoiceUseCases? _voice;
  Future<void>? _voiceStopping;
  int _audioGeneration = 0;
  bool _ownsAudio = false;
  bool _audioBusy = false;
  bool _audioFailed = false;
  bool _reportOverlay = false;

  Future<void> _stopQuizVoice() {
    _audioGeneration++;
    _audioBusy = false;
    if (!_ownsAudio) return _voiceStopping ?? Future<void>.value();
    _ownsAudio = false;
    final voice = _voice;
    final stopped = () async {
      try {
        await voice?.stop();
      } on Object {
        // Audio cleanup cannot change an acknowledged answer.
      }
    }();
    _voiceStopping = stopped;
    unawaited(
      stopped.then((_) {
        if (identical(_voiceStopping, stopped)) _voiceStopping = null;
      }),
    );
    return stopped;
  }

  Future<void> _speakAnswer() async {
    final quiz = _quiz;
    final voice = _voice;
    if (quiz == null ||
        voice == null ||
        !_answered ||
        _blocked ||
        _audioBusy ||
        quiz.plan.configuration.lexical?.settings.manualAudio != true ||
        !_current(_generation)) {
      return;
    }
    final stopped = _stopQuizVoice();
    final audio = _audioGeneration;
    final generation = _generation;
    bool current() =>
        _current(generation) &&
        audio == _audioGeneration &&
        identical(voice, _voice) &&
        identical(quiz, _quiz) &&
        _answered;
    setState(() {
      _audioBusy = true;
      _audioFailed = false;
    });
    try {
      await stopped;
      if (!current()) return;
      final saved = await _learning!.resumeQuiz(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
      );
      if (!current()) return;
      if (saved.checkpointRevision != quiz.checkpointRevision ||
          saved.plan.id != quiz.plan.id ||
          saved.checkpoint is! AnsweredQuizQuestion) {
        throw StateError('Feedback changed');
      }
      _ownsAudio = true;
      await voice.speak(
        VoiceRequest.create(
          text: quiz.plan.questions[_index].word.spelling,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          contentId: '${quiz.plan.id}:$_index',
          contentType: 'vocabulary_word',
          mode: VoiceMode.practice,
        ),
      );
    } on Object {
      if (current()) setState(() => _audioFailed = true);
    } finally {
      if (current()) setState(() => _audioBusy = false);
    }
  }

  void _typedChanged() {
    if (_restoringTyped || !mounted) return;
    _timeBinding?.interacted();
    setState(() => _typedDirty = true);
  }

  void _restoreTyped(ConfiguredQuizState saved) {
    final local = saved.checkpoint.lexical;
    final text = local is LexicalTypedLocalData
        ? saved.checkpoint.answer?.submittedText ?? local.draft
        : '';
    _restoringTyped = true;
    _typed.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _restoringTyped = false;
    _typedDirty = false;
  }

  void _suspendTime() {
    _timeRequest++;
    _timeBinding?.suspend();
  }

  void _retireTime() {
    _timeRequest++;
    _timeBinding?.retireDependencies();
    _timeBinding?.dispose();
    _timeBinding = null;
  }

  Future<void> _readyTime() async {
    final quiz = _quiz;
    final learning = _learning;
    final time = _time;
    final generation = _generation;
    if (quiz == null ||
        learning == null ||
        time == null ||
        widget.timeCallerContext != LearningTimeCallerContext.ordinary ||
        !_current(generation) ||
        _saving ||
        _retryAction != null ||
        quiz.checkpoint is! AwaitingQuizAnswer) {
      return;
    }
    var binding = _timeBinding;
    if (binding == null || binding.expectedOwnerId != quiz.ownerId) {
      _retireTime();
      binding = LearningTimeBinding(
        time: time,
        expectedOwnerId: quiz.ownerId,
        visible: () =>
            _current(_generation) &&
            TickerMode.valuesOf(context).enabled &&
            Visibility.of(context),
      );
      _timeBinding = binding;
    }
    final request = ++_timeRequest;
    bool current() =>
        request == _timeRequest &&
        identical(_timeBinding, binding) &&
        identical(_quiz, quiz) &&
        identical(_time, time) &&
        _current(generation) &&
        !_saving &&
        _retryAction == null;
    try {
      final proof = await learning.admitCanonicalLearningTime(
        ConfiguredQuizTimeAdmission(
          quiz,
          callerContext: widget.timeCallerContext,
        ),
        expectedOwnerId: quiz.ownerId,
        stillCurrent: current,
      );
      if (!current()) return;
      await binding.ready(
        CanonicalTimeSource(proof, callerContext: widget.timeCallerContext),
      );
    } on Object {
      if (current()) binding.suspend();
    }
  }

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
    if (_quiz?.checkpoint.lexical is LexicalTypedLocalData) {
      return _quiz?.checkpoint.answer?.submittedText ??
          _answerIntent?.typedResponse;
    }
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
    _typed.addListener(_typedChanged);
    _foreground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    _acceptedSessionId = widget.resumeSessionId;
    _boundOwnerId =
        widget.expectedOwnerId ?? widget.preparedLaunch?.session.ownerId;
  }

  @override
  void didUpdateWidget(covariant QuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preparedLaunch != widget.preparedLaunch ||
        oldWidget.learning != widget.learning ||
        oldWidget.categoryId != widget.categoryId ||
        !listEquals(oldWidget.wordIds, widget.wordIds) ||
        oldWidget.selectionMode != widget.selectionMode ||
        oldWidget.resumeSessionId != widget.resumeSessionId ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        oldWidget.configureBeforeStart != widget.configureBeforeStart ||
        oldWidget.timeCallerContext != widget.timeCallerContext) {
      _retireTime();
      _binding++;
      _generation++;
      _launch = null;
      _setupComplete = false;
      _acceptedSessionId = widget.resumeSessionId;
      _boundOwnerId =
          widget.expectedOwnerId ?? widget.preparedLaunch?.session.ownerId;
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
    final time = widget.learningTime ?? dependencies?.learningTime;
    final voice = widget.voice ?? dependencies?.voice;
    if (!identical(voice, _voice)) {
      unawaited(_stopQuizVoice());
      _voice = voice;
    }
    if (!identical(_time, time) || !identical(_learning, learning)) {
      _retireTime();
      _time = time;
    }
    if (!identical(_learning, learning)) {
      _binding++;
      _generation++;
      _learning = learning;
      _load = null;
      _launch = null;
      _acceptedSessionId = widget.resumeSessionId;
      _boundOwnerId =
          widget.expectedOwnerId ?? widget.preparedLaunch?.session.ownerId;
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
    if (_visible && _load == null && !_needsSetup) {
      _load = _open(_generation, _binding);
    }
    final timeBinding = _timeBinding;
    final visibility = timeBinding?.visibilityGeneration;
    timeBinding?.syncVisibility();
    if (timeBinding != null && visibility != timeBinding.visibilityGeneration) {
      _timeRequest++;
      if (timeBinding.current) unawaited(_readyTime());
    }
  }

  void _ownerChanged(String? owner) {
    if (!mounted) return;
    _ownerToken.value = owner;
    _ownerKnown = true;
    if (!_ownerCurrent) {
      _retireTime();
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
    if (_reportOverlay && _foreground && _route?.isCurrent == false) {
      _suspendTime();
      return;
    }
    final visible = _foreground && (_route?.isCurrent ?? true);
    if (_visible == visible) return;
    _suspendTime();
    _visible = visible;
    _generation++;
    _quiz = null;
    _load = null;
    _clearPendingUi();
    if (_visible && !_needsSetup) _load = _open(_generation, _binding);
  }

  void _clearPendingUi() {
    unawaited(_stopQuizVoice());
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
    if (widget.preparedLaunch case final launch?) {
      if (widget.resumeSessionId != null ||
          widget.categoryId != null ||
          widget.wordIds != null ||
          (widget.expectedOwnerId != null &&
              widget.expectedOwnerId != launch.session.ownerId)) {
        throw ArgumentError(
          'Prepared quiz must retain its original owner and selection',
        );
      }
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
          ? QuizConfiguration.category(
              categoryId: widget.categoryId,
              direction: _direction,
              hints: _hints,
            )
          : widget.selectionMode == QuizWordSelectionMode.sourcePractice
          ? QuizConfiguration.sourcePractice(wordIds: widget.wordIds!)
          : QuizConfiguration.weaknessPractice(wordIds: widget.wordIds!);
      final launchFuture = _launch ??= widget.preparedLaunch == null
          ? learning.prepareConfiguredQuiz(
              configuration: configuration,
              expectedOwnerId: widget.expectedOwnerId,
            )
          : Future.value(widget.preparedLaunch!);
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
        _restoreTyped(saved);
        if (!saved.restored && saved.checkpoint is AwaitingQuizAnswer) {
          _questionClock = Stopwatch()..start();
        }
      });
      unawaited(_readyTime());
    }
    return saved;
  }

  @override
  void dispose() {
    unawaited(_stopQuizVoice());
    _typed.dispose();
    _timeBinding?.dispose();
    _timeRequest++;
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
    return LessonScaffold(
      title: _title,
      largeControls:
          _quiz?.plan.configuration.lexical?.settings.accessibleInput == true,
      reduceMotion:
          _quiz?.plan.configuration.lexical?.settings.reduceMotion == true,
      body: !_visible
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
          : _needsSetup
          ? _buildSetup()
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
                  return _QuizMessage(
                    icon: Icons.library_add_outlined,
                    message: _direction == MeaningQuizDirection.reverse
                        ? 'ยังไม่มีคำศัพท์และตัวเลือกที่แยกความหมายได้ชัดเจนสำหรับทิศทางนี้ ลองฝึกคำศัพท์ → ความหมายหรือเพิ่มคำศัพท์ก่อน'
                        : 'ไม่พบคำศัพท์สำหรับแบบทดสอบนี้',
                    actionLabel: 'กลับไปเลือกกิจกรรม',
                    onAction: () => Navigator.maybePop(context),
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
                    actionLabel: _saving || _scoreOpen ? null : 'ดูผลการเรียน',
                    onAction: _saving || _scoreOpen ? null : _next,
                  );
                }
                return _buildQuestion(quiz.asQuizSession);
              },
            ),
    );
  }

  String get _title {
    if (_quiz?.plan.configuration.lexical != null ||
        widget.preparedLaunch?.configuration.lexical != null) {
      return 'ฝึกคำศัพท์จากนิยาม';
    }
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

  Widget _buildSetup() {
    final generation = _generation;
    final binding = _binding;
    bool current() =>
        _needsSetup && _current(generation) && binding == _binding;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ตั้งค่าแบบทดสอบ',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text('ทิศทางคำถาม'),
          RadioGroup<MeaningQuizDirection>(
            key: const ValueKey('meaning-direction'),
            groupValue: _direction,
            onChanged: (value) {
              if (value != null && current()) {
                setState(() => _direction = value);
              }
            },
            child: const Column(
              children: [
                RadioListTile<MeaningQuizDirection>(
                  contentPadding: EdgeInsets.zero,
                  value: MeaningQuizDirection.forward,
                  title: Text('คำศัพท์ → ความหมาย'),
                ),
                RadioListTile<MeaningQuizDirection>(
                  key: ValueKey('meaning-reverse'),
                  contentPadding: EdgeInsets.zero,
                  value: MeaningQuizDirection.reverse,
                  title: Text('ความหมาย → คำศัพท์'),
                ),
              ],
            ),
          ),
          SwitchListTile(
            key: const ValueKey('meaning-hints'),
            contentPadding: EdgeInsets.zero,
            title: const Text('อนุญาตคำใบ้'),
            value: _hints == QuizHintPolicy.optional,
            onChanged: (value) {
              if (!current()) return;
              setState(
                () => _hints = value
                    ? QuizHintPolicy.optional
                    : QuizHintPolicy.disabled,
              );
            },
          ),
          FilledButton(
            key: const ValueKey('meaning-start'),
            onPressed: () {
              if (!current()) return;
              setState(() {
                _setupComplete = true;
                _load = _open(generation, binding);
              });
            },
            child: const Text('เริ่มฝึก'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(QuizSession session) {
    final question = session.questions[_index];
    final lexical = question.lexical;
    final typed = lexical is DefinitionTypedContent;
    final accessible =
        _quiz!.plan.configuration.lexical?.settings.accessibleInput == true;
    final help = lexical?.target.entry;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LessonProgress(
              current: _index + 1,
              total: session.questions.length,
            ),
            if (_quiz!.plan.configuration.lexical?.settings.advisoryMinutes
                case final minutes?)
              Text('เป้าหมาย $minutes นาที · พักหรือจบเมื่อพร้อม'),
            const SizedBox(height: 24),
            Text(
              typed
                  ? 'อ่านนิยามแล้วพิมพ์คำศัพท์'
                  : lexical != null
                  ? 'อ่านนิยามแล้วเลือกคำศัพท์'
                  : question.direction == MeaningQuizDirection.reverse
                  ? 'เลือกคำศัพท์ที่ตรงกับความหมาย'
                  : 'เลือกคำแปลที่ตรงกับคำศัพท์',
            ),
            const SizedBox(height: 12),
            Text(
              question.prompt,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            if (lexical == null && (_hintVisible || _answered))
              Text(
                question.word.partOfSpeech,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (!_answered) ...[
              if (_quiz!.plan.configuration.allowsHints &&
                  (help == null
                      ? question.word.partOfSpeech.isNotEmpty
                      : help.hint != null ||
                            help.strategy != null ||
                            help.memoryCue != null ||
                            help.examples.isNotEmpty))
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
            if (help != null && _hintVisible && !_answered) ...[
              if (help.hint != null) Text('คำใบ้: ${help.hint}'),
              if (help.strategy != null) Text('วิธีฝึก: ${help.strategy}'),
              if (help.memoryCue != null) Text('ช่วยจำ: ${help.memoryCue}'),
              for (final example in help.examples)
                Text('ตัวอย่าง: ${example.text}'),
            ],
            if (lexical != null &&
                _quiz!.checkpoint.assistance.hintFirstShownAtUtcMs != null)
              const Text('ใช้ตัวช่วยแล้วในข้อนี้'),
            const SizedBox(height: 24),
            if (typed) ...[
              TextField(
                key: const ValueKey('definition-response'),
                controller: _typed,
                enabled: !_answered && !_blocked,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'คำศัพท์ของคุณ',
                  border: OutlineInputBorder(),
                  helperText: 'กดเก็บร่างเพื่อเปิดข้อความเดิมต่อได้',
                ),
                onSubmitted: (_) =>
                    _record(question, null, typedResponse: _typed.text),
              ),
              const SizedBox(height: 12),
              if (!_answered) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _typedDirty
                        ? 'ร่างยังไม่ได้บันทึก'
                        : 'เก็บร่างแล้ว ยังไม่บันทึกคำตอบ',
                    key: const ValueKey('definition-draft-status'),
                  ),
                ),
                if (_typed.text.length > 512)
                  const Text('คำตอบยาวเกิน 512 ตัวอักษร'),
                if (!_typed.value.composing.isCollapsed)
                  const Text('ยืนยันข้อความบนแป้นพิมพ์ก่อนส่ง'),
                OutlinedButton(
                  key: const ValueKey('definition-save-draft'),
                  onPressed:
                      _blocked ||
                          !_typedDirty ||
                          !_typed.value.composing.isCollapsed ||
                          _typed.text.length > 512
                      ? null
                      : _saveTypedDraft,
                  child: const Text('เก็บร่าง'),
                ),
                FilledButton(
                  key: const ValueKey('definition-submit'),
                  onPressed:
                      _blocked ||
                          _typed.text.trim().isEmpty ||
                          _typed.text.length > 512 ||
                          !_typed.value.composing.isCollapsed
                      ? null
                      : () =>
                            _record(question, null, typedResponse: _typed.text),
                  child: const Text('บันทึกคำตอบ'),
                ),
              ],
            ],
            ...question.options.map((option) {
              final feedbackColors = _answerColors(question, option);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.tonal(
                  onPressed: _answered || _blocked
                      ? null
                      : () => _record(question, option),
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(accessible ? 64 : 52),
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
                      _quiz!.checkpoint.answer!.isCorrect
                          ? 'ถูกต้อง'
                          : 'ยังไม่ถูก ลองดูคำตอบที่ถูกต้องอีกครั้ง',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'คำตอบของคุณ: ${_revealed ? 'ไม่ได้ตอบ (ขอเฉลย)' : _selected}',
                    ),
                    Text(
                      '${question.word.spelling} — ${question.word.meaning}',
                    ),
                    if (lexical != null)
                      LexicalEntryDetails(
                        entry: lexical.target.entry,
                        showIdentity: false,
                        showAssistance: true,
                      ),
                    if (_quiz!.acknowledgedContrastiveExplanation
                        case final explanation?)
                      Text(
                        explanation,
                        key: const ValueKey(
                          'definition-contrastive-explanation',
                        ),
                      ),
                    if (_quiz!
                            .plan
                            .configuration
                            .lexical
                            ?.settings
                            .manualAudio ==
                        true) ...[
                      OutlinedButton.icon(
                        key: const ValueKey('definition-feedback-audio'),
                        onPressed: _voice == null || _audioBusy || _blocked
                            ? null
                            : _speakAnswer,
                        icon: const Icon(Icons.volume_up_outlined),
                        label: Text(
                          _voice == null
                              ? 'ระบบเสียงยังไม่พร้อม'
                              : _audioBusy
                              ? 'กำลังเล่นเสียง'
                              : 'ฟังคำศัพท์',
                        ),
                      ),
                      if (_audioFailed)
                        const Text('เล่นเสียงไม่สำเร็จ ลองฟังอีกครั้งได้'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _reportQuestion(question),
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

  Widget _reportQuestion(QuizQuestion question) {
    final quiz = _quiz;
    if (quiz == null ||
        !_answered ||
        widget.timeCallerContext != LearningTimeCallerContext.ordinary ||
        !LearningEvidenceContract.isOrdinaryEvidence(
          quiz.checkpoint.answer!.evidenceContext,
        )) {
      return const SizedBox.shrink();
    }
    final generation = _generation;
    final ordinal = _index;
    bool current() =>
        _current(generation) &&
        identical(_quiz, quiz) &&
        _index == ordinal &&
        !_blocked;
    Future<void> validate(bool Function() current) async {
      if (!current() || !identical(_quiz, quiz) || _index != ordinal) {
        throw StateError('The reported question changed');
      }
      quiz.requireCurrent();
    }

    final lexical = question.lexical;
    final key = ValueKey('content-report-quiz:${quiz.plan.id}:$ordinal');
    if (lexical == null) {
      return ContentReportButton.ownedWord(
        key: key,
        expectedOwnerId: quiz.ownerId,
        word: question.word,
        sessionId: quiz.sessionId,
        callerContext: widget.timeCallerContext,
        canOpen: current,
        beforeOpen: _stopQuizVoice,
        revalidateSource: validate,
        onOverlayChanged: (open) {
          _reportOverlay = open;
        },
        onRouteChanged: widget.onOwnedRouteChanged,
      );
    }
    return ContentReportButton.content(
      key: key,
      expectedOwnerId: quiz.ownerId,
      sessionId: quiz.sessionId,
      sourceIdentity: (quiz.plan.id, ordinal, quiz.checkpointRevision),
      sourceText: contentReportEntryText(lexical.target.entry),
      callerContext: widget.timeCallerContext,
      canOpen: current,
      beforeOpen: _stopQuizVoice,
      revalidateSource: validate,
      onOverlayChanged: (open) {
        _reportOverlay = open;
      },
      onRouteChanged: widget.onOwnedRouteChanged,
      targetForSelection: (text, excerpt) => ContentReportTarget.packEntry(
        text: text,
        isExcerpt: excerpt,
        packId: lexical.source.packId,
        packVersion: lexical.source.version,
        packageSha256: lexical.source.packageSha256,
        entryCode: lexical.target.entry.code,
        entrySha256: lexical.target.entry.contentSha256,
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
      if (freshQuestion ||
          saved.checkpoint is PendingQuizAnswer ||
          saved.checkpoint is AnsweredQuizQuestion) {
        _restoreTyped(saved);
      }
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
    _suspendTime();
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
      if (_current(generation)) {
        setState(() => _saving = false);
        unawaited(_readyTime());
      }
    }
  }

  Future<void> _toggleHint() async {
    final quiz = _quiz;
    if (quiz == null ||
        !quiz.plan.configuration.allowsHints ||
        _blocked ||
        quiz.checkpoint is! AwaitingQuizAnswer) {
      return;
    }
    final visible = !quiz.checkpoint.assistance.hintVisible;
    _timeBinding?.interacted();
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

  Future<void> _saveTypedDraft() async {
    final quiz = _quiz;
    if (quiz == null ||
        _blocked ||
        quiz.checkpoint is! AwaitingQuizAnswer ||
        !_typed.value.composing.isCollapsed ||
        _typed.text.length > 512) {
      return;
    }
    final text = _typed.text;
    await _run(_QuizOperation.draft, (generation) async {
      final saved = await _learning!.saveQuizTypedDraft(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
        text: text,
      );
      if (_apply(saved, generation)) setState(() => _restoreTyped(saved));
    });
  }

  Future<void> _record(
    QuizQuestion question,
    String? option, {
    bool reveal = false,
    String? typedResponse,
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
    final typed = question.lexical is DefinitionTypedContent;
    if (typed &&
        !reveal &&
        (typedResponse == null ||
            typedResponse.trim().isEmpty ||
            typedResponse.length > 512 ||
            !_typed.value.composing.isCollapsed)) {
      return;
    }
    final ordinal = typed || option == null
        ? null
        : question.options.indexOf(option);
    if (!typed && !reveal && (ordinal == null || ordinal < 0)) return;
    _timeBinding?.interacted();
    final intent = (
      revision: quiz.checkpointRevision,
      optionOrdinal: ordinal,
      reveal: reveal,
      latencyMs: _questionClock?.elapsedMilliseconds,
      typedResponse: typed && !reveal ? typedResponse : null,
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
        typedResponse: intent.typedResponse,
        stillCurrent: () => _current(generation),
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
    unawaited(_stopQuizVoice());
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
    bool scoreCurrent() =>
        mounted &&
        binding == _binding &&
        identical(_finished, result) &&
        _ownerToken.value == result.state.ownerId;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/score',
          reduceMotion:
              result.state.plan.configuration.lexical?.settings.reduceMotion ==
              true,
          builder: (scoreContext) {
            final visible = ModalRoute.isCurrentOf(scoreContext) == true;
            if (!_practicingMistakes || visible) {
              widget.onOwnedRouteChanged?.call(
                ModalRoute.of(scoreContext),
                visible,
              );
            }
            return ValueListenableBuilder<String?>(
              valueListenable: _ownerToken,
              builder: (context, owner, _) => scoreCurrent()
                  ? ScoreScreen(
                      backLabel: widget.resultBackLabel,
                      learningTime: _time,
                      resultOwnerId: result.state.ownerId,
                      resultSessionId: result.summary.id,
                      correctAnswers: result.summary.correctCount,
                      wrongAnswers: result.summary.wrongCount,
                      score: result.summary.score,
                      mistakes: mistakes,
                      onPracticeMistakes: mistakes.isEmpty
                          ? null
                          : () {
                              if (scoreCurrent()) {
                                _practiceMistakes(scoreContext, mistakes);
                              }
                            },
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
            widget.onOwnedRouteChanged?.call(route, true),
      );
      if (mounted &&
          binding == _binding &&
          _ownerCurrent &&
          _route?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } finally {
      widget.onOwnedRouteChanged?.call(null, false);
      if (mounted && binding == _binding) setState(() => _scoreOpen = false);
    }
  }

  Future<void> _practiceMistakes(
    BuildContext scoreContext,
    List<QuizWord> mistakes,
  ) async {
    if (_practicingMistakes || !_ownerCurrent) return;
    final scoreRoute = ModalRoute.of(scoreContext);
    Route<dynamic>? childRoute;
    _practicingMistakes = true;
    try {
      await AppNavigator.pushPage<void>(
        scoreContext,
        AppPage<void>(
          name: 'learning/mistake-practice',
          builder: (practiceContext) {
            final route = ModalRoute.of(practiceContext);
            final visible = ModalRoute.isCurrentOf(practiceContext) == true;
            if (visible || childRoute?.isCurrent != true) {
              widget.onOwnedRouteChanged?.call(route, visible);
            }
            return QuizScreen(
              resultBackLabel: widget.resultBackLabel,
              wordIds: mistakes.map((word) => word.id).toSet().toList(),
              learning: _learning,
              expectedOwnerId: _boundOwnerId,
              ownerChanges: widget.ownerChanges,
              learningTime: _time,
              timeCallerContext: widget.timeCallerContext,
              onOwnedRouteChanged: (route, current) {
                if (route == null || current) childRoute = route;
                widget.onOwnedRouteChanged?.call(route, current);
              },
            );
          },
        ),
        onRouteCreated: (route) =>
            widget.onOwnedRouteChanged?.call(route, true),
      );
      if (scoreContext.mounted && scoreRoute?.isCurrent == true) {
        Navigator.of(scoreContext).pop();
      }
    } finally {
      _practicingMistakes = false;
      if (scoreContext.mounted && scoreRoute?.isCurrent == true) {
        widget.onOwnedRouteChanged?.call(scoreRoute, true);
      }
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
