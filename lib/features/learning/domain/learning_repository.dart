import 'learning_models.dart';
import 'quiz_round.dart';
import 'review_ladder.dart';
import 'source_reading_round.dart';

abstract interface class LearningRepository {
  /// A null limit reads the complete matching pool for prompt eligibility.
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    Iterable<String>? normalizedSpellings,
    Iterable<String>? normalizedMeanings,
    required int? limit,
  });

  Future<void> startSession(LearningSessionDraft session);

  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command);

  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  });

  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  });

  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  });

  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  );
}

abstract interface class DurableSourceReadingRepository
    implements LearningRepository {
  Future<SourceReadingRound> openSourceReadingRound({
    required LearningSessionDraft session,
    required SourceReadingScope scope,
  });

  Future<SourceReadingRound> saveSourceReadingRound({
    required String ownerId,
    required SourceReadingRound expected,
    required SourceReadingDraft draft,
  });

  Future<LearningSessionSummary> finishSourceReadingRound({
    required String ownerId,
    required SourceReadingRound expected,
    required DateTime endedAtUtc,
  });
}

abstract interface class ReviewLadderRepository implements LearningRepository {
  Future<ReviewLadderPair?> findReviewLadderPair({required String ownerId});

  Future<ReviewLadderRound?> readLatestReviewLadder({required String ownerId});

  Future<ReviewLadderRound> openReviewLadderRound({
    required LearningSessionDraft session,
    required ReviewLadderPair pair,
  });

  Future<ReviewLadderRound> changeReviewLadderRound({
    required String ownerId,
    required ReviewLadderRound expected,
    required ReviewLadderAction action,
    required DateTime atUtc,
    int? option,
    String? text,
  });

  Future<LearningSessionSummary> finishReviewLadderRound({
    required String ownerId,
    required ReviewLadderRound expected,
    required DateTime endedAtUtc,
  });
}

abstract interface class DurableQuizRepository implements LearningRepository {
  Future<QuizRound> openOrStartAuthoredRound(
    LearningSessionDraft draft, {
    required bool skipUnavailable,
  });

  Future<Set<String>> loadCompletedQuizMistakeIds({
    required String ownerId,
    required String sessionId,
  });

  Future<QuizRound?> loadQuizRound({
    required String ownerId,
    required String sessionId,
  });

  Future<QuizRound?> findOpenQuizRound({
    required String ownerId,
    required QuizOrigin origin,
    bool skipUnavailable = false,
  });

  Future<QuizRound> advanceQuizRound({
    required String ownerId,
    required String sessionId,
    required int expectedRevision,
    required QuizStep step,
    required DateTime atUtc,
    int activeResponseMs = 0,
  });
}
