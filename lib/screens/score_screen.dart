import 'package:flutter/material.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/recorded_time_view.dart';
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
    this.learningTime,
    this.resultOwnerId,
    this.resultSessionId,
    this.languageCode = 'th',
  });

  final int correctAnswers;
  final int wrongAnswers;
  final int? score;
  final List<QuizWord> mistakes;
  final VoidCallback? onPracticeMistakes;
  final VoidCallback? onBack;
  final LearningTimeUseCases? learningTime;
  final String? resultOwnerId;
  final String? resultSessionId;
  final String languageCode;

  /// Retained for source compatibility; score data is always local-first.
  final bool isFromFirestore;
  final String? selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final thai = languageCode == 'th';
    final total = correctAnswers + wrongAnswers;
    final resolvedScore =
        score ?? (total == 0 ? 0 : ((correctAnswers * 100) / total).round());
    return LessonScaffold(
      title: thai ? 'ผลการเรียน' : 'Results',
      leading: onBack == null ? null : BackButton(onPressed: onBack),
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
                  label: thai ? 'ตอบถูก' : 'Correct',
                  value: correctAnswers,
                  icon: Icons.check_circle_outline,
                ),
                _ResultRow(
                  label: thai ? 'ตอบผิด' : 'Incorrect',
                  value: wrongAnswers,
                  icon: Icons.cancel_outlined,
                ),
                _ResultRow(
                  label: thai ? 'คำตอบที่ใช้คำนวณ' : 'Answers counted',
                  value: total,
                  icon: Icons.dataset_outlined,
                ),
                const SizedBox(height: 24),
                if (learningTime != null &&
                    resultOwnerId?.trim().isNotEmpty == true &&
                    resultSessionId?.trim().isNotEmpty == true) ...[
                  RecordedTimeView(
                    key: ValueKey((
                      resultOwnerId,
                      resultSessionId,
                      learningTime?.ownerGeneration,
                    )),
                    time: learningTime,
                    expectedOwnerId: resultOwnerId!,
                    target: SessionTimeRead(resultSessionId!),
                    languageCode: languageCode,
                    collapseExplanation: true,
                  ),
                  const SizedBox(height: 24),
                ],
                if (mistakes.isNotEmpty) ...[
                  Text(
                    thai ? 'คำที่ควรฝึกต่อ' : 'Words to practise',
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
                      label: Text(
                        thai
                            ? 'ฝึกคำที่ผิด (${mistakes.length})'
                            : 'Practise mistakes (${mistakes.length})',
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: onBack ?? () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(thai ? 'ย้อนกลับ' : 'Back'),
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
