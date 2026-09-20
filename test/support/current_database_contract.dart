import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

const currentDatabaseTableInventory = <String>{
  'written_practice_results',
  'guided_repair_operations',
  'study_plan_revisions',
  'active_plan_pointers',
  'personal_set_revisions',
  'personal_set_members',
  'local_owners',
  'research_consents',
  'experiment_assignments',
  'assessment_runs',
  'motivation_measurement_runs',
  'motivation_responses',
  'research_participation_permits',
  'measurement_opportunities',
  'research_session_proofs',
  'vocabulary_categories',
  'vocabulary_words',
  'vocabulary_imports',
  'vocabulary_import_rows',
  'learning_packs',
  'learning_pack_items',
  'content_manifests',
  'content_download_states',
  'learning_sessions',
  'session_configurations',
  'answer_attempts',
  'srs_states',
  'reading_progress_entries',
  'reading_events',
  'points_ledger_entries',
  'achievement_unlocks',
  'reward_transactions',
  'owned_reward_items',
  'equipped_reward_items',
  'outbox_operations',
  'sync_checkpoints',
  'sync_conflicts',
  'runtime_flags',
  'model_downloads',
  'events_v2',
  'legacy_learning_records',
  'quest_definitions',
  'quest_instances',
  'quest_objective_progress',
  'streak_states',
  'learning_day_log',
  'association_records',
  'associative_memory_states',
  'ai_usage_events',
  'speech_evidence',
  'saved_learning_items',
  'content_quality_reports',
  'learning_time_segments',
  'learning_goals',
  'study_reminders',
  'learner_preferences',
};

Future<Set<String>> currentDatabaseTableNames(AppDatabase database) {
  return database
      .customSelect(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      )
      .map((row) => row.read<String>('name'))
      .get()
      .then((rows) => rows.toSet());
}

Future<void> expectCurrentDatabaseContract(AppDatabase database) async {
  expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
  expect(
    await database
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle(),
    AppDatabase.currentSchemaVersion,
  );
  expect(
    await currentDatabaseTableNames(database),
    currentDatabaseTableInventory,
  );
}
