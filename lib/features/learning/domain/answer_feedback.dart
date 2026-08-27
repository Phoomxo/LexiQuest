import 'learning_models.dart';
import 'contrastive_explanation.dart';
import '../../learning_packs/domain/content_manifest.dart';

enum AnswerFeedbackAction { retry, next }

/// Reviewed display context captured with the learner's immutable submission.
/// It is presentation-only and never becomes evidence or a persisted score.
final class AnswerFeedbackContext {
  const AnswerFeedbackContext({
    required this.canonicalCorrectAnswer,
    this.bookmarkIdentity,
  });

  final String canonicalCorrectAnswer;
  final ContentIdentity? bookmarkIdentity;

  /// Produces the immutable display value that is safe to retain with a
  /// pending submission before any evidence write begins.
  FrozenAnswerFeedbackContext freeze() {
    final correctAnswer = canonicalCorrectAnswer.trim();
    if (correctAnswer.isEmpty) {
      throw ArgumentError.value(
        canonicalCorrectAnswer,
        'canonicalCorrectAnswer',
        'must not be blank',
      );
    }
    final identity = bookmarkIdentity;
    if (identity != null &&
        (identity.id.isEmpty ||
            identity.id != identity.id.trim() ||
            identity.id.runes.length > 256 ||
            identity.revision <= 0)) {
      throw ArgumentError.value(
        identity,
        'bookmarkIdentity',
        'must contain canonical nonblank id and positive revision',
      );
    }
    return FrozenAnswerFeedbackContext._(
      canonicalCorrectAnswer: correctAnswer,
      bookmarkIdentity: identity,
    );
  }

  AnswerFeedbackContext normalized() => freeze().asContext;
}

/// Complete validated presentation context retained with a pending write.
/// Construction is private so publishing feedback from this value cannot fail.
final class FrozenAnswerFeedbackContext {
  const FrozenAnswerFeedbackContext._({
    required this.canonicalCorrectAnswer,
    required this.bookmarkIdentity,
  });

  final String canonicalCorrectAnswer;
  final ContentIdentity? bookmarkIdentity;

  AnswerFeedbackContext get asContext => AnswerFeedbackContext(
    canonicalCorrectAnswer: canonicalCorrectAnswer,
    bookmarkIdentity: bookmarkIdentity,
  );
}

/// A pure learner-facing interpretation of one already committed answer.
final class AnswerFeedback {
  factory AnswerFeedback.fromCommittedResult({
    required AnswerRecordResult result,
    required AnswerFeedbackContext context,
  }) => AnswerFeedback.fromFrozenCommittedResult(
    result: result,
    context: context.freeze(),
  );

  factory AnswerFeedback.fromFrozenCommittedResult({
    required AnswerRecordResult result,
    required FrozenAnswerFeedbackContext context,
  }) {
    return AnswerFeedback._(
      isCorrect: result.isCorrect,
      canonicalCorrectAnswer: context.canonicalCorrectAnswer,
      bookmarkIdentity: context.bookmarkIdentity,
      committedContrastiveAttempt: result.committedContrastiveAttempt,
    );
  }

  const AnswerFeedback._({
    required this.isCorrect,
    required this.canonicalCorrectAnswer,
    required this.bookmarkIdentity,
    required this.committedContrastiveAttempt,
  });

  final bool isCorrect;
  final String canonicalCorrectAnswer;
  final ContentIdentity? bookmarkIdentity;
  final CommittedContrastiveAttempt? committedContrastiveAttempt;

  AnswerFeedbackAction get nextAction =>
      isCorrect ? AnswerFeedbackAction.next : AnswerFeedbackAction.retry;

  String get statusLabel => isCorrect ? 'Correct' : 'Not quite';

  String get actionLabel =>
      nextAction == AnswerFeedbackAction.next ? 'Next question' : 'Try again';

  String get semanticAnnouncement =>
      '$statusLabel. Correct answer: $canonicalCorrectAnswer. $actionLabel.';
}
