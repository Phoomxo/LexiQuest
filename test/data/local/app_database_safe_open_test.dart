import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import '../../support/schema_v25_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('b03-safe-open-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });
  for (final kind in ['future', 'corrupt', 'unversioned', 'legacy']) {
    test(
      'B03 production preserves $kind database and reports readiness',
      () async {
        final file = File(
          '${directory.path}/${kind == 'legacy' ? 'learning' : 'lexiquest'}.sqlite',
        );
        if (kind == 'corrupt') {
          await file.writeAsString('not a SQLite database; must be retained');
        } else {
          final raw = sqlite3.open(file.path);
          raw.execute('CREATE TABLE sentinel(value TEXT)');
          raw.execute("INSERT INTO sentinel VALUES ('preserve-me')");
          raw.execute(
            'PRAGMA user_version = ${kind == 'future'
                ? AppDatabase.currentSchemaVersion + 1
                : kind == 'legacy'
                ? 1
                : 0}',
          );
          raw.close();
        }
        final before = await file.readAsBytes();
        final database = AppDatabase.production();
        try {
          await expectLater(
            database.customSelect('SELECT 1').getSingle(),
            throwsA(
              predicate(
                (error) => error.toString().contains(
                  kind == 'corrupt'
                      ? 'corruptOrUnreadable'
                      : kind == 'legacy'
                      ? 'legacyImportRequired'
                      : 'incompatibleSchema',
                ),
              ),
            ),
          );
        } finally {
          await database.close();
        }
        expect(await file.readAsBytes(), before);
        if (kind == 'legacy') {
          expect(
            File('${directory.path}/lexiquest.sqlite').existsSync(),
            isFalse,
          );
        }
      },
    );
  }
  test(
    'B03 production fresh store reopens same owner with WAL and timeout',
    () async {
      var database = AppDatabase.production();
      try {
        await database.customStatement(
          "INSERT INTO local_owners(id, account_state, created_at_utc_ms) VALUES ('durable', 'localGuest', 1)",
        );
        expect(
          (await database.customSelect('PRAGMA journal_mode').getSingle())
              .data
              .values
              .single,
          'wal',
        );
        expect(
          (await database.customSelect('PRAGMA busy_timeout').getSingle())
              .data
              .values
              .single,
          5000,
        );
        await database.close();
        database = AppDatabase.production();
        expect(
          (await database.select(database.localOwners).get()).single.id,
          'durable',
        );
        expect(
          (await database.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          AppDatabase.currentSchemaVersion,
        );
      } finally {
        await database.close();
      }
    },
  );
  test('B03 production raw25 migrates with owner retained', () async {
    final file = File('${directory.path}/lexiquest.sqlite');
    final raw = sqlite3.open(file.path);
    createSchemaTwentyFiveFixture(raw);
    raw.execute("INSERT INTO local_owners(id, account_state, created_at_utc_ms) VALUES ('migrated', 'localGuest', 1)");
    final ownersBefore = raw.select('SELECT * FROM local_owners ORDER BY id')
      .map((row) => Map<String, Object?>.from(row)).toList();
    raw.close();
    final database = AppDatabase.production();
    try {
      expect((await database.customSelect('SELECT * FROM local_owners ORDER BY id').get()).map((row) => row.data).toList(), ownersBefore);
      expect((await database.customSelect('PRAGMA user_version').getSingle()).data.values.single, AppDatabase.currentSchemaVersion);
      expect(await database.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    } finally { await database.close(); }
  });
  test('B03 directory-provider failure reports unavailable storage', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => throw PlatformException(code: 'unavailable'));
    final database = AppDatabase.production();
    try {
      await expectLater(database.customSelect('SELECT 1').getSingle(),
        throwsA(predicate((error) => error.toString().contains('corruptOrUnreadable'))));
    } finally { await database.close(); }
  });
}
