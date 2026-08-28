import '../../learning_packs/domain/content_manifest.dart';
import 'learning_models.dart';

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

  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
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
