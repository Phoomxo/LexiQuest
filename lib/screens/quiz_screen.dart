import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
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
  });

  final String? categoryId;
  final String? categoryName;
  final String? returnLabel;
  final LearningUseCases? learning;
  final List<String>? wordIds;
  final FieldFeatureRegistry? featureRegistry;
  final QuizWordSelectionMode selectionMode;

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
  int _generation = 0;
  bool _addingWords = false;

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
      (widget.categoryName == null ? 'กลับไปเลือกกิจกรรม' : 'กลับไปที่ชุดคำ');

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

  void _bindLearning({bool reload = false}) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (dependencies != null) _wasScoped = true;
    final learning = _currentLearning;
    if (!reload &&
        _load != null &&
        identical(dependencies, _dependencies) &&
        identical(learning, _learning) &&
        widget.categoryId == _categoryId &&
        listEquals(widget.wordIds, _wordIds) &&
        widget.selectionMode == _selectionMode) {
      return;
    }
    _dependencies = dependencies;
    _learning = learning;
    _categoryId = widget.categoryId;
    _wordIds = widget.wordIds == null
        ? null
        : List.unmodifiable(widget.wordIds!);
    _selectionMode = widget.selectionMode;
    final generation = ++_generation;
    _ownerId = null;
    _session = null;
    _index = 0;
    _answered = false;
    _saving = false;
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
    _load = _startSession(learning, generation);
    _load!.ignore();
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      identical(AppDependenciesScope.maybeOf(context), _dependencies) &&
      identical(_currentLearning, _learning) &&
      widget.categoryId == _categoryId &&
      listEquals(widget.wordIds, _wordIds) &&
      widget.selectionMode == _selectionMode;

  Future<QuizSession> _startSession(
    LearningUseCases? learning,
    int generation,
  ) async {
    if (learning == null) {
      throw StateError('local learning dependency unavailable');
    }
    final owner = await learning.owners.getOrCreateActiveOwner();
    if (!_current(generation)) throw StateError('quiz context changed');
    final session = _wordIds == null
        ? await learning.startQuiz(categoryId: _categoryId)
        : _selectionMode == QuizWordSelectionMode.sourcePractice
        ? await learning.startSourcePracticeForWords(wordIds: _wordIds!)
        : await learning.startWeaknessPractice(wordIds: _wordIds!);
    final currentOwner = await learning.owners.getOrCreateActiveOwner();
    if (!_current(generation) || currentOwner.id != owner.id) {
      throw StateError('quiz context changed');
    }
    _ownerId = owner.id;
    return session;
  }

  bool _hasChoiceContrast(QuizSession session) => session.questions.every(
    (question) => question.options.toSet().length >= 2,
  );

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
        child: FutureBuilder<QuizSession>(
          key: ValueKey(_generation),
          future: _load,
          builder: (context, snapshot) {
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
              return const _QuizMessage(
                icon: Icons.library_add_outlined,
                message: 'ยังไม่มีคำศัพท์สำหรับแบบทดสอบ กรุณาเพิ่มคำศัพท์ก่อน',
              );
            }
            if (!_hasChoiceContrast(session)) return _buildOneChoiceFallback();
            _session ??= session;
            _questionStartedAt ??= DateTime.now();
            return _buildQuestion(session);
          },
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
                      '${question.word.spelling} — ${question.correctAnswer}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
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
    _responseTimeMs ??= DateTime.now()
        .difference(_questionStartedAt ?? DateTime.now())
        .inMilliseconds;
    _attemptId ??= 'attempt:${const Uuid().v4()}';
    setState(() {
      _saving = true;
    });
    try {
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: question.word.id,
        promptMode: 'meaningChoice',
        isCorrect: correct,
        responseTimeMs: _responseTimeMs,
        attemptNumber: _index + 1,
        attemptId: _attemptId,
        occurredAtUtc: _submittedAtUtc,
      );
      if (!_current(generation)) return;
      setState(() {
        _answered = true;
        _saving = false;
        if (!correct) _mistakes.add(question.word);
      });
      try {
        if (correct) {
          await HapticFeedback.lightImpact();
        } else {
          await HapticFeedback.vibrate();
        }
      } catch (_) {
        // Device feedback must not turn a committed answer into a retry.
      }
    } catch (_) {
      if (!mounted || !_current(generation)) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  Future<void> _next() async {
    final generation = _generation;
    if (_saving || !_answered || !_current(generation)) return;
    final session = _session!;
    final learning = _learning!;
    if (_index < session.questions.length - 1) {
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
    setState(() => _saving = true);
    try {
      final summary = await learning.finishSession(session.id);
      if (!mounted || !_current(generation)) return;
      final mistakes = List<QuizWord>.unmodifiable(_mistakes);
      final mistakeIds = List<String>.unmodifiable(
        mistakes.map((word) => word.id).toSet(),
      );
      final categoryId = widget.categoryId;
      final categoryName = widget.categoryName;
      final returnLabel = _returnLabel;
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
            categoryName: categoryName,
            returnLabel: returnLabel,
            learning: learning,
            featureRegistry: features,
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
