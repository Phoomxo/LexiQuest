import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/domain/evidence_context.dart';
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
  });

  final String? categoryId;
  final LearningUseCases? learning;
  final List<String>? wordIds;
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
  bool _hintEverUsed = false;
  bool _revealed = false;
  EvidenceContext? _pendingEvidence;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    _learning =
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
    final learning = _learning;
    _load = learning == null
        ? Future<QuizSession>.error(
            StateError('local learning dependency unavailable'),
          )
        : widget.wordIds == null
        ? learning.startQuiz(categoryId: widget.categoryId)
        : widget.selectionMode == QuizWordSelectionMode.sourcePractice
        ? learning.startSourcePracticeForWords(wordIds: widget.wordIds!)
        : learning.startWeaknessPractice(wordIds: widget.wordIds!);
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
                  onPressed: _saving || _attemptId != null
                      ? null
                      : () => setState(() {
                          _hintVisible = !_hintVisible;
                          _hintEverUsed = true;
                        }),
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
    _pendingEvidence ??= captureCurrentActivityEvidence(
      promptMode: 'meaningChoice',
      contentRevision: question.word.contentRevision,
      hintLevel: _revealed
          ? 2
          : _hintEverUsed
          ? 1
          : 0,
    );
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
        evidenceContext: _pendingEvidence,
      );
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  Future<void> _next() async {
    if (_saving) return;
    final session = _session!;
    if (_index < session.questions.length - 1) {
      setState(() {
        _index++;
        _answered = false;
        _selected = null;
        _revealed = false;
        _hintVisible = false;
        _hintEverUsed = false;
        _pendingEvidence = null;
        _attemptId = null;
        _submittedAtUtc = null;
        _responseTimeMs = null;
        _questionStartedAt = DateTime.now();
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final summary = await _learning!.finishSession(session.id);
      if (!mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/score',
          builder: (scoreContext) => ScoreScreen(
            correctAnswers: summary.correctCount,
            wrongAnswers: summary.wrongCount,
            score: summary.score,
            mistakes: List.unmodifiable(_mistakes),
            onPracticeMistakes: _mistakes.isEmpty
                ? null
                : () => _practiceMistakes(scoreContext),
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('จบรอบการฝึกไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  Future<void> _practiceMistakes(BuildContext scoreContext) async {
    if (_practicingMistakes) return;
    _practicingMistakes = true;
    try {
      await AppNavigator.pushPage<void>(
        scoreContext,
        AppPage<void>(
          name: 'learning/mistake-practice',
          builder: (_) => QuizScreen(
            wordIds: _mistakes.map((word) => word.id).toSet().toList(),
            learning: _learning,
          ),
        ),
      );
      if (scoreContext.mounted) Navigator.of(scoreContext).pop();
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
