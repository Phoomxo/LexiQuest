import 'dart:async';

import 'package:flutter/material.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/cloze_prompt_policy.dart';
import '../features/progress/domain/progress_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import 'fill_in_the_blanks_screen.dart';
import '../widgets/adaptive_content_pane.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({
    super.key,
    required this.correctAnswers,
    required this.wrongAnswers,
    this.score,
    this.isFromFirestore = false,
    this.selectedCategoryId,
    this.mistakes = const [],
    this.onPracticeMistakes,
    this.categoryName,
    this.sessionId,
    this.returnLabel = 'กลับไปเลือกกิจกรรม',
    this.showOriginalHistory = false,
    this.originalAnswers,
    this.originalRecallAnswers,
    this.expectedOwnerId,
    this.onOpenReviewDesk,
    this.onOpenSentence,
    this.sourceSentence,
  });

  final int correctAnswers;
  final int wrongAnswers;
  final int? score;
  final List<QuizWord> mistakes;
  final VoidCallback? onPracticeMistakes;
  final String? categoryName;
  final String? sessionId;
  final String returnLabel;
  final bool showOriginalHistory;
  final List<OriginalQuizAnswer>? originalAnswers;
  final List<OriginalSrsRecallAnswer>? originalRecallAnswers;
  final String? expectedOwnerId;
  final ValueChanged<BuildContext>? onOpenReviewDesk;
  final ValueChanged<BuildContext>? onOpenSentence;
  final String? sourceSentence;

  /// Retained for source compatibility; score data is always local-first.
  final bool isFromFirestore;
  final String? selectedCategoryId;

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  AppDependencies? _dependencies;
  bool _captured = false;
  bool _invalidated = false;
  bool _openingCloze = false;
  Future<bool>? _clozeAvailable;
  StreamSubscription<String?>? _ownerChanges;
  StreamSubscription<void>? _ownerWrites;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = AppDependenciesScope.maybeOf(context);
    if (!_captured) {
      _dependencies = current;
      _captured = true;
      final ownerId = widget.expectedOwnerId;
      if (ownerId != null) {
        _ownerChanges = current?.watchActiveOwnerId()?.listen((active) {
          if (active != ownerId) _hideResult();
        }, onError: (Object _) => _hideResult());
        _ownerWrites = current?.watchLocalOwnerWrites()?.listen(
          (_) => _hideResult(),
          onError: (Object _) => _hideResult(),
        );
      }
      _prepareCloze();
    } else if (!identical(current, _dependencies)) {
      _invalidated = true;
    }
  }

  @override
  void didUpdateWidget(covariant ScoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.mistakes, widget.mistakes)) {
      _prepareCloze();
    }
  }

  void _prepareCloze() {
    _clozeAvailable = _canCheckCloze
        ? _dependencies!.learning!.hasClozeRepair(
            parentSessionId: widget.sessionId!,
            expectedOwnerId: widget.expectedOwnerId!,
          )
        : null;
    _clozeAvailable?.ignore();
  }

  void _hideResult() {
    if (mounted && !_invalidated) setState(() => _invalidated = true);
  }

  @override
  void dispose() {
    unawaited(_ownerChanges?.cancel());
    unawaited(_ownerWrites?.cancel());
    super.dispose();
  }

  bool get _isCurrent =>
      mounted &&
      !_invalidated &&
      identical(AppDependenciesScope.maybeOf(context), _dependencies);

  bool get _canAct => _isCurrent && (ModalRoute.of(context)?.isCurrent ?? true);

  bool get _canCheckCloze =>
      widget.sessionId != null &&
      widget.expectedOwnerId != null &&
      (_dependencies?.learning?.supportsDurableQuiz ?? false) &&
      (_dependencies?.fieldFeatures.isVisible(FieldFeature.quiz) ?? false) &&
      (_dependencies?.fieldFeatures.isVisible(FieldFeature.weakness) ??
          false) &&
      widget.mistakes.any(ClozePromptPolicy.supportsTarget);

  Future<void> _openCloze() async {
    if (!_canAct || !_canCheckCloze || _openingCloze) return;
    _openingCloze = true;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/cloze-repair',
          builder: (clozeContext) => FillInTheBlanksScreen(
            kind: QuizPromptKind.clozeChoice,
            expectedOwnerId: widget.expectedOwnerId,
            parentSessionId: widget.sessionId,
            categoryName: widget.categoryName,
            onComplete: () =>
                AppNavigator.resetTo<void>(clozeContext, AppRoute.home),
          ),
        ),
      );
    } finally {
      _openingCloze = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCurrent) {
      return Scaffold(
        appBar: AppBar(title: const Text('ผลการเรียน')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('กรุณากลับไปเปิดผลการฝึกอีกครั้ง'),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    if (mounted &&
                        (ModalRoute.of(context)?.isCurrent ?? true)) {
                      Navigator.of(context).maybePop();
                    }
                  },
                  child: const Text('กลับ'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final total = widget.correctAnswers + widget.wrongAnswers;
    final resolvedScore =
        widget.score ??
        (total == 0 ? 0 : ((widget.correctAnswers * 100) / total).round());
    return Scaffold(
      key: widget.sessionId == null
          ? null
          : ValueKey('score-session:${widget.sessionId}'),
      appBar: AppBar(title: const Text('ผลการเรียน')),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.categoryName != null) ...[
                  Text(
                    widget.categoryName!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  '$resolvedScore%',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 20),
                _ResultRow(
                  label: 'ตอบถูก',
                  value: widget.correctAnswers,
                  icon: Icons.check_circle_outline,
                ),
                _ResultRow(
                  label: 'ตอบผิด',
                  value: widget.wrongAnswers,
                  icon: Icons.cancel_outlined,
                ),
                _ResultRow(
                  label: 'คำตอบที่ใช้คำนวณ',
                  value: total,
                  icon: Icons.dataset_outlined,
                ),
                const SizedBox(height: 24),
                if (widget.sourceSentence case final sentence?
                    when sentence.isNotEmpty)
                  ListTile(
                    title: const Text('ประโยคที่แต่ง'),
                    subtitle: Text(sentence),
                  ),
                if (widget.onOpenSentence case final openSentence?)
                  OutlinedButton(
                    onPressed: () {
                      if (_canAct) openSentence(context);
                    },
                    child: const Text('ลองเรียงประโยค'),
                  ),
                if (widget.showOriginalHistory) ...[
                  Text(
                    'คำตอบจากรอบเดิม',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (widget.originalRecallAnswers case final recalls?)
                    for (final answer in recalls)
                      ListTile(
                        title: Text(answer.card.spelling),
                        subtitle: Text(
                          [
                            answer.card.meaning,
                            if (answer.card.partOfSpeech.isNotEmpty)
                              answer.card.partOfSpeech,
                            answer.remembered ? 'จำได้แล้ว' : 'ยังจำไม่ได้',
                          ].join('\n'),
                        ),
                      )
                  else if (widget.originalAnswers == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('ไม่มีข้อความโจทย์และคำตอบเดิมของรอบนี้'),
                    )
                  else
                    for (final answer in widget.originalAnswers!)
                      ListTile(
                        leading: Icon(
                          answer.isCorrect
                              ? Icons.check_circle_outline
                              : Icons.cancel_outlined,
                          semanticLabel: answer.isCorrect ? 'ตอบถูก' : 'ตอบผิด',
                        ),
                        title: Text(answer.question.promptText),
                        subtitle: Text(switch (answer.chosenAnswer) {
                          null => 'ครั้งก่อนขอดูคำตอบ',
                          final value
                              when answer.question.kind ==
                                  QuizPromptKind.clozeTyped =>
                            'ครั้งก่อนพิมพ์ $value',
                          final value => 'ครั้งก่อนเลือก $value',
                        }),
                      ),
                ],
                if (widget.mistakes.isNotEmpty) ...[
                  Text(
                    'คำที่ควรฝึกต่อ',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ...widget.mistakes.map(
                    (word) => ListTile(
                      title: Text(word.spelling),
                      subtitle: Text(word.meaning),
                    ),
                  ),
                  if (widget.onPracticeMistakes != null)
                    FilledButton.icon(
                      onPressed: () {
                        if (_canAct) widget.onPracticeMistakes?.call();
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text('ฝึกคำที่ผิด (${widget.mistakes.length})'),
                    ),
                  if (_clozeAvailable != null)
                    FutureBuilder<bool>(
                      key: ValueKey(widget.sessionId),
                      future: _clozeAvailable,
                      builder: (context, snapshot) =>
                          snapshot.connectionState == ConnectionState.done &&
                              snapshot.data == true &&
                              _canCheckCloze
                          ? OutlinedButton.icon(
                              onPressed: _openCloze,
                              icon: const Icon(Icons.edit_note_outlined),
                              label: const Text('ลองเติมคำนี้ในประโยค'),
                            )
                          : const SizedBox.shrink(),
                    ),
                  const SizedBox(height: 12),
                ],
                if (widget.onOpenReviewDesk case final openDesk?)
                  OutlinedButton.icon(
                    onPressed: () {
                      if (_canAct) openDesk(context);
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('เปิดศูนย์ทบทวน'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    if (_canAct) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(widget.returnLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text('$value'),
    );
  }
}
