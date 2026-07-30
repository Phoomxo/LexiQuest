import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/identity_tables.dart';
import 'tables/learning_tables.dart';
import 'tables/model_tables.dart';
import 'tables/progress_tables.dart';
import 'tables/runtime_tables.dart';
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
    OutboxOperations,
    SyncCheckpoints,
    SyncConflicts,
    RuntimeFlags,
    ModelDownloads,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.production() : super(driftDatabase(name: 'lexiquest'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(
          vocabularyCategories,
          vocabularyCategories.cloudRevision,
        );
        await migrator.addColumn(
          vocabularyCategories,
          vocabularyCategories.lastAcknowledgedAtUtcMs,
        );
        await migrator.addColumn(
          vocabularyCategories,
          vocabularyCategories.serverUpdatedAtUtcMs,
        );
        await migrator.addColumn(
          vocabularyWords,
          vocabularyWords.cloudRevision,
        );
        await migrator.addColumn(
          vocabularyWords,
          vocabularyWords.lastAcknowledgedAtUtcMs,
        );
        await migrator.addColumn(
          vocabularyWords,
          vocabularyWords.serverUpdatedAtUtcMs,
        );
        await migrator.addColumn(outboxOperations, outboxOperations.leaseToken);
        await migrator.addColumn(
          outboxOperations,
          outboxOperations.leaseExpiresAtUtcMs,
        );
        await migrator.addColumn(
          outboxOperations,
          outboxOperations.lastAttemptAtUtcMs,
        );
        await migrator.addColumn(
          syncConflicts,
          syncConflicts.localSnapshotJson,
        );
        await migrator.addColumn(
          syncConflicts,
          syncConflicts.cloudSnapshotJson,
        );
        await migrator.createTable(runtimeFlags);
      }
      if (from < 3) {
        await _createLearningIndexes();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createLearningIndexes();
    },
  );

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
}
