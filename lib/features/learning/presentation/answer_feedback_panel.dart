import 'package:flutter/material.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../review/domain/learner_intent.dart';
import '../domain/answer_feedback.dart';

final class AnswerFeedbackPanel extends StatelessWidget {
  const AnswerFeedbackPanel({
    super.key,
    required this.feedback,
    this.onRetry,
    this.onNext,
    this.bookmarkIdentity,
    this.onBookmark,
  });

  final AnswerFeedback feedback;
  final VoidCallback? onRetry;
  final VoidCallback? onNext;
  final ContentIdentity? bookmarkIdentity;
  final BookmarkLearningItemAction? onBookmark;

  @override
  Widget build(BuildContext context) {
    final isCorrect = feedback.isCorrect;
    final callback = isCorrect ? onNext : onRetry;
    final icon = isCorrect ? Icons.check_circle : Icons.cancel;
    return Semantics(
      key: const ValueKey<String>('answer-feedback-panel'),
      container: true,
      explicitChildNodes: true,
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
              if (bookmarkIdentity case final identity?)
                if (onBookmark case final bookmark?) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    container: true,
                    explicitChildNodes: true,
                    button: true,
                    label: 'Save for review',
                    child: ExcludeSemantics(
                      child: OutlinedButton.icon(
                        onPressed: () => bookmark(identity),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save for review'),
                      ),
                    ),
                  ),
                ],
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
