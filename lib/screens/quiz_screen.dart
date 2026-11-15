import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/cloze_prompt_policy.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import '../features/learning/domain/quiz_round.dart';
import '../features/learning/domain/scramble_prompt_policy.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import '../voice/voice_models.dart';
import 'score_screen.dart';
import 'scramble_tiles.dart';
import 'add_vocab_screen.dart';
import 'categories_page.dart';
import '../navigation/app_routes.dart';

enum QuizWordSelectionMode { weakness, sourcePractice }

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    this.categoryId,
    this.categoryName,
    this.returnLabel,
    this.learning,
    this.wordIds,
    this.featureRegistry,
    this.selectionMode = QuizWordSelectionMode.weakness,
    this.promptKind = QuizPromptKind.meaningChoice,
    this.expectedOwnerId,
    this.originParentId,
    this.configureRound = false,
    this.voice,
    this.onClozeComplete,
  });

  final String? categoryId;
  final String? categoryName;
  final String? returnLabel;
  final LearningUseCases? learning;
  final List<String>? wordIds;
  final FieldFeatureRegistry? featureRegistry;
  final QuizWordSelectionMode selectionMode;
  final QuizPromptKind promptKind;
  final String? expectedOwnerId;
  final String? originParentId;
  final bool configureRound;
  final VoiceUseCases? voice;
  final VoidCallback? onClozeComplete;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  LearningUseCases? _learning;
  Future<QuizSession?>? _load;
  int? _availableQuestions;
  int? _questionCount;
  bool _listenAndRead = false;
  bool _fiveMinuteGuide = false;
  bool _starting = false;
  bool _configureRound = false;
  bool _skipUnavailable = false;
  Timer? _guideTimer;
  bool _guideElapsed = false;
  VoiceUseCases? _promptVoice;
  bool _startingVoice = false;
  bool _voiceFailed = false;
  int _voiceGeneration = 0;
  QuizSession? _session;
  QuizRound? _round;
  final _questionClock = Stopwatch();
  int _activeElapsedMs = 0;
  String? _originParentId;
  String? _roundError;
  bool _pauseAfterWrite = false;
  bool _vocabularyChanged = false;
  int _index = 0;
  int _committedAnswers = 0;
  bool _answered = false;
  bool _saving = false;
  bool _answerSaveFailed = false;
  String? _selected;
  DateTime? _questionStartedAt;
  final List<QuizWord> _mistakes = [];
  String? _attemptId;
  DateTime? _submittedAtUtc;
  int? _responseTimeMs;
  bool _practicingMistakes = false;
  bool _hintVisible = false;
  bool _revealed = false;
  bool _responseCorrect = false;
  final _typedAnswer = TextEditingController();
  List<int> _scrambleOrder = const [];
  AppDependencies? _dependencies;
  bool _wasScoped = false;
  String? _ownerId;
  String? _categoryId;
  List<String>? _wordIds;
  QuizWordSelectionMode? _selectionMode;
  QuizPromptKind? _promptKind;
  String? _expectedOwnerId;
  int _generation = 0;
  bool _addingWords = false;
  bool _ownerChanged = false;
  bool _observedOwner = false;
  String? _activeOwnerId;
  StreamSubscription<String?>? _ownerChanges;
  StreamSubscription<void>? _linkedOwnerWrites;

  LearningUseCases? get _currentLearning {
    final dependencies = AppDependenciesScope.maybeOf(context);
    return dependencies == null
        ? (_wasScoped ? null : widget.learning)
        : dependencies.learning;
  }

  FieldFeatureRegistry get _features =>
      widget.featureRegistry ??
      AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
      const BuildFieldFeatureRegistry.allEnabled();

  bool get _canPracticeMistakes =>
      _features.isVisible(FieldFeature.weakness) &&
      _features.isVisible(FieldFeature.quiz);

  String get _returnLabel =>
      widget.returnLabel ??
      (widget.configureRound && widget.categoryName != null
          ? 'กลับไปที่ชุดคำ'
          : _round?.plan.returnLabel) ??
      (widget.categoryName == null ? 'กลับไปเลือกกิจกรรม' : 'กลับไปที่ชุดคำ');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ownerChanges?.cancel());
    unawaited(_linkedOwnerWrites?.cancel());
    _guideTimer?.cancel();
    _stopPromptVoice();
    _typedAnswer.dispose();
    _questionClock.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    setState(_stopPromptVoice);
    _questionClock.stop();
    if (_round == null || _round!.isPaused || _round!.summary != null) return;
    if (_saving || (_attemptId != null && !_answered)) {
      _pauseAfterWrite = true;
    } else {
      _advanceDurable(QuizStep.pause);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindLearning();
  }

  @override
  void didUpdateWidget(covariant QuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindLearning();
  }

  void _bindLearning({
    bool reload = false,
    bool skipUnavailable = false,
    QuizRoundSettings? settings,
  }) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (dependencies != null) _wasScoped = true;
    final learning = _currentLearning;
    if (!reload &&
        _load != null &&
        identical(dependencies, _dependencies) &&
        identical(learning, _learning) &&
        widget.categoryId == _categoryId &&
        listEquals(widget.wordIds, _wordIds) &&
        widget.selectionMode == _selectionMode &&
        widget.promptKind == _promptKind &&
        widget.originParentId == _originParentId &&
        widget.configureRound == _configureRound &&
        widget.expectedOwnerId == _expectedOwnerId) {
      return;
    }
    final scopeChanged = !identical(dependencies, _dependencies);
    _dependencies = dependencies;
    _learning = learning;
    _categoryId = widget.categoryId;
    _wordIds = widget.wordIds == null
        ? null
        : List.unmodifiable(widget.wordIds!);
    _selectionMode = widget.selectionMode;
    _promptKind = widget.promptKind;
    _expectedOwnerId = widget.expectedOwnerId;
    _originParentId = widget.originParentId;
    _configureRound = widget.configureRound;
    _skipUnavailable = skipUnavailable;
    final generation = ++_generation;
    _stopPromptVoice();
    _guideTimer?.cancel();
    _guideElapsed = false;
    _availableQuestions = null;
    _starting = settings != null;
    if (!reload) {
      _questionCount = null;
      _listenAndRead = false;
      _fiveMinuteGuide = false;
    }
    _ownerId = null;
    if (scopeChanged || _ownerChanges == null) {
      unawaited(_ownerChanges?.cancel());
      _ownerChanged = false;
      _observedOwner = false;
      _activeOwnerId = null;
      _ownerChanges = dependencies?.watchActiveOwnerId()?.listen((active) {
        _observedOwner = true;
        _activeOwnerId = active;
        final expected = _ownerId ?? _expectedOwnerId;
        if (expected != null && active != expected) _hideForOwnerChange();
      }, onError: (Object _) => _hideForOwnerChange());
    }
    unawaited(_linkedOwnerWrites?.cancel());
    _linkedOwnerWrites =
        _expectedOwnerId != null &&
            _originParentId != null &&
            _selectionMode == QuizWordSelectionMode.weakness
        ? dependencies?.watchLocalOwnerWrites()?.listen(
            (_) => _hideForOwnerChange(),
            onError: (Object _) => _hideForOwnerChange(),
          )
        : null;
    _session = null;
    _round = null;
    _roundError = null;
    _vocabularyChanged = false;
    _pauseAfterWrite = false;
    _questionClock
      ..stop()
      ..reset();
    _activeElapsedMs = 0;
    _index = 0;
    _committedAnswers = 0;
    _answered = false;
    _saving = false;
    _answerSaveFailed = false;
    _addingWords = false;
    _selected = null;
    _questionStartedAt = null;
    _attemptId = null;
    _submittedAtUtc = null;
    _responseTimeMs = null;
    _practicingMistakes = false;
    _hintVisible = false;
    _revealed = false;
    _responseCorrect = false;
    _typedAnswer.clear();
    _scrambleOrder = const [];
    _mistakes.clear();
    _load = _startSession(learning, generation, skipUnavailable, settings)
        .whenComplete(() {
          if (_current(generation)) _starting = false;
        });
    _load!.ignore();
  }

  bool _current(int generation) =>
      mounted &&
      !_ownerChanged &&
      generation == _generation &&
      identical(AppDependenciesScope.maybeOf(context), _dependencies) &&
      identical(_currentLearning, _learning) &&
      widget.categoryId == _categoryId &&
      listEquals(widget.wordIds, _wordIds) &&
      widget.selectionMode == _selectionMode &&
      widget.promptKind == _promptKind &&
      widget.originParentId == _originParentId &&
      widget.configureRound == _configureRound &&
      widget.expectedOwnerId == _expectedOwnerId;

  void _hideForOwnerChange() {
    if (!mounted || _ownerChanged) return;
    _questionClock.stop();
    _guideTimer?.cancel();
    _stopPromptVoice();
    setState(() {
      _ownerChanged = true;
      _generation++;
      _session = null;
      _round = null;
      _saving = false;
      _starting = false;
    });
  }

  Future<QuizSession?> _startSession(
    LearningUseCases? learning,
    int generation,
    bool skipUnavailable,
    QuizRoundSettings? settings,
  ) async {
    if (learning == null) {
      throw StateError('local learning dependency unavailable');
    }
    final owner = await learning.owners.getOrCreateActiveOwner();
    if (!_current(generation)) throw StateError('quiz context changed');
    if (_expectedOwnerId != null && owner.id != _expectedOwnerId) {
      throw StateError('quiz owner changed');
    }
    if (_observedOwner && _activeOwnerId != owner.id) {
      _hideForOwnerChange();
      throw StateError('quiz owner changed');
    }
    _ownerId = owner.id;
    final canPinOrigin =
        _wordIds == null ||
        (_wordIds!.isNotEmpty &&
            _wordIds!.length <= 100 &&
            (_selectionMode != QuizWordSelectionMode.sourcePractice ||
                _originParentId != null));
    final origin = learning.supportsDurableQuiz && canPinOrigin
        ? QuizOrigin(
            route: _wordIds == null ? 'category' : _selectionMode!.name,
            categoryId: _categoryId,
            wordIds: _wordIds,
            promptKind: widget.promptKind,
            parentId: _originParentId,
          )
        : null;
    final configure =
        _configureRound &&
        _categoryId != null &&
        _wordIds == null &&
        origin != null;
    if (configure && settings == null) {
      final setup = await learning.prepareCategoryQuiz(
        origin: origin,
        expectedOwnerId: owner.id,
        skipUnavailable: skipUnavailable,
      );
      await _requireSessionOwner(learning, generation, owner.id);
      _availableQuestions = setup.available;
      return setup.existing;
    }
    final QuizSession session;
    try {
      session = widget.promptKind.isScramble
          ? await learning.startScramble(
              categoryId: _categoryId,
              kind: widget.promptKind,
              expectedOwnerId: owner.id,
              wordId: _wordIds?.single,
              parentSessionId: _originParentId,
              skipUnavailable: skipUnavailable,
              categoryName: widget.categoryName,
              returnLabel: _returnLabel,
            )
          : widget.promptKind.isCloze
          ? await learning.startCloze(
              categoryId: _categoryId,
              kind: widget.promptKind,
              expectedOwnerId: owner.id,
              parentSessionId: _originParentId,
              skipUnavailable: skipUnavailable,
              categoryName: widget.categoryName,
              returnLabel: _returnLabel,
            )
          : _wordIds == null
          ? await learning.startQuiz(
              categoryId: _categoryId,
              kind: widget.promptKind,
              expectedOwnerId: owner.id,
              origin: origin,
              skipUnavailable: skipUnavailable,
              categoryName: widget.categoryName,
              returnLabel: _returnLabel,
              settings: settings,
            )
          : _selectionMode == QuizWordSelectionMode.sourcePractice
          ? await learning.startSourcePracticeForWords(
              wordIds: _wordIds!,
              kind: widget.promptKind,
              expectedOwnerId: owner.id,
              origin: origin,
              skipUnavailable: skipUnavailable,
              categoryName: widget.categoryName,
              returnLabel: _returnLabel,
            )
          : await learning.startWeaknessPractice(
              wordIds: _wordIds!,
              limit: _originParentId == null
                  ? 20
                  : _wordIds!.length.clamp(1, 100),
              kind: widget.promptKind,
              expectedOwnerId: owner.id,
              origin: origin,
              skipUnavailable: skipUnavailable,
              categoryName: widget.categoryName,
              returnLabel: _returnLabel,
            );
    } on QuizRoundShortage catch (shortage) {
      await _requireSessionOwner(learning, generation, owner.id);
      _availableQuestions = shortage.available;
      return null;
    }
    await _requireSessionOwner(learning, generation, owner.id);
    return session;
  }

  Future<void> _requireSessionOwner(
    LearningUseCases learning,
    int generation,
    String ownerId,
  ) async {
    final currentOwner = await learning.owners.getOrCreateActiveOwner();
    if (!_current(generation) || currentOwner.id != ownerId) {
      throw StateError('quiz context changed');
    }
  }

  void _startConfiguredRound(int count, int generation) {
    if (_starting ||
        !_current(generation) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(
      () => _bindLearning(
        reload: true,
        skipUnavailable: _skipUnavailable,
        settings: QuizRoundSettings(
          questionCount: count,
          listenAndRead: _listenAndRead,
          fiveMinuteGuide: _fiveMinuteGuide,
        ),
      ),
    );
  }

  void _startGuide(QuizRound round) {
    if (round.plan.settings?.fiveMinuteGuide != true) return;
    final remaining = round.startedAtUtc
        .add(const Duration(minutes: 5))
        .difference(_learning!.nowUtc());
    _guideElapsed = remaining <= Duration.zero;
    if (!_guideElapsed) {
      _guideTimer = Timer(remaining, () {
        if (mounted) setState(() => _guideElapsed = true);
      });
    }
  }

  void _stopPromptVoice() {
    _voiceGeneration++;
    _startingVoice = false;
    _voiceFailed = false;
    final voice = _promptVoice;
    if (voice != null) unawaited(voice.stop().catchError((Object _) {}));
  }

  bool _canSpeak(QuizQuestion question, int generation) {
    final round = _round;
    final session = _session;
    return _current(generation) &&
        !_saving &&
        round != null &&
        !round.isPaused &&
        round.summary == null &&
        round.plan.settings?.listenAndRead == true &&
        session != null &&
        identical(session.questions[_index], question) &&
        ModalRoute.of(context)?.isCurrent == true &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  Future<void> _speakPrompt(QuizQuestion question) async {
    final generation = _generation;
    if (_startingVoice || !_canSpeak(question, generation)) return;
    final requestGeneration = ++_voiceGeneration;
    setState(() {
      _startingVoice = true;
      _voiceFailed = false;
    });
    var failed = false;
    try {
      final learning = _learning!;
      final owner = await learning.owners.getOrCreateActiveOwner();
      if (requestGeneration != _voiceGeneration ||
          !_canSpeak(question, generation)) {
        return;
      }
      if (owner.id != _ownerId) {
        _hideForOwnerChange();
        return;
      }
      final voice = _promptVoice ??=
          widget.voice ?? VoiceUseCases.createOnDevice();
      await voice.speak(
        VoiceRequest.create(
          text: question.promptText,
          language: question.kind == QuizPromptKind.spellingChoice
              ? 'th'
              : 'en',
          voiceId: 'native-default',
          speed: 1,
          contentId: question.word.id,
          contentType: 'quiz_prompt',
          mode: VoiceMode.practice,
        ),
      );
    } on Object {
      failed = true;
    } finally {
      if (_current(generation) && requestGeneration == _voiceGeneration) {
        setState(() {
          _startingVoice = false;
          _voiceFailed = failed;
        });
      }
    }
  }

  bool _hasChoiceContrast(QuizSession session) => session.questions.every(
    (question) =>
        question.kind == QuizPromptKind.clozeTyped ||
        question.kind.isScramble ||
        question.options.toSet().length >= 2,
  );

  int get _elapsed => (_activeElapsedMs + _questionClock.elapsedMilliseconds)
      .clamp(0, LearningEvidenceContract.maxResponseTimeMs);

  void _applyRound(QuizRound round) {
    final previous = _round;
    _round = round;
    _index = round.cursor.slot;
    _committedAnswers = round.committedAnswers;
    _mistakes
      ..clear()
      ..addAll(round.mistakes);
    final response = round.feedback;
    _answered = response != null;
    final question = round.plan.questions[_index];
    _selected = response?.answerFor(question);
    _revealed = response != null && _selected == null;
    _responseCorrect = response?.isCorrectFor(question) ?? false;
    if (question.kind == QuizPromptKind.clozeTyped) {
      if (_selected != null) {
        _typedAnswer.text = _selected!;
      } else if (previous?.sessionId != round.sessionId ||
          previous?.cursor.slot != round.cursor.slot ||
          previous?.cursor.phase == QuizPhase.feedback) {
        _typedAnswer.clear();
      }
    }
    if (response case QuizOrderResponse(:final indexes)) {
      _scrambleOrder = indexes;
    } else if (question.kind.isScramble &&
        (previous?.sessionId != round.sessionId ||
            previous?.cursor.slot != round.cursor.slot ||
            previous?.cursor.phase == QuizPhase.feedback)) {
      _scrambleOrder = const [];
    }
    _activeElapsedMs = round.cursor.activeResponseMs;
    _questionClock
      ..stop()
      ..reset();
    if (!round.isPaused &&
        !_answered &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _questionClock.start();
    }
    _attemptId = null;
    _submittedAtUtc = null;
    _responseTimeMs = null;
    _answerSaveFailed = false;
  }

  Future<QuizRound?> _advanceDurable(
    QuizStep step, {
    bool leave = false,
  }) async {
    final round = _round;
    final learning = _learning;
    final ownerId = _ownerId;
    final generation = _generation;
    if (round == null ||
        learning == null ||
        ownerId == null ||
        _saving ||
        !_current(generation)) {
      return null;
    }
    if (step == QuizStep.pause) _questionClock.stop();
    setState(() {
      _stopPromptVoice();
      _roundError = null;
      _saving = true;
    });
    QuizRound? next;
    var vocabularyChanged = false;
    try {
      next = await learning.advanceQuizRound(
        round.sessionId,
        expectedRevision: round.cursor.revision,
        step: step,
        expectedOwnerId: ownerId,
        activeResponseMs: _elapsed,
      );
    } on QuizVocabularyChanged {
      vocabularyChanged = true;
    } catch (_) {
      try {
        final saved = await learning.loadQuizRound(
          round.sessionId,
          expectedOwnerId: ownerId,
        );
        if (saved != null && saved.cursor.revision > round.cursor.revision) {
          next = saved;
        }
      } catch (_) {}
    }
    if (!_current(generation)) return null;
    final admitted = next;
    setState(() {
      _saving = false;
      _vocabularyChanged = vocabularyChanged;
      if (admitted != null) {
        _hintVisible = false;
        _applyRound(admitted);
      } else {
        _roundError = 'เปลี่ยนสถานะรอบไม่สำเร็จ กรุณาลองอีกครั้ง';
        if (!round.isPaused &&
            !_answered &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          _questionClock.start();
        }
      }
    });
    if (leave && admitted?.isPaused == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(generation) &&
            _round?.isPaused == true &&
            ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      });
    }
    if (_pauseAfterWrite &&
        admitted != null &&
        !admitted.isPaused &&
        admitted.summary == null) {
      _pauseAfterWrite = false;
      return _advanceDurable(QuizStep.pause);
    }
    return admitted;
  }

  Future<void> _addWords() async {
    final generation = _generation;
    final dependencies = _dependencies;
    final vocabulary = dependencies?.vocabulary;
    final ownerId = _ownerId;
    final categoryId = _categoryId;
    if (_addingWords ||
        _saving ||
        !_current(generation) ||
        !_features.isVisible(FieldFeature.vocabulary) ||
        vocabulary == null ||
        ownerId == null) {
      return;
    }
    setState(() => _addingWords = true);
    try {
      final owner = await vocabulary.owners.getOrCreateActiveOwner();
      if (!mounted ||
          !_current(generation) ||
          owner.id != ownerId ||
          !_features.isVisible(FieldFeature.vocabulary)) {
        return;
      }
      if (categoryId == null) {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'vocabulary/quiz-add-destination',
            builder: (_) => const CategoriesPage(),
          ),
        );
        return;
      }
      VocabularyWord? savedWord;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'vocabulary/quiz-add-word',
          builder: (_) => AddWordScreen(
            categoryId: categoryId,
            categoryName: widget.categoryName,
            vocabulary: vocabulary,
            expectedOwnerId: ownerId,
            onCreated: (word) => savedWord = word,
          ),
        ),
      );
      if (savedWord == null || !_current(generation)) return;
      final currentOwner = await vocabulary.owners.getOrCreateActiveOwner();
      if (!_current(generation) ||
          currentOwner.id != ownerId ||
          savedWord!.ownerId != ownerId ||
          savedWord!.categoryId != categoryId) {
        return;
      }
      setState(() => _bindLearning(reload: true));
    } catch (_) {
      if (mounted && _current(generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เปิดคลังคำศัพท์ไม่สำเร็จ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (_current(generation)) setState(() => _addingWords = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usesAdaptiveTitle =
        _title.runes.length > 18 ||
        MediaQuery.textScalerOf(context).scale(1) >= 2;
    return PopScope(
      canPop: !_saving && !_starting,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: usesAdaptiveTitle
              ? M3Theme.appBarToolbarHeight(context)
              : null,
          title: usesAdaptiveTitle
              ? M3Theme.appBarTitle(context, _title)
              : Text(_title),
        ),
        body: AdaptiveContentPane(
          child: _ownerChanged
              ? _QuizMessage(
                  icon: Icons.error_outline,
                  message: 'บัญชีผู้เรียนเปลี่ยนแล้ว',
                  actionLabel: widget.promptKind.isCloze
                      ? 'กลับ'
                      : _returnLabel,
                  onAction: () => Navigator.maybePop(context),
                )
              : FutureBuilder<QuizSession?>(
                  key: ValueKey(_generation),
                  future: _load,
                  builder: (context, snapshot) {
                    if (_vocabularyChanged ||
                        snapshot.error is QuizVocabularyChanged) {
                      return _QuizMessage(
                        icon: Icons.update,
                        message:
                            'คำศัพท์ในรอบเดิมเปลี่ยนแล้ว เริ่มรอบใหม่จากข้อมูลปัจจุบันได้',
                        liveRegion: true,
                        actionLabel: 'เริ่มรอบใหม่',
                        onAction: () => setState(
                          () => _bindLearning(
                            reload: true,
                            skipUnavailable: true,
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return _QuizMessage(
                        icon: Icons.error_outline,
                        message:
                            'เปิดแบบทดสอบไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกเปลี่ยนแปลง',
                        liveRegion: true,
                        actionLabel: 'กลับไปเลือกกิจกรรม',
                        onAction: () => Navigator.maybePop(context),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.done &&
                        _availableQuestions != null &&
                        !snapshot.hasData) {
                      return _buildRoundSetup(_availableQuestions!);
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'กำลังเตรียมแบบทดสอบ',
                        ),
                      );
                    }
                    final session = snapshot.data!;
                    if (session.isEmpty) {
                      return _QuizMessage(
                        icon: Icons.library_add_outlined,
                        message: switch (widget.promptKind) {
                          QuizPromptKind.meaningChoice =>
                            'ยังไม่มีคำศัพท์สำหรับแบบทดสอบ กรุณาเพิ่มคำศัพท์ก่อน',
                          QuizPromptKind.spellingChoice =>
                            'ยังไม่มีคำและความหมายที่แยกตัวเลือกได้ชัดเจน',
                          QuizPromptKind.definitionChoice =>
                            'ยังไม่มีคู่นิยามที่รองรับ\nโจทย์นี้ใช้ platform · ชานชาลา และ ticket · ตั๋ว ชนิดคำนามในชุดเดียวกัน',
                          QuizPromptKind.clozeChoice ||
                          QuizPromptKind.clozeTyped =>
                            'ยังไม่มีประโยคสำหรับคำนี้ในชุดฝึก',
                          QuizPromptKind.wordScramble =>
                            'ยังไม่มีคำภาษาอังกฤษที่ใช้เรียงตัวอักษรได้ในชุดนี้',
                          QuizPromptKind.sentenceScramble =>
                            'ชุดนี้ยังไม่มีคำที่มีประโยคฝึกที่รองรับ',
                        },
                        actionLabel: widget.promptKind.isCloze
                            ? 'กลับ'
                            : _returnLabel,
                        onAction: () => Navigator.maybePop(context),
                      );
                    }
                    if (!_hasChoiceContrast(session)) {
                      return _buildOneChoiceFallback();
                    }
                    if (_session == null) {
                      _session = session;
                      final round = session.durableRound;
                      if (round != null) {
                        _applyRound(round);
                        _startGuide(round);
                      } else {
                        _questionStartedAt = DateTime.now();
                      }
                    }
                    if (_round?.isPaused == true) {
                      return _QuizMessage(
                        icon: Icons.pause_circle_outline,
                        message:
                            _roundError ??
                            'พักที่คำถาม ${_index + 1} จาก ${session.questions.length}',
                        actionLabel: 'ฝึกต่อ',
                        onAction: _saving
                            ? null
                            : () => _advanceDurable(QuizStep.resume),
                      );
                    }
                    return _buildQuestion(session);
                  },
                ),
        ),
      ),
    );
  }

  String get _title => widget.promptKind == QuizPromptKind.wordScramble
      ? 'เรียงตัวอักษร'
      : widget.promptKind == QuizPromptKind.sentenceScramble
      ? 'เรียงคำให้จบประโยค'
      : widget.promptKind.isCloze
      ? 'เติมคำในประโยค'
      : widget.wordIds == null
      ? 'แบบทดสอบคำศัพท์'
      : widget.selectionMode == QuizWordSelectionMode.sourcePractice
      ? 'แบบทดสอบจากเนื้อหานี้'
      : 'ฝึกคำที่ผิด';

  Widget _buildRoundSetup(int available) {
    final count = _questionCount ?? (available == 0 ? 1 : available);
    final generation = _generation;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('ตั้งค่าก่อนฝึก', style: Theme.of(context).textTheme.titleLarge),
          if (widget.categoryName case final name?) Text(name),
          const SizedBox(height: 16),
          const Text('จำนวนคำ'),
          DropdownButton<int>(
            value: count,
            isExpanded: true,
            onChanged: (value) => setState(() => _questionCount = value),
            items: [
              for (var count = 1; count <= 10; count++)
                DropdownMenuItem(value: count, child: Text('$count คำ')),
            ],
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              available == 0
                  ? 'รอบนี้ยังไม่มีความหมายอื่นให้เลือก'
                  : count > available
                  ? 'คำไม่พอสำหรับรอบนี้ เลือกได้สูงสุด $available คำ'
                  : 'ฝึกได้ $available คำ',
            ),
          ),
          if (available == 0 &&
              _features.isVisible(FieldFeature.vocabulary) &&
              _dependencies?.vocabulary != null)
            OutlinedButton.icon(
              key: const ValueKey('quiz-add-word'),
              onPressed: _addingWords ? null : _addWords,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มคำในชุดนี้'),
            ),
          const SizedBox(height: 16),
          const Text('วิธีรับโจทย์'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('ฝึกแบบอ่านเอง'),
                selected: !_listenAndRead,
                onSelected: (_) => setState(() => _listenAndRead = false),
              ),
              ChoiceChip(
                label: const Text('ฟังและอ่าน'),
                selected: _listenAndRead,
                onSelected: (_) => setState(() => _listenAndRead = true),
              ),
            ],
          ),
          if (_listenAndRead) const Text('ใช้เสียงจากระบบเมื่อกดฟังคำนี้'),
          const SizedBox(height: 12),
          const Text('จังหวะฝึก'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('ฝึกตามจังหวะของฉัน'),
                selected: !_fiveMinuteGuide,
                onSelected: (_) => setState(() => _fiveMinuteGuide = false),
              ),
              ChoiceChip(
                label: const Text('ใช้เวลาเป็นแนวทาง'),
                selected: _fiveMinuteGuide,
                onSelected: (_) => setState(() => _fiveMinuteGuide = true),
              ),
            ],
          ),
          if (_fiveMinuteGuide)
            const Text('5 นาทีจากเริ่มรอบ · ครบเวลาแล้วยังตอบต่อได้'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: count > available || _addingWords
                ? null
                : () => _startConfiguredRound(count, generation),
            child: const Text('เริ่มฝึก'),
          ),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('ยกเลิกก่อนเริ่ม'),
          ),
        ],
      ),
    );
  }

  Widget _buildOneChoiceFallback() {
    final canAdd =
        _features.isVisible(FieldFeature.vocabulary) &&
        _dependencies?.vocabulary != null;
    // Loading retains the existing active zero-attempt session, as Back does.
    // This fallback never records an answer or manufactures a completed result.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.categoryName != null) ...[
              Text(
                widget.categoryName!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
            ],
            const Text('รอบนี้ยังไม่มีความหมายอื่นให้เลือก'),
            const SizedBox(height: 8),
            const Text('เพิ่มคำที่มีความหมายต่างกัน แล้วลองเริ่มรอบใหม่'),
            if (canAdd) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('quiz-add-word'),
                onPressed: _addingWords ? null : _addWords,
                icon: const Icon(Icons.add),
                label: Text(
                  _categoryId == null
                      ? 'เปิดคลังเพื่อเพิ่มคำ'
                      : 'เพิ่มคำในชุดนี้',
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _addingWords
                  ? null
                  : () => setState(() => _bindLearning(reload: true)),
              child: const Text('ลองเริ่มรอบใหม่'),
            ),
            TextButton(
              onPressed: _addingWords
                  ? null
                  : () => Navigator.maybePop(context),
              child: Text(_returnLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(QuizSession session) {
    final question = session.questions[_index];
    final isCloze = question.kind.isCloze;
    final isScramble = question.kind.isScramble;
    final isSentence = question.kind == QuizPromptKind.sentenceScramble;
    final settings = _round?.plan.settings;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.categoryName != null) ...[
              Text(
                widget.categoryName!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'คำถาม ${_index + 1} จาก ${session.questions.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (settings != null)
              Semantics(
                liveRegion: settings.fiveMinuteGuide && _guideElapsed,
                child: Text(
                  settings.fiveMinuteGuide
                      ? (_guideElapsed
                            ? 'ครบ 5 นาทีแล้ว · ยังตอบต่อได้'
                            : '5 นาที · ไม่มีการตัดจบ')
                      : 'ไม่จับเวลา',
                ),
              ),
            if (_round != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _saving || (!_answered && _attemptId != null)
                      ? null
                      : () => _advanceDurable(QuizStep.pause, leave: true),
                  icon: const Icon(Icons.pause),
                  label: const Text('พักรอบนี้'),
                ),
              ),
            if (_roundError != null)
              Semantics(liveRegion: true, child: Text(_roundError!)),
            const SizedBox(height: 8),
            Semantics(
              label: 'คำถาม ${_index + 1} จาก ${session.questions.length}',
              child: LinearProgressIndicator(
                value: (_index + 1) / session.questions.length,
              ),
            ),
            const SizedBox(height: 24),
            Text(switch (question.kind) {
              QuizPromptKind.meaningChoice => 'เลือกคำแปลที่ตรงกับคำศัพท์',
              QuizPromptKind.spellingChoice => 'เลือกคำอังกฤษที่ตรงกับความหมาย',
              QuizPromptKind.definitionChoice => 'โจทย์นิยามภาษาอังกฤษ',
              QuizPromptKind.clozeChoice => 'เลือกคำที่หายไป',
              QuizPromptKind.clozeTyped => 'พิมพ์คำที่หายไป',
              QuizPromptKind.wordScramble => 'เรียงตัวอักษรให้ตรงกับความหมาย',
              QuizPromptKind.sentenceScramble => 'เรียงคำให้ตรงกับความหมาย',
            }),
            const SizedBox(height: 12),
            Text(
              question.promptText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (isScramble) ...[
              const SizedBox(height: 16),
              ScrambleTiles(
                tokens: question.scrambleTokens,
                order: _scrambleOrder,
                isSentence: isSentence,
                onChanged: _answered || _saving || _attemptId != null
                    ? null
                    : (order) => setState(() => _scrambleOrder = order),
                onCheck: () => _record(question, null),
              ),
            ],
            if (isCloze &&
                (_answered || question.kind == QuizPromptKind.clozeChoice))
              Text(question.clozeTranslation!, textAlign: TextAlign.center),
            if (question.kind == QuizPromptKind.clozeTyped) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('cloze-typed-answer'),
                controller: _typedAnswer,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'คำตอบ'),
                maxLength: 120,
                enabled: !_answered && !_saving && _attemptId == null,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitTypedCloze(question),
              ),
              if (!_answered)
                OutlinedButton(
                  onPressed:
                      _saving ||
                          _attemptId != null ||
                          _typedAnswer.text.trim().isEmpty
                      ? null
                      : () => _submitTypedCloze(question),
                  child: const Text('ตรวจคำตอบ'),
                ),
            ],
            if (settings?.listenAndRead == true) ...[
              OutlinedButton.icon(
                onPressed: _startingVoice || _saving
                    ? null
                    : () => _speakPrompt(question),
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(_startingVoice ? 'กำลังเตรียมเสียง' : 'ฟังคำนี้'),
              ),
              if (_voiceFailed)
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'เล่นเสียงไม่ได้ ลองอ่านโจทย์แล้วตอบต่อได้',
                  ),
                ),
            ],
            const SizedBox(height: 4),
            if (_hintVisible || _answered)
              Text(
                question.word.partOfSpeech,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (!_answered) ...[
              if (!isCloze &&
                  !isScramble &&
                  question.word.partOfSpeech.isNotEmpty)
                TextButton(
                  onPressed: _saving || _attemptId != null
                      ? null
                      : () => setState(() => _hintVisible = !_hintVisible),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(_hintVisible ? 'ซ่อนคำใบ้' : 'ดูคำใบ้'),
                ),
              if (!isCloze && !isScramble)
                TextButton(
                  onPressed: _saving || _attemptId != null
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
                  onPressed: _answered || _saving || _attemptId != null
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
            if (_answerSaveFailed)
              Semantics(
                liveRegion: true,
                child: const Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง'),
              ),
            if (!_answered && !_saving && _attemptId != null)
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
                      isScramble
                          ? _scrambleFeedback(isSentence)
                          : _responseCorrect
                          ? (isCloze ? 'เติมคำได้ถูกต้อง' : 'ถูกต้อง')
                          : (isCloze
                                ? 'ยังไม่ถูก ลองดูคำใบ้'
                                : 'ยังไม่ถูก ลองดูคำแปลอีกครั้ง'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'คำตอบของคุณ: ${_revealed ? 'ไม่ได้ตอบ (ขอเฉลย)' : _selected}',
                    ),
                    if (isCloze && _responseCorrect)
                      Text(question.promptText.replaceFirst('____', _selected!))
                    else if (isCloze)
                      Text('คำใบ้ · ${question.word.meaning}')
                    else if (!isScramble)
                      Text(
                        '${question.word.spelling} — ${question.word.meaning}',
                      ),
                    if (isScramble && !_responseCorrect)
                      Text(_scrambleHint(question, isSentence)),
                    if (isScramble && _responseCorrect && !isSentence)
                      if (ScramblePromptPolicy.sentenceFor(question.word)
                          case final authored?)
                        Text(authored.sentence),
                    if (question.optionWords?[_selected]
                        case final selectedWord?)
                      if (_selected != question.correctAnswer)
                        Text(
                          '${selectedWord.spelling} — ${selectedWord.meaning}',
                        ),
                    if (question.optionExplanations?[_selected]
                        case final explanation?)
                      Text(explanation),
                    if (question.kind == QuizPromptKind.clozeChoice &&
                        !_responseCorrect)
                      if (ClozePromptPolicy.distractorMeaning(_selected)
                          case final meaning?)
                        Text('$_selected — $meaning'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_answered &&
                question.kind != QuizPromptKind.meaningChoice &&
                !_responseCorrect)
              OutlinedButton(
                onPressed: _saving ? null : _retryQuestion,
                child: Text(isCloze ? 'ลองตอบอีกครั้ง' : 'ลองข้อเดิม'),
              ),
            if (isCloze &&
                _answered &&
                _responseCorrect &&
                ScramblePromptPolicy.sentenceFor(question.word) != null)
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => _openSentence(
                        context,
                        session.id,
                        question.word,
                        'กลับไปดูผลเติมคำ',
                      ),
                child: const Text('ลองเรียงประโยค'),
              ),
            if (_answered && (!isCloze || _responseCorrect))
              FilledButton(
                onPressed: _saving ? null : _next,
                child: Text(
                  isCloze
                      ? _returnLabel
                      : isScramble
                      ? 'ดูผลการฝึก'
                      : _index == session.questions.length - 1
                      ? 'ดูผลการเรียน'
                      : 'คำถามถัดไป',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _scrambleFeedback(bool sentence) => _responseCorrect
      ? (sentence ? 'เรียงได้ถูกต้อง' : 'สะกดถูกแล้ว')
      : (sentence ? 'ลองสลับตำแหน่งคำ' : 'ลองอีกตัวหนึ่ง');

  void _openSentence(
    BuildContext from,
    String parentId,
    QuizWord word,
    String returnLabel,
  ) {
    final owner = _ownerId;
    if (owner == null ||
        !_current(_generation) ||
        ModalRoute.of(from)?.isCurrent != true) {
      return;
    }
    unawaited(
      AppNavigator.pushPage<void>(
        from,
        AppPage<void>(
          name: 'learning/word-games/sentence-from-feedback',
          builder: (_) => QuizScreen(
            categoryId: word.categoryId,
            categoryName: widget.categoryName,
            wordIds: [word.id],
            expectedOwnerId: owner,
            promptKind: QuizPromptKind.sentenceScramble,
            originParentId: parentId,
            returnLabel: returnLabel,
          ),
        ),
      ),
    );
  }

  String _scrambleHint(QuizQuestion question, bool sentence) {
    final correct = question.correctAnswer.split(sentence ? ' ' : '');
    for (final (position, index) in _scrambleOrder.indexed) {
      if (question.scrambleTokens[index] != correct[position]) {
        return '${sentence ? 'คำ' : 'ตัวอักษร'}ลำดับที่ ${position + 1} ยังสลับอยู่';
      }
    }
    return 'ตรวจลำดับอีกครั้ง';
  }

  ({Color background, Color foreground})? _answerColors(
    QuizQuestion question,
    String option,
  ) {
    if (!_answered) return null;
    final colors = Theme.of(context).colorScheme;
    if (QuizChoiceResponse(
      slot: _index,
      selectedOption: question.options.indexOf(option),
    ).isCorrectFor(question)) {
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

  Future<void> _record(
    QuizQuestion question,
    String? option, {
    bool reveal = false,
  }) async {
    if (_saving || _answered) return;
    final learning = _learning;
    final session = _session;
    if (learning == null || session == null) return;
    final generation = _generation;
    if (!_current(generation) ||
        !_hasChoiceContrast(session) ||
        !identical(question, session.questions[_index])) {
      return;
    }
    if (_attemptId == null) {
      _selected = option;
      _revealed = reveal;
    }
    final response = question.kind.isScramble
        ? QuizOrderResponse(slot: _index, indexes: _scrambleOrder)
        : question.kind == QuizPromptKind.clozeTyped && !_revealed
        ? QuizTextResponse(slot: _index, text: _selected!)
        : QuizChoiceResponse(
            slot: _index,
            selectedOption: _revealed
                ? null
                : question.options.indexOf(_selected!),
          );
    final correct = response.isCorrectFor(question);
    _submittedAtUtc ??= DateTime.now().toUtc();
    _responseTimeMs ??= _round != null
        ? _elapsed
        : DateTime.now()
              .difference(_questionStartedAt ?? DateTime.now())
              .inMilliseconds;
    _attemptId ??= 'attempt:${const Uuid().v4()}';
    setState(() {
      _stopPromptVoice();
      _saving = true;
    });
    try {
      final round = _round;
      final result = await learning.recordAnswer(
        sessionId: session.id,
        wordId: question.word.id,
        promptMode: question.kind.name,
        isCorrect: correct,
        responseTimeMs: _responseTimeMs,
        attemptNumber: _committedAnswers + 1,
        attemptId: _attemptId,
        occurredAtUtc: _submittedAtUtc,
        expectedOwnerId: _ownerId,
        quiz: round == null
            ? null
            : (expectedRevision: round.cursor.revision, response: response),
      );
      if (!_current(generation)) return;
      setState(() {
        _answered = true;
        _responseCorrect = correct;
        _saving = false;
        _answerSaveFailed = false;
        if (result.durableRound case final saved?) {
          _applyRound(saved);
        } else {
          _committedAnswers++;
        }
        if (result.durableRound == null &&
            !correct &&
            !_mistakes.any((word) => word.id == question.word.id)) {
          _mistakes.add(question.word);
        }
      });
      if (_pauseAfterWrite && _round != null) {
        _pauseAfterWrite = false;
        await _advanceDurable(QuizStep.pause);
      }
      if (!result.inserted || !_current(generation)) return;
      try {
        if (correct) {
          await HapticFeedback.lightImpact();
        } else {
          await HapticFeedback.vibrate();
        }
      } catch (_) {
        // Device feedback must not turn a committed answer into a retry.
      }
    } on QuizVocabularyChanged {
      if (!_current(generation)) return;
      _questionClock.stop();
      setState(() {
        _saving = false;
        _vocabularyChanged = true;
      });
    } catch (_) {
      if (!mounted || !_current(generation)) return;
      setState(() {
        _saving = false;
        _answerSaveFailed = true;
      });
    }
  }

  void _submitTypedCloze(QuizQuestion question) {
    final text = _typedAnswer.text;
    if (_attemptId != null) return;
    try {
      normalizeQuizClozeAnswer(text);
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรอกคำตอบในบรรทัดเดียว ไม่เกิน 120 อักขระ'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _record(question, text.trim());
  }

  void _retryQuestion() {
    if (_saving || !_answered || !_current(_generation)) return;
    if (_round != null) {
      _advanceDurable(QuizStep.retryQuestion);
      return;
    }
    setState(() {
      _answered = false;
      _responseCorrect = false;
      _selected = null;
      _revealed = false;
      _hintVisible = false;
      _attemptId = null;
      _submittedAtUtc = null;
      _responseTimeMs = null;
      _questionStartedAt = DateTime.now();
    });
  }

  Future<void> _next() async {
    final generation = _generation;
    if (_saving || !_answered || !_current(generation)) return;
    final session = _session!;
    final learning = _learning!;
    if (_index < session.questions.length - 1) {
      if (_round != null) {
        await _advanceDurable(QuizStep.next);
        return;
      }
      setState(() {
        _index++;
        _answered = false;
        _selected = null;
        _revealed = false;
        _hintVisible = false;
        _attemptId = null;
        _submittedAtUtc = null;
        _responseTimeMs = null;
        _questionStartedAt = DateTime.now();
      });
      return;
    }
    final planned = _round != null;
    final finished = planned ? await _advanceDurable(QuizStep.finish) : null;
    if (!mounted ||
        !_current(generation) ||
        (planned && finished?.summary == null)) {
      return;
    }
    if (widget.promptKind.isCloze && finished?.summary != null) {
      final onComplete = widget.onClozeComplete;
      if (onComplete == null) {
        Navigator.of(context).pop();
      } else {
        onComplete();
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final summary =
          finished?.summary ??
          await learning.finishSession(session.id, expectedOwnerId: _ownerId);
      if (!mounted || !_current(generation)) return;
      final mistakes = List<QuizWord>.unmodifiable(_mistakes);
      final mistakeIds = List<String>.unmodifiable(
        mistakes.map((word) => word.id).toSet(),
      );
      final categoryId = widget.categoryId;
      final categoryName = finished?.plan.categoryName ?? widget.categoryName;
      final returnLabel = _returnLabel;
      final promptKind = widget.promptKind;
      final expectedOwnerId = _ownerId;
      final linkedWeakness =
          _selectionMode == QuizWordSelectionMode.weakness &&
          _originParentId != null;
      final canPracticeMistakes =
          _canPracticeMistakes && !promptKind.isScramble;
      final solved = finished?.plan.questions.last.word;
      final canOrderSentence =
          promptKind == QuizPromptKind.wordScramble &&
          _responseCorrect &&
          solved != null &&
          ScramblePromptPolicy.sentenceFor(solved) != null;
      bool? scoreAdmitted;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/score',
          builder: (scoreContext) {
            scoreAdmitted ??= !linkedWeakness || _current(generation);
            if (scoreAdmitted == false) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(
                  child: Text('กรุณากลับไปเปิดผลการฝึกอีกครั้ง'),
                ),
              );
            }
            return ScoreScreen(
              correctAnswers: summary.correctCount,
              wrongAnswers: summary.wrongCount,
              score: summary.score,
              categoryName: categoryName,
              sessionId: summary.id,
              expectedOwnerId: expectedOwnerId,
              returnLabel: returnLabel,
              mistakes: mistakes,
              onOpenSentence: canOrderSentence
                  ? (from) => _openSentence(
                      from,
                      summary.id,
                      solved,
                      'กลับไปดูผลสะกดคำ',
                    )
                  : null,
              onPracticeMistakes: mistakes.isEmpty || !canPracticeMistakes
                  ? null
                  : () => _practiceMistakes(
                      scoreContext,
                      generation: generation,
                      learning: learning,
                      wordIds: mistakeIds,
                      categoryId: categoryId,
                      categoryName: categoryName,
                      returnLabel: returnLabel,
                      promptKind: promptKind,
                      expectedOwnerId: expectedOwnerId,
                    ),
            );
          },
        ),
      );
      if (mounted &&
          _current(generation) &&
          ModalRoute.isCurrentOf(context) == true) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted || !_current(generation)) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('จบรอบการฝึกไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  Future<void> _practiceMistakes(
    BuildContext scoreContext, {
    required int generation,
    required LearningUseCases learning,
    required List<String> wordIds,
    required String? categoryId,
    required String? categoryName,
    required String returnLabel,
    required QuizPromptKind promptKind,
    required String? expectedOwnerId,
  }) async {
    if (!_current(generation) ||
        _practicingMistakes ||
        !_canPracticeMistakes ||
        !identical(_learning, learning) ||
        !scoreContext.mounted ||
        ModalRoute.of(scoreContext)?.isCurrent != true) {
      return;
    }
    _practicingMistakes = true;
    final features = _features;
    try {
      await AppNavigator.pushPage<void>(
        scoreContext,
        AppPage<void>(
          name: 'learning/mistake-practice',
          builder: (_) => QuizScreen(
            categoryId: categoryId,
            wordIds: wordIds,
            originParentId: _session?.id,
            categoryName: categoryName,
            returnLabel: returnLabel,
            learning: learning,
            featureRegistry: features,
            promptKind: promptKind,
            expectedOwnerId: expectedOwnerId,
          ),
        ),
      );
      if (_current(generation) &&
          scoreContext.mounted &&
          ModalRoute.of(scoreContext)?.isCurrent == true) {
        Navigator.of(scoreContext).pop();
      }
    } finally {
      if (_current(generation)) _practicingMistakes = false;
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
  });

  final IconData icon;
  final String message;
  final bool liveRegion;
  final String? actionLabel;
  final VoidCallback? onAction;

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
