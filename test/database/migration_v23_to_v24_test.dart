import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v22_to_v23_test.dart' as fixture;

void main() {
  test(
    'v24 adds exactly four empty research tables and preserves v23 data',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaTwentyThreeFixture),
      );
      addTearDown(database.close);
      expect(AppDatabase.currentSchemaVersion, 24);
      await expectCurrentDatabaseContract(database);
      expect(await currentDatabaseTableNames(database), hasLength(48));
      for (final table in researchTables) {
        expect(
          await database.customSelect('SELECT * FROM $table').get(),
          isEmpty,
        );
      }
      final preferences = await database
          .customSelect('SELECT * FROM learner_preferences ORDER BY owner_id')
          .get();
      expect(preferences, hasLength(2));
      expect(preferences.last.read<String>('home_experience'), 'adventure');
      expect(preferences.last.read<int>('local_revision'), 7);
      expect(preferences.last.read<int>('cloud_revision'), 5);
      expect(
        preferences.last.read<int>('display_updated_at_utc_ms'),
        1788048000500,
      );
      expect(preferences.first.read<int>('is_deleted'), 1);
      final assignments = await database
          .customSelect(
            "SELECT * FROM experiment_assignments WHERE id = 'assignment:fixture'",
          )
          .get();
      expect(assignments.single.read<String>('cohort'), 'adventure');
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  group('research SQL constraints', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      for (final owner in ['owner:a', 'owner:b']) {
        await insertResearchTestRow(db, 'local_owners', {
          'id': owner,
          'account_state': 'localGuest',
          'created_at_utc_ms': 1,
        });
      }
      await insertResearchTestRow(db, 'experiment_assignments', {
        'id': 'assignment:a',
        'owner_id': 'owner:a',
        'experiment_id': 'motivation',
        'experiment_version': 1,
        'cohort': 'adventure',
        'protocol_version': '1',
        'assigned_at_utc_ms': 1,
      });
      await insertResearchTestRow(
        db,
        'motivation_measurement_runs',
        researchRunRow(),
      );
      await insertResearchTestRow(
        db,
        'research_participation_permits',
        researchPermitRow(),
      );
    });
    tearDown(() => db.close());

    test('cross-owner assignment and permit pins are rejected', () async {
      await expectLater(
        insertResearchTestRow(db, 'motivation_measurement_runs', {
          ...researchRunRow(),
          'id': 'run:b',
          'owner_id': 'owner:b',
        }),
        throwsA(anything),
      );
      await expectLater(
        insertResearchTestRow(db, 'research_participation_permits', {
          ...researchPermitRow(),
          'id': 'permit:b',
          'owner_id': 'owner:b',
        }),
        throwsA(anything),
      );
    });

    test(
      'minor permit requires both receipt references and valid time/revisions',
      () async {
        for (final override in <Map<String, Object?>>[
          {'participant_class': 'minor'},
          {
            'participant_class': 'minor',
            'guardian_permission_receipt_ref': 'receipt:g',
          },
          {'expires_at_utc_ms': 1},
          {'local_revision': 0},
          {'assigned_treatment': 'unknown'},
        ]) {
          await expectLater(
            insertResearchTestRow(db, 'research_participation_permits', {
              ...researchPermitRow(),
              'id': 'permit:invalid',
              ...override,
            }),
            throwsA(anything),
          );
        }
        await insertResearchTestRow(db, 'research_participation_permits', {
          ...researchPermitRow(),
          'id': 'permit:minor',
          'participant_class': 'minor',
          'guardian_permission_receipt_ref': 'receipt:g',
          'learner_assent_receipt_ref': 'receipt:l',
        });
      },
    );

    test(
      'responses preserve one identity and reject cross-owner writes',
      () async {
        final response = <String, Object?>{
          'id': 'response:1',
          'owner_id': 'owner:a',
          'run_id': 'run:a',
          'item_id': 'baseline.interest',
          'item_catalog_version': '1',
          'response_code': 'agree',
          'ordinal_value': 3,
          'answered_at_utc_ms': 2,
        };
        await insertResearchTestRow(db, 'motivation_responses', response);
        await expectLater(
          insertResearchTestRow(db, 'motivation_responses', {
            ...response,
            'id': 'response:2',
          }),
          throwsA(anything),
        );
        await expectLater(
          insertResearchTestRow(db, 'motivation_responses', {
            ...response,
            'id': 'response:3',
            'owner_id': 'owner:b',
          }),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement(
            "UPDATE motivation_responses SET owner_id = 'owner:b' WHERE id = 'response:1'",
          ),
          throwsA(anything),
        );
      },
    );

    test(
      'opportunity denominator is unique and switch counters are bounded',
      () async {
        final opportunity = researchOpportunityRow();
        await insertResearchTestRow(
          db,
          'measurement_opportunities',
          opportunity,
        );
        await expectLater(
          insertResearchTestRow(db, 'measurement_opportunities', {
            ...opportunity,
            'id': 'opportunity:2',
          }),
          throwsA(anything),
        );
        for (final value in [-1, 11]) {
          await expectLater(
            db.customStatement(
              'UPDATE measurement_opportunities SET last_switch_ordinal = ?',
              [value],
            ),
            throwsA(anything),
          );
        }
        await expectLater(
          db.customStatement(
            'UPDATE measurement_opportunities SET suppressed_switch_count = -1',
          ),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement(
            "UPDATE measurement_opportunities SET owner_id = 'owner:b'",
          ),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement(
            "UPDATE measurement_opportunities SET assigned_treatment = 'standard'",
          ),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement(
            "UPDATE measurement_opportunities SET learning_session_id = 'missing-session'",
          ),
          throwsA(anything),
        );
      },
    );

    test(
      'research rows cascade through owner deletion without orphaned children',
      () async {
        await insertResearchTestRow(
          db,
          'measurement_opportunities',
          researchOpportunityRow(),
        );
        // Existing assignment authority is explicitly deleted after its dependents.
        await db.customStatement(
          "DELETE FROM measurement_opportunities WHERE owner_id = 'owner:a'",
        );
        await db.customStatement(
          "DELETE FROM research_participation_permits WHERE owner_id = 'owner:a'",
        );
        await db.customStatement(
          "DELETE FROM motivation_measurement_runs WHERE owner_id = 'owner:a'",
        );
        await db.customStatement(
          "DELETE FROM experiment_assignments WHERE owner_id = 'owner:a'",
        );
        await db.customStatement(
          "DELETE FROM local_owners WHERE id = 'owner:a'",
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await db.customSelect('SELECT id FROM local_owners').get()).single
              .read<String>('id'),
          'owner:b',
        );
      },
    );
    group('review fixes', () {
      final invalidReferences = <String, String>{
        'empty': '',
        'blank': ' ',
        'embedded space': 'receipt:private text',
        'overlong': 'r' * 129,
        'embedded NUL': 'receipt:valid\u0000hidden',
      };
      for (final field in [
        'consent_receipt_id',
        'guardian_permission_receipt_ref',
        'learner_assent_receipt_ref',
      ]) {
        for (final invalid in invalidReferences.entries) {
          for (final operation in ['insert', 'update']) {
            test('$operation rejects ${invalid.key} $field in SQL', () async {
              final permit = <String, Object?>{
                ...researchPermitRow(),
                'id': 'permit:strict-refs',
                'participant_class': 'minor',
                'guardian_permission_receipt_ref': 'receipt:guardian',
                'learner_assent_receipt_ref': 'receipt:assent',
              };
              // No opportunity references this permit: rejection must come
              // from reference validation, not immutable-parent protection.
              if (operation == 'update') {
                await insertResearchTestRow(
                  db,
                  'research_participation_permits',
                  permit,
                );
              }
              await expectResearchSqlRejected(db, () {
                if (operation == 'insert') {
                  return insertResearchTestRow(
                    db,
                    'research_participation_permits',
                    {...permit, field: invalid.value},
                  );
                }
                return updateResearchTestRow(
                  db,
                  'research_participation_permits',
                  'permit:strict-refs',
                  {field: invalid.value},
                );
              });
            });
          }
        }
      }

      test(
        'canonical receipt bounds and adult nullable refs remain valid',
        () async {
          await insertResearchTestRow(db, 'research_participation_permits', {
            ...researchPermitRow(),
            'id': 'permit:bounded-minor',
            'participant_class': 'minor',
            'consent_receipt_id': 'r' * 128,
            'guardian_permission_receipt_ref': 'g',
            'learner_assent_receipt_ref': 'receipt:Assent_1.v2-final',
          });
          await updateResearchTestRow(
            db,
            'research_participation_permits',
            'permit:a',
            {
              'guardian_permission_receipt_ref': null,
              'learner_assent_receipt_ref': null,
              'local_revision': 2,
            },
          );
          final permits = await db
              .customSelect('SELECT id FROM research_participation_permits')
              .get();
          expect(permits, hasLength(2));
        },
      );

      final runMutations = <String, Map<String, Object?>>{
        'owner and matching assignment': {
          'owner_id': 'owner:b',
          'assignment_id': 'assignment:b',
        },
        'assignment': {'assignment_id': 'assignment:a:replacement'},
        'protocol id': {'protocol_id': 'motivation:other'},
        'protocol version and matching assignment': {
          'protocol_version': '2',
          'assignment_id': 'assignment:a:protocol-v2',
        },
        'treatment and matching assignment': {
          'treatment': 'standard',
          'assignment_id': 'assignment:a:standard',
        },
        'consent version': {'consent_version': 2},
        'consent decision': {'consent_decided_at_utc_ms': 0},
        'instrument id': {'instrument_id': 'instrument:other'},
        'instrument version': {'instrument_version': '2'},
        'form id': {'form_id': 'form:other'},
        'form version': {'form_version': '2'},
        'app version': {'app_version': '2'},
        'build id': {'build_id': 'other-build'},
        'schema pin': {'database_schema_version': 25},
        'content revision': {'content_revision': '2'},
        'evidence policy': {'evidence_policy_version': '2'},
        'start time': {'started_at_utc_ms': 2},
      };
      for (final child in ['response', 'opportunity']) {
        for (final mutation in runMutations.entries) {
          test('$child pins run ${mutation.key}', () async {
            await seedResearchReversePinGraph(
              db,
              response: child == 'response',
              opportunity: child == 'opportunity',
            );
            await expectResearchSqlRejected(
              db,
              () => updateResearchTestRow(
                db,
                'motivation_measurement_runs',
                'run:a',
                mutation.value,
              ),
            );
          });
        }
      }

      final permitMutations = <String, Map<String, Object?>>{
        'owner and matching assignment': {
          'owner_id': 'owner:b',
          'assignment_id': 'assignment:b',
        },
        'assignment': {'assignment_id': 'assignment:a:replacement'},
        'protocol id': {'protocol_id': 'motivation:other'},
        'protocol version and matching assignment': {
          'protocol_version': '2',
          'assignment_id': 'assignment:a:protocol-v2',
        },
        'treatment and matching assignment': {
          'assigned_treatment': 'standard',
          'assignment_id': 'assignment:a:standard',
        },
        'participant class': {
          'participant_class': 'minor',
          'guardian_permission_receipt_ref': 'receipt:guardian',
          'learner_assent_receipt_ref': 'receipt:assent',
        },
        'age band': {'age_band_code': 'adult:older'},
        'consent receipt': {'consent_receipt_id': 'receipt:replacement'},
        'guardian receipt null to value': {
          'guardian_permission_receipt_ref': 'receipt:guardian',
        },
        'assent receipt null to value': {
          'learner_assent_receipt_ref': 'receipt:assent',
        },
        'issued identity': {'issued_at_utc_ms': 2},
      };
      for (final mutation in permitMutations.entries) {
        test('opportunity pins permit ${mutation.key}', () async {
          await seedResearchReversePinGraph(db);
          await expectResearchSqlRejected(
            db,
            () => updateResearchTestRow(
              db,
              'research_participation_permits',
              'permit:a',
              mutation.value,
            ),
          );
        });
      }

      final assignmentMutations = <String, Map<String, Object?>>{
        'owner': {'owner_id': 'owner:b'},
        'protocol': {'protocol_version': '2'},
        'treatment': {'cohort': 'standard'},
        'experiment id': {'experiment_id': 'motivation:other'},
        'experiment version': {'experiment_version': 2},
        'assigned time': {'assigned_at_utc_ms': 2},
      };
      for (final child in ['run', 'permit']) {
        for (final mutation in assignmentMutations.entries) {
          test('$child pins assignment ${mutation.key}', () async {
            // Exercise each reverse edge independently, without opportunities.
            await db.customStatement(
              child == 'run'
                  ? 'DELETE FROM research_participation_permits'
                  : 'DELETE FROM motivation_measurement_runs',
            );
            await expectResearchSqlRejected(
              db,
              () => updateResearchTestRow(
                db,
                'experiment_assignments',
                'assignment:a',
                mutation.value,
              ),
            );
          });
        }
      }

      test('opportunity pins the referenced learning session owner', () async {
        await seedResearchReversePinGraph(db);
        await expectResearchSqlRejected(
          db,
          () => updateResearchTestRow(db, 'learning_sessions', 'session:a', {
            'owner_id': 'owner:b',
          }),
        );
      });

      for (final parent in [
        (
          'motivation_measurement_runs',
          'run:a',
          <String, Object?>{
            'owner_id': 'owner:b',
            'assignment_id': 'assignment:b',
          },
        ),
        (
          'research_participation_permits',
          'permit:a',
          <String, Object?>{'consent_receipt_id': 'receipt:replacement'},
        ),
        (
          'experiment_assignments',
          'assignment:a',
          <String, Object?>{'owner_id': 'owner:b'},
        ),
        (
          'learning_sessions',
          'session:a',
          <String, Object?>{'owner_id': 'owner:b'},
        ),
      ]) {
        test('tombstoned children still pin ${parent.$1}', () async {
          await seedResearchReversePinGraph(db);
          for (final table in researchTables) {
            await db.customStatement('UPDATE $table SET is_deleted = 1');
          }
          await expectResearchSqlRejected(
            db,
            () => updateResearchTestRow(db, parent.$1, parent.$2, parent.$3),
          );
        });
      }

      test('same-owner lifecycle updates preserve referenced identity', () async {
        await seedResearchReversePinGraph(db);
        final permitUpdate = <String, Object?>{
          ...researchPermitRow(),
          'local_revision': 2,
          'cloud_revision': 3,
          'last_acknowledged_at_utc_ms': 10,
          'server_updated_at_utc_ms': 11,
          'expires_at_utc_ms': 20000,
          'issuer_key_id': 'issuer:synthetic-rotation',
          'signature': 'synthetic-revocation-signature',
          'payload_sha256': 'b' * 64,
          'revoked_at_utc_ms': 9,
          'is_deleted': 1,
        };
        // Full-row updates repeat unchanged pins, as the permit importer does.
        // Synthetic SQL payloads here test storage, not signature authenticity.
        await updateResearchTestRow(
          db,
          'research_participation_permits',
          'permit:a',
          permitUpdate,
        );
        final runUpdate = <String, Object?>{
          ...researchRunRow(),
          'state': 'withdrawn',
          'closed_at_utc_ms': 9,
          'local_revision': 2,
          'cloud_revision': 3,
          'last_acknowledged_at_utc_ms': 10,
          'server_updated_at_utc_ms': 11,
          'is_deleted': 1,
        };
        await updateResearchTestRow(
          db,
          'motivation_measurement_runs',
          'run:a',
          runUpdate,
        );
        await updateResearchTestRow(db, 'motivation_responses', 'response:a', {
          'local_revision': 2,
          'cloud_revision': 3,
          'is_deleted': 1,
        });
        await updateResearchTestRow(
          db,
          'measurement_opportunities',
          'opportunity:a',
          {
            'effective_presentation': 'standard',
            'last_switch_ordinal': 1,
            'suppressed_switch_count': 1,
            'started_event_id': 'event:synthetic-start',
            'completed_event_id': 'event:synthetic-completion',
            'closed_at_utc_ms': 7,
            'local_revision': 2,
            'cloud_revision': 3,
            'is_deleted': 1,
          },
        );
        await updateResearchTestRow(db, 'learning_sessions', 'session:a', {
          'owner_id': 'owner:a',
          'state': 'completed',
          'ended_at_utc_ms': 7,
          'correct_count': 1,
        });
        await db.customStatement(
          'UPDATE experiment_assignments SET owner_id = owner_id, '
          'protocol_version = protocol_version, cohort = cohort',
        );
        for (final entry in {
          'research_participation_permits': permitUpdate,
          'motivation_measurement_runs': runUpdate,
        }.entries) {
          final actual =
              (await db.customSelect('SELECT * FROM ${entry.key}').getSingle())
                  .data;
          for (final field in entry.value.entries) {
            expect(actual[field.key], field.value, reason: field.key);
          }
        }
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      });

      test(
        'unreferenced ordinary assignments and sessions can rekey',
        () async {
          await seedResearchReversePinGraph(db);
          final before = await researchSqlSnapshot(db, tables: researchTables);
          await insertResearchTestRow(db, 'experiment_assignments', {
            'id': 'assignment:ordinary',
            'owner_id': 'owner:a',
            'experiment_id': 'ordinary',
            'experiment_version': 1,
            'cohort': 'standard',
            'protocol_version': '1',
            'assigned_at_utc_ms': 1,
          });
          await insertResearchTestRow(db, 'learning_sessions', {
            'id': 'session:ordinary',
            'owner_id': 'owner:a',
            'activity_type': 'quiz',
            'state': 'started',
            'started_at_utc_ms': 1,
            'app_version': '1',
            'build_id': 'synthetic',
          });
          for (final parent in [
            ('experiment_assignments', 'assignment:ordinary'),
            ('learning_sessions', 'session:ordinary'),
          ]) {
            await updateResearchTestRow(db, parent.$1, parent.$2, {
              'id': '${parent.$2}:rebound',
              'owner_id': 'owner:b',
            });
            final row = await db
                .customSelect(
                  "SELECT owner_id FROM ${parent.$1} "
                  "WHERE id = '${parent.$2}:rebound'",
                )
                .getSingle();
            expect(row.read<String>('owner_id'), 'owner:b');
          }
          expect(await researchSqlSnapshot(db, tables: researchTables), before);
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        },
      );

      test(
        'v24 beforeOpen adds forward guards beside existing owner triggers',
        () async {
          await seedResearchReversePinGraph(db);
          final legacyNames = <String>{
            for (final table in researchTables)
              for (final operation in ['insert', 'update'])
                '${table}_owner_$operation',
          };
          final triggers = await db
              .customSelect(
                "SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'trigger'",
              )
              .get();
          final legacySql = <String, String>{
            for (final row in triggers)
              if (legacyNames.contains(row.read<String>('name')))
                row.read<String>('name'): row.read<String>('sql'),
          };
          expect(legacySql.keys.toSet(), legacyNames);
          final guardedTables = {
            ...researchTables,
            'experiment_assignments',
            'learning_sessions',
          };
          // Reconstruct the pre-fix v24 trigger state in this synthetic database.
          // Preserve all eight legacy owner guards and unrelated triggers.
          for (final row in triggers) {
            final name = row.read<String>('name');
            if (guardedTables.contains(row.read<String>('tbl_name')) &&
                !legacyNames.contains(name)) {
              final quotedName = name.replaceAll('"', '""');
              await db.customStatement('DROP TRIGGER "$quotedName"');
            }
          }
          final before = await researchSqlSnapshot(db);
          for (var reopening = 0; reopening < 2; reopening++) {
            await db.migration.beforeOpen!(const OpeningDetails(24, 24));
          }
          final installed = await db
              .customSelect(
                "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
              )
              .get();
          for (final old in legacySql.entries) {
            expect(
              installed
                  .singleWhere((row) => row.read<String>('name') == old.key)
                  .read<String>('sql'),
              old.value,
            );
          }
          expect(await researchSqlSnapshot(db), before);
          await expectCurrentDatabaseContract(db);
          expect(await currentDatabaseTableNames(db), hasLength(48));
          await expectResearchSqlRejected(
            db,
            () => updateResearchTestRow(
              db,
              'motivation_measurement_runs',
              'run:a',
              {'owner_id': 'owner:b', 'assignment_id': 'assignment:b'},
            ),
          );
          await expectResearchSqlRejected(
            db,
            () => insertResearchTestRow(db, 'research_participation_permits', {
              ...researchPermitRow(),
              'id': 'permit:empty-receipts',
              'participant_class': 'minor',
              'guardian_permission_receipt_ref': '',
              'learner_assent_receipt_ref': '',
            }),
          );
        },
      );
    });
  });
}

const researchTables = <String>{
  'motivation_measurement_runs',
  'motivation_responses',
  'research_participation_permits',
  'measurement_opportunities',
};

void createSchemaTwentyThreeFixture(dynamic sqlite) {
  fixture.createSchemaTwentyTwoFixture(sqlite);
  sqlite.execute(
    "ALTER TABLE learner_preferences ADD COLUMN home_experience TEXT NOT NULL DEFAULT 'standard'",
  );
  sqlite.execute(
    "UPDATE learner_preferences SET preference_version = 2, home_experience = 'adventure'",
  );
  sqlite.execute(
    "INSERT INTO experiment_assignments (id,owner_id,experiment_id,experiment_version,cohort,protocol_version,assigned_at_utc_ms) VALUES ('assignment:fixture','owner:v19','motivation',1,'adventure','1',1788048000000)",
  );
  sqlite.execute('PRAGMA user_version = 23');
}

Future<void> insertResearchTestRow(
  AppDatabase db,
  String table,
  Map<String, Object?> values,
) => db.customStatement(
  'INSERT INTO $table (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
  values.values.toList(),
);

Map<String, Object?> researchRunRow() => {
  'id': 'run:a',
  'owner_id': 'owner:a',
  'assignment_id': 'assignment:a',
  'consent_version': 1,
  'consent_decided_at_utc_ms': 1,
  'protocol_id': 'motivation',
  'protocol_version': '1',
  'treatment': 'adventure',
  'instrument_id': 'instrument',
  'instrument_version': '1',
  'form_id': 'paired-form',
  'form_version': '1',
  'app_version': '1',
  'build_id': 'test',
  'database_schema_version': 24,
  'content_revision': '1',
  'evidence_policy_version': '1',
  'state': 'started',
  'started_at_utc_ms': 1,
};

Map<String, Object?> researchPermitRow() => {
  'id': 'permit:a',
  'owner_id': 'owner:a',
  'participant_class': 'adult',
  'age_band_code': 'adult',
  'assignment_id': 'assignment:a',
  'assigned_treatment': 'adventure',
  'consent_receipt_id': 'receipt:a',
  'protocol_id': 'motivation',
  'protocol_version': '1',
  'issued_at_utc_ms': 1,
  'expires_at_utc_ms': 10000,
  'issuer_key_id': 'issuer:test',
  'payload_sha256': 'a' * 64,
  'signature': 'signed-test-fixture',
  'local_revision': 1,
  'cloud_revision': 1,
};

Map<String, Object?> researchOpportunityRow() => {
  'id': 'opportunity:a',
  'owner_id': 'owner:a',
  'measurement_run_id': 'run:a',
  'permit_id': 'permit:a',
  'entry_attempt_id': '11111111-1111-4111-8111-111111111111',
  'assigned_treatment': 'adventure',
  'effective_presentation': 'adventure',
  'opened_at_utc_ms': 2,
};

Future<void> updateResearchTestRow(
  AppDatabase db,
  String table,
  String id,
  Map<String, Object?> values,
) => db.customStatement(
  'UPDATE $table SET ${values.keys.map((key) => '$key = ?').join(', ')} '
  'WHERE id = ?',
  [...values.values, id],
);

Future<Map<String, List<Map<String, Object?>>>> researchSqlSnapshot(
  AppDatabase db, {
  Iterable<String> tables = const [
    'local_owners',
    'experiment_assignments',
    'learning_sessions',
    ...researchTables,
  ],
}) async => {
  for (final table in tables)
    table: [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY id').get())
        Map<String, Object?>.from(row.data),
    ],
};

Future<void> expectResearchSqlRejected(
  AppDatabase db,
  Future<void> Function() write,
) async {
  final before = await researchSqlSnapshot(db);
  await expectLater(
    write(),
    throwsA(
      isA<SqliteException>().having(
        (error) => error.resultCode,
        'SQLITE_CONSTRAINT (not a SQL syntax or fixture error)',
        19,
      ),
    ),
  );
  expect(await researchSqlSnapshot(db), before);
  expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
}

Future<void> seedResearchReversePinGraph(
  AppDatabase db, {
  bool response = true,
  bool opportunity = true,
}) async {
  for (final assignment in [
    ('assignment:b', 'owner:b', 'other-owner', '1', 'adventure'),
    ('assignment:a:replacement', 'owner:a', 'replacement', '1', 'adventure'),
    ('assignment:a:protocol-v2', 'owner:a', 'protocol-v2', '2', 'adventure'),
    ('assignment:a:standard', 'owner:a', 'standard', '1', 'standard'),
  ]) {
    await insertResearchTestRow(db, 'experiment_assignments', {
      'id': assignment.$1,
      'owner_id': assignment.$2,
      'experiment_id': assignment.$3,
      'experiment_version': 1,
      'protocol_version': assignment.$4,
      'cohort': assignment.$5,
      'assigned_at_utc_ms': 1,
    });
  }
  if (response) {
    await insertResearchTestRow(db, 'motivation_responses', {
      'id': 'response:a',
      'owner_id': 'owner:a',
      'run_id': 'run:a',
      'item_id': 'baseline.interest',
      'item_catalog_version': '1',
      'response_code': 'agree',
      'ordinal_value': 3,
      'answered_at_utc_ms': 2,
    });
  }
  if (opportunity) {
    await insertResearchTestRow(db, 'learning_sessions', {
      'id': 'session:a',
      'owner_id': 'owner:a',
      'activity_type': 'quiz',
      'state': 'started',
      'started_at_utc_ms': 2,
      'app_version': '1',
      'build_id': 'synthetic',
    });
    await insertResearchTestRow(db, 'measurement_opportunities', {
      ...researchOpportunityRow(),
      'learning_session_id': 'session:a',
    });
  }
}
