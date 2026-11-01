import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_calendar_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test(
    'calendar reads every ordinary owner fact beyond the history page without writing',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement(
        "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('a','localGuest',1,1),('b','localGuest',1,0)",
      );
      for (final owner in ['a', 'b']) {
        await database.customStatement(
          'INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,\'Synthetic\',\'synthetic\',1,1)',
          ['category-$owner', owner],
        );
        await database.customStatement(
          'INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?,\'sample\',\'sample\',\'example\',\'example\',\'noun\',1,1)',
          ['word-$owner', owner, 'category-$owner'],
        );
      }
      final at = DateTime(2026, 11, 1, 12).toUtc().millisecondsSinceEpoch;
      for (var index = 0; index < 60; index++) {
        await database.customStatement(
          'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) VALUES (?,\'a\',\'quiz\',\'completed\',?,?,\'synthetic\',\'synthetic\')',
          ['session-$index', at, at],
        );
        await database.customStatement(
          'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms) VALUES (?,\'a\',?,\'word-a\',\'meaningChoice\',?,1,?)',
          ['answer-$index', 'session-$index', index.isEven ? 1 : 0, at],
        );
      }
      await database.customStatement(
        'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) VALUES (\'session-b\',\'b\',\'quiz\',\'completed\',?,?,\'synthetic\',\'synthetic\')',
        [at, at],
      );
      await database.customStatement(
        'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms) VALUES (\'answer-b\',\'b\',\'session-b\',\'word-b\',\'meaningChoice\',1,1,?)',
        [at],
      );
      await database.customStatement(
        'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms) VALUES (\'cross-owner\',\'b\',\'session-0\',\'word-b\',\'meaningChoice\',1,1,?)',
        [at],
      );
      final before = await _snapshot(database);
      final result = await DriftLearningCalendarQueries(database).load(
        ownerId: 'a',
        period: LearningCalendarPeriod.weekEnding(DateTime(2026, 11, 1)),
        nowUtc: DateTime(2026, 11, 1, 20).toUtc(),
      );
      expect(result.days, hasLength(7));
      expect(result.answerCount, 60);
      expect(result.correctCount, 30);
      expect(result.completedSessionCount, 60);
      expect(result.days.take(6).every((day) => day.answerCount == 0), isTrue);
      expect(await _snapshot(database), before);
    },
  );

  test(
    'calendar excludes controlled Study, Assessment, malformed evidence and foreign owner facts',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final captured =
          jsonDecode(
                File(
                  'test/fixtures/populated_schema_v21.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rows = captured['rows'] as Map<String, dynamic>;
      await database.customSelect('SELECT 1').getSingle();
      await database.transaction(() async {
        await database.customStatement('PRAGMA defer_foreign_keys = ON');
        for (final entry in rows.entries) {
          for (final row in entry.value as List) {
            await insertOwnerMigrationRow(
              database,
              entry.key,
              Map<String, Object?>.from(row as Map),
            );
          }
        }
      });
      final original = Map<String, Object?>.from(
        (rows['answer_attempts'] as List).single as Map,
      );
      for (final change in [
        {'id': 'synthetic-calendar-study', 'session_id': 'first-session'},
        {
          'id': 'synthetic-calendar-assessment',
          'session_id': 'synthetic-assessment-one',
        },
        {'id': 'synthetic-calendar-corrupt', 'evidence_class': 'assessment'},
        {'id': 'synthetic-calendar-foreign', 'owner_id': 'owner-b'},
      ]) {
        await insertOwnerMigrationRow(database, 'answer_attempts', {
          ...original,
          ...change,
        });
      }
      final at = DateTime.fromMillisecondsSinceEpoch(
        original['occurred_at_utc_ms'] as int,
        isUtc: true,
      );
      final fenced = await _snapshot(database);
      await expectLater(
        DriftLearningCalendarQueries(database).load(
          ownerId: 'owner-a',
          period: LearningCalendarPeriod.weekEnding(at.toLocal()),
          nowUtc: at.add(const Duration(days: 1)),
        ),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(await _snapshot(database), fenced);
      await database.customStatement(
        'DELETE FROM runtime_flags WHERE key = ?',
        ['accountDeletion.ownerWriteIntent'],
      );
      final before = await _snapshot(database);
      final result = await DriftLearningCalendarQueries(database).load(
        ownerId: 'owner-a',
        period: LearningCalendarPeriod.weekEnding(at.toLocal()),
        nowUtc: at.add(const Duration(days: 1)),
      );
      expect(result.answerCount, 1);
      expect(result.correctCount, original['is_correct']);
      expect(result.completedSessionCount, 1);
      expect(await _snapshot(database), before);
    },
  );

  test(
    'periods preserve civil dates across month and daylight-saving boundaries',
    () {
      final march = LearningCalendarPeriod.month(2026, 3);
      expect(march.dayCount, 31);
      expect(march.dayAt(7), DateTime(2026, 3, 8));
      expect(march.dayAt(8), DateTime(2026, 3, 9));
      expect(LearningCalendarPeriod.month(2028, 2).dayCount, 29);
      expect(
        LearningCalendarPeriod.weekEnding(DateTime(2026, 11, 3)).firstDay,
        DateTime(2026, 10, 28),
      );
      for (final month in [0, 13]) {
        expect(
          () => LearningCalendarPeriod.month(2026, month),
          throwsArgumentError,
        );
      }
      expect(
        () => LearningCalendarPeriod(firstDay: DateTime(2026), dayCount: 0),
        throwsArgumentError,
      );
      expect(
        () => LearningCalendarPeriod(firstDay: DateTime(2026), dayCount: 32),
        throwsArgumentError,
      );
    },
  );
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        row.data,
    ],
};
