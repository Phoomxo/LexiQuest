import 'association_record.dart';
import 'deletion_tombstone.dart';
import 'learning_event.dart';
import 'learning_record_validation.dart';
import 'memory_state.dart';
import 'reading_session.dart';
import 'recall_attempt.dart';
import 'sync_outbox_entry.dart';

enum CommitDisposition { applied, alreadyApplied }

final class CommitResult {
  const CommitResult({
    required this.commitId,
    required this.disposition,
    required this.writtenRecords,
  }) : assert(writtenRecords >= 0);

  final String commitId;
  final CommitDisposition disposition;
  final int writtenRecords;

  bool get wasApplied => disposition == CommitDisposition.applied;
}

final class LearningCommit {
  LearningCommit({
    required this.commitId,
    required this.ownerId,
    required DateTime recordedAtUtc,
    List<AssociationRecord> associations = const [],
    List<ReadingSession> sessions = const [],
    List<RecallAttempt> recallAttempts = const [],
    List<MemoryState> memoryStates = const [],
    List<LearningEvent> learningEvents = const [],
    List<SyncOutboxEntry> outboxEntries = const [],
    List<DeletionTombstone> tombstones = const [],
  }) : recordedAtUtc = LearningRecordValidation.utc(recordedAtUtc),
       associations = List<AssociationRecord>.unmodifiable(associations),
       sessions = List<ReadingSession>.unmodifiable(sessions),
       recallAttempts = List<RecallAttempt>.unmodifiable(recallAttempts),
       memoryStates = List<MemoryState>.unmodifiable(memoryStates),
       learningEvents = List<LearningEvent>.unmodifiable(learningEvents),
       outboxEntries = List<SyncOutboxEntry>.unmodifiable(outboxEntries),
       tombstones = List<DeletionTombstone>.unmodifiable(tombstones) {
    LearningRecordValidation.identifier(commitId, 'commitId');
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    if (recordCount == 0) {
      throw ArgumentError('LearningCommit must contain at least one record');
    }
    _validateOwnership();
  }

  final String commitId;
  final String ownerId;
  final DateTime recordedAtUtc;
  final List<AssociationRecord> associations;
  final List<ReadingSession> sessions;
  final List<RecallAttempt> recallAttempts;
  final List<MemoryState> memoryStates;
  final List<LearningEvent> learningEvents;
  final List<SyncOutboxEntry> outboxEntries;
  final List<DeletionTombstone> tombstones;

  int get recordCount =>
      associations.length +
      sessions.length +
      recallAttempts.length +
      memoryStates.length +
      learningEvents.length +
      outboxEntries.length +
      tombstones.length;

  void _validateOwnership() {
    final recordOwners = <String>[
      ...associations.map((record) => record.ownerId),
      ...sessions.map((record) => record.ownerId),
      ...recallAttempts.map((record) => record.ownerId),
      ...memoryStates.map((record) => record.ownerId),
      ...learningEvents.map((record) => record.pseudonymousUserId),
      ...outboxEntries.map((record) => record.ownerId),
      ...tombstones.map((record) => record.ownerId),
    ];
    if (recordOwners.any((recordOwner) => recordOwner != ownerId)) {
      throw ArgumentError(
        'Every record in a LearningCommit must belong to its ownerId',
      );
    }
  }
}
