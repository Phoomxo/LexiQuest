import 'learning_models.dart';

enum AnswerFeedbackAction { retry, next }

/// Reviewed display context captured with the learner's immutable submission.
/// It is presentation-only and never becomes evidence or a persisted score.
final class AnswerFeedbackContext {
  const AnswerFeedbackContext({required this.canonicalCorrectAnswer});

  final String canonicalCorrectAnswer;

  /// Produces the immutable display value that is safe to retain with a
  /// pending submission before any evidence write begins.
  AnswerFeedbackContext normalized() {
    final correctAnswer = canonicalCorrectAnswer.trim();
    if (correctAnswer.isEmpty) {
      throw ArgumentError.value(
        canonicalCorrectAnswer,
        'canonicalCorrectAnswer',
        'must not be blank',
      );
    }
    return AnswerFeedbackContext(canonicalCorrectAnswer: correctAnswer);
  }
}

/// A pure learner-facing interpretation of one already committed answer.
final class AnswerFeedback {
  factory AnswerFeedback.fromCommittedResult({
    required AnswerRecordResult result,
    required AnswerFeedbackContext context,
  }) {
    final frozenContext = context.normalized();
    return AnswerFeedback._(
      isCorrect: result.isCorrect,
      canonicalCorrectAnswer: frozenContext.canonicalCorrectAnswer,
    );
  }

  const AnswerFeedback._({
    required this.isCorrect,
    required this.canonicalCorrectAnswer,
  });

  final bool isCorrect;
  final String canonicalCorrectAnswer;

  AnswerFeedbackAction get nextAction =>
      isCorrect ? AnswerFeedbackAction.next : AnswerFeedbackAction.retry;

  String get statusLabel => isCorrect ? 'Correct' : 'Not quite';

  String get actionLabel =>
      nextAction == AnswerFeedbackAction.next ? 'Next question' : 'Try again';

  String get semanticAnnouncement =>
      '$statusLabel. Correct answer: $canonicalCorrectAnswer. $actionLabel.';
}
