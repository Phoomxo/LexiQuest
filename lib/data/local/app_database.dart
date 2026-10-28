import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'app_database_open_policy.dart';
import 'app_database_stub_path.dart'
    if (dart.library.ffi) 'app_database_native_path.dart';

import 'research_schema_guards.dart';
import '../../features/quest/domain/quest_definition_codec.dart';
import '../../features/quest/domain/quest_period.dart';

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
import 'tables/personal_set_tables.dart';
import 'tables/study_plan_tables.dart';
import 'tables/guided_repair_tables.dart';
import 'tables/written_practice_tables.dart';
import 'tables/speaking_practice_tables.dart';
import 'tables/audio_lesson_tables.dart';
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
    MotivationMeasurementRuns,
    MotivationResponses,
    ResearchParticipationPermits,
    MeasurementOpportunities,
    ResearchSessionProofs,
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
    LegacyLearningRecords,
    AssociativeMemoryStates,
    AiUsageEvents,
    SpeechEvidence,
    SavedLearningItems,
    ContentQualityReports,
    LearningTimeSegments,
    LearningGoals,
    StudyReminders,
    LearnerPreferences,
    PersonalSetRevisions,
    PersonalSetMembers,
    StudyPlanRevisions,
    ActivePlanPointers,
    GuidedRepairOperations,
    WrittenPracticeResults,
    SpeakingPracticeResults,
    AudioLessonCheckpoints,
  ],
)
final class AppDatabase extends _$AppDatabase {
  static const int currentSchemaVersion = 34;

  AppDatabase(super.executor);

  AppDatabase.production()
    : super(
        LazyDatabase(() async {
          // Run preflight before drift_flutter creates its eager delayed connection.
          final path = await resolveAppDatabasePath(currentSchemaVersion);
          return driftDatabase(
            name: 'lexiquest',
            native: path == null
                ? null
                : DriftNativeOptions(
                    databasePath: () async => path,
                    setup: (database) =>
                        configureAppDatabase(database, currentSchemaVersion),
                  ),
          );
        }),
      );

  @override
  Future<void> close() async {
    try {
      await super.close();
    } on AppDatabaseOpenException {
      // A rejected read-only preflight has no open delegate to dispose.
      // The readiness query already reported the typed failure to its caller.
    }
  }

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      await _createMissingTables(migrator);
      if (from < 28) {
        await _addColumnIfMissing(
          migrator,
          'outbox_operations',
          outboxOperations,
          outboxOperations.attemptedMutationJson,
        );
      }
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
      if (from < 22) {
        await _addColumnIfMissing(
          migrator,
          'learner_preferences',
          learnerPreferences,
          learnerPreferences.themeMode,
        );
        await _addColumnIfMissing(
          migrator,
          'learner_preferences',
          learnerPreferences,
          learnerPreferences.motionMode,
        );
        await _addColumnIfMissing(
          migrator,
          'learner_preferences',
          learnerPreferences,
          learnerPreferences.displayUpdatedAtUtcMs,
        );
      }
      if (from < 23) {
        await _addColumnIfMissing(
          migrator,
          'learner_preferences',
          learnerPreferences,
          learnerPreferences.homeExperience,
        );
        await customStatement('''
          UPDATE learner_preferences
          SET preference_version = 2
          WHERE preference_version = 1
        ''');
      }
      if (from < 24) {
        await migrator.createTable(motivationMeasurementRuns);
        await migrator.createTable(motivationResponses);
        await migrator.createTable(researchParticipationPermits);
        await migrator.createTable(measurementOpportunities);
      }
      if (from < 25) await _upgradeQuestPeriods(migrator);
      if (from < 26) await _upgradeResearchSessionProofs(migrator);
      // The v29-v34 extensions are one additive unit. Do not wrap historical table
      // rebuilds here: those own their foreign-key/transaction boundaries.
      await transaction(() async {
        if (!await _tableExists('personal_set_revisions')) {
          await migrator.createTable(personalSetRevisions);
        }
        if (!await _tableExists('personal_set_members')) {
          await migrator.createTable(personalSetMembers);
        }
        if (!await _tableExists('audio_lesson_checkpoints')) {
          await migrator.createTable(audioLessonCheckpoints);
        }
        if (!await _tableExists('speaking_practice_results')) {
          await migrator.createTable(speakingPracticeResults);
        }
        if (!await _tableExists('written_practice_results')) {
          await migrator.createTable(writtenPracticeResults);
        }
        if (!await _tableExists('guided_repair_operations')) {
          await migrator.createTable(guidedRepairOperations);
        }
        if (!await _tableExists('study_plan_revisions')) {
          await migrator.createTable(studyPlanRevisions);
        }
        if (!await _tableExists('active_plan_pointers')) {
          await migrator.createTable(activePlanPointers);
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement("CREATE TRIGGER IF NOT EXISTS audio_lesson_immutable "
          "BEFORE UPDATE OF activity_id, revision, operation_id, payload_json ON audio_lesson_checkpoints "
          "BEGIN SELECT RAISE(ABORT, 'audio_lesson_immutable'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS audio_lesson_no_replace "
          "BEFORE INSERT ON audio_lesson_checkpoints WHEN EXISTS (SELECT 1 FROM audio_lesson_checkpoints "
          "WHERE owner_id=NEW.owner_id AND (operation_id=NEW.operation_id OR "
          "(activity_id=NEW.activity_id AND revision=NEW.revision))) "
          "BEGIN SELECT RAISE(ABORT, 'audio_lesson_duplicate'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS written_practice_immutable "
          "BEFORE UPDATE OF activity_id, revision, operation_id, payload_json ON written_practice_results "
          "BEGIN SELECT RAISE(ABORT, 'written_practice_immutable'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS written_practice_no_replace "
          "BEFORE INSERT ON written_practice_results WHEN EXISTS (SELECT 1 FROM written_practice_results "
          "WHERE owner_id=NEW.owner_id AND (operation_id=NEW.operation_id OR "
          "(activity_id=NEW.activity_id AND revision=NEW.revision))) "
          "BEGIN SELECT RAISE(ABORT, 'written_practice_duplicate'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS speaking_practice_immutable "
          "BEFORE UPDATE OF activity_id, revision, operation_id, payload_json ON speaking_practice_results "
          "BEGIN SELECT RAISE(ABORT, 'speaking_practice_immutable'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS speaking_practice_no_replace "
          "BEFORE INSERT ON speaking_practice_results WHEN EXISTS (SELECT 1 FROM speaking_practice_results "
          "WHERE owner_id=NEW.owner_id AND (operation_id=NEW.operation_id OR "
          "(activity_id=NEW.activity_id AND revision=NEW.revision))) "
          "BEGIN SELECT RAISE(ABORT, 'speaking_practice_duplicate'); END");
      await customStatement("""
        CREATE TRIGGER IF NOT EXISTS legacy_learning_records_immutable
        BEFORE UPDATE OF id, source_table, payload_json ON legacy_learning_records
        BEGIN SELECT RAISE(ABORT, 'legacy_learning_history_immutable'); END
      """);
      await customStatement("CREATE TRIGGER IF NOT EXISTS guided_repair_immutable "
          "BEFORE UPDATE OF operation_id, origin_id, revision, payload_json ON guided_repair_operations "
          "BEGIN SELECT RAISE(ABORT, 'guided_repair_immutable'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS guided_repair_no_replace "
          "BEFORE INSERT ON guided_repair_operations WHEN EXISTS (SELECT 1 FROM guided_repair_operations "
          "WHERE owner_id=NEW.owner_id AND operation_id=NEW.operation_id) "
          "BEGIN SELECT RAISE(ABORT, 'guided_repair_duplicate'); END");
      await _createLearningIndexes();
      await _createEventIndexes();
      await _createAiUsageIndexes();
      await _createContentManifestImmutabilityTriggers();
      await _createLearningTimeGuards();
      await _createQuestGuards();
      await _createPersonalSetGuards();
      await customStatement("CREATE TRIGGER IF NOT EXISTS study_plan_immutable "
          "BEFORE UPDATE OF operation_id, revision, payload_hash, payload_json ON study_plan_revisions "
          "WHEN OLD.operation_id IS NOT NEW.operation_id OR OLD.revision IS NOT NEW.revision "
          "OR OLD.payload_hash IS NOT NEW.payload_hash OR OLD.payload_json IS NOT NEW.payload_json "
          "BEGIN SELECT RAISE(ABORT, 'study_plan_immutable'); END");
      await customStatement("CREATE TRIGGER IF NOT EXISTS study_plan_no_replace "
          "BEFORE INSERT ON study_plan_revisions WHEN EXISTS (SELECT 1 FROM study_plan_revisions "
          "WHERE owner_id=NEW.owner_id AND operation_id=NEW.operation_id) "
          "BEGIN SELECT RAISE(ABORT, 'study_plan_duplicate'); END");
      await installResearchSchemaGuards((sql) => customStatement(sql));
    },
  );

  Future<void> _upgradeResearchSessionProofs(Migrator migrator) async {
    final foreignKeys = (await customSelect(
      'PRAGMA foreign_keys',
    ).getSingle()).read<int>('foreign_keys');
    final legacyAlter = (await customSelect(
      'PRAGMA legacy_alter_table',
    ).getSingle()).read<int>('legacy_alter_table');
    try {
      // The older quest migration may have restored FK ON. SQLite ignores
      // disabling it inside a transaction, so verify this boundary explicitly.
      await customStatement('PRAGMA foreign_keys = OFF');
      if ((await customSelect(
            'PRAGMA foreign_keys',
          ).getSingle()).read<int>('foreign_keys') !=
          0) {
        throw StateError(
          'research proof migration requires foreign keys off before transaction',
        );
      }
      await transaction(() async {
        final retained = <String, String>{};
        for (final table in [
          'motivation_measurement_runs',
          'motivation_responses',
          'research_participation_permits',
          'measurement_opportunities',
          'learning_sessions',
          'quest_instances',
          'quest_objective_progress',
          'points_ledger_entries',
          'reward_transactions',
          'events_v2',
          if (await _tableExists('research_session_proofs'))
            'research_session_proofs',
        ]) {
          retained[table] = await _researchMigrationRows(table);
        }
        // Keep creation within this transaction. A failed retained-authority
        // check must leave raw25 without a partially installed proof table.
        if (!await _tableExists('research_session_proofs')) {
          await migrator.createTable(researchSessionProofs);
        }
        final references = await customSelect(
          'PRAGMA foreign_key_list(measurement_opportunities)',
        ).get();
        if (references.any(
          (row) => row.read<String>('table') == 'learning_sessions',
        )) {
          // This retained parent trigger references the table across the
          // DROP/rename gap. Reinstall its unchanged definition before commit.
          await customStatement(
            'DROP TRIGGER IF EXISTS learning_sessions_referenced_pins_v24_update',
          );
          await migrator.alterTable(TableMigration(measurementOpportunities));
        }
        await installResearchSchemaGuards((sql) => customStatement(sql));
        for (final entry in retained.entries) {
          if (await _researchMigrationRows(entry.key) != entry.value) {
            throw StateError(
              'research proof migration changed retained ${entry.key}',
            );
          }
        }
        if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw StateError(
            'research proof migration foreign key validation failed',
          );
        }
        // The removed canonical-session FK cannot check polymorphic authority.
        // Validate every retained row, including tombstones, before commit.
        final orphan = await customSelect(
          '''SELECT 1 FROM measurement_opportunities o
          WHERE ${researchOpportunityAuthorityMismatch('o')} LIMIT 1''',
        ).get();
        final invalidProof = await customSelect(
          '''SELECT 1 FROM research_session_proofs q
          WHERE ${researchSessionProofOwnerMismatch('q')}
            OR ${researchSessionProofSiblingMismatch('q')} LIMIT 1''',
        ).get();
        if (orphan.isNotEmpty || invalidProof.isNotEmpty) {
          throw StateError(
            'research proof migration retained authority validation failed',
          );
        }
      });
    } finally {
      try {
        await customStatement('PRAGMA legacy_alter_table = $legacyAlter');
      } finally {
        await customStatement('PRAGMA foreign_keys = $foreignKeys');
      }
    }
  }

  Future<String> _researchMigrationRows(String table) async => jsonEncode(
    (await customSelect(
      'SELECT * FROM $table ORDER BY 1',
    ).get()).map((row) => row.data).toList(),
  );

  Future<void> _upgradeQuestPeriods(Migrator migrator) async {
    final foreignKeys = (await customSelect(
      'PRAGMA foreign_keys',
    ).getSingle()).read<int>('foreign_keys');
    final legacyAlter = (await customSelect(
      'PRAGMA legacy_alter_table',
    ).getSingle()).read<int>('legacy_alter_table');
    try {
      // SQLite ignores this pragma inside a transaction. The parent rebuild
      // must not cascade-delete objective rows while replacing its table.
      await customStatement('PRAGMA foreign_keys = OFF');
      if ((await customSelect(
            'PRAGMA foreign_keys',
          ).getSingle()).read<int>('foreign_keys') !=
          0) {
        throw StateError(
          'quest migration requires foreign keys off before transaction',
        );
      }
      await transaction(() async {
        const instanceIdentity =
            'instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,completed_at_utc_ms,expired_at_utc_ms';
        final beforeInstances = await _questMigrationIdentity(
          'SELECT $instanceIdentity FROM quest_instances ORDER BY instance_id',
        );
        final retained = <String, String>{};
        for (final table in [
          'quest_objective_progress',
          'points_ledger_entries',
          'reward_transactions',
        ]) {
          retained[table] = await _questMigrationIdentity(
            'SELECT * FROM $table ORDER BY 1',
          );
        }
        final names = (await customSelect(
          'PRAGMA table_info(quest_instances)',
        ).get()).map((row) => row.read<String>('name')).toSet();
        final columns = [
          questInstances.periodPolicy,
          questInstances.periodKey,
          questInstances.periodTimezoneId,
          questInstances.periodStartAtUtcMs,
          questInstances.periodEndAtUtcMs,
          questInstances.deadlineAtUtcMs,
          questInstances.isCanonical,
          questInstances.definitionSnapshotJson,
        ];
        final missing = columns
            .where((column) => !names.contains(column.$name))
            .toList();
        if (missing.isNotEmpty) {
          await migrator.alterTable(
            TableMigration(questInstances, newColumns: missing),
          );
        }
        final legacyRows = await customSelect(
          "SELECT * FROM quest_instances WHERE period_key = '' AND period_policy = 'legacyDuration'",
        ).get();
        for (final row in legacyRows) {
          final id = row.read<String>('instance_id');
          final assigned = row.read<int>('assigned_at_utc_ms');
          String? snapshotJson;
          int? deadline;
          final stored = await customSelect(
            'SELECT * FROM quest_definitions WHERE quest_id = ?',
            variables: [Variable(row.read<String>('quest_id'))],
          ).getSingleOrNull();
          if (stored != null) {
            try {
              final definition = QuestDefinitionCodec.fromStorage(stored.data);
              final progressRows = await customSelect(
                'SELECT * FROM quest_objective_progress WHERE instance_id = ?',
                variables: [Variable(id)],
              ).get();
              if (definition.catalogVersion ==
                      row.read<int>('catalog_version') &&
                  QuestDefinitionCodec.matchesStoredProgress(
                    definition,
                    progressRows.map((item) => item.data).toList(),
                  )) {
                snapshotJson = QuestDefinitionCodec.encode(
                  QuestDefinitionSnapshot(
                    definition: definition,
                    origin: QuestDefinitionSnapshotOrigin.migrationCatalog,
                  ),
                );
                final duration = definition.expiresIn;
                if (duration != null) {
                  deadline = QuestPeriod.safeDeadline(
                    DateTime.fromMillisecondsSinceEpoch(assigned, isUtc: true),
                    duration,
                  ).millisecondsSinceEpoch;
                }
              }
            } on FormatException {
              /* Unknown history stays unknown. */
            } on TypeError {
              /* Malformed catalog/progress cannot become a pin. */
            } on ArgumentError {
              /* Invalid historical enum cannot become a pin. */
            }
          }
          await customStatement(
            'UPDATE quest_instances SET period_key = ?, period_start_at_utc_ms = ?, period_end_at_utc_ms = ?, deadline_at_utc_ms = ?, definition_snapshot_json = ? WHERE instance_id = ?',
            ['legacy:$id', assigned, deadline, deadline, snapshotJson, id],
          );
        }
        await _createQuestGuards();
        if (await _questMigrationIdentity(
              'SELECT $instanceIdentity FROM quest_instances ORDER BY instance_id',
            ) !=
            beforeInstances) {
          throw StateError(
            'quest migration changed historical instance identity',
          );
        }
        for (final entry in retained.entries) {
          if (await _questMigrationIdentity(
                'SELECT * FROM ${entry.key} ORDER BY 1',
              ) !=
              entry.value) {
            throw StateError('quest migration changed retained ${entry.key}');
          }
        }
        if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
          throw StateError('quest migration foreign key validation failed');
        }
      });
    } finally {
      await customStatement('PRAGMA legacy_alter_table = $legacyAlter');
      await customStatement('PRAGMA foreign_keys = $foreignKeys');
    }
  }

  Future<String> _questMigrationIdentity(String query) async => jsonEncode(
    (await customSelect(query).get()).map((row) => row.data).toList(),
  );

  Future<void> _createQuestGuards() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS quest_canonical_period ON quest_instances(owner_id,quest_id,period_key) WHERE is_canonical = 1',
    );
    await customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS quest_canonical_active ON quest_instances(owner_id,quest_id) WHERE is_canonical = 1 AND state = 'active'",
    );
    await customStatement(
      '''CREATE TRIGGER IF NOT EXISTS quest_definition_snapshot_immutable
      BEFORE UPDATE OF definition_snapshot_json ON quest_instances
      WHEN NEW.definition_snapshot_json IS NOT OLD.definition_snapshot_json
      BEGIN SELECT RAISE(ABORT, 'quest_definition_snapshot_is_immutable'); END''',
    );
  }

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

  Future<void> _createPersonalSetGuards() async {
    for (final (table, fields, key) in [
      ('personal_set_revisions',
       'set_id, revision, operation_id, payload_hash, payload_json, archived',
       '(owner_id = NEW.owner_id AND set_id = NEW.set_id AND revision = NEW.revision) OR (owner_id = NEW.owner_id AND operation_id = NEW.operation_id)'),
      ('personal_set_members',
       'set_id, revision, position, sense_ref_hash, sense_ref_json',
       'owner_id = NEW.owner_id AND set_id = NEW.set_id AND revision = NEW.revision AND (position = NEW.position OR sense_ref_hash = NEW.sense_ref_hash)'),
    ]) {
      // Only owner remapping is mutable; composite FK cascades to members.
      // Deletion is intentionally available to the owner lifecycle authority.
      final changed = fields.split(', ').map((field) => 'OLD.$field IS NOT NEW.$field').join(' OR ');
      await customStatement('CREATE TRIGGER IF NOT EXISTS ${table}_immutable '
          'BEFORE UPDATE OF $fields ON $table WHEN $changed BEGIN '
          "SELECT RAISE(ABORT, 'personal_set_immutable'); END");
      await customStatement('CREATE TRIGGER IF NOT EXISTS ${table}_no_replace '
          'BEFORE INSERT ON $table WHEN EXISTS (SELECT 1 FROM $table WHERE $key) '
          "BEGIN SELECT RAISE(ABORT, 'personal_set_duplicate'); END");
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
    if (!await _tableExists('legacy_learning_records')) {
      await migrator.createTable(legacyLearningRecords);
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
