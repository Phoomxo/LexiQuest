import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../runtime/app_dependencies.dart';
import 'score_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, this.categoryId, this.learning});

  final String? categoryId;
  final LearningUseCases? learning;

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
        : learning.startQuiz(categoryId: widget.categoryId);
    _load!.then((session) {
      if (!mounted) return;
      _session = session;
      _questionStartedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  Widget _buildQuestion(QuizSession session) {
    final question = session.questions[_index];
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
                  onPressed: _answered || _saving
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

  Color? _answerColor(QuizQuestion question, String option) {
    if (!_answered) return null;
    if (option == question.correctAnswer) return Colors.green.shade100;
    if (option == _selected) return Colors.red.shade100;
    return null;
  }

  Future<void> _record(QuizQuestion question, String option) async {
    final learning = _learning;
    final session = _session;
    if (learning == null || session == null) return;
    final correct = option == question.correctAnswer;
    setState(() {
      _saving = true;
      _selected = option;
    });
    final elapsed = DateTime.now().difference(
      _questionStartedAt ?? DateTime.now(),
    );
    try {
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: question.word.id,
        promptMode: 'meaningChoice',
        isCorrect: correct,
        responseTimeMs: elapsed.inMilliseconds,
        attemptNumber: _index + 1,
      );
      if (!mounted) return;
      if (correct) {
        await HapticFeedback.lightImpact();
      } else {
        await HapticFeedback.vibrate();
      }
      setState(() {
        _answered = true;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
  }

  Future<void> _next() async {
    final session = _session!;
    if (_index < session.questions.length - 1) {
      setState(() {
        _index++;
        _answered = false;
        _selected = null;
        _questionStartedAt = DateTime.now();
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final summary = await _learning!.finishSession(session.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScoreScreen(
            correctAnswers: summary.correctCount,
            wrongAnswers: summary.wrongCount,
            score: summary.score,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ปิด session ไม่สำเร็จ กรุณาลองอีกครั้ง')),
      );
    }
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
