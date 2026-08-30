import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/ai_usage_tables.dart';
import 'tables/associative_tables.dart';
import 'tables/content_download_tables.dart';
import 'tables/content_tables.dart';
import 'tables/event_tables.dart';
import 'tables/identity_tables.dart';
import 'tables/learning_tables.dart';
import 'tables/model_tables.dart';
import 'tables/motivation_tables.dart';
import 'tables/planning_tables.dart';
import 'tables/preference_tables.dart';
import 'tables/progress_tables.dart';
import 'tables/quest_tables.dart';
import 'tables/research_tables.dart';
import 'tables/review_tables.dart';
import 'tables/runtime_tables.dart';
import 'tables/speech_evidence_tables.dart';
import 'tables/sync_tables.dart';
import 'tables/time_tracking_tables.dart';
import 'tables/vocabulary_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    LocalOwners,
    ResearchConsents,
    ExperimentAssignments,
    AssessmentRuns,
    VocabularyCategories,
    VocabularyWords,
    VocabularyImports,
    VocabularyImportRows,
    ContentManifests,
    LearningPacks,
    LearningPackItems,
    ContentDownloadStates,
    LearningSessions,
    SessionConfigurations,
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
    SavedLearningItems,
    ContentQualityReports,
    LearningTimeSegments,
    LearningGoals,
    StudyReminders,
    LearnerPreferences,
  ],
)
final class AppDatabase extends _$AppDatabase {
  static const int currentSchemaVersion = 21;

  AppDatabase(super.executor);

  AppDatabase.production() : super(driftDatabase(name: 'lexiquest'));

  @override
  int get schemaVersion => currentSchemaVersion;

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
      if (from < 12) {
        await _migrateAiUsageToOwnerScope(migrator);
      }
      if (from < 13) {
        await _addColumnIfMissing(
          migrator,
          'answer_attempts',
          answerAttempts,
          answerAttempts.evidenceClass,
        );
        await _addColumnIfMissing(
          migrator,
          'answer_attempts',
          answerAttempts,
          answerAttempts.evidenceContextJson,
        );
      }
      if (from < 14 && !await _tableExists('experiment_assignments')) {
        await migrator.createTable(experimentAssignments);
      }
      if (from < 15 && !await _tableExists('assessment_runs')) {
        await migrator.createTable(assessmentRuns);
      }
      if (from < 16) {
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.contentRevision,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.contentChecksumSha256,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.contentProvenance,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.contentReviewState,
        );
        await _addColumnIfMissing(
          migrator,
          'vocabulary_words',
          vocabularyWords,
          vocabularyWords.contentPublicationState,
        );
      }
      if (from < 17) {
        if (!await _tableExists('saved_learning_items')) {
          await migrator.createTable(savedLearningItems);
        }
        if (!await _tableExists('content_quality_reports')) {
          await migrator.createTable(contentQualityReports);
        }
      }
      if (from < 18 && !await _tableExists('learning_time_segments')) {
        await migrator.createTable(learningTimeSegments);
      }
      if (from < 19) {
        if (!await _tableExists('learning_goals')) {
          await migrator.createTable(learningGoals);
        }
        if (!await _tableExists('study_reminders')) {
          await migrator.createTable(studyReminders);
        }
      }
      if (from < 20) {
        if (!await _tableExists('session_configurations')) {
          await migrator.createTable(sessionConfigurations);
        }
        await _addColumnIfMissing(
          migrator,
          'learning_sessions',
          learningSessions,
          learningSessions.sessionConfigurationIdentity,
        );
        await _addColumnIfMissing(
          migrator,
          'learning_sessions',
          learningSessions,
          learningSessions.sessionConfigurationJson,
        );
        await _addColumnIfMissing(
          migrator,
          'learning_sessions',
          learningSessions,
          learningSessions.configurationActiveEffortUs,
        );
      }
      if (from < 21 && !await _tableExists('learner_preferences')) {
        await migrator.createTable(learnerPreferences);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createLearningIndexes();
      await _createEventIndexes();
      await _createAiUsageIndexes();
      await _createContentManifestImmutabilityTriggers();
      await _createLearningTimeGuards();
    },
  );

  Future<void> _createLearningTimeGuards() async {
    if (!await _tableExists('learning_time_segments')) return;
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS learning_time_segments_require_authority
      BEFORE INSERT ON learning_time_segments
      WHEN NEW.active_duration_ms > 300000 OR NOT EXISTS (
        SELECT 1 FROM learning_sessions AS session
        WHERE session.id = NEW.session_id
          AND session.owner_id = NEW.owner_id
      )
      BEGIN
        SELECT RAISE(ABORT, 'learning_time_segment_authority_invalid');
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS learning_time_segments_reject_overlap
      BEFORE INSERT ON learning_time_segments
      WHEN EXISTS (
        SELECT 1 FROM learning_time_segments AS existing
        WHERE existing.session_id = NEW.session_id
          AND existing.active_start_offset_ms
                < NEW.active_start_offset_ms + NEW.active_duration_ms
          AND existing.active_start_offset_ms + existing.active_duration_ms
                > NEW.active_start_offset_ms
      )
      BEGIN
        SELECT RAISE(ABORT, 'learning_time_segments_must_not_overlap');
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS learning_time_segments_reject_mutation
      BEFORE UPDATE OF id, session_id, active_start_offset_ms, active_duration_ms,
        started_at_utc_ms, ended_at_utc_ms, timezone_id,
        timezone_offset_minutes, capture_source
      ON learning_time_segments
      BEGIN
        SELECT RAISE(ABORT, 'learning_time_segment_is_immutable');
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS learning_time_segments_require_owner_update
      BEFORE UPDATE OF owner_id ON learning_time_segments
      WHEN NOT EXISTS (
        SELECT 1 FROM learning_sessions AS session
        WHERE session.id = OLD.session_id
          AND session.owner_id = NEW.owner_id
      )
      BEGIN
        SELECT RAISE(ABORT, 'learning_time_segment_owner_mismatch');
      END
    ''');
  }

  Future<void> _createContentManifestImmutabilityTriggers() async {
    if (!await _tableExists('content_manifests')) return;
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS content_manifests_reject_conflicting_insert
      BEFORE INSERT ON content_manifests
      WHEN EXISTS (
        SELECT 1
        FROM content_manifests AS existing
        WHERE (
          existing.id = NEW.id OR (
            existing.content_type = NEW.content_type AND
            existing.content_id = NEW.content_id AND
            existing.revision = NEW.revision
          )
        ) AND NOT (
          existing.id IS NEW.id AND
          existing.content_type IS NEW.content_type AND
          existing.content_id IS NEW.content_id AND
          existing.revision IS NEW.revision AND
          existing.checksum_sha256 IS NEW.checksum_sha256 AND
          existing.byte_length IS NEW.byte_length AND
          existing.provenance IS NEW.provenance AND
          existing.source_uri IS NEW.source_uri AND
          existing.review_state IS NEW.review_state AND
          existing.publication_state IS NEW.publication_state AND
          existing.created_at_utc_ms IS NEW.created_at_utc_ms AND
          existing.reviewed_at_utc_ms IS NEW.reviewed_at_utc_ms AND
          existing.published_at_utc_ms IS NEW.published_at_utc_ms
        )
      )
      BEGIN
        SELECT RAISE(ABORT, 'content_manifest_revision_is_immutable');
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS content_manifests_reject_update
      BEFORE UPDATE ON content_manifests
      BEGIN
        SELECT RAISE(ABORT, 'content_manifest_revision_is_immutable');
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS content_manifests_reject_delete
      BEFORE DELETE ON content_manifests
      BEGIN
        SELECT RAISE(ABORT, 'content_manifest_revision_is_immutable');
      END
    ''');
  }

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

  Future<void> _createAiUsageIndexes() async {
    if (await _tableExists('ai_usage_events') &&
        await _columnExists('ai_usage_events', 'owner_id')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_ai_usage_owner_occurred '
        'ON ai_usage_events(owner_id, occurred_at_utc_ms)',
      );
    }
  }

  Future<void> _migrateAiUsageToOwnerScope(Migrator migrator) async {
    if (!await _tableExists('ai_usage_events')) {
      await migrator.createTable(aiUsageEvents);
      return;
    }
    if (await _columnExists('ai_usage_events', 'owner_id')) return;

    // Schema v11 usage rows have no owner attribution. Assigning them to the
    // owner active at migration time would leak metadata across accounts, so
    // discard only this bounded 90-day telemetry table and recreate it.
    await customStatement('DROP TABLE ai_usage_events');
    await migrator.createTable(aiUsageEvents);
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
    if (!await _tableExists('content_manifests')) {
      await migrator.createTable(contentManifests);
    }
    if (!await _tableExists('learning_packs')) {
      await migrator.createTable(learningPacks);
    }
    if (!await _tableExists('learning_pack_items')) {
      await migrator.createTable(learningPackItems);
    }
    if (!await _tableExists('content_download_states')) {
      await migrator.createTable(contentDownloadStates);
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
    if (!await _tableExists('saved_learning_items')) {
      await migrator.createTable(savedLearningItems);
    }
    if (!await _tableExists('content_quality_reports')) {
      await migrator.createTable(contentQualityReports);
    }
    if (!await _tableExists('learning_time_segments')) {
      await migrator.createTable(learningTimeSegments);
    }
    if (!await _tableExists('learning_goals')) {
      await migrator.createTable(learningGoals);
    }
    if (!await _tableExists('study_reminders')) {
      await migrator.createTable(studyReminders);
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
