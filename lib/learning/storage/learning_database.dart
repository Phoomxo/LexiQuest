import 'package:drift/drift.dart';

part 'learning_database.g.dart';

abstract class OwnedLearningTable extends Table {
  TextColumn get ownerId => text().withLength(min: 1, max: 200)();

  IntColumn get schemaVersion =>
      integer().withDefault(const Constant<int>(1))();

  IntColumn get createdAtUtc => integer()();

  IntColumn get updatedAtUtc => integer()();
}

@DataClassName('LearningCommitRow')
class LearningCommits extends OwnedLearningTable {
  @override
  String get tableName => 'learning_commits';

  TextColumn get commitId => text().withLength(min: 1, max: 200)();

  IntColumn get recordedAtUtc => integer()();

  IntColumn get recordCount => integer()();

  TextColumn get contentFingerprint => text().withLength(min: 64, max: 64)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, commitId};
}

@DataClassName('AssociationRow')
class Associations extends OwnedLearningTable {
  @override
  String get tableName => 'associations';

  TextColumn get associationId => text().withLength(min: 1, max: 200)();

  TextColumn get wordKey => text().withLength(min: 1, max: 200)();

  TextColumn get cueType => text().withLength(min: 1, max: 40)();

  TextColumn get cueText => text().withLength(min: 1, max: 500)();

  TextColumn get origin => text().withLength(min: 1, max: 40)();

  RealColumn get strength => real()();

  IntColumn get successCount => integer()();

  IntColumn get failureCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    ownerId,
    associationId,
  };
}

@DataClassName('ReadingSessionRow')
class ReadingSessions extends OwnedLearningTable {
  @override
  String get tableName => 'reading_sessions';

  TextColumn get sessionId => text().withLength(min: 1, max: 200)();

  TextColumn get cefrLevel => text().withLength(min: 2, max: 2)();

  TextColumn get targetWordKeysJson => text()();

  TextColumn get mixPolicyVersion => text().withLength(min: 1, max: 200)();

  TextColumn get contentId => text().withLength(min: 1, max: 200)();

  TextColumn get contentVersion => text().withLength(min: 1, max: 200)();

  TextColumn get currentStage => text().withLength(min: 1, max: 40)();

  IntColumn get startedAtUtc => integer()();

  IntColumn get completedAtUtc => integer().nullable()();

  IntColumn get abandonedAtUtc => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, sessionId};
}

@DataClassName('RecallAttemptRow')
class RecallAttempts extends OwnedLearningTable {
  @override
  String get tableName => 'recall_attempts';

  TextColumn get attemptId => text().withLength(min: 1, max: 200)();

  TextColumn get sessionId => text().withLength(min: 1, max: 200)();

  TextColumn get wordKey => text().withLength(min: 1, max: 200)();

  TextColumn get recallMode => text().withLength(min: 1, max: 40)();

  TextColumn get cueLevel => text().withLength(min: 1, max: 40)();

  BoolColumn get correctness => boolean()();

  IntColumn get responseTimeMs => integer()();

  IntColumn get confidence => integer()();

  TextColumn get contextId => text().withLength(min: 1, max: 200).nullable()();

  TextColumn get algorithmVersion => text().withLength(min: 1, max: 200)();

  IntColumn get occurredAtUtc => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, attemptId};
}

@DataClassName('MemoryStateRow')
class MemoryStates extends OwnedLearningTable {
  @override
  String get tableName => 'memory_states';

  TextColumn get wordKey => text().withLength(min: 1, max: 200)();

  RealColumn get strength => real()();

  RealColumn get cueDependency => real()();

  RealColumn get stability => real()();

  RealColumn get difficulty => real()();

  IntColumn get lapseCount => integer()();

  IntColumn get lastReviewedAtUtc => integer().nullable()();

  IntColumn get nextDueAtUtc => integer()();

  TextColumn get lastErrorType =>
      text().withLength(min: 1, max: 200).nullable()();

  TextColumn get algorithmVersion => text().withLength(min: 1, max: 200)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, wordKey};
}

@DataClassName('LearningEventRow')
class LearningEvents extends OwnedLearningTable {
  @override
  String get tableName => 'learning_events';

  TextColumn get eventId => text().withLength(min: 1, max: 200)();

  IntColumn get occurredAtUtc => integer()();

  TextColumn get activity => text().withLength(min: 1, max: 80)();

  TextColumn get contentId => text().withLength(min: 1, max: 200)();

  TextColumn get categoryId => text().withLength(min: 1, max: 200).nullable()();

  TextColumn get cefrLevel => text().withLength(min: 2, max: 2).nullable()();

  TextColumn get skill => text().withLength(min: 1, max: 80)();

  BoolColumn get correct => boolean()();

  IntColumn get score => integer()();

  IntColumn get responseTimeMs => integer().nullable()();

  IntColumn get attemptNumber => integer()();

  TextColumn get appVersion => text().withLength(min: 1, max: 200)();

  TextColumn get buildId => text().withLength(min: 1, max: 200)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, eventId};
}

@DataClassName('SyncOutboxRow')
class SyncOutbox extends OwnedLearningTable {
  @override
  String get tableName => 'sync_outbox';

  TextColumn get outboxId => text().withLength(min: 1, max: 200)();

  TextColumn get eventId => text().withLength(min: 1, max: 200)();

  TextColumn get operation => text().withLength(min: 1, max: 80)();

  TextColumn get payloadJson => text()();

  IntColumn get acknowledgedAtUtc => integer().nullable()();

  IntColumn get attemptCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, outboxId};
}

@DataClassName('DeletionTombstoneRow')
class DeletionTombstones extends OwnedLearningTable {
  @override
  String get tableName => 'deletion_tombstones';

  TextColumn get tombstoneId => text().withLength(min: 1, max: 200)();

  TextColumn get entityType => text().withLength(min: 1, max: 40)();

  TextColumn get entityId => text().withLength(min: 1, max: 200)();

  IntColumn get deletedAtUtc => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{ownerId, tombstoneId};
}

@DriftDatabase(
  tables: <Type>[
    LearningCommits,
    Associations,
    ReadingSessions,
    RecallAttempts,
    MemoryStates,
    LearningEvents,
    SyncOutbox,
    DeletionTombstones,
  ],
)
class LearningDatabase extends _$LearningDatabase {
  LearningDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
