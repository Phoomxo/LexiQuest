import 'package:flutter/material.dart';
import '../features/learning/domain/learning_models.dart';
import '../runtime/app_dependencies.dart';
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
  });

  final int correctAnswers;
  final int wrongAnswers;
  final int? score;
  final List<QuizWord> mistakes;
  final VoidCallback? onPracticeMistakes;
  final String? categoryName;
  final String? sessionId;
  final String returnLabel;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = AppDependenciesScope.maybeOf(context);
    if (!_captured) {
      _dependencies = current;
      _captured = true;
    } else if (!identical(current, _dependencies)) {
      _invalidated = true;
    }
  }

  bool get _isCurrent =>
      mounted &&
      !_invalidated &&
      identical(AppDependenciesScope.maybeOf(context), _dependencies);

  bool get _canAct => _isCurrent && (ModalRoute.of(context)?.isCurrent ?? true);

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
                  const SizedBox(height: 12),
                ],
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
