import 'package:drift/drift.dart';
// Drift marks its wire protocol experimental. Its public exception API is stable.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart' show SqlError, SqliteException;

import 'legacy_v25_migration.dart';
import 'tables/associative_tables.dart';
import 'tables/event_tables.dart';
import 'tables/identity_tables.dart';
import 'tables/learning_tables.dart';
import 'tables/model_tables.dart';
import 'tables/motivation_tables.dart';
import 'tables/progress_tables.dart';
import 'tables/quest_tables.dart';
import 'tables/runtime_tables.dart';
import 'tables/study_tables.dart';
import 'tables/sync_tables.dart';
import 'tables/vocabulary_tables.dart';

part 'app_database.g.dart';

const _writerWait = Duration(seconds: 5);
const _writerRetryDelay = Duration(milliseconds: 25);

final _productionNativeOptions = DriftNativeOptions(
  setup: (database) {
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('PRAGMA busy_timeout = ${_writerWait.inMilliseconds}');
    database.execute('PRAGMA journal_mode = WAL');
  },
);

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
    OwnerCalendarEpochs,
    QuestDefinitionRevisions,
    QuestInstances,
    QuestObjectiveProgress,
    QuestClaimReceipts,
    StreakStates,
    LearningDayLog,
    StreakBaselines,
    StreakTokenAdjustments,
    AssociationRecords,
    AssociativeMemoryStates,
    LocalContentReports,
    FocusSessions,
    LearningPreferences,
    ArchivedV25Records,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.production()
    : super(driftDatabase(name: 'lexiquest', native: _productionNativeOptions));

  @override
  int get schemaVersion => 26;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    final elapsed = Stopwatch()..start();
    var actionStarted = false;
    while (true) {
      try {
        return await super.transaction(() {
          actionStarted = true;
          return action();
        }, requireNew: requireNew);
      } catch (error) {
        final cause = error is DriftRemoteException ? error.remoteCause : error;
        // SQLite can report BUSY immediately when acquiring the writer.
        // Once Drift has entered the callback, replay could repeat side effects.
        if (actionStarted ||
            cause is! SqliteException ||
            cause.resultCode != SqlError.SQLITE_BUSY ||
            cause.causingStatement != 'BEGIN IMMEDIATE' ||
            elapsed.elapsed + _writerRetryDelay >= _writerWait) {
          rethrow;
        }
        await Future<void>.delayed(_writerRetryDelay);
      }
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      await customStatement('PRAGMA foreign_keys = ON');
      final enforcement = await customSelect('PRAGMA foreign_keys').getSingle();
      if (enforcement.read<int>('foreign_keys') != 1) {
        throw StateError('Migration requires foreign-key enforcement');
      }
      await transaction(() async {
        final oldLineage = await LegacyV25Migration.detect(this, from);
        if (!oldLineage && (from > 12 || from < 1)) {
          throw StateError('Unsupported local database version $from');
        }
        if (from < 11 || oldLineage) {
          final unexpected = await customSelect(
            "SELECT name FROM sqlite_master WHERE lower(name) IN ("
            "'owner_calendar_epochs','quest_definition_revisions',"
            "'quest_claim_receipts','streak_baselines','streak_token_adjustments')",
          ).get();
          if (unexpected.isNotEmpty) {
            throw StateError('Unexpected schema 11 objects in legacy database');
          }
        }
        if (from < 12 || oldLineage) await _checkStudyMigrationSource();
        if (await _tableExists('archived_v25_records') ||
            await _columnExists(
              'learning_sessions',
              'legacy_evidence_disposition',
            ) ||
            await _columnExists(
              'answer_attempts',
              'legacy_evidence_disposition',
            )) {
          throw StateError('Unexpected schema 26 objects in legacy database');
        }
        final questParentExisted = await _tableExists('quest_instances');
        final sessionTableExisted = await _tableExists('learning_sessions');
        final attemptTableExisted = await _tableExists('answer_attempts');
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
        if (from < 11 || oldLineage) {
          await _addColumnIfMissing(
            migrator,
            'answer_attempts',
            answerAttempts,
            answerAttempts.calendarEvidence,
          );
          await _addColumnIfMissing(
            migrator,
            'answer_attempts',
            answerAttempts,
            answerAttempts.questIntent,
          );
          if (oldLineage) {
            await migrator.createTable(archivedV25Records);
            await LegacyV25Migration(this).archiveAndNormalize(migrator);
          } else {
            await _rebuildQuestPeriods(
              migrator,
              createdCurrentParent: !questParentExisted,
            );
          }
          if (!await _tableExists('quest_claim_receipts')) {
            await migrator.createTable(questClaimReceipts);
          }
          if (!await _tableExists('streak_baselines')) {
            await migrator.createTable(streakBaselines);
          }
          if (!await _tableExists('streak_token_adjustments')) {
            await migrator.createTable(streakTokenAdjustments);
          }
          await _sealStreakBaselines();
          await _createS6Indexes();
          if ((await customSelect(
            'PRAGMA foreign_key_check',
          ).get()).isNotEmpty) {
            throw StateError('Schema 11 foreign-key validation failed');
          }
        }
        if (from < 12 || oldLineage) {
          await _migrateLocalStudy(migrator);
        }
        if (!oldLineage) await migrator.createTable(archivedV25Records);
        if (sessionTableExisted) {
          await migrator.addColumn(
            learningSessions,
            learningSessions.legacyEvidenceDisposition,
          );
        }
        if (attemptTableExisted) {
          await migrator.addColumn(
            answerAttempts,
            answerAttempts.legacyEvidenceDisposition,
          );
        }
        if (oldLineage) await LegacyV25Migration(this).restoreStudyFlags();
        await _createLegacyArchiveIndex();
        if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw StateError('Schema 26 foreign-key validation failed');
        }
        // Publish with the validated DDL so a beforeOpen failure cannot replay it.
        await customStatement('PRAGMA user_version = 26');
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createLearningIndexes();
      await _createEventIndexes();
      await _createS6Indexes();
      await _createStudyIndexes();
      await _createLegacyArchiveIndex();
    },
  );

  Future<void> _createLegacyArchiveIndex() => _ensureExactIndexes(const [
    'CREATE INDEX IF NOT EXISTS idx_archived_v25_owner ON archived_v25_records(owner_id, source_table, source_row_key)',
  ]);

  Future<void> _checkStudyMigrationSource() async {
    final unexpected = await customSelect(
      "SELECT name FROM sqlite_master WHERE lower(name) IN ("
      "'local_content_reports','focus_sessions','learning_preferences',"
      "'idx_focus_open_owner','idx_focus_owner_start_week') "
      "ORDER BY name LIMIT 1",
    ).getSingleOrNull();
    if (unexpected != null) {
      throw StateError(
        'Unexpected schema 12 object in legacy database: '
        '${unexpected.read<String>('name')}',
      );
    }
    for (final (table, column) in const [
      ('learning_sessions', 'question_plan_json'),
      ('learning_sessions', 'continuation_json'),
      ('answer_attempts', 'answer_evidence_json'),
      ('vocabulary_words', 'is_bookmarked'),
    ]) {
      if (await _columnExists(table, column)) {
        throw StateError('Unexpected schema 12 column: $table.$column');
      }
    }
  }

  Future<void> _migrateLocalStudy(Migrator migrator) async {
    await _addColumnIfMissing(
      migrator,
      'learning_sessions',
      learningSessions,
      learningSessions.questionPlanJson,
    );
    await _addColumnIfMissing(
      migrator,
      'learning_sessions',
      learningSessions,
      learningSessions.continuationJson,
    );
    await _addColumnIfMissing(
      migrator,
      'answer_attempts',
      answerAttempts,
      answerAttempts.answerEvidenceJson,
    );
    await _addColumnIfMissing(
      migrator,
      'vocabulary_words',
      vocabularyWords,
      vocabularyWords.isBookmarked,
    );
    await migrator.createTable(localContentReports);
    await migrator.createTable(focusSessions);
    await migrator.createTable(learningPreferences);
    await _createStudyIndexes();
    final violations = await customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      throw StateError('Schema 12 foreign-key validation failed');
    }
  }

  Future<void> _rebuildQuestPeriods(
    Migrator migrator, {
    required bool createdCurrentParent,
  }) async {
    if (createdCurrentParent) return;
    const parent = 'quest_instances';
    const child = 'quest_objective_progress';
    const parentFields =
        'instance_id,quest_id,owner_id,catalog_version,'
        'assigned_at_utc_ms,state,completed_at_utc_ms,expired_at_utc_ms';
    const childFields =
        'id,instance_id,objective_id,current_count,'
        'target_count,source_event_ids_json';
    final fields = (await customSelect(
      'PRAGMA table_info($parent)',
    ).get()).map((row) => row.read<String>('name')).toSet();
    var lifetimeUnique = false;
    for (final index in await customSelect(
      'PRAGMA index_list($parent)',
    ).get()) {
      if (index.read<int>('unique') != 1) continue;
      final name = index.read<String>('name').replaceAll('"', '""');
      final columns = (await customSelect(
        'PRAGMA index_info("$name")',
      ).get()).map((row) => row.readNullable<String>('name')).toSet();
      if (columns.length == 2 &&
          columns.containsAll({'owner_id', 'quest_id'})) {
        lifetimeUnique = true;
      }
    }
    if (!lifetimeUnique ||
        fields.length != 8 ||
        !fields.containsAll(parentFields.split(','))) {
      throw StateError('Unsupported legacy Quest parent shape');
    }
    final objectiveFields = (await customSelect(
      'PRAGMA table_info($child)',
    ).get()).map((row) => row.read<String>('name')).toSet();
    if (objectiveFields.length != 6 ||
        !objectiveFields.containsAll(childFields.split(','))) {
      throw StateError('Unsupported legacy Quest objective shape');
    }
    final objects = await customSelect(
      "SELECT name FROM sqlite_master WHERE sql IS NOT NULL AND "
      "((tbl_name IN ('$parent','$child') AND type IN ('index','trigger')) "
      "OR (type='view' AND (lower(sql) LIKE '%$parent%' OR lower(sql) LIKE '%$child%')))",
    ).get();
    if (objects.isNotEmpty) {
      throw StateError('Unsupported legacy Quest dependent object');
    }
    for (final table in await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get()) {
      final name = table.read<String>('name');
      final quoted = name.replaceAll('"', '""');
      for (final fk in await customSelect(
        'PRAGMA foreign_key_list("$quoted")',
      ).get()) {
        final target = fk.read<String>('table').toLowerCase();
        if ((target == parent && name != child) || target == child) {
          throw StateError('Unsupported legacy Quest dependent table');
        }
      }
    }
    await customStatement(
      'CREATE TEMP TABLE _s6_quest_parent AS SELECT $parentFields FROM $parent',
    );
    await customStatement(
      'CREATE TEMP TABLE _s6_quest_child AS SELECT $childFields FROM $child',
    );
    await customStatement('DROP TABLE $child');
    await customStatement('DROP TABLE $parent');
    await migrator.createTable(questInstances);
    await migrator.createTable(questObjectiveProgress);
    await customStatement(
      'INSERT INTO $parent ($parentFields) SELECT $parentFields FROM _s6_quest_parent',
    );
    await customStatement(
      'INSERT INTO $child ($childFields) SELECT $childFields FROM _s6_quest_child',
    );
    for (final (table, staged, columns) in [
      (parent, '_s6_quest_parent', parentFields),
      (child, '_s6_quest_child', childFields),
    ]) {
      final before = await customSelect(
        'SELECT COUNT(*) AS n FROM $staged',
      ).getSingle();
      final after = await customSelect(
        'SELECT COUNT(*) AS n FROM $table',
      ).getSingle();
      final missing = await customSelect(
        'SELECT $columns FROM $staged EXCEPT SELECT $columns FROM $table LIMIT 1',
      ).get();
      final extra = await customSelect(
        'SELECT $columns FROM $table EXCEPT SELECT $columns FROM $staged LIMIT 1',
      ).get();
      if (before.read<int>('n') != after.read<int>('n') ||
          missing.isNotEmpty ||
          extra.isNotEmpty) {
        throw StateError('Legacy Quest data conservation failed');
      }
    }
    await customStatement('DROP TABLE _s6_quest_child');
    await customStatement('DROP TABLE _s6_quest_parent');
  }

  Future<void> _sealStreakBaselines() async {
    await customStatement(
      'INSERT INTO streak_baselines (origin_owner_id,owner_id,cutoff_utc_ms,'
      'current_streak_days,longest_streak_days,freeze_count,last_learned_at_utc_ms,'
      'updated_at_utc_ms,controls_continuity) SELECT owner_id,owner_id,?,'
      'current_streak_days,longest_streak_days,freeze_count,last_learned_at_utc_ms,'
      'updated_at_utc_ms,1 FROM streak_states s WHERE NOT EXISTS '
      '(SELECT 1 FROM streak_baselines b WHERE b.origin_owner_id=s.owner_id)',
      [DateTime.now().toUtc().millisecondsSinceEpoch],
    );
    final conflicts = await customSelect(
      'SELECT 1 FROM streak_states s JOIN streak_baselines b ON b.origin_owner_id=s.owner_id '
      'WHERE b.owner_id IS NOT s.owner_id OR b.current_streak_days IS NOT s.current_streak_days '
      'OR b.longest_streak_days IS NOT s.longest_streak_days OR b.freeze_count IS NOT s.freeze_count '
      'OR b.last_learned_at_utc_ms IS NOT s.last_learned_at_utc_ms OR b.updated_at_utc_ms IS NOT s.updated_at_utc_ms LIMIT 1',
    ).get();
    if (conflicts.isNotEmpty) {
      throw StateError('Legacy Streak baseline conflict');
    }
  }

  Future<void> _createS6Indexes() => _ensureExactIndexes(const [
    'CREATE INDEX IF NOT EXISTS idx_learning_attempts_owner_time_id ON answer_attempts(owner_id,occurred_at_utc_ms,id)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_selected_owner_effective ON owner_calendar_epochs(owner_id,effective_utc_us) WHERE is_selected=1',
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_quest_canonical_owner_period ON quest_instances(owner_id,period_key) WHERE record_kind='canonical'",
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_streak_continuity_owner ON streak_baselines(owner_id) WHERE controls_continuity=1',
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_streak_auto_protection_origin_day ON streak_token_adjustments(origin_owner_id,protected_day) WHERE kind='autoProtect'",
  ]);

  Future<void> _createStudyIndexes() => _ensureExactIndexes(const [
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_focus_open_owner ON focus_sessions(owner_id) WHERE state IN ('running','paused')",
    'CREATE INDEX IF NOT EXISTS idx_focus_owner_start_week ON focus_sessions(owner_id,start_civil_week)',
  ]);

  Future<void> _ensureExactIndexes(List<String> definitions) async {
    for (final sql in definitions) {
      final name = sql.split(' IF NOT EXISTS ')[1].split(' ')[0];
      final existing = await customSelect(
        'SELECT type,sql FROM sqlite_master WHERE name = ? COLLATE NOCASE',
        variables: [Variable<String>(name)],
      ).getSingleOrNull();
      if (existing != null &&
          (existing.read<String>('type') != 'index' ||
              existing.readNullable<String>('sql')?.trim() !=
                  sql.replaceFirst(' IF NOT EXISTS', '').trim())) {
        throw StateError('Unexpected definition for index $name');
      }
      await customStatement(sql);
    }
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
    if (!await _tableExists('owner_calendar_epochs')) {
      await migrator.createTable(ownerCalendarEpochs);
    }
    if (!await _tableExists('quest_definition_revisions')) {
      await migrator.createTable(questDefinitionRevisions);
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
