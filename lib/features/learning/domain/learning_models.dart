final class QuizWord {
  const QuizWord({
    required this.id,
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
  });

  final String id;
  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
}

enum QuizPromptKind { meaningChoice, spellingChoice, definitionChoice }

final class QuizQuestion {
  const QuizQuestion({required this.word, required this.options})
    : kind = QuizPromptKind.meaningChoice,
      _definition = null,
      optionWords = null,
      optionExplanations = null,
      sourcePin = null;

  QuizQuestion.spellingChoice({
    required this.word,
    required List<String> options,
    required Map<String, QuizWord> optionWords,
  }) : kind = QuizPromptKind.spellingChoice,
       options = List.unmodifiable(options),
       _definition = null,
       optionWords = Map.unmodifiable(optionWords),
       optionExplanations = null,
       sourcePin = null;

  QuizQuestion.definitionChoice({
    required this.word,
    required List<String> options,
    required this._definition,
    required Map<String, QuizWord> optionWords,
    required Map<String, String> optionExplanations,
    required this.sourcePin,
  }) : kind = QuizPromptKind.definitionChoice,
       options = List.unmodifiable(options),
       optionWords = Map.unmodifiable(optionWords),
       optionExplanations = Map.unmodifiable(optionExplanations);

  final QuizWord word;
  final List<String> options;
  final QuizPromptKind kind;
  final String? _definition;
  final Map<String, QuizWord>? optionWords;
  final Map<String, String>? optionExplanations;
  final String? sourcePin;

  String get correctAnswer =>
      kind == QuizPromptKind.meaningChoice ? word.meaning : word.spelling;
  String get promptText => switch (kind) {
    QuizPromptKind.meaningChoice => word.spelling,
    QuizPromptKind.spellingChoice => word.meaning,
    QuizPromptKind.definitionChoice => _definition!,
  };
}

final class QuizSession {
  const QuizSession({
    required this.id,
    required this.questions,
    required this.startedAtUtc,
  });

  final String id;
  final List<QuizQuestion> questions;
  final DateTime? startedAtUtc;

  bool get isEmpty => questions.isEmpty;
}

final class LearningSessionDraft {
  const LearningSessionDraft({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtc,
    required this.appVersion,
    required this.buildId,
  });

  final String id;
  final String ownerId;
  final String activityType;
  final DateTime? startedAtUtc;
  final String appVersion;
  final String buildId;

  LearningSessionDraft copyWith({DateTime? startedAtUtc}) {
    return LearningSessionDraft(
      id: id,
      ownerId: ownerId,
      activityType: activityType,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      appVersion: appVersion,
      buildId: buildId,
    );
  }
}

final class RecordAnswerCommand {
  const RecordAnswerCommand({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.occurredAtUtc,
    this.providerProvenance,
  });

  final String id;
  final String ownerId;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final DateTime occurredAtUtc;
  final String? providerProvenance;
}

final class SrsSnapshot {
  const SrsSnapshot({
    required this.intervalDays,
    required this.repetitions,
    required this.lapses,
    required this.stability,
    required this.difficulty,
    required this.lastReviewAtUtc,
    required this.dueAtUtc,
    required this.algorithmVersion,
  });

  final int intervalDays;
  final int repetitions;
  final int lapses;
  final double stability;
  final double difficulty;
  final DateTime? lastReviewAtUtc;
  final DateTime? dueAtUtc;
  final int algorithmVersion;
}

final class AnswerRecordResult {
  const AnswerRecordResult({required this.inserted, required this.srs});

  final bool inserted;
  final SrsSnapshot srs;
}

final class LearningSessionSummary {
  const LearningSessionSummary({
    required this.id,
    required this.state,
    required this.correctCount,
    required this.wrongCount,
    required this.score,
  });

  final String id;
  final String state;
  final int correctCount;
  final int wrongCount;
  final int score;
}

final class LearningSessionResult {
  LearningSessionResult({
    required this.summary,
    required Iterable<String> mistakeWordIds,
  }) : mistakeWordIds = List.unmodifiable(mistakeWordIds);

  final LearningSessionSummary summary;
  final List<String> mistakeWordIds;
}

final class ReadingProgressCommand {
  const ReadingProgressCommand({
    required this.eventId,
    required this.ownerId,
    required this.documentId,
    required this.documentRevision,
    required this.position,
    required this.isCompleted,
    required this.occurredAtUtc,
  });

  final String eventId;
  final String ownerId;
  final String documentId;
  final int documentRevision;
  final int position;
  final bool isCompleted;
  final DateTime occurredAtUtc;
}

final class ReadingProgressSnapshot {
  const ReadingProgressSnapshot({
    required this.documentId,
    required this.documentRevision,
    required this.lastPosition,
    required this.isCompleted,
    required this.updatedAtUtc,
  });

  final String documentId;
  final int documentRevision;
  final int lastPosition;
  final bool isCompleted;
  final DateTime updatedAtUtc;

  @override
  bool operator ==(Object other) {
    return other is ReadingProgressSnapshot &&
        other.documentId == documentId &&
        other.documentRevision == documentRevision &&
        other.lastPosition == lastPosition &&
        other.isCompleted == isCompleted &&
        other.updatedAtUtc == updatedAtUtc;
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    documentRevision,
    lastPosition,
    isCompleted,
    updatedAtUtc,
  );
}
