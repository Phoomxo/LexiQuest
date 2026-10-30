import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';

import '../../support/measurement_opportunity_harness.dart';
import '../../support/populated_owner_migration_fixture.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  test('fresh v20 has one empty seven-column SavedWords relation', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(database.schemaVersion, 20);
    expect(database.allTables, hasLength(37));
    expect(
      await database.customSelect('SELECT * FROM word_reports').get(),
      isEmpty,
    );
    final columns = await database
        .customSelect('PRAGMA table_info(saved_words)')
        .get();
    expect(columns.map((row) => row.read<String>('name')).toList(), [
      'owner_id',
      'word_id',
      'is_saved',
      'local_revision',
      'first_saved_at_utc_ms',
      'updated_at_utc_ms',
      'last_mutation_id',
    ]);
    expect(columns.map((row) => row.read<int>('notnull')), everyElement(1));
    expect(columns.map((row) => row.read<int>('pk')).toList(), [
      1,
      2,
      0,
      0,
      0,
      0,
      0,
    ]);
    final keys = await database
        .customSelect('PRAGMA foreign_key_list(saved_words)')
        .get();
    expect(
      keys
          .map((row) => (row.read<String>('from'), row.read<String>('table')))
          .toSet(),
      {('owner_id', 'local_owners'), ('word_id', 'vocabulary_words')},
    );
    expect(
      keys.map((row) => row.read<String>('on_delete')),
      everyElement('RESTRICT'),
    );
    expect(
      (await database.customSelect('PRAGMA foreign_keys').getSingle())
          .read<int>('foreign_keys'),
      1,
    );
    expect(
      await database.customSelect('SELECT * FROM saved_words').get(),
      isEmpty,
    );
  });

  test(
    'saved relation enforces scalar checks, byte bound and parent foreign keys',
    () async {
      final h = await ConfiguredQuizHarness.open();
      addTearDown(h.close);
      final valid = <String, Object?>{
        'owner_id': configuredOwnerId,
        'word_id': configuredWordIds.first,
        'is_saved': 1,
        'local_revision': 1,
        'first_saved_at_utc_ms': 1,
        'updated_at_utc_ms': 0,
        'last_mutation_id': 'synthetic-save',
      };
      for (final change in <(String, Object?)>[
        ('owner_id', 'missing-owner'),
        ('word_id', 'missing-word'),
        ('is_saved', 2),
        ('local_revision', 0),
        ('local_revision', -1),
        ('local_revision', 1.5),
        ('first_saved_at_utc_ms', -1),
        ('first_saved_at_utc_ms', 0.5),
        ('updated_at_utc_ms', -1),
        ('updated_at_utc_ms', 0.5),
        ('last_mutation_id', ''),
        ('last_mutation_id', '   '),
        ('last_mutation_id', 'a' * 257),
        ('last_mutation_id', 'ก' * 86),
      ]) {
        await expectLater(
          _insert(h.database, {...valid, change.$1: change.$2}),
          throwsException,
          reason: '${change.$1}=${change.$2}',
        );
        expect(
          await h.database.customSelect('SELECT * FROM saved_words').get(),
          isEmpty,
        );
      }
      await _insert(h.database, valid);
      await expectLater(_insert(h.database, valid), throwsException);
      await expectLater(
        h.database.customStatement(
          'DELETE FROM vocabulary_words WHERE id = ?',
          [configuredWordIds.first],
        ),
        throwsException,
      );
      await expectLater(
        h.database.customStatement('DELETE FROM local_owners WHERE id = ?', [
          configuredOwnerId,
        ]),
        throwsException,
      );
      await h.database.customStatement('UPDATE saved_words SET is_saved = 0');
      await expectLater(
        h.database.customStatement(
          'DELETE FROM vocabulary_words WHERE id = ?',
          [configuredWordIds.first],
        ),
        throwsException,
        reason: 'An unsaved tombstone still protects its parent',
      );
      expect(
        await h.database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
  test(
    'genuine v18 retains every populated table, quiz, pending presentation and deletion intent',
    () async {
      final schema = File(
        'test/fixtures/schema_v18.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        sha256.convert(utf8.encode(schema)).toString(),
        '9cff95c607a68bf6960ec451148280526bf902e3249d2767b7ebee2925c221c1',
      );
      expect(
        RegExp(r'^CREATE TABLE', multiLine: true).allMatches(schema),
        hasLength(35),
      );
      expect(schema, isNot(contains('saved_words')));
      final source = await OpportunityFixture.open(
        treatment: TodayExperiencePresentation.adventure,
      );
      late Map<String, List<Map<String, Object?>>> oldRows;
      late DeletionIntentToken token;
      late DateTime checkedAt;
      late String opportunityId;
      try {
        // Current synthetic canonical facts use the genuine old storage shape;
        // they do not claim enrollment or collection by an old production runtime.
        await populateOwnerMigrationFacts(source);
        await source.database.customStatement(
          'INSERT INTO learning_sessions '
          '(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
          "VALUES ('synthetic-assessment-one','owner-a','assessment','active',?,'synthetic-assessment','storage-only')",
          [
            participationStart
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
          ],
        );
        final assessment = await assessmentMigrationRow(source)
          ..['database_schema_version'] = 18;
        await insertOwnerMigrationRow(
          source.database,
          'assessment_runs',
          assessment,
        );
        checkedAt = source.participation.clock.now;
        opportunityId = source.opportunityId;
        token = await source.participation.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'delete:synthetic-saved-words-v18-migration',
        );
        await source.participation.ownerWrites.markPending(token);
        oldRows = await ownerMigrationRows(source.database);
        expect(oldRows.remove('saved_words'), isEmpty);
        expect(oldRows.remove('word_reports'), isEmpty);
        expect(oldRows, hasLength(35));
        for (final table in oldRows.entries) {
          expect(
            table.value,
            isNotEmpty,
            reason: 'Populate ${table.key} before retaining it',
          );
        }
      } finally {
        await source.database.close();
      }
      final before = <String, List<Map<String, Object?>>>{};
      final oldObjects = <String, String>{};
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory(
        tempRoot,
      ).createTemp('lexiquest-saved-words-v18-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}historical.sqlite',
      );
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            for (final statement in schema.split(';')) {
              if (statement.trim().isNotEmpty) sqlite.execute(statement);
            }
            for (final table in oldRows.entries) {
              for (final row in table.value) {
                sqlite.execute(
                  'INSERT INTO "${table.key}" (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
                  row.values.toList(),
                );
              }
            }
            for (final object in sqlite.select(
              "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )) {
              oldObjects[object['name']! as String] = object['sql']! as String;
              if (object['type'] != 'table') continue;
              final name = object['name']! as String;
              before[name] = [
                for (final row in sqlite.select(
                  'SELECT * FROM "$name" ORDER BY rowid',
                ))
                  Map<String, Object?>.from(row),
              ];
            }
            sqlite.execute('PRAGMA user_version = 18');
          },
        ),
      );
      var closed = false;
      AppDatabase? reopened;
      addTearDown(() async {
        await reopened?.close();
        if (!closed) await database.close();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-saved-words-v18-',
          ),
        );
        expect(resolved, directory.absolute.path);
        await Directory(resolved).delete(recursive: true);
      });
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        20,
      );
      expect(database.allTables, hasLength(37));
      expect(
        await database.customSelect('SELECT * FROM word_reports').get(),
        isEmpty,
      );
      expect(before, oldRows);
      final after = await ownerMigrationRows(database);
      expect(after['saved_words'], isEmpty);
      expect(after['word_reports'], isEmpty);
      expect(
        Map<String, List<Map<String, Object?>>>.of(after)
          ..remove('saved_words')
          ..remove('word_reports'),
        before,
      );
      final newObjects = await database
          .customSelect(
            "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final byName = {
        for (final row in newObjects)
          row.read<String>('name'): row.read<String>('sql'),
      };
      expect(byName.keys.toSet(), {
        ...oldObjects.keys,
        'saved_words',
        'word_reports',
      });
      for (final object in oldObjects.entries) {
        expect(
          byName[object.key],
          object.value,
          reason: 'Retain exact old DDL ${object.key}',
        );
      }
      final pendingQuiz = after['learning_sessions']!.singleWhere(
        (row) => row['id'] == 'synthetic-retained-pending-quiz',
      );
      expect(pendingQuiz['accepted_plan_json'], isNotNull);
      expect(
        pendingQuiz['checkpoint_json'],
        contains('synthetic-retained-unsubmitted-answer'),
      );
      final pending = after['measurement_opportunities']!.singleWhere(
        (row) => row['id'] == opportunityId,
      );
      expect(pending['last_switch_ordinal'], 10);
      expect(pending['suppressed_switch_count'], 2);
      final receipt = PendingPresentationChange.fromJson(
        pending['pending_presentation_change_json']! as String,
      );
      expect(receipt.position, 13);
      expect(
        receipt.canonicalJson,
        pending['pending_presentation_change_json'],
      );
      expect(after['assessment_runs'], hasLength(1));
      expect(after['assessment_runs']!.single['database_schema_version'], 18);
      expect(after['outbox_operations'], hasLength(3));
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final coordinator = DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => checkedAt,
      );
      final intent = (await coordinator.inspect())!;
      expect(intent.phase, DeletionIntentPhase.pendingCloud);
      expect(intent.casToken!.sameAttempt(token), isTrue);
      await expectLater(
        coordinator.requireOwnerUnfenced('owner-a'),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.unavailable,
          ),
        ),
      );
      expect(await ownerMigrationRows(database), after);
      await database.close();
      closed = true;
      reopened = AppDatabase(NativeDatabase(file));
      expect(await ownerMigrationRows(reopened), after);
      expect(
        await reopened.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

Future<void> _insert(
  AppDatabase database,
  Map<String, Object?> row,
) => database.customStatement(
  'INSERT INTO saved_words (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
  row.values.toList(),
);
