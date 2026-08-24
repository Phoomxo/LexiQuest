import 'package:flutter/material.dart';

import '../domain/answer_feedback.dart';

final class AnswerFeedbackPanel extends StatelessWidget {
  const AnswerFeedbackPanel({
    super.key,
    required this.feedback,
    this.onRetry,
    this.onNext,
  });

  final AnswerFeedback feedback;
  final VoidCallback? onRetry;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final isCorrect = feedback.isCorrect;
    final callback = isCorrect ? onNext : onRetry;
    final icon = isCorrect ? Icons.check_circle : Icons.cancel;
    return Semantics(
      key: const ValueKey<String>('answer-feedback-panel'),
      container: true,
      liveRegion: true,
      label: feedback.semanticAnnouncement,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, semanticLabel: feedback.statusLabel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feedback.statusLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Correct answer: ${feedback.canonicalCorrectAnswer}'),
              const SizedBox(height: 12),
              if (callback != null)
                FilledButton(
                  onPressed: callback,
                  child: Text(feedback.actionLabel),
                )
              else
                Text('Next action: ${feedback.actionLabel}'),
            ],
          ),
        ),
      ),
    );
  }
}
