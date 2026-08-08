import '../../../data/local/app_database.dart' as db;

/// Erases all local data for the active owner.
///
/// This implements the participant's right-to-erasure: all learning sessions,
/// answer attempts, SRS states, reading data, reward transactions, quest
/// instances, streak data, events, and speech evidence are deleted.
///
/// Vocabulary categories and words are NOT deleted by default (they may
/// represent user-created content the participant wants to keep) — pass
/// [deleteVocabulary] to also erase them.
class LocalDataDeletion {
  LocalDataDeletion(this._database);

  final db.AppDatabase _database;

  /// Deletes all owner-scoped data for [ownerId].
  ///
  /// Returns the count of rows deleted across all tables.
  Future<int> eraseAll({
    required String ownerId,
    bool deleteVocabulary = false,
  }) async {
    final d = _database;
    var total = 0;

    // Learning evidence
    total += await (d.delete(d.answerAttempts)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.learningSessions)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.srsStates)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.readingProgressEntries)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.readingEvents)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.speechEvidence)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();

    // Motivation + economy
    total += await (d.delete(d.pointsLedgerEntries)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.achievementUnlocks)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.rewardTransactions)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.ownedRewardItems)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.equippedRewardItems)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.questInstances)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.streakStates)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.learningDayLog)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();

    // Associative learning
    total += await (d.delete(d.associationRecords)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.associativeMemoryStates)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();

    // Events + sync
    total += await (d.delete(d.eventsV2)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.outboxOperations)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.syncCheckpoints)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();
    total += await (d.delete(d.syncConflicts)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();

    // Research consent
    total += await (d.delete(d.researchConsents)
          ..where((t) => t.ownerId.equals(ownerId)))
        .go();

    if (deleteVocabulary) {
      total += await (d.delete(d.vocabularyWords)
            ..where((t) => t.ownerId.equals(ownerId)))
          .go();
      total += await (d.delete(d.vocabularyCategories)
            ..where((t) => t.ownerId.equals(ownerId)))
          .go();
      total += await (d.delete(d.vocabularyImports)
            ..where((t) => t.ownerId.equals(ownerId)))
          .go();
    }

    return total;
  }
}
