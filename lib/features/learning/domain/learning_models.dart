import 'quiz_round.dart';
import 'srs_recall_snapshot.dart';

final class QuizWord {
  const QuizWord({
    required this.id,
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.localRevision = 1,
  });

  final String id;
  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final int localRevision;
}

enum QuizPromptKind {
  meaningChoice,
  spellingChoice,
  definitionChoice,
  clozeChoice,
  clozeTyped,
  wordScramble,
  sentenceScramble;

  bool get isCloze => this == clozeChoice || this == clozeTyped;
  bool get isScramble => this == wordScramble || this == sentenceScramble;
}

String normalizeQuizClozeAnswer(String value) {
  if (value.runes.length > 120 ||
      value.trim().isEmpty ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value)) {
    throw const FormatException('Invalid cloze answer text');
  }
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

final class QuizQuestion {
  const QuizQuestion({
    required this.word,
    required this.options,
    this.optionWords,
  }) : kind = QuizPromptKind.meaningChoice,
       _definition = null,
       optionExplanations = null,
       sourcePin = null,
       clozeTranslation = null,
       acceptedAnswers = const [],
       scrambleTokens = const [],
       _scrambleAnswer = null;

  QuizQuestion.spellingChoice({
    required this.word,
    required List<String> options,
    required Map<String, QuizWord> optionWords,
  }) : kind = QuizPromptKind.spellingChoice,
       options = List.unmodifiable(options),
       _definition = null,
       optionWords = Map.unmodifiable(optionWords),
       optionExplanations = null,
       sourcePin = null,
       clozeTranslation = null,
       acceptedAnswers = const [],
       scrambleTokens = const [],
       _scrambleAnswer = null;

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
       optionExplanations = Map.unmodifiable(optionExplanations),
       clozeTranslation = null,
       acceptedAnswers = const [],
       scrambleTokens = const [],
       _scrambleAnswer = null;

  QuizQuestion.cloze({
    required this.word,
    required this.kind,
    required String prompt,
    required Iterable<String> options,
    required String translation,
    required Iterable<String> acceptedAnswers,
    required String sourcePin,
  }) : options = List.unmodifiable(options),
       _definition = prompt,
       optionWords = null,
       optionExplanations = null,
       clozeTranslation = translation,
       acceptedAnswers = List.unmodifiable(acceptedAnswers),
       scrambleTokens = const [],
       _scrambleAnswer = null,
       sourcePin = sourcePin {
    if (!kind.isCloze ||
        prompt.split('____').length != 2 ||
        prompt.length > 4096 ||
        translation.trim().isEmpty ||
        translation.length > 4096 ||
        sourcePin.trim().isEmpty ||
        sourcePin.length > 4096 ||
        this.acceptedAnswers.isEmpty ||
        this.acceptedAnswers.length > 100 ||
        !this.acceptedAnswers.contains(word.spelling)) {
      throw const FormatException('Invalid authored cloze');
    }
    final answers = this.acceptedAnswers.map(normalizeQuizClozeAnswer).toSet();
    if (answers.length != this.acceptedAnswers.length) {
      throw const FormatException('Duplicate cloze answers');
    }
    if (kind == QuizPromptKind.clozeTyped) {
      if (this.options.isNotEmpty) {
        throw const FormatException('Typed cloze cannot contain choices');
      }
    } else {
      final choices = this.options.map(normalizeQuizClozeAnswer).toSet();
      if (this.options.length < 2 ||
          this.options.length > 4 ||
          choices.length != this.options.length ||
          !this.options.contains(word.spelling) ||
          choices.every(answers.contains)) {
        throw const FormatException('Invalid cloze choices');
      }
    }
  }

  QuizQuestion.scramble({
    required this.word,
    required this.kind,
    required String prompt,
    required List<String> tokens,
    required String correctAnswer,
    required String sourcePin,
  }) : options = const [],
       _definition = prompt,
       optionWords = null,
       optionExplanations = null,
       clozeTranslation = null,
       acceptedAnswers = const [],
       scrambleTokens = List.unmodifiable(tokens),
       _scrambleAnswer = correctAnswer,
       sourcePin = sourcePin {
    if (!kind.isScramble ||
        !_scrambleText(prompt, 4096) ||
        !_scrambleText(correctAnswer, 4096) ||
        !_scrambleText(sourcePin, 4096) ||
        scrambleTokens.length < 2 ||
        scrambleTokens.length > maxScrambleTokens ||
        scrambleTokens.any(
          (tile) => !_scrambleText(tile, 120) || RegExp(r'\s').hasMatch(tile),
        )) {
      throw const FormatException('Invalid scramble question');
    }
    final spelling = kind == QuizPromptKind.wordScramble;
    if (spelling &&
        (word.spelling != correctAnswer ||
            !RegExp(r'^[A-Za-z]+$').hasMatch(correctAnswer))) {
      throw const FormatException('Invalid scramble spelling');
    }
    final solution = spelling
        ? correctAnswer.split('')
        : correctAnswer.split(' ');
    final separator = spelling ? '' : ' ';
    if (solution.length != scrambleTokens.length ||
        scrambleTokens.join(separator) == correctAnswer) {
      throw const FormatException('Invalid scramble tile order');
    }
    final remaining = scrambleTokens.toList();
    for (final tile in solution) {
      if (!remaining.remove(tile)) {
        throw const FormatException('Scramble tiles do not match the answer');
      }
    }
  }

  static const maxScrambleTokens = 24;

  static bool _scrambleText(String value, int maxLength) =>
      value.trim().isNotEmpty &&
      value.length <= maxLength &&
      !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value);

  final QuizWord word;
  final List<String> options;
  final QuizPromptKind kind;
  final String? _definition;
  final Map<String, QuizWord>? optionWords;
  final Map<String, String>? optionExplanations;
  final String? sourcePin;
  final String? clozeTranslation;
  final List<String> acceptedAnswers;
  final List<String> scrambleTokens;
  final String? _scrambleAnswer;

  String get correctAnswer => switch (kind) {
    QuizPromptKind.meaningChoice => word.meaning,
    QuizPromptKind.wordScramble ||
    QuizPromptKind.sentenceScramble => _scrambleAnswer!,
    _ => word.spelling,
  };
  String get promptText => switch (kind) {
    QuizPromptKind.meaningChoice => word.spelling,
    QuizPromptKind.spellingChoice => word.meaning,
    QuizPromptKind.definitionChoice ||
    QuizPromptKind.clozeChoice ||
    QuizPromptKind.clozeTyped ||
    QuizPromptKind.wordScramble ||
    QuizPromptKind.sentenceScramble => _definition!,
  };
}

final class QuizSession {
  const QuizSession({
    required this.id,
    required this.questions,
    required this.startedAtUtc,
    this.durableRound,
  });

  final String id;
  final List<QuizQuestion> questions;
  final DateTime? startedAtUtc;
  final QuizRound? durableRound;

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
    this.quizPlan,
  });

  final String id;
  final String ownerId;
  final String activityType;
  final DateTime? startedAtUtc;
  final String appVersion;
  final String buildId;
  final QuizPlan? quizPlan;

  LearningSessionDraft copyWith({DateTime? startedAtUtc}) {
    return LearningSessionDraft(
      id: id,
      ownerId: ownerId,
      activityType: activityType,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      appVersion: appVersion,
      buildId: buildId,
      quizPlan: quizPlan,
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
    this.quiz,
    this.srsRecallSnapshot,
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
  final QuizAdmission? quiz;
  final SrsRecallSnapshot? srsRecallSnapshot;
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
  const AnswerRecordResult({
    required this.inserted,
    required this.srs,
    this.durableRound,
  });

  final bool inserted;
  final SrsSnapshot srs;
  final QuizRound? durableRound;
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
    this.sourceSentence,
  }) : mistakeWordIds = List.unmodifiable(mistakeWordIds);

  final LearningSessionSummary summary;
  final List<String> mistakeWordIds;
  final String? sourceSentence;
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
