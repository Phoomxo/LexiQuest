import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';

import '../test/support/populated_owner_migration_fixture.dart';

typedef _Rows = Map<String, List<Map<String, Object?>>>;

const _previousPath = 'test/fixtures/populated_schema_v22.json';
const _schemaPath = 'test/fixtures/schema_v23.sql';
const _capturePath = 'test/fixtures/populated_schema_v23.json';

void main() {
  test('capture genuine populated v23 before the next migration', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _initialize(database);
    final previousBytes = File(_previousPath).readAsBytesSync();
    final previousHash = sha256.convert(previousBytes).toString();
    expect(
      previousHash,
      'd09dc35bc9103456092c5f133bca2a62540f49dd3bfe0525f1d48252d2e839e9',
      reason: 'Preserve the genuine v22 capture recorded in the schema ledger',
    );
    final previous =
        jsonDecode(utf8.decode(previousBytes)) as Map<String, dynamic>;
    expect(previous['schemaVersion'], 22);
    expect(previous['synthetic'], isTrue);
    final oldRows = _decodeRows(previous['rows']);
    expect(oldRows.length, 41);
    expect(
      oldRows.values.fold<int>(0, (total, rows) => total + rows.length),
      68,
    );
    expect(oldRows.values.every((rows) => rows.isNotEmpty), isTrue);

    // The retained pending-deletion fence must follow the earlier installation.
    await _restore(database, {'local_owners': oldRows['local_owners']!});
    final owners = oldRows['local_owners']!
        .where((row) => row['is_active'] == 1)
        .toList();
    expect(owners, hasLength(1));
    final ownerId = owners.single['id'] as String;
    expect(ownerId, 'owner-a');
    final now = DateTime.utc(2026, 10, 1);
    final originalFence = oldRows['runtime_flags']!.singleWhere(
      (row) => row['key'] == 'accountDeletion.ownerWriteIntent',
    );
    expect(
      now.millisecondsSinceEpoch,
      lessThan(originalFence['updated_at_utc_ms'] as int),
      reason: 'Synthetic installation predates the retained deletion intent',
    );
    final ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => now,
      nonceGenerator: () => 'synthetic-schema23-unused-nonce',
    );
    expect(await ownerWrites.inspect(), isNull);
    final useCases = LearningPackUseCases(
      repository: DriftLearningPackRepository(
        database: database,
        ownerWrites: ownerWrites,
      ),
      nowUtc: () => now,
      generateId: () => 'synthetic-schema23-install-command',
    );
    addTearDown(useCases.dispose);
    final scope = await useCases.captureOwner(stillCurrent: () => true);
    expect(scope, isNotNull);
    expect(scope!.ownerId, ownerId);
    const codec = LearningPackCodec();
    final pack = codec.decode(
      codec.encode(
        metadata: LearningPackMetadata(
          packId: 'synthetic-schema23-capture',
          version: '1',
          title: 'Synthetic schema capture pack',
          objectives: ['Preserve installed content across a migration'],
          cefrLevel: 'A1',
          language: 'en',
          meaningLanguage: 'th',
          provenance: const LearningPackProvenance(
            author: 'Synthetic test author',
            source: 'Synthetic schema capture',
            license: 'Synthetic tests only',
            attribution: 'No real publisher',
          ),
        ),
        entries: [
          LearningPackEntry(
            code: 'harbor',
            spelling: 'harbor',
            meaning: 'ท่าเรือ',
            partOfSpeech: 'noun',
          ),
        ],
      ),
    );
    final installed = await useCases.importPack(
      useCases.prepareImport(scope: scope, pack: pack, pinned: true),
    );
    expect(installed.ownerId, ownerId);
    expect(installed.isInstalled, isTrue);
    expect(installed.isPinned, isTrue);
    expect(installed.cacheState, PackCacheState.verified);
    expect(installed.packageSha256, pack.packageSha256);
    expect(installed.installedAtUtc, now);
    final detail = await useCases.detail(scope, installed.id);
    expect(detail.content, isNotNull);
    expect(detail.bindings, hasLength(1));
    final binding = detail.bindings.single;
    expect(binding.isCurrent, isTrue);
    expect(binding.wordRevision, 1);
    expect(binding.entry.canonicalJson, pack.entries.single.canonicalJson);
    final current = await useCases.currentLexical(
      scope: scope,
      wordId: binding.wordId,
      packVersionId: installed.id,
    );
    expect(current, isNotNull);
    expect(current!.pack.packageSha256, pack.packageSha256);
    expect(current.entry.contentSha256, pack.entries.single.contentSha256);
    await useCases.dispose();

    final installedRows = await ownerMigrationRows(database);
    for (final old in oldRows.entries) {
      if (old.key == 'local_owners') continue;
      final generatedIds = installedRows[old.key]!
          .map((row) => row['id'])
          .whereType<String>()
          .toSet();
      for (final row in old.value) {
        if (row['id'] case final String id) {
          expect(generatedIds, isNot(contains(id)), reason: old.key);
        }
      }
    }
    await _restore(database, {
      for (final entry in oldRows.entries)
        if (entry.key != 'local_owners') entry.key: entry.value,
    });
    final fence = await ownerWrites.inspect();
    expect(fence, isNotNull);
    expect(fence!.phase, DeletionIntentPhase.pendingCloud);
    expect(fence.casToken!.matchesOwner(ownerId), isTrue);
    final rows = await ownerMigrationRows(database);
    for (final old in oldRows.entries) {
      expect(rows[old.key], containsAll(old.value), reason: old.key);
      expect(
        rows[old.key]!.length,
        old.value.length +
            (old.key == 'local_owners' ? 0 : installedRows[old.key]!.length),
        reason: 'Every original row and canonical install row survives',
      );
    }
    expect(rows.length, 43);
    expect(rows.values.every((value) => value.isNotEmpty), isTrue);
    expect(rows['learning_pack_versions'], hasLength(1));
    expect(rows['lexical_content_snapshots'], hasLength(1));
    expect(rows['learning_pack_versions']!.single['package_bytes'], pack.bytes);
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
      'schemaVersion': 23,
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
      'previousRowsPreserved': 68,
      'captureConstruction': {
        'sequence': [
          'Restore original local_owners',
          'Install one codec-validated pack through shared owner-write coordinator',
          'Verify canonical receipt, content and revision pins while unfenced',
          'Restore all remaining original rows including pending-deletion fence',
        ],
        'reason':
            'Models content installed before deletion became pending; the original fence and all old rows remain unchanged',
        'fixedNowUtc': now.toIso8601String(),
        'packVersionId': installed.id,
        'packageSha256': pack.packageSha256,
      },
      'rows': rows,
    };
    final payload = '${const JsonEncoder.withIndent('  ').convert(capture)}\n';

    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final decodedRows = _decodeRows(decoded['rows']);
    expect(decodedRows, rows, reason: 'JSON byte arrays preserve every BLOB');
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await _initialize(restored);
    await _restore(restored, decodedRows);
    expect(await ownerMigrationRows(restored), rows);
    await _assertHealthy(restored);
    expect(await _schema(restored), schema);

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
      _writeExact(output.key, output.value);
    }
  });
}

Future<void> _initialize(AppDatabase database) async {
  expect(database.schemaVersion, 23);
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

Future<void> _restore(AppDatabase database, _Rows rows) =>
    database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final table in rows.entries) {
        for (final row in table.value) {
          await insertOwnerMigrationRow(database, table.key, row);
        }
      }
    });

Future<void> _assertHealthy(AppDatabase database) async {
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  expect(
    (await database.customSelect('PRAGMA integrity_check').getSingle())
        .read<String>('integrity_check'),
    'ok',
  );
  final blob = await database
      .customSelect(
        'SELECT typeof(package_bytes) AS storage_type FROM learning_pack_versions',
      )
      .getSingle();
  expect(blob.read<String>('storage_type'), 'blob');
}

Future<String> _schema(AppDatabase database) async {
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

void _writeExact(String path, String value) {
  final file = File(path);
  if (file.existsSync()) {
    expect(file.readAsStringSync(), value, reason: 'Never replace a capture');
  } else {
    file.writeAsStringSync(value, flush: true);
  }
  expect(file.readAsStringSync(), value);
}
