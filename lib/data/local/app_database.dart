import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/ai_usage_tables.dart';
import 'tables/associative_tables.dart';
import 'tables/event_tables.dart';
import 'tables/identity_tables.dart';
import 'tables/learning_tables.dart';
import 'tables/model_tables.dart';
import 'tables/motivation_tables.dart';
import 'tables/progress_tables.dart';
import 'tables/quest_tables.dart';
import 'tables/runtime_tables.dart';
import 'tables/speech_evidence_tables.dart';
import 'tables/sync_tables.dart';
import 'tables/vocabulary_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    LocalOwners,
    ResearchConsents,
    VocabularyCategories,
    VocabularyWords,
    VocabularyImports,
    VocabularyImportRows,
    LearningSessions,
    AnswerAttempts,
    SrsStates,
    ReadingProgressEntries,
    ReadingEvents,
    PointsLedgerEntries,
    AchievementUnlocks,
    RewardTransactions,
    OwnedRewardItems,
    EquippedRewardItems,
    OutboxOperations,
    SyncCheckpoints,
    SyncConflicts,
    RuntimeFlags,
    ModelDownloads,
    EventsV2,
    QuestDefinitions,
    QuestInstances,
    QuestObjectiveProgress,
    StreakStates,
    LearningDayLog,
    AssociationRecords,
    AssociativeMemoryStates,
    AiUsageEvents,
    SpeechEvidence,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.production() : super(driftDatabase(name: 'lexiquest'));

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      await _createMissingTables(migrator);
      if (from < 2) {
        await _addColumnIfMissing(
          migrator,
          'vocabulary_categories',
          vocabularyCategories,
          vocabularyCategories.cloudRevision,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_categories',
          vocabularyCategories,
          vocabularyCategories.lastAcknowledgedAtUtcMs,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_categories',
          vocabularyCategories,
          vocabularyCategories.serverUpdatedAtUtcMs,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.cloudRevision,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.lastAcknowledgedAtUtcMs,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.serverUpdatedAtUtcMs,
        );
        await _addColumnIfMissing(
          migrator,
          'outbox_operations',
          outboxOperations,
          outboxOperations.leaseToken,
        );
        await _addColumnIfMissing(
          migrator,
          'outbox_operations',
          outboxOperations,
          outboxOperations.leaseExpiresAtUtcMs,
        );
        await _addColumnIfMissing(
          migrator,
          'outbox_operations',
          outboxOperations,
          outboxOperations.lastAttemptAtUtcMs,
        );
        await _addColumnIfMissing(
          migrator,
          'sync_conflicts',
          syncConflicts,
          syncConflicts.localSnapshotJson,
        );
        await _addColumnIfMissing(
          migrator,
          'sync_conflicts',
          syncConflicts,
          syncConflicts.cloudSnapshotJson,
        );
      }
      if (from < 3) {
        await _createLearningIndexes();
      }
      if (from < 4) {
        await _addColumnIfMissing(
          migrator,
          'reading_events',
          readingEvents,
          readingEvents.documentRevision,
        );
      }
      if (from < 5) {
        await _addColumnIfMissing(
          migrator,
          'model_downloads',
          modelDownloads,
          modelDownloads.failureCode,
        );
      }
      if (from < 6) {
        await _createMissingTables(migrator);
      }
      if (from < 7) {
        await _createMissingTables(migrator);
      }
      if (from < 8) {
        await _createMissingTables(migrator);
      }
      if (from < 9) {
        await _createMissingTables(migrator);
      }
      if (from < 10) {
        await _createMissingTables(migrator);
      }
      if (from < 11) {
        await _createMissingTables(migrator);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createLearningIndexes();
      await _createEventIndexes();
    },
  );

  Future<void> _createEventIndexes() async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).map((row) => row.read<String>('name')).get();
    if (tables.contains('events_v2')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_events_v2_owner_occurred '
        'ON events_v2(owner_id, occurred_at_utc)',
      );
    }
  }

  Future<void> _createLearningIndexes() async {
    final tableNames = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).map((row) => row.read<String>('name')).get();
    final tables = tableNames.toSet();
    if (tables.contains('learning_sessions')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_learning_sessions_owner_started '
        'ON learning_sessions(owner_id, started_at_utc_ms)',
      );
    }
    if (tables.contains('answer_attempts')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_learning_attempts_owner_word_time '
        'ON answer_attempts(owner_id, word_id, occurred_at_utc_ms)',
      );
    }
    if (tables.contains('srs_states')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_learning_srs_owner_due '
        'ON srs_states(owner_id, due_at_utc_ms)',
      );
    }
    if (tables.contains('reading_progress_entries')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_learning_reading_owner_document '
        'ON reading_progress_entries(owner_id, document_id, document_revision)',
      );
    }
  }

  Future<void> _createMissingTables(Migrator migrator) async {
    if (!await _tableExists('local_owners')) {
      await migrator.createTable(localOwners);
    }
    if (!await _tableExists('research_consents')) {
      await migrator.createTable(researchConsents);
    }
    if (!await _tableExists('vocabulary_categories')) {
      await migrator.createTable(vocabularyCategories);
    }
    if (!await _tableExists('vocabulary_words')) {
      await migrator.createTable(vocabularyWords);
    }
    if (!await _tableExists('vocabulary_imports')) {
      await migrator.createTable(vocabularyImports);
    }
    if (!await _tableExists('vocabulary_import_rows')) {
      await migrator.createTable(vocabularyImportRows);
    }
    if (!await _tableExists('learning_sessions')) {
      await migrator.createTable(learningSessions);
    }
    if (!await _tableExists('answer_attempts')) {
      await migrator.createTable(answerAttempts);
    }
    if (!await _tableExists('srs_states')) {
      await migrator.createTable(srsStates);
    }
    if (!await _tableExists('reading_progress_entries')) {
      await migrator.createTable(readingProgressEntries);
    }
    if (!await _tableExists('reading_events')) {
      await migrator.createTable(readingEvents);
    }
    if (!await _tableExists('points_ledger_entries')) {
      await migrator.createTable(pointsLedgerEntries);
    }
    if (!await _tableExists('achievement_unlocks')) {
      await migrator.createTable(achievementUnlocks);
    }
    if (!await _tableExists('reward_transactions')) {
      await migrator.createTable(rewardTransactions);
    }
    if (!await _tableExists('owned_reward_items')) {
      await migrator.createTable(ownedRewardItems);
    }
    if (!await _tableExists('equipped_reward_items')) {
      await migrator.createTable(equippedRewardItems);
    }
    if (!await _tableExists('outbox_operations')) {
      await migrator.createTable(outboxOperations);
    }
    if (!await _tableExists('sync_checkpoints')) {
      await migrator.createTable(syncCheckpoints);
    }
    if (!await _tableExists('sync_conflicts')) {
      await migrator.createTable(syncConflicts);
    }
    if (!await _tableExists('runtime_flags')) {
      await migrator.createTable(runtimeFlags);
    }
    if (!await _tableExists('model_downloads')) {
      await migrator.createTable(modelDownloads);
    }
    if (!await _tableExists('events_v2')) {
      await migrator.createTable(eventsV2);
    }
    if (!await _tableExists('quest_definitions')) {
      await migrator.createTable(questDefinitions);
    }
    if (!await _tableExists('quest_instances')) {
      await migrator.createTable(questInstances);
    }
    if (!await _tableExists('quest_objective_progress')) {
      await migrator.createTable(questObjectiveProgress);
    }
    if (!await _tableExists('streak_states')) {
      await migrator.createTable(streakStates);
    }
    if (!await _tableExists('learning_day_log')) {
      await migrator.createTable(learningDayLog);
    }
    if (!await _tableExists('association_records')) {
      await migrator.createTable(associationRecords);
    }
    if (!await _tableExists('associative_memory_states')) {
      await migrator.createTable(associativeMemoryStates);
    }
    if (!await _tableExists('ai_usage_events')) {
      await migrator.createTable(aiUsageEvents);
    }
    if (!await _tableExists('speech_evidence')) {
      await migrator.createTable(speechEvidence);
    }
  }

  Future<void> _addColumnIfMissing(
    Migrator migrator,
    String tableName,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    if (!await _columnExists(tableName, column.$name)) {
      await migrator.addColumn(table, column);
    }
  }

  Future<bool> _columnExists(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  Future<bool> _tableExists(String tableName) async {
    final row = await customSelect(
      "SELECT 1 AS present FROM sqlite_master "
      "WHERE type = 'table' AND name = ? LIMIT 1",
      variables: [Variable<String>(tableName)],
    ).getSingleOrNull();
    return row != null;
  }
}
