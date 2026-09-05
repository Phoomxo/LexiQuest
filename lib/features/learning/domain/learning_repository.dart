import '../../learning_packs/domain/content_manifest.dart';
import 'learning_models.dart';
import '../pair_matching/domain/pair_matching_plan.dart';

abstract interface class PairPinnedLearningActivityRepository {
  Future<void> startMeasuredPinnedPairSession({
    required LearningSessionDraft session,
    required PairMatchingPlanV1 plan,
    required String launchOperationId,
    required LearningActivityCheckpoint checkpoint,
    required PairMatchingStartCapability capability,
  });
  Future<void> startPinnedPairSession({
    required LearningSessionDraft session,
    required PairMatchingPlanV1 plan,
    required String launchOperationId,
    required LearningActivityCheckpoint checkpoint,
    required PairMatchingStartCapability capability,
  });
}

/// A checkpointed Learning start found another accepted session for the same
/// owner. Callers must resume or retire [activeSessionId] instead of creating
/// [requestedSessionId].
final class ActiveLearningSessionConflict implements Exception {
  const ActiveLearningSessionConflict({
    required this.ownerId,
    required this.activeSessionId,
    required this.requestedSessionId,
  });

  final String ownerId;
  final String activeSessionId;
  final String requestedSessionId;

  @override
  String toString() =>
      'ActiveLearningSessionConflict($ownerId, $activeSessionId, '
      '$requestedSessionId)';
}

abstract interface class LearningEvidenceReplayRepository {
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  );
}

abstract interface class LearningSessionLifecycleRepository {
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  });
}

/// Durable f16 authority attached to the canonical learning session. The
/// latest owner/mode preference is never used to reconstruct an active run.
abstract interface class SessionConfiguredLearningRepository {
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  });

  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  });
}

abstract interface class PinnedLearningContentRepository {
  Future<List<QuizWord>> listPinnedQuizWords({
    required String ownerId,
    required List<String> wordIds,
  });

  Future<List<QuizWord>> listExactPinnedQuizWords({
    required String ownerId,
    required List<PinnedQuizContent> content,
  });
}

/// Atomically revalidates exact lexical pins and the uniquely active owner
/// before accepting a Learning session and its initial recovery checkpoint.
abstract interface class ExactPinnedLearningActivityRepository {
  Future<void> startExactPinnedSessionWithCheckpoint({
    required LearningSessionDraft session,
    required List<PinnedQuizContent> content,
    required LearningActivityCheckpoint checkpoint,
  });
}

/// Revalidates an exact review selection and persists its canonical session
/// in one repository snapshot.
abstract interface class ReviewSessionLearningRepository {
  Future<PinnedReviewSessionLaunch> startPinnedReviewSession({
    required LearningSessionDraft session,
    required List<ReviewedLexicalContentSnapshot> items,
  });
}

/// Durable, versioned activity-state storage backed by the canonical learning
/// session event stream. This is intentionally separate from projections and
/// score storage.
abstract interface class LearningActivityRecoveryRepository {
  Future<void> startSessionWithCheckpoint({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
  });

  Future<LearningActivityRecovery?> loadLatestActivityRecovery({
    required String ownerId,
    required String activityType,
  });

  Future<LearningActivityRecovery?> loadExactActivityRecovery({
    required String ownerId,
    required String sessionId,
    required String activityType,
  });

  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  });
}

/// Read model for bounded recovery scans that must not be displaced by newer
/// sessions from unrelated activity types.
abstract interface class LearningActivitySessionHistoryRepository {
  Future<List<LearningSessionSummary>> listCompletedActivitySessionHistory({
    required String ownerId,
    required String activityType,
    required int limit,
  });
}

abstract interface class LearningRepository {
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  });

  Future<void> startSession(LearningSessionDraft session);

  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command);

  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  });

  /// Returns the most recent active (unfinished) session for [ownerId], or
  /// null when none exists. Used to resume an interrupted session.
  Future<LearningSessionSummary?> getActiveSession({required String ownerId});

  /// Marks all active sessions for [ownerId] as abandoned. Called on app
  /// start when the user chooses not to resume.
  Future<void> abandonActiveSessions({required String ownerId});

  /// Returns recent completed sessions for [ownerId], newest first.
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
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
