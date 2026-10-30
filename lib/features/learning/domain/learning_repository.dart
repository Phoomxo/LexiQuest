import 'accepted_quiz_plan.dart';
import 'learning_models.dart';

abstract interface class LearningRepository {
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
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

abstract interface class NativeExerciseRepository {
  Future<bool> hasAmbientTransaction();

  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T exercise, {
    required bool Function() stillCurrent,
  });

  Future<AnswerRecordResult> commitNativeAnswer(
    AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  });

  Future<LearningSessionSummary> finishNativeExercise(
    NativeFinishIntent intent, {
    required bool Function() stillCurrent,
  });
}

abstract interface class ConfiguredQuizRepository {
  Future<ConfiguredQuizState?> findConfiguredQuizStart(
    ConfiguredQuizLaunch launch,
  );

  Future<ConfiguredQuizState> startConfiguredQuiz({
    required LearningSessionDraft session,
    required AcceptedQuizPlan plan,
  });

  Future<ConfiguredQuizState> resumeQuiz({
    required String sessionId,
    required String expectedOwnerId,
  });

  Future<ConfiguredQuizState> saveQuizCheckpoint({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    required QuizCheckpoint checkpoint,
  });

  Future<ConfiguredQuizAnswerResult> commitQuizAnswer({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  });

  Future<ConfiguredQuizFinishResult> finishConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  });
}

abstract interface class SrsReviewRepository {
  Future<SrsReviewSession?> prepareSrsReview({
    required LearningSessionDraft session,
    required SrsReviewSelection selection,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  });

  Future<SrsReviewStartResult> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  });

  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  });

  Future<SrsReviewFinishResult> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  });
}
