import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';

void main() {
  test('v10 facts retain frozen v11 evidence in the current schema', () async {
    final before = <String, List<Map<String, Object?>>>{};
    final sql = File('test/fixtures/schema_v10.sql').readAsStringSync();
    expect(sql, isNot(contains('evidence_context_json')));
    expect(sql, isNot(contains('evidence_class')));
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          for (final statement in sql.split(';')) {
            if (statement.trim().isNotEmpty) sqlite.execute(statement);
          }
          sqlite.execute(
            "INSERT INTO local_owners (id, created_at_utc_ms) VALUES ('owner-a', 1), ('owner-b', 2)",
          );
          sqlite.execute('''
INSERT INTO vocabulary_categories
(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms)
VALUES ('category-a', 'owner-a', 'Synthetic', 'synthetic', 1, 1)
''');
          sqlite.execute('''
INSERT INTO vocabulary_words
(id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning,
part_of_speech, source, created_at_utc_ms, updated_at_utc_ms)
VALUES ('word-a', 'owner-a', 'category-a', 'cat', 'cat', 'แมว', 'แมว', 'noun', 'manual', 1, 1)
''');
          sqlite.execute('''
INSERT INTO learning_sessions
(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id)
VALUES ('session-a', 'owner-a', 'quiz', 'active', 3, 'test', 'v10-snapshot')
''');
          sqlite.execute('''
INSERT INTO answer_attempts
(id, owner_id, session_id, word_id, prompt_mode, is_correct, response_time_ms,
attempt_number, occurred_at_utc_ms, provider_provenance)
VALUES ('answer-a', 'owner-a', 'session-a', 'word-a', 'meaningChoice', 1, 700, 1, 4, 'synthetic-provider')
''');
          sqlite.execute('''
INSERT INTO outbox_operations
(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms)
VALUES ('attempt:answer-a:1', 'owner-a', 'attempt', 'answer-a', 'append', 4)
''');
          final tables = sqlite.select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          );
          for (final table in tables) {
            final name = table['name'] as String;
            before[name] = [
              for (final row in sqlite.select('SELECT * FROM "$name"'))
                Map<String, Object?>.from(row),
            ];
          }
          sqlite.execute('PRAGMA user_version = 10');
        },
      ),
    );
    addTearDown(database.close);
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 17);
    expect(before, hasLength(29));
    expect(database.allTables, hasLength(34));
    expect(
      await database.customSelect('SELECT * FROM experiment_assignments').get(),
      isEmpty,
    );
    for (final entry in before.entries) {
      final rows = await database
          .customSelect('SELECT * FROM "${entry.key}"')
          .get();
      expect(
        [
          for (final row in rows)
            Map<String, Object?>.from(row.data)
              ..remove('evidence_class')
              ..remove('evidence_context_json')
              ..remove('accepted_plan_id')
              ..remove('accepted_plan_json')
              ..remove('checkpoint_revision')
              ..remove('checkpoint_json'),
        ],
        entry.value,
        reason: 'Migration must preserve ${entry.key} facts.',
      );
    }
    final attempt = await database
        .customSelect('SELECT * FROM answer_attempts')
        .getSingle();
    expect(attempt.read<String>('evidence_class'), 'independentRecall');
    final contextJson =
        jsonDecode(attempt.read<String>('evidence_context_json'))
            as Map<String, dynamic>;
    final expected = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'legacy-unspecified',
      hintLevel: 0,
      contentRevision: 'legacy-unknown',
      engagementAllowed: true,
    );
    expect(contextJson, expected.toJson());
    final context = EvidenceContext.fromJson(contextJson);
    for (final projection in LearningProjection.values) {
      expect(
        EvidenceProjectionDecision.resolve(
          context: context,
          projection: projection,
        ).contributesToEfficacyOutcomes,
        isFalse,
      );
    }
    expect(
      context.classificationSource,
      EvidenceClassificationSource.legacyInferred,
    );
    expect(context.assignmentId, isNull);
    expect(context.researchConsentVersion, isNull);
  });

  test('new databases retain the v11 answer evidence metadata', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final columns = await database
        .customSelect('PRAGMA table_info(answer_attempts)')
        .get();
    expect(database.schemaVersion, 17);
    expect(database.allTables, hasLength(34));
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(['evidence_class', 'evidence_context_json']),
    );
  });
}
