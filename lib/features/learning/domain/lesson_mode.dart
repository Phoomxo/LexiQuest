import 'answer_feedback.dart';
import 'evidence_context.dart';

enum LessonMode { associativeReading, meaningQuiz, definitionQuiz, flashcard }

extension LessonModeIdentity on LessonMode {
  String get id => switch (this) {
    LessonMode.associativeReading => 'associative-reading',
    LessonMode.meaningQuiz => 'meaning-quiz',
    LessonMode.definitionQuiz => 'definition-quiz',
    LessonMode.flashcard => 'flashcard',
  };
}

final class LessonResponse {
  const LessonResponse({
    required this.sourceEvidenceId,
    required this.occurredAtUtc,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.feedbackContext,
    this.providerProvenance,
  });

  final String sourceEvidenceId;
  final DateTime occurredAtUtc;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final AnswerFeedbackContext feedbackContext;
  final String? providerProvenance;
}

final class LessonSupport {
  const LessonSupport({required this.evidenceContext});

  final EvidenceContext evidenceContext;
}

final class LessonCursor {
  const LessonCursor({required this.sessionId, required this.index});

  final String sessionId;
  final int index;
}

final class LessonItem {
  const LessonItem({required this.id});

  final String id;
}

abstract interface class LessonModeAdapter {
  LessonMode get mode;

  EvidenceContext classify(LessonResponse response, LessonSupport support);

  Future<LessonItem> next(LessonCursor cursor);
}

/// Marker for adapters whose complete session is educational active effort.
/// Recreational activities must never implement this contract.
abstract interface class TrustworthyActiveEffortLessonModeAdapter
    implements LessonModeAdapter {}

/// Marker for educational modes that can expose explicit focus intervals.
/// Recreational adapters cannot satisfy the trustworthy-effort parent.
abstract interface class FocusTimerSupportingLessonModeAdapter
    implements TrustworthyActiveEffortLessonModeAdapter {}
