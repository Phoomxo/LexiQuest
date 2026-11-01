import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_motivation_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/motivation_rewards.dart';

import '../test/support/populated_owner_migration_fixture.dart';

typedef _Rows = Map<String, List<Map<String, Object?>>>;

const _previousPath = 'test/fixtures/populated_schema_v23.json';
const _previousSchemaPath = 'test/fixtures/schema_v23.sql';
const _schemaPath = 'test/fixtures/schema_v24.sql';
const _capturePath = 'test/fixtures/populated_schema_v24.json';
const _fenceKey = 'accountDeletion.ownerWriteIntent';

void main() {
  test('capture genuine populated v24 before the next migration', () async {
    final previousBytes = File(_previousPath).readAsBytesSync();
    final previousHash = sha256.convert(previousBytes).toString();
    expect(
      previousHash,
      '92a58eecd4ccb85df48efff41274f74ed2628f81bea5383b382fb296eab459df',
    );
    final previousSchema = File(_previousSchemaPath).readAsStringSync();
    expect(
      sha256.convert(utf8.encode(previousSchema)).toString(),
      '4b43330c96a62dc1451926f2f5c83854188fc08038e2268105614a1ca7a32c78',
    );
    final previous = jsonDecode(utf8.decode(previousBytes)) as Map;
    expect(previous['schemaVersion'], 23);
    expect(previous['synthetic'], isTrue);
    final oldRows = _decodeRows(previous['rows']);
    expect(oldRows.length, 43);
    expect(oldRows.values.every((rows) => rows.isNotEmpty), isTrue);
    final originalFence = oldRows['runtime_flags']!.singleWhere(
      (row) => row['key'] == _fenceKey,
    );
    final setupRows = {
      for (final entry in oldRows.entries)
        entry.key: entry.key == 'runtime_flags'
            ? entry.value.where((row) => row['key'] != _fenceKey).toList()
            : entry.value,
    };
    final database = db.AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(previousSchema);
          sqlite.execute('PRAGMA foreign_keys = ON');
          sqlite.execute('BEGIN');
          sqlite.execute('PRAGMA defer_foreign_keys = ON');
          for (final entry in setupRows.entries) {
            for (final row in entry.value) {
              sqlite.execute(
                'INSERT INTO "${entry.key}" (${row.keys.join(',')}) '
                'VALUES (${List.filled(row.length, '?').join(',')})',
                row.values.toList(),
              );
            }
          }
          sqlite.execute('COMMIT');
          sqlite.execute('PRAGMA user_version = 23');
        },
      ),
    );
    addTearDown(database.close);
    await _initialize(database);
    final migrated = await ownerMigrationRows(database);
    _expectOriginalFields(migrated, setupRows);
    for (final row in migrated['quest_instances']!) {
      expect(row['period_key'], 'legacy:${row['instance_id']}');
      expect(row['period_json'], isNull);
      expect(row['definition_snapshot_json'], isNull);
      expect(row['definition_sha256'], isNull);
    }
    for (final row in migrated['learning_day_log']!) {
      expect(row['source_attempt_id'], isNull);
      expect(row['timezone_id'], isNull);
      expect(row['policy_version'], isNull);
    }
    expect(
      migrated['learning_profiles']!.single['learning_timezone_id'],
      isNull,
    );

    const ownerId = 'owner-b';
    var now = DateTime.utc(2026, 10, 29, 12, 1);
    expect(
      now.millisecondsSinceEpoch,
      lessThan(originalFence['updated_at_utc_ms'] as int),
    );
    final ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => now,
      nonceGenerator: () => 'synthetic-schema24-unused-nonce',
    );
    expect(await ownerWrites.inspect(), isNull);
    // Isolate new projections from retained historical owner-a projection rows.
    await database.transaction(() async {
      await database.customStatement('UPDATE local_owners SET is_active=0');
      await database.customStatement(
        'UPDATE local_owners SET is_active=1 WHERE id=?',
        [ownerId],
      );
    });
    final packs = LearningPackUseCases(
      repository: DriftLearningPackRepository(
        database: database,
        ownerWrites: ownerWrites,
      ),
      nowUtc: () => now,
      generateId: () => 'synthetic-schema24-pack-command',
    );
    addTearDown(packs.dispose);
    final scope = await packs.captureOwner(stillCurrent: () => true);
    expect(scope!.ownerId, ownerId);
    final pack = const LearningPackCodec().decode(
      oldRows['learning_pack_versions']!.single['package_bytes']! as Uint8List,
    );
    final installed = await packs.importPack(
      packs.prepareImport(scope: scope, pack: pack, pinned: true),
    );
    final detail = await packs.detail(scope, installed.id);
    final wordId = detail.bindings.single.wordId;
    expect(installed.ownerId, ownerId);
    expect(installed.packageSha256, pack.packageSha256);
    final profile =
        await DriftLearningProfileRepository(
          database: database,
          ownerWrites: ownerWrites,
        ).save(
          LearningProfileChange(
            expectedOwnerId: ownerId,
            expectedRevision: 0,
            draft: LearningProfileDraft(
              onboardingState: LearningOnboardingState.completed,
              learningTimezoneId: 'Asia/Bangkok',
            ),
            updatedAtUtc: now,
            stillCurrent: () => true,
          ),
        );
    expect(profile.draft.learningTimezoneId, 'Asia/Bangkok');
    expect(
      migrated['srs_states']!.where((row) => row['word_id'] == wordId),
      isEmpty,
    );
    final quests = DriftQuestRepository(
      database,
      ownerWrites: ownerWrites,
      nowUtc: () => now,
    );
    final definition = QuestDefinition(
      questId: 'synthetic-schema24-weekly',
      catalogVersion: 1,
      title: 'Synthetic retained weekly Quest',
      description: 'Preserve genuine period and source pins through migration',
      type: QuestType.weekly,
      objectives: [
        QuestObjective(
          objectiveId: 'synthetic-schema24-harbor',
          description: 'Answer the installed synthetic word',
          targetCount: 1,
          criteria: ObjectiveCriteria(
            eventType: 'QuizCompleted',
            filters: {'wordId': wordId, 'correct': true},
          ),
        ),
      ],
      reward: const RewardSpec(xpAmount: 200),
    );
    final instance = await quests.assignCurrentPeriod(
      ownerId: ownerId,
      definition: definition,
      instanceId: 'synthetic-schema24-weekly-instance',
      assignedAtUtc: now,
      timezoneId: 'Asia/Bangkok',
      stillCurrent: () => true,
    );
    expect(instance, isNotNull);
    expect(instance!.period!.kind, 'weekly');
    final learning = DriftLearningRepository(
      database,
      ownerWrites: ownerWrites,
    );
    const sessionId = 'synthetic-schema24-learning-session';
    const answerId = 'synthetic-schema24-learning-answer';
    await learning.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: ownerId,
        activityType: 'quiz',
        startedAtUtc: now,
        appVersion: 'synthetic-schema24',
        buildId: 'synthetic-capture-only',
      ),
    );
    now = now.add(const Duration(milliseconds: 1));
    await learning.recordAnswer(
      RecordAnswerCommand(
        id: answerId,
        ownerId: ownerId,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'activeRecall',
        isCorrect: true,
        responseTimeMs: 500,
        attemptNumber: 1,
        occurredAtUtc: now,
      ),
    );
    final completions = await quests.reconcile(
      expectedOwnerId: ownerId,
      catalog: [definition],
      stillCurrent: () => true,
    );
    expect(completions, hasLength(1));
    expect(completions.single.objectiveEventIds, [answerId]);
    final rewards = DriftMotivationRewardRepository(
      database,
      ownerWrites: ownerWrites,
      quests: quests,
      nowUtc: () => now,
    );
    await rewards.reconcile(expectedOwnerId: ownerId, stillCurrent: () => true);
    final generated = await ownerMigrationRows(database);
    final day = generated['learning_day_log']!.singleWhere(
      (row) => row['source_attempt_id'] == answerId,
    );
    expect(day['learning_day'], '2026-10-29');
    expect(day['timezone_id'], 'Asia/Bangkok');
    expect(day['policy_version'], 1);
    expect(day['first_session_at_utc_ms'], now.millisecondsSinceEpoch);
    final pinnedQuest = generated['quest_instances']!.singleWhere(
      (row) => row['instance_id'] == instance.instanceId,
    );
    expect(pinnedQuest['period_json'], instance.period!.json);
    expect(pinnedQuest['definition_snapshot_json'], isNotNull);
    expect(pinnedQuest['definition_sha256'], instance.definitionSha256);
    expect(pinnedQuest['state'], 'completed');
    for (final type in [
      MotivationRewardPolicy.questXp,
      MotivationRewardPolicy.weeklyFreeze,
    ]) {
      expect(
        generated['reward_transactions']!.where(
          (row) => row['transaction_type'] == type,
        ),
        hasLength(1),
      );
    }

    await packs.dispose();
    await database.transaction(() async {
      for (final owner in oldRows['local_owners']!) {
        await database.customStatement(
          'UPDATE local_owners SET is_active=? WHERE id=?',
          [owner['is_active'], owner['id']],
        );
      }
    });
    // The original fence follows the synthetic predecessor operations unchanged.
    await insertOwnerMigrationRow(database, 'runtime_flags', originalFence);
    final fence = await ownerWrites.inspect();
    expect(fence!.phase, DeletionIntentPhase.pendingCloud);
    expect(fence.casToken!.matchesOwner('owner-a'), isTrue);
    final rows = await ownerMigrationRows(database);
    _expectOriginalFields(rows, oldRows);
    expect(rows.length, 43);
    expect(rows.values.every((value) => value.isNotEmpty), isTrue);
    expect(rows['runtime_flags'], oldRows['runtime_flags']);
    await _assertHealthy(database);
    final schema = await _schema(database);
    final status = _git([
      'status',
      '--porcelain=v1',
      '--untracked-files=all',
      '--',
      '.',
      ':(exclude)$_schemaPath',
      ':(exclude)$_capturePath',
    ]).trimRight();
    final capture = <String, Object?>{
      'schemaVersion': 24,
      'sourceBaselineCommit': _git(['rev-parse', 'HEAD']).trim(),
      'sourceState': status.isEmpty ? 'committed' : 'local-changes',
      'sourceWorktreeStatus': status.isEmpty ? <String>[] : status.split('\n'),
      'sourceStateExcludedCapturePaths': [_schemaPath, _capturePath],
      'databaseGeneratedSourceSha256': sha256
          .convert(File('lib/data/local/app_database.g.dart').readAsBytesSync())
          .toString(),
      'synthetic': true,
      'previousFixturePath': _previousPath,
      'previousFixtureSha256': previousHash,
      'previousRowsPreserved': oldRows.values.fold<int>(
        0,
        (sum, value) => sum + value.length,
      ),
      'captureConstruction': {
        'sequence': [
          'Restore genuine v23 DDL and all old rows except the pending-deletion fence',
          'Run the actual v23-to-v24 migration and check every original field',
          'Temporarily activate retained synthetic owner-b and import its own codec-validated pack',
          'Create owner-b timezone through the actual profile writer without changing old profile facts',
          'Assign a weekly Quest and commit a canonical installed-word answer and day receipt',
          'Reconcile the canonical completion and typed XP/freeze grants',
          'Restore original owner activation and exact pending-deletion fence; check every old field again',
        ],
        'reason':
            'Synthetic learning predates the retained pending deletion; no old fact or authority is rewritten',
        'fixedAnswerAtUtc': now.toIso8601String(),
        'answerId': answerId,
        'newFactsOwnerId': ownerId,
        'packVersionId': installed.id,
        'packageSha256': pack.packageSha256,
        'questInstanceId': instance.instanceId,
      },
      'rows': rows,
    };
    final payload = '${const JsonEncoder.withIndent('  ').convert(capture)}\n';
    final decodedRows = _decodeRows((jsonDecode(payload) as Map)['rows']);
    expect(decodedRows, rows, reason: 'Every JSON BLOB roundtrips exactly');
    final restored = db.AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(schema);
          sqlite.execute('PRAGMA user_version = 24');
        },
      ),
    );
    addTearDown(restored.close);
    await _initialize(restored);
    await restored.transaction(() async {
      await restored.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in decodedRows.entries) {
        for (final row in table.value) {
          await insertOwnerMigrationRow(restored, table.key, row);
        }
      }
    });
    expect(await ownerMigrationRows(restored), rows);
    expect(await _schema(restored), schema);
    await _assertHealthy(restored);
    final outputs = {_schemaPath: schema, _capturePath: payload};
    for (final output in outputs.entries) {
      final file = File(output.key);
      if (file.existsSync()) {
        expect(
          file.readAsStringSync(),
          output.value,
          reason: 'Never replace a capture',
        );
      }
    }
    for (final output in outputs.entries) {
      final file = File(output.key);
      if (!file.existsSync()) file.writeAsStringSync(output.value, flush: true);
      expect(file.readAsStringSync(), output.value);
    }
  });
}

Future<void> _initialize(db.AppDatabase database) async {
  expect(database.schemaVersion, 24);
  expect(database.allTables.length, 43);
  await database.customSelect('SELECT 1').getSingle();
  await database.customStatement('PRAGMA foreign_keys = ON');
  expect(
    (await database.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
      'foreign_keys',
    ),
    1,
  );
}

_Rows _decodeRows(Object? value) => {
  for (final table in (value as Map<String, dynamic>).entries)
    table.key: [
      for (final raw in table.value as List)
        {
          for (final cell in (raw as Map<String, dynamic>).entries)
            cell.key: cell.value is List
                ? Uint8List.fromList((cell.value as List).cast<int>())
                : cell.value,
        },
    ],
};

void _expectOriginalFields(_Rows actual, _Rows original) {
  for (final table in original.entries) {
    for (final row in table.value) {
      expect(
        actual[table.key]!.map(
          (candidate) => {for (final key in row.keys) key: candidate[key]},
        ),
        contains(equals(row)),
        reason: 'Preserve every original field in ${table.key}',
      );
    }
  }
}

Future<void> _assertHealthy(db.AppDatabase database) async {
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  expect(
    (await database.customSelect('PRAGMA integrity_check').getSingle())
        .read<String>('integrity_check'),
    'ok',
  );
  final blobs = await database
      .customSelect(
        'SELECT typeof(package_bytes) AS storage_type FROM learning_pack_versions',
      )
      .get();
  expect(blobs, isNotEmpty);
  expect(
    blobs.map((row) => row.read<String>('storage_type')),
    everyElement('blob'),
  );
}

Future<String> _schema(db.AppDatabase database) async {
  final ddl = await database
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type IN ('table','index','trigger') "
        "AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name",
      )
      .get();
  return '${ddl.map((row) => '${row.read<String>('sql')};').join('\n')}\n';
}

String _git(List<String> arguments) {
  final result = Process.runSync('git', arguments);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout as String;
}
