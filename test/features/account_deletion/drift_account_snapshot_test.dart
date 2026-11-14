import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 10, 24, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement(
      "INSERT INTO local_owners "
      "(id, firebase_uid, account_state, is_active, created_at_utc_ms) "
      "VALUES ('owner-a', 'uid-a', 'registered', 1, 1), "
      "('owner-b', 'uid-b', 'registered', 0, 2)",
    );
    await database.customStatement(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, sort_order, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('cat-a', 'owner-a', 'A', 'a', 0, 0, 1, 1), "
      "('cat-b', 'owner-b', 'B', 'b', 0, 0, 1, 1)",
    );
  });

  tearDown(() => database.close());

  test(
    'covers every required local scope and isolates the requested owner',
    () async {
      final snapshot = await DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => now,
      ).build(ownerId: 'owner-a');

      expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
      expect(snapshot.sha256, sha256.convert(snapshot.bytes).toString());
      expect(snapshot.schemaVersion, database.schemaVersion);
      final json =
          jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
      expect(json['schemaVersion'], 11);
      expect(json['ownerId'], 'owner-a');
      final data = json['data'] as Map<String, dynamic>;
      expect(data.keys.toSet(), requiredFullAccountExportScopes);
      expect(
        snapshot.recordCount,
        data.values.fold<int>(
          0,
          (count, rows) => count + (rows as List).length,
        ),
      );
      expect((data['vocabulary_categories'] as List).single['id'], 'cat-a');
      expect(utf8.decode(snapshot.bytes), isNot(contains('cat-b')));
      expect(utf8.decode(snapshot.bytes), isNot(contains('uid-b')));
    },
  );

  test(
    'schema 11 exports every owner scope and exact public pinned catalog',
    () async {
      await _seedS6Rows(database);
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/account_deletion_export_scopes.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final expectedScopes = (fixture['exportV11'] as List)
          .cast<String>()
          .toSet();
      expect(expectedScopes, hasLength(32));
      expect(requiredFullAccountExportScopes, expectedScopes);
      final builder = DriftAccountSnapshotBuilder(database, nowUtc: () => now);
      final snapshot = await builder.build(ownerId: 'owner-a');
      final repeated = await builder.build(ownerId: 'owner-a');
      expect(snapshot.bytes, repeated.bytes);
      expect(snapshot.sha256, sha256.convert(snapshot.bytes).toString());
      expect(snapshot.schemaVersion, 11);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle()).data,
        {'user_version': 11},
      );
      expect(snapshot.coveredScopes, expectedScopes);
      final decoded =
          jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 11);
      expect(data.keys.toSet(), expectedScopes);
      final sortedScopes = expectedScopes.toList()..sort();
      expect(decoded['coveredScopes'], sortedScopes);
      expect(data.keys, sortedScopes);
      const publicScopes = {'quest_definitions', 'quest_definition_revisions'};
      const childScopes = {
        'vocabulary_import_rows',
        'quest_objective_progress',
      };
      for (final scope in expectedScopes.difference({
        ...publicScopes,
        ...childScopes,
        'local_owners',
      })) {
        final actual = await database
            .customSelect(
              "SELECT * FROM $scope WHERE owner_id = 'owner-a' ORDER BY rowid",
            )
            .get();
        expect(
          data[scope],
          actual.map((row) => row.data).toList(),
          reason: scope,
        );
        for (final row in data[scope] as List) {
          expect((row as Map)['owner_id'], 'owner-a', reason: scope);
          final keys = row.keys.cast<String>().toList();
          expect(keys, keys.toList()..sort(), reason: 'canonical $scope keys');
        }
      }
      for (final scope in publicScopes) {
        final actual = await database
            .customSelect('SELECT * FROM $scope')
            .get();
        expect(data[scope], unorderedEquals(actual.map((row) => row.data)));
      }
      expect(
        (data['owner_calendar_epochs'] as List).single['rule_id'],
        'rule-a',
      );
      expect((data['quest_claim_receipts'] as List).single['id'], 'receipt-a');
      expect(
        (data['streak_baselines'] as List).single['origin_owner_id'],
        'synthetic-origin-a',
      );
      expect(
        (data['streak_token_adjustments'] as List).single['id'],
        'adjustment-a',
      );
      final revisions = data['quest_definition_revisions'] as List;
      expect(revisions, hasLength(2));
      expect(
        revisions.map((row) => (row as Map)['canonical_definition']),
        unorderedEquals({
          '{"synthetic":true,"publicTitle":"A","xpAmount":50}',
          '{"synthetic":true,"publicTitle":"B","xpAmount":50}',
        }),
      );
      expect((data['local_owners'] as List).single['id'], 'owner-a');
      expect(
        (data['quest_instances'] as List).single['instance_id'],
        'pinned-a',
      );
      expect(
        (data['quest_objective_progress'] as List).single['id'],
        'child-a',
      );
      expect(utf8.decode(snapshot.bytes), isNot(contains('uid-b')));
      expect(utf8.decode(snapshot.bytes), isNot(contains('cat-b')));
      expect(
        snapshot.recordCount,
        data.values.fold<int>(
          0,
          (count, rows) => count + (rows as List).length,
        ),
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(data['events_v2'], isEmpty);
      expect(data['research_consents'], isEmpty);
    },
  );
}

Future<void> _seedS6Rows(AppDatabase database) async {
  const at = 1792833600000;
  await database.customStatement(
    'INSERT INTO quest_definitions '
    '(quest_id,catalog_version,title,description,type,objectives_json,reward_json) '
    "VALUES ('public-quest',1,'Synthetic public Quest','Public catalog','daily','[]','{\"xpAmount\":50}')",
  );
  for (final (suffix, version) in [('a', 1), ('b', 2)]) {
    final body =
        '{"synthetic":true,"publicTitle":"${suffix.toUpperCase()}","xpAmount":50}';
    final digest = sha256.convert(utf8.encode(body)).toString();
    await database.customStatement(
      'INSERT INTO owner_calendar_epochs '
      '(rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) '
      'VALUES (?,?,?,?,?,?,1)',
      [
        'rule-$suffix',
        'owner-$suffix',
        'synthetic-origin-$suffix',
        at * 1000,
        'UTC',
        'synthetic-tzdb',
      ],
    );
    await database.customStatement(
      'INSERT INTO quest_definition_revisions '
      '(quest_id,catalog_version,definition_digest,canonical_definition) VALUES (?,?,?,?)',
      ['public-quest', version, digest, body],
    );
    // Raw lifecycle fixtures, not claims verified or issued by a real authority.
    await database.customStatement(
      'INSERT INTO quest_instances '
      '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,'
      'origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,'
      'definition_digest,record_kind) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        'pinned-$suffix',
        'public-quest',
        'owner-$suffix',
        version,
        at,
        'completed',
        'synthetic-origin-$suffix',
        'synthetic-period-$suffix',
        'rule-$suffix',
        '2026-10-24',
        '[[${at * 1000},${(at + 86400000) * 1000}]]',
        digest,
        'canonical',
      ],
    );
    await database.customStatement(
      'INSERT INTO quest_objective_progress '
      '(id,instance_id,objective_id,current_count,target_count,source_event_ids_json) '
      'VALUES (?,?,?,?,?,?)',
      [
        'child-$suffix',
        'pinned-$suffix',
        'synthetic-correct',
        1,
        5,
        '["synthetic-source-$suffix"]',
      ],
    );
    await database.customStatement(
      'INSERT INTO quest_claim_receipts '
      '(id,owner_id,origin_owner_id,instance_id,issued_at_utc_ms,completed_at_utc_ms,xp_amount,evidence_json) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        'receipt-$suffix',
        'owner-$suffix',
        'synthetic-origin-$suffix',
        'pinned-$suffix',
        at + 1,
        at,
        50,
        '{"synthetic":true,"attemptIds":["synthetic-$suffix"]}',
      ],
    );
    await database.customStatement(
      'INSERT INTO streak_baselines '
      '(origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,'
      'freeze_count,last_learned_at_utc_ms,updated_at_utc_ms,controls_continuity) '
      'VALUES (?,?,?,?,?,?,?,?,1)',
      ['synthetic-origin-$suffix', 'owner-$suffix', at, 3, 7, 2, null, at],
    );
    await database.customStatement(
      'INSERT INTO streak_token_adjustments '
      '(id,owner_id,origin_owner_id,command_id,occurred_at_utc_ms,kind,delta,protected_day) '
      "VALUES (?,?,?,?,?,'autoProtect',-1,'2026-10-23')",
      [
        'adjustment-$suffix',
        'owner-$suffix',
        'synthetic-origin-$suffix',
        'synthetic-command-$suffix',
        at,
      ],
    );
  }
}
