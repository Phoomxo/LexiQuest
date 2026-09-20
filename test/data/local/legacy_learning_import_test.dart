import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:vocab_learning_app/data/local/legacy_learning_import.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import '../../support/current_database_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Directory support;
  late bool previousWarning;
  setUp(() async {
    previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('b15-legacy-');
    support = await Directory('${directory.path}/support').create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : directory.path,
        );
  });
  tearDown(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });
  test('B15 schema26 upgrades without changing modern records', () async {
    var database = AppDatabase.production();
    await database.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms) VALUES('modern-owner',1)",
    );
    final before = (await database.select(database.localOwners).get()).single
        .toJson();
    await database.close();
    final raw = sqlite3.open('${directory.path}/lexiquest.sqlite');
    // Restore the v26 physical shape, not only its version marker. Later
    // extension tables and the v28 first-send column must be absent.
    for (final table in <String>[
      'personal_set_members',
      'personal_set_revisions',
      'active_plan_pointers',
      'study_plan_revisions',
      'guided_repair_operations',
      'written_practice_results',
      'speaking_practice_results',
      'audio_lesson_checkpoints',
      'legacy_learning_records',
    ]) {
      raw.execute('DROP TABLE $table');
    }
    raw.execute(
      'ALTER TABLE outbox_operations DROP COLUMN attempted_mutation_json',
    );
    expect(
      raw.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ),
      hasLength(49),
    );
    expect(
      raw
          .select('PRAGMA table_info(outbox_operations)')
          .map((row) => row['name']),
      isNot(contains('attempted_mutation_json')),
    );
    raw.execute('PRAGMA user_version=26');
    raw.close();
    database = AppDatabase.production();
    try {
      expect(
        (await database.select(database.localOwners).get()).single.toJson(),
        before,
      );
      expect(
        await database
            .customSelect('SELECT * FROM legacy_learning_records')
            .get(),
        isEmpty,
      );
      await expectCurrentDatabaseContract(database);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await database.close();
    }
  });
  test(
    'B15 zero-byte destination cannot silently bypass legacy history',
    () async {
      final source = File('${support.path}/learning.sqlite');
      seedLegacy(source);
      final before = source.readAsBytesSync();
      final destination = File('${directory.path}/lexiquest.sqlite');
      destination.writeAsBytesSync([]);
      final database = AppDatabase.production();
      try {
        await expectLater(
          database.customSelect('SELECT 1').get(),
          throwsA(
            predicate((e) => e.toString().contains('legacyImportRequired')),
          ),
        );
      } finally {
        await database.close();
      }
      expect(destination.lengthSync(), 0);
      expect(source.readAsBytesSync(), before);
    },
  );
  test(
    'B15 WAL snapshot includes committed rows while source stays untouched',
    () async {
      final file = File('${support.path}/learning.sqlite');
      seedLegacy(file);
      final source = sqlite3.open(file.path);
      source.execute('PRAGMA journal_mode=WAL');
      source.execute("UPDATE associations SET cue_text='committed-in-wal'");
      final before = file.readAsBytesSync();
      final snapshot = LegacyLearningSnapshot.read(file);
      expect(
        snapshot.records['associations']!.single['cue_text'],
        'committed-in-wal',
      );
      expect(file.readAsBytesSync(), before);
      source.close();
    },
  );
  for (final invalid in [
    'future',
    'missing-column',
    'row-version',
    'multi-owner',
    'dual-conflict',
  ]) {
    test(
      'B15 preserves and rejects $invalid legacy source without destination',
      () async {
        final file = File('${support.path}/learning.sqlite');
        seedLegacy(file);
        final raw = sqlite3.open(file.path);
        switch (invalid) {
          case 'future':
            raw.execute('PRAGMA user_version=2');
          case 'missing-column':
            raw.execute(
              'ALTER TABLE associations RENAME COLUMN cue_text TO unexpected',
            );
          case 'row-version':
            raw.execute('UPDATE associations SET schema_version=2');
          case 'multi-owner':
            raw.execute("UPDATE associations SET owner_id='other-person'");
          case 'dual-conflict':
            final other = File('${directory.path}/learning.sqlite');
            seedLegacy(other);
            final second = sqlite3.open(other.path);
            second.execute("UPDATE associations SET cue_text='conflict'");
            second.close();
        }
        raw.close();
        final before = file.readAsBytesSync();
        final database = AppDatabase.production();
        try {
          await expectLater(
            database.customSelect('SELECT 1').get(),
            throwsA(
              predicate((e) => e.toString().contains('legacyImportRequired')),
            ),
          );
        } finally {
          await database.close();
        }
        expect(file.readAsBytesSync(), before);
        expect(
          File('${directory.path}/lexiquest.sqlite').existsSync(),
          isFalse,
        );
      },
    );
  }
  test(
    'B15 import transaction rolls back owner and all rows after partial failure',
    () async {
      final file = File('${support.path}/learning.sqlite');
      seedLegacy(file);
      final snapshot = LegacyLearningSnapshot.read(file);
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await database.customStatement(
          "CREATE TRIGGER reject_legacy BEFORE INSERT ON legacy_learning_records WHEN NEW.source_table='recall_attempts' BEGIN SELECT RAISE(ABORT,'injected import failure'); END",
        );
        await expectLater(snapshot.importInto(database), throwsA(anything));
        expect(await database.select(database.localOwners).get(), isEmpty);
        expect(
          await database
              .customSelect('SELECT * FROM legacy_learning_records')
              .get(),
          isEmpty,
        );
        await database.customStatement('DROP TRIGGER reject_legacy');
        await snapshot.importInto(database);
        expect(
          (await database
                  .customSelect('SELECT * FROM legacy_learning_records')
                  .get())
              .length,
          8,
        );
      } finally {
        await database.close();
      }
    },
  );
  test(
    'B15 owner merge retains immutable legacy history and account isolation',
    () async {
      final file = File('${support.path}/learning.sqlite');
      final original = seedLegacy(file);
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await LegacyLearningSnapshot.read(file).importInto(database);
        await database.customStatement(
          "INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES('account-b','uid-b','firebaseBound',1,0)",
        );
        final upgrade = DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026),
          generateConflictId: () => 'conflict',
          deleteOwnerSecrets: (_) async {},
          generateOwnerId: () => 'guest-next',
          generateOwnerOperationToken: () => 'upgrade-lease',
        );
        await upgrade.upgrade(
          activeOwnerId: 'legacy-owner',
          firebaseUid: 'uid-b',
        );
        final records = await database
            .customSelect('SELECT * FROM legacy_learning_records')
            .get();
        expect(records.length, 8);
        expect(
          records.every((r) => r.read<String>('owner_id') == 'account-b'),
          isTrue,
        );
        for (final row in records) {
          expect(
            jsonDecode(row.read<String>('payload_json')),
            original[row.read<String>('source_table')],
          );
        }
        await expectLater(
          database.customStatement(
            "UPDATE legacy_learning_records SET payload_json='{}'",
          ),
          throwsA(anything),
        );
        await LocalDataDeletion(
          database,
          deleteOwnerSecrets: (_) async {},
        ).eraseAll(ownerId: 'legacy-owner');
        expect(
          (await database
                  .customSelect('SELECT * FROM legacy_learning_records')
                  .get())
              .length,
          8,
        );
        await LocalDataDeletion(
          database,
          deleteOwnerSecrets: (_) async {},
        ).eraseAll(ownerId: 'account-b');
        expect(
          await database
              .customSelect('SELECT * FROM legacy_learning_records')
              .get(),
          isEmpty,
        );
      } finally {
        await database.close();
      }
    },
  );
  for (final location in ['support', 'documents']) {
    test(
      'B15 imports exact schema1 history from $location once without rewards or queue',
      () async {
        final file = File(
          '${location == 'support' ? support.path : directory.path}/learning.sqlite',
        );
        final expected = seedLegacy(file);
        final before = file.readAsBytesSync();
        var database = AppDatabase.production();
        try {
          final records = await database
              .customSelect(
                'SELECT source_table, payload_json FROM legacy_learning_records ORDER BY source_table',
              )
              .get();
          expect(records.length, 8);
          for (final record in records) {
            expect(
              jsonDecode(record.read<String>('payload_json')),
              expected[record.read<String>('source_table')],
            );
          }
          expect(
            (await database.select(database.localOwners).get()).single.id,
            'legacy-owner',
          );
          expect(
            await database.select(database.rewardTransactions).get(),
            isEmpty,
          );
          expect(await database.select(database.answerAttempts).get(), isEmpty);
          expect(await database.select(database.srsStates).get(), isEmpty);
          expect(
            await database.select(database.outboxOperations).get(),
            isEmpty,
          );
          await database.close();
          database = AppDatabase.production();
          expect(
            (await database
                    .customSelect('SELECT * FROM legacy_learning_records')
                    .get())
                .length,
            8,
          );
          final archive = await OwnerLifecycleArchiveExporter(
            database: database,
            nowUtc: () => DateTime.utc(2026),
          ).prepareActive();
          final content = jsonDecode(utf8.decode(archive.bytes))['content'];
          final legacy = (content['tables'] as List).singleWhere(
            (t) => t['alias'] == 'legacyLearningHistory',
          );
          expect(legacy['records'].length, 8);
          await LocalDataDeletion(
            database,
            deleteOwnerSecrets: (_) async {},
          ).eraseAll(ownerId: 'legacy-owner');
          expect(
            await database
                .customSelect('SELECT * FROM legacy_learning_records')
                .get(),
            isEmpty,
          );
          await database.close();
          database = AppDatabase.production();
          expect(
            await database
                .customSelect('SELECT * FROM legacy_learning_records')
                .get(),
            isEmpty,
          );
          expect(file.readAsBytesSync(), before);
        } finally {
          await database.close();
        }
      },
    );
  }
}

Map<String, Map<String, Object?>> seedLegacy(File file) {
  final raw = sqlite3.open(file.path);
  try {
    raw.execute(File('test/support/legacy_learning_v1.sql').readAsStringSync());
    final expected = <String, Map<String, Object?>>{};
    final tables = raw.select(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    for (final table in tables) {
      final name = table['name'] as String;
      final values = <String, Object?>{};
      for (final column in raw.select('PRAGMA table_info($name)')) {
        final key = column['name'] as String;
        values[key] = column['type'] == 'TEXT'
            ? 'legacy-$key'
            : column['type'] == 'REAL'
            ? 1.25
            : 1;
      }
      values['owner_id'] = 'legacy-owner';
      if (values.containsKey('target_word_keys_json')) {
        values['target_word_keys_json'] = '["word-a"]';
      }
      if (values.containsKey('payload_json')) {
        values['payload_json'] = '{"preserved":true}';
      }
      if (values.containsKey('content_fingerprint')) {
        values['content_fingerprint'] = 'a' * 64;
      }
      raw.execute(
        'INSERT INTO $name (${values.keys.join(',')}) VALUES (${values.keys.map((_) => '?').join(',')})',
        values.values.toList(),
      );
      expected[name] = values;
    }
    return expected;
  } finally {
    raw.close();
  }
}
