import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'app_database.dart';
import 'legacy_v25_evidence.dart';

const baseV25Evidence = 'base-v25';
const historyV25Evidence = 'history-v25';

final class LegacyV25Migration {
  final AppDatabase database;
  const LegacyV25Migration(this.database);

  static Future<bool> detect(AppDatabase database, int version) async {
    if (version != 10 && version != 25) return false;
    final objects = await database
        .customSelect(
          "SELECT type,name,sql FROM sqlite_master "
          "WHERE name NOT GLOB 'sqlite_*' AND sql IS NOT NULL ORDER BY type,name",
        )
        .get();
    final names = objects.map((row) => row.read<String>('name')).toSet();
    final hasHistoricalTables = _historicalTables.any(names.contains);
    if (version == 10 && !hasHistoricalTables) return false;
    final encoded = jsonEncode([
      for (final row in objects)
        [
          row.read<String>('type'),
          row.read<String>('name'),
          row.read<String>('sql'),
        ],
    ]);
    // The fresh, v23-upgraded, and v29-relabelled captures share this catalog.
    const expected =
        'fd28bd89a5d272e0557ee3b35b9960554f910b61a7c16fc4e8da01017e0368bf';
    if (sha256.convert(utf8.encode(encoded)).toString() != expected) {
      throw StateError('Unrecognized historical schema 25 layout');
    }
    return true;
  }

  static const _historicalTables = [
    'motivation_responses',
    'measurement_opportunities',
    'assessment_runs',
    'motivation_measurement_runs',
    'research_participation_permits',
    'experiment_assignments',
    'learning_time_segments',
    'learning_time_scopes',
    'lexical_content_snapshots',
    'learning_pack_versions',
    'saved_words',
    'word_reports',
    'content_reports',
    'study_reminder_preferences',
    'learning_time_preferences',
    'learning_profiles',
  ];

  Future<void> archiveAndNormalize(Migrator migrator) async {
    await _validateOwnership();
    for (final table in _historicalTables) {
      await _archive(table);
    }
    await _archive('quest_instances', key: 'instance_id');
    await _archive('learning_day_log');
    await _archive('learning_sessions');

    await database.customStatement('''
      CREATE TEMP TABLE legacy_v25_assessments (id TEXT PRIMARY KEY)
      ''');
    await database.customStatement('''
      INSERT INTO legacy_v25_assessments
      SELECT id FROM learning_sessions
      WHERE activity_type = 'assessment' OR id GLOB 'assessment-session:*'
      UNION SELECT learning_session_id FROM assessment_runs
      UNION SELECT session_id FROM answer_attempts
        WHERE evidence_class = 'assessment' OR id GLOB 'assessment-response:*'
      ''');
    await database.customStatement('''
      CREATE TEMP TABLE legacy_v25_admission (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
        compatible INTEGER NOT NULL, reward_eligible INTEGER NOT NULL,
        native_prompt INTEGER NOT NULL
      )
      ''');
    int? start;
    while (true) {
      final batch = await database
          .customSelect(
            'SELECT a.rowid AS source_rowid,a.id,a.session_id,a.prompt_mode,'
            'a.evidence_class,a.evidence_context_json,s.activity_type,'
            'EXISTS(SELECT 1 FROM legacy_v25_assessments p WHERE p.id=s.id) AS private '
            'FROM answer_attempts a JOIN learning_sessions s ON s.id=a.session_id '
            '${start == null ? '' : 'WHERE a.rowid > ? '}ORDER BY a.rowid LIMIT 64',
            variables: [if (start != null) Variable<int>(start)],
          )
          .get();
      if (batch.isEmpty) break;
      for (final row in batch) {
        final ordinary = row.read<int>('private') == 0;
        final prompt = row.read<String>('prompt_mode');
        final evidenceClass = row.read<String>('evidence_class');
        final evidenceContext = row.read<String>('evidence_context_json');
        final compatible =
            ordinary &&
            isCompatibleV25Attempt(
              activityType: row.read<String>('activity_type'),
              promptMode: prompt,
              evidenceClass: evidenceClass,
              evidenceContextJson: evidenceContext,
            );
        final rewardEligible =
            ordinary &&
            isV25RewardEvidence(
              promptMode: prompt,
              evidenceClass: evidenceClass,
              evidenceContextJson: evidenceContext,
            );
        await database.customStatement(
          'INSERT INTO legacy_v25_admission VALUES (?,?,?,?,?)',
          [
            row.read<String>('id'),
            row.read<String>('session_id'),
            compatible ? 1 : 0,
            rewardEligible ? 1 : 0,
            v25NativeRewardPromptModes.contains(prompt) ? 1 : 0,
          ],
        );
      }
      start = batch.last.read<int>('source_rowid');
    }
    await database.customStatement(
      'CREATE INDEX temp.idx_legacy_v25_session ON legacy_v25_admission(session_id,compatible)',
    );
    const excludedRewardSources = '''
      SELECT id FROM legacy_v25_assessments
      UNION SELECT id FROM legacy_v25_admission WHERE reward_eligible = 0
      UNION SELECT session_id FROM legacy_v25_admission
        GROUP BY session_id HAVING MAX(reward_eligible) = 0 AND MAX(native_prompt) = 1
      ''';
    await _archive(
      'answer_attempts',
      rewardExcluded: '''
      EXISTS (SELECT 1 FROM legacy_v25_admission a
              WHERE a.id=r.id AND a.reward_eligible=0)
      ''',
    );
    await _archive(
      'points_ledger_entries',
      rewardExcluded:
          '''
      r.source_event_id IN ($excludedRewardSources)
      ''',
    );
    const denied =
        'SELECT session_id FROM legacy_v25_admission WHERE compatible = 0';
    const incompatibleOutbox =
        "payload_version <> 1 OR entity_type NOT IN ('category','word','attempt',"
        "'readingEvent','rewardTransaction','srsState','achievementUnlock') OR "
        "(entity_type = 'attempt' AND entity_id IN (SELECT id FROM legacy_v25_admission "
        "WHERE session_id IN ($denied))) OR "
        "(entity_type = 'achievementUnlock' AND entity_id IN ("
        "SELECT id FROM achievement_unlocks WHERE source_event_id IN ($excludedRewardSources)))";
    await _archive(
      'outbox_operations',
      key: 'operation_id',
      where: incompatibleOutbox,
    );
    await database.customStatement(
      "UPDATE outbox_operations SET state='historicalV25' "
      "WHERE ($incompatibleOutbox) AND state <> 'acknowledged'",
    );
    for (final table in _historicalTables) {
      await database.customStatement('DROP TABLE $table');
    }
    await _normalizeQuest(migrator);
    await _normalizeDays(migrator, denied);
    await database.customStatement(
      'ALTER TABLE learning_sessions DROP COLUMN accepted_plan_id',
    );
    await database.customStatement(
      'ALTER TABLE learning_sessions DROP COLUMN accepted_plan_json',
    );
    await database.customStatement(
      'ALTER TABLE learning_sessions DROP COLUMN checkpoint_revision',
    );
    await database.customStatement(
      'ALTER TABLE learning_sessions DROP COLUMN checkpoint_json',
    );
    await database.customStatement(
      'ALTER TABLE answer_attempts DROP COLUMN evidence_class',
    );
    await database.customStatement(
      'ALTER TABLE answer_attempts DROP COLUMN evidence_context_json',
    );
  }

  Future<void> restoreStudyFlags() async {
    await database.customStatement('''
      UPDATE learning_sessions SET activity_type='assessment'
      WHERE id IN (SELECT id FROM legacy_v25_assessments)
      ''');
    await database.customStatement('''
      UPDATE learning_sessions SET legacy_evidence_disposition =
        CASE WHEN EXISTS (SELECT 1 FROM legacy_v25_admission a
                          WHERE a.session_id = learning_sessions.id)
                   AND NOT EXISTS (SELECT 1 FROM legacy_v25_admission a
                          WHERE a.session_id = learning_sessions.id AND compatible = 0)
          THEN '$baseV25Evidence' ELSE '$historyV25Evidence' END
      ''');
    await database.customStatement('''
      UPDATE answer_attempts SET legacy_evidence_disposition =
        (SELECT legacy_evidence_disposition FROM learning_sessions
         WHERE learning_sessions.id = answer_attempts.session_id)
      ''');
    await database.customStatement(r'''
      UPDATE vocabulary_words SET is_bookmarked = 1
      WHERE is_deleted = 0 AND EXISTS (
        SELECT 1 FROM archived_v25_records a
        WHERE a.source_table='saved_words' AND a.owner_id = vocabulary_words.owner_id
          AND json_extract(a.payload_json,'$.word_id') = vocabulary_words.id
          AND json_extract(a.payload_json,'$.is_saved') = 1
      )
      ''');
    await database.customStatement('DROP TABLE legacy_v25_admission');
    await database.customStatement('DROP TABLE legacy_v25_assessments');
  }

  Future<void> _archive(
    String table, {
    String key = 'id',
    String where = '1',
    String? rewardExcluded,
  }) async {
    if ([
      'study_reminder_preferences',
      'learning_time_preferences',
      'learning_profiles',
    ].contains(table)) {
      key = 'owner_id';
    }
    final known = await database
        .customSelect('SELECT COUNT(*) AS n FROM $table WHERE $where')
        .getSingle();
    final expressions = table == 'learning_time_segments'
        ? 'r.*,p.owner_id AS archive_owner'
        : 'r.*,r.owner_id AS archive_owner';
    final source = table == 'learning_time_segments'
        ? '$table r JOIN learning_time_scopes p ON p.id=r.scope_id'
        : '$table r';
    int? start;
    var copied = 0;
    final batchSize = table == 'learning_pack_versions' ? 1 : 64;
    while (true) {
      final rows = await database
          .customSelect(
            'SELECT r.rowid AS source_rowid,$expressions'
            "${rewardExcluded == null ? '' : ',COALESCE(($rewardExcluded),0) AS _v25_reward_excluded'} "
            'FROM $source '
            'WHERE ${start == null ? '' : 'r.rowid > ? AND '}'
            '($where) ORDER BY r.rowid LIMIT $batchSize',
            variables: [if (start != null) Variable<int>(start)],
          )
          .get();
      if (rows.isEmpty) break;
      for (final row in rows) {
        final owner = row.read<String>('archive_owner');
        final id = table == 'saved_words'
            ? jsonEncode([owner, row.read<String>('word_id')])
            : row.read<String>(key);
        final payload = Map<String, Object?>.of(row.data)
          ..remove('source_rowid')
          ..remove('archive_owner');
        final blob = payload['package_bytes'];
        if (blob is Uint8List) payload.remove('package_bytes');
        await database.customStatement(
          'INSERT INTO archived_v25_records '
          '(id,owner_id,origin_owner_id,source_table,source_row_key,payload_json,payload_blob) '
          'VALUES (?,?,?,?,?,?,?)',
          [
            'legacy-v25:$table:$id',
            owner,
            owner,
            table,
            id,
            jsonEncode(payload),
            blob,
          ],
        );
        copied++;
      }
      start = rows.last.read<int>('source_rowid');
    }
    if (copied != known.read<int>('n')) {
      throw StateError('Historical archive count mismatch for $table');
    }
  }

  Future<void> _validateOwnership() async {
    final violations = await database
        .customSelect('PRAGMA foreign_key_check')
        .get();
    if (violations.isNotEmpty) {
      throw StateError('Historical database has invalid foreign keys');
    }
    for (final (child, field, parent, key) in const [
      ('answer_attempts', 'session_id', 'learning_sessions', 'id'),
      ('answer_attempts', 'word_id', 'vocabulary_words', 'id'),
      ('vocabulary_words', 'category_id', 'vocabulary_categories', 'id'),
      ('vocabulary_imports', 'category_id', 'vocabulary_categories', 'id'),
      ('srs_states', 'word_id', 'vocabulary_words', 'id'),
      (
        'owned_reward_items',
        'acquired_by_transaction_id',
        'reward_transactions',
        'id',
      ),
      ('learning_day_log', 'source_attempt_id', 'answer_attempts', 'id'),
      ('saved_words', 'word_id', 'vocabulary_words', 'id'),
      ('learning_time_scopes', 'linked_session_id', 'learning_sessions', 'id'),
      (
        'lexical_content_snapshots',
        'pack_version_id',
        'learning_pack_versions',
        'id',
      ),
      ('lexical_content_snapshots', 'word_id', 'vocabulary_words', 'id'),
      ('learning_pack_versions', 'category_id', 'vocabulary_categories', 'id'),
      ('learning_pack_versions', 'import_id', 'vocabulary_imports', 'id'),
      (
        'research_participation_permits',
        'assignment_id',
        'experiment_assignments',
        'id',
      ),
      (
        'motivation_measurement_runs',
        'assignment_id',
        'experiment_assignments',
        'id',
      ),
      (
        'motivation_measurement_runs',
        'permit_id',
        'research_participation_permits',
        'id',
      ),
      ('assessment_runs', 'learning_session_id', 'learning_sessions', 'id'),
      (
        'assessment_runs',
        'study_cycle_id',
        'motivation_measurement_runs',
        'id',
      ),
      ('assessment_runs', 'assignment_id', 'experiment_assignments', 'id'),
      (
        'assessment_runs',
        'participation_permit_id',
        'research_participation_permits',
        'id',
      ),
      ('motivation_responses', 'run_id', 'motivation_measurement_runs', 'id'),
      (
        'measurement_opportunities',
        'learning_session_id',
        'learning_sessions',
        'id',
      ),
      (
        'measurement_opportunities',
        'presented_event_id',
        'events_v2',
        'event_id',
      ),
      (
        'measurement_opportunities',
        'measurement_run_id',
        'motivation_measurement_runs',
        'id',
      ),
      (
        'measurement_opportunities',
        'permit_id',
        'research_participation_permits',
        'id',
      ),
    ]) {
      final row = await database
          .customSelect(
            'SELECT 1 FROM $child c JOIN $parent p ON c.$field=p.$key '
            'WHERE c.owner_id IS NOT p.owner_id LIMIT 1',
          )
          .getSingleOrNull();
      if (row != null) {
        throw StateError('Historical owner link mismatch: $child.$field');
      }
    }
  }

  Future<void> _normalizeQuest(Migrator migrator) async {
    const parent =
        'instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,completed_at_utc_ms,expired_at_utc_ms';
    const child =
        'id,instance_id,objective_id,current_count,target_count,source_event_ids_json';
    await database.customStatement(
      'CREATE TEMP TABLE legacy_v25_quests AS SELECT $parent FROM quest_instances',
    );
    await database.customStatement(
      'CREATE TEMP TABLE legacy_v25_objectives AS SELECT $child FROM quest_objective_progress',
    );
    await database.customStatement('DROP TABLE quest_objective_progress');
    await database.customStatement('DROP TABLE quest_instances');
    await migrator.createTable(database.questInstances);
    await migrator.createTable(database.questObjectiveProgress);
    await database.customStatement(
      'INSERT INTO quest_instances ($parent) SELECT $parent FROM legacy_v25_quests',
    );
    await database.customStatement(
      'INSERT INTO quest_objective_progress ($child) SELECT $child FROM legacy_v25_objectives',
    );
    await database.customStatement('DROP TABLE legacy_v25_quests');
    await database.customStatement('DROP TABLE legacy_v25_objectives');
  }

  Future<void> _normalizeDays(Migrator migrator, String denied) async {
    const fields = 'id,owner_id,learning_day,first_session_at_utc_ms';
    await database.customStatement('''
      CREATE TEMP TABLE legacy_v25_days AS
      SELECT $fields FROM (
        SELECT $fields,
          row_number() OVER(PARTITION BY owner_id,learning_day
            ORDER BY first_session_at_utc_ms,id) AS rank
        FROM learning_day_log
        WHERE source_attempt_id IS NULL OR source_attempt_id IN (
          SELECT id FROM legacy_v25_admission WHERE session_id NOT IN ($denied)
        )
      ) WHERE rank=1
      ''');
    await database.customStatement('DROP TABLE learning_day_log');
    await migrator.createTable(database.learningDayLog);
    await database.customStatement(
      'INSERT INTO learning_day_log ($fields) SELECT $fields FROM legacy_v25_days',
    );
    await database.customStatement('DROP TABLE legacy_v25_days');
  }
}
