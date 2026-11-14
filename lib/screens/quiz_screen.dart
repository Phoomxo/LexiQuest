import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import '../features/learning/domain/quiz_round.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'score_screen.dart';
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

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  LearningUseCases? _learning;
  Future<QuizSession>? _load;
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
      _round?.plan.returnLabel ??
      widget.returnLabel ??
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
    _questionClock.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
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

  void _bindLearning({bool reload = false, bool skipUnavailable = false}) {
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
    final generation = ++_generation;
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
    _mistakes.clear();
    _load = _startSession(learning, generation, skipUnavailable);
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
      widget.expectedOwnerId == _expectedOwnerId;

  void _hideForOwnerChange() {
    if (!mounted || _ownerChanged) return;
    _questionClock.stop();
    setState(() {
      _ownerChanged = true;
      _generation++;
      _session = null;
      _round = null;
      _saving = false;
    });
  }

  Future<QuizSession> _startSession(
    LearningUseCases? learning,
    int generation,
    bool skipUnavailable,
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
    final session = _wordIds == null
        ? await learning.startQuiz(
            categoryId: _categoryId,
            kind: widget.promptKind,
            expectedOwnerId: owner.id,
            origin: origin,
            skipUnavailable: skipUnavailable,
            categoryName: widget.categoryName,
            returnLabel: _returnLabel,
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
            kind: widget.promptKind,
            expectedOwnerId: owner.id,
            origin: origin,
            skipUnavailable: skipUnavailable,
            categoryName: widget.categoryName,
            returnLabel: _returnLabel,
          );
    final currentOwner = await learning.owners.getOrCreateActiveOwner();
    if (!_current(generation) || currentOwner.id != owner.id) {
      throw StateError('quiz context changed');
    }
    return session;
  }

  bool _hasChoiceContrast(QuizSession session) => session.questions.every(
    (question) => question.options.toSet().length >= 2,
  );

  int get _elapsed => (_activeElapsedMs + _questionClock.elapsedMilliseconds)
      .clamp(0, LearningEvidenceContract.maxResponseTimeMs);

  void _applyRound(QuizRound round) {
    _round = round;
    _index = round.cursor.slot;
    _committedAnswers = round.committedAnswers;
    _mistakes
      ..clear()
      ..addAll(round.mistakes);
    final response = round.feedback;
    _answered = response != null;
    _revealed = response != null && response.selectedOption == null;
    _selected = response?.selectedOption == null
        ? null
        : round.plan.questions[_index].options[response!.selectedOption!];
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
      canPop: !_saving,
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
                  actionLabel: _returnLabel,
                  onAction: () => Navigator.maybePop(context),
                )
              : FutureBuilder<QuizSession>(
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
                        },
                        actionLabel: _returnLabel,
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

  String get _title => widget.wordIds == null
      ? 'แบบทดสอบคำศัพท์'
      : widget.selectionMode == QuizWordSelectionMode.sourcePractice
      ? 'แบบทดสอบจากเนื้อหานี้'
      : 'ฝึกคำที่ผิด';

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
            }),
            const SizedBox(height: 12),
            Text(
              question.promptText,
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
                  onPressed: _saving || _attemptId != null
                      ? null
                      : () => setState(() => _hintVisible = !_hintVisible),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(_hintVisible ? 'ซ่อนคำใบ้' : 'ดูคำใบ้'),
                ),
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
                      '${question.word.spelling} — ${question.word.meaning}',
                    ),
                    if (question.optionWords?[_selected]
                        case final selectedWord?)
                      if (_selected != question.correctAnswer)
                        Text(
                          '${selectedWord.spelling} — ${selectedWord.meaning}',
                        ),
                    if (question.optionExplanations?[_selected]
                        case final explanation?)
                      Text(explanation),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_answered &&
                question.kind != QuizPromptKind.meaningChoice &&
                _selected != question.correctAnswer)
              OutlinedButton(
                onPressed: _saving ? null : _retryQuestion,
                child: const Text('ลองข้อเดิม'),
              ),
            if (_answered)
              FilledButton(
                onPressed: _saving ? null : _next,
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
    final correct = !_revealed && _selected == question.correctAnswer;
    _submittedAtUtc ??= DateTime.now().toUtc();
    _responseTimeMs ??= _round != null
        ? _elapsed
        : DateTime.now()
              .difference(_questionStartedAt ?? DateTime.now())
              .inMilliseconds;
    _attemptId ??= 'attempt:${const Uuid().v4()}';
    setState(() {
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
            : (
                expectedRevision: round.cursor.revision,
                response: (
                  slot: round.cursor.slot,
                  selectedOption: _revealed
                      ? null
                      : question.options.indexOf(_selected!),
                ),
              ),
      );
      if (!_current(generation)) return;
      setState(() {
        _answered = true;
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

  void _retryQuestion() {
    if (_saving || !_answered || !_current(_generation)) return;
    if (_round != null) {
      _advanceDurable(QuizStep.retryQuestion);
      return;
    }
    setState(() {
      _answered = false;
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
    if (!_current(generation) || (planned && finished?.summary == null)) return;
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
      final canPracticeMistakes = _canPracticeMistakes;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/score',
          builder: (scoreContext) => ScoreScreen(
            correctAnswers: summary.correctCount,
            wrongAnswers: summary.wrongCount,
            score: summary.score,
            categoryName: categoryName,
            sessionId: summary.id,
            expectedOwnerId: expectedOwnerId,
            returnLabel: returnLabel,
            mistakes: mistakes,
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
          ),
        ),
      );
      if (mounted && _current(generation)) Navigator.of(context).pop();
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
