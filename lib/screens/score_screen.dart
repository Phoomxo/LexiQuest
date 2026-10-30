import 'package:flutter/material.dart';
import '../features/learning/domain/learning_models.dart';
import '../widgets/adaptive_content_pane.dart';

class ScoreScreen extends StatelessWidget {
  const ScoreScreen({
    super.key,
    required this.correctAnswers,
    required this.wrongAnswers,
    this.score,
    this.isFromFirestore = false,
    this.selectedCategoryId,
    this.mistakes = const [],
    this.onPracticeMistakes,
    this.onBack,
  });

  final int correctAnswers;
  final int wrongAnswers;
  final int? score;
  final List<QuizWord> mistakes;
  final VoidCallback? onPracticeMistakes;
  final VoidCallback? onBack;

  /// Retained for source compatibility; score data is always local-first.
  final bool isFromFirestore;
  final String? selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final total = correctAnswers + wrongAnswers;
    final resolvedScore =
        score ?? (total == 0 ? 0 : ((correctAnswers * 100) / total).round());
    return Scaffold(
      appBar: AppBar(
        title: const Text('ผลการเรียน'),
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$resolvedScore%',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 20),
                _ResultRow(
                  label: 'ตอบถูก',
                  value: correctAnswers,
                  icon: Icons.check_circle_outline,
                ),
                _ResultRow(
                  label: 'ตอบผิด',
                  value: wrongAnswers,
                  icon: Icons.cancel_outlined,
                ),
                _ResultRow(
                  label: 'คำตอบที่ใช้คำนวณ',
                  value: total,
                  icon: Icons.dataset_outlined,
                ),
                const SizedBox(height: 24),
                if (mistakes.isNotEmpty) ...[
                  Text(
                    'คำที่ควรฝึกต่อ',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ...mistakes.map(
                    (word) => ListTile(
                      title: Text(word.spelling),
                      subtitle: Text(word.meaning),
                    ),
                  ),
                  if (onPracticeMistakes != null)
                    FilledButton.icon(
                      onPressed: onPracticeMistakes,
                      icon: const Icon(Icons.refresh),
                      label: Text('ฝึกคำที่ผิด (${mistakes.length})'),
                    ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: onBack ?? () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('กลับไปเลือกกิจกรรม'),
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
