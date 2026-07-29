import 'association_record.dart';
import 'learning_commit.dart';
import 'memory_state.dart';
import 'reading_session.dart';
import 'recall_attempt.dart';
import 'sync_outbox_entry.dart';

enum LearningRepositoryErrorCode {
  idempotencyConflict,
  writeConflict,
  invalidStoredData,
  unavailable,
}

final class LearningRepositoryException implements Exception {
  const LearningRepositoryException(this.code, this.message);

  final LearningRepositoryErrorCode code;
  final String message;

  @override
  String toString() => 'LearningRepositoryException($code, $message)';
}

abstract interface class LearningRepository {
  Future<CommitResult> commit(LearningCommit commit);
}

abstract interface class LearningReader {
  Future<List<AssociationRecord>> readAssociations({
    required String ownerId,
    required String wordKey,
  });

  Future<ReadingSession?> readSession({
    required String ownerId,
    required String sessionId,
  });

  Future<MemoryState?> readMemoryState({
    required String ownerId,
    required String wordKey,
  });

  Future<List<RecallAttempt>> readRecallAttempts({
    required String ownerId,
    required String sessionId,
  });

  Future<List<SyncOutboxEntry>> readPendingOutbox({required String ownerId});
}
