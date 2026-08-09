import '../../../data/local/app_database.dart' as db;

typedef DeleteOwnerSecrets = Future<void> Function(String ownerId);

abstract interface class LocalDataEraser {
  Future<int> eraseAll({required String ownerId});
}

/// Child-before-parent deletion order for every owner-scoped Drift table.
const List<String> localDataDeletionInventory = <String>[
  'answer_attempts',
  'learning_sessions',
  'srs_states',
  'reading_progress_entries',
  'reading_events',
  'speech_evidence',
  'points_ledger_entries',
  'achievement_unlocks',
  'equipped_reward_items',
  'owned_reward_items',
  'reward_transactions',
  'quest_instances',
  'streak_states',
  'learning_day_log',
  'association_records',
  'associative_memory_states',
  'events_v2',
  'outbox_operations',
  'sync_checkpoints',
  'sync_conflicts',
  'ai_usage_events',
  'research_consents',
  'vocabulary_imports',
  'vocabulary_words',
  'vocabulary_categories',
];

/// Erases all local data for the active owner.
///
/// This implements the participant's right-to-erasure: all learning sessions,
/// answer attempts, SRS states, reading data, reward transactions, quest
/// instances, streak data, events, and speech evidence are deleted.
///
/// Vocabulary and import metadata are included; this API must never perform a
/// partial learning-history reset under the name `eraseAll`.
///
/// Cross-store failure policy is privacy-first: secure BYOK values are erased
/// before SQLite work starts. A later SQLite failure rolls database changes
/// back but cannot restore the key; the participant must configure it again.
class LocalDataDeletion implements LocalDataEraser {
  LocalDataDeletion(this._database, {required this.deleteOwnerSecrets});

  final db.AppDatabase _database;
  final DeleteOwnerSecrets deleteOwnerSecrets;

  /// Deletes all owner-scoped data for [ownerId].
  ///
  /// Returns the count of rows deleted across all tables.
  @override
  Future<int> eraseAll({required String ownerId}) async {
    final normalizedOwnerId = ownerId.trim();
    if (normalizedOwnerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must not be empty');
    }
    // Secure storage cannot participate in the SQLite transaction. Erase it
    // first so a secure-storage failure leaves all database rows untouched and
    // a later database failure cannot leave a provider secret behind.
    await deleteOwnerSecrets(normalizedOwnerId);
    return _database.transaction(
      () => _eraseAllInTransaction(ownerId: normalizedOwnerId),
    );
  }

  Future<int> _eraseAllInTransaction({required String ownerId}) async {
    final d = _database;
    var total = 0;

    // Learning evidence
    total += await (d.delete(
      d.answerAttempts,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.learningSessions,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.srsStates,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.readingProgressEntries,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.readingEvents,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.speechEvidence,
    )..where((t) => t.ownerId.equals(ownerId))).go();

    // Motivation + economy
    total += await (d.delete(
      d.pointsLedgerEntries,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.achievementUnlocks,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.equippedRewardItems,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.ownedRewardItems,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.rewardTransactions,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.questInstances,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.streakStates,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.learningDayLog,
    )..where((t) => t.ownerId.equals(ownerId))).go();

    // Associative learning
    total += await (d.delete(
      d.associationRecords,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.associativeMemoryStates,
    )..where((t) => t.ownerId.equals(ownerId))).go();

    // Events + sync
    total += await (d.delete(
      d.eventsV2,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.outboxOperations,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.syncCheckpoints,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.syncConflicts,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.aiUsageEvents,
    )..where((t) => t.ownerId.equals(ownerId))).go();

    // Research consent
    total += await (d.delete(
      d.researchConsents,
    )..where((t) => t.ownerId.equals(ownerId))).go();

    total += await (d.delete(
      d.vocabularyImports,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.vocabularyWords,
    )..where((t) => t.ownerId.equals(ownerId))).go();
    total += await (d.delete(
      d.vocabularyCategories,
    )..where((t) => t.ownerId.equals(ownerId))).go();

    return total;
  }
}
