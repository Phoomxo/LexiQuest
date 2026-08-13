import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/runtime/download_counter.dart';

void main() {
  test('persists every successful download event per version', () async {
    final database = AppDatabase(NativeDatabase.memory());
    var event = 0;
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'event-${++event}',
      nowUtc: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(database.close);

    await counter.increment('model-v1');
    await counter.increment('model-v1');
    await counter.increment('model-v2');

    expect(await counter.count('model-v1'), 2);
    expect(await counter.count('model-v2'), 1);
    expect(await counter.count('missing'), 0);
  });

  test('duplicate event id is rejected without inflating the count', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'same-event',
      nowUtc: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(database.close);

    await counter.increment('model-v1');
    await expectLater(counter.increment('model-v1'), throwsA(anything));

    expect(await counter.count('model-v1'), 1);
  });

  test('foreign exact-key collision cannot impersonate a completion', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'unused',
      nowUtc: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(database.close);
    const collisionKey = 'download_count:bW9kZWwtdjE:verified-fixed';
    await database.customInsert(
      'INSERT INTO runtime_flags '
      '("key", bool_value, source, updated_at_utc_ms) '
      "VALUES ('$collisionKey', 1, 'operator', 1)",
    );

    await expectLater(
      counter.recordCompletion('model-v1', 'verified-fixed'),
      throwsStateError,
    );

    expect(await counter.count('model-v1'), 0);
    final collision = await database
        .customSelect(
          'SELECT * FROM runtime_flags WHERE "key" = ?',
          variables: const [Variable<String>(collisionKey)],
        )
        .getSingle();
    expect(collision.read<String>('source'), 'operator');
    expect(collision.read<bool>('bool_value'), isTrue);
  });

  test(
    'cached reconciliation preserves every historical legacy transfer',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final legacyIds = <String>[
        '123e4567-e89b-42d3-a456-426614174000',
        '223e4567-e89b-42d3-a456-426614174001',
        '323e4567-e89b-42d3-a456-426614174002',
      ].iterator;
      final counter = DownloadCounter(
        database,
        generateEventId: () {
          expect(legacyIds.moveNext(), isTrue);
          return legacyIds.current;
        },
        nowUtc: () => DateTime.utc(2026, 8, 9, 12),
      );
      addTearDown(database.close);

      await counter.increment('model-v1');
      await counter.increment('model-v1');
      await counter.increment('model-v1');
      expect(await counter.count('model-v1'), 3);

      await counter.reconcileCompletion('model-v1', 'verified-current');
      expect(await counter.count('model-v1'), 3);
      await counter.reconcileCompletion('model-v1', 'verified-current');
      expect(await counter.count('model-v1'), 3);
      await counter.reconcileCompletion('model-v1', 'verified-current');

      expect(await counter.count('model-v1'), 3);
    },
  );

  test(
    'retained success window is capped source-scoped and survives reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-download-counter-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}counter.sqlite',
      );
      var database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await database.customInsert(
        'INSERT INTO runtime_flags '
        '("key", bool_value, source, updated_at_utc_ms) VALUES '
        "('feature_emergency_off:aiTutor', 1, 'operator', 1), "
        "('aiCredentialPointer:foreign', 1, 'version:foreign', 2), "
        "('download_count:bW9kZWwtdjE:foreign-source', 1, 'operator', 3), "
        "('unrelated-global', 1, 'operator', 4), "
        "('unrelated-download-source', 1, 'download_counter', 5)",
      );
      final unrelatedBefore = await _nonDownloadRows(database);
      var event = 0;
      var now = DateTime.utc(2026, 8, 11, 12);
      DownloadCounter buildCounter() => DownloadCounter(
        database,
        generateEventId: () => 'event-${++event}',
        nowUtc: () => now = now.add(const Duration(seconds: 1)),
        maxRetainedEventsPerVersion: 3,
        maxTrackedVersions: 2,
      );
      var counter = buildCounter();

      for (var index = 0; index < 5; index += 1) {
        await counter.increment('model-v1');
      }
      expect(await counter.count('model-v1'), 3);
      final snapshot = await counter.snapshot('model-v1');
      expect(snapshot.retainedCount, 3);
      expect(snapshot.retentionLimit, 3);
      expect(snapshot.mayBeSaturated, isTrue);
      expect(snapshot.semantics, 'boundedRetainedWindow');
      expect(await _downloadRows(database), 3);
      expect(await _nonDownloadRows(database), unrelatedBefore);
      await expectLater(counter.count('   '), throwsArgumentError);
      await expectLater(counter.increment('   '), throwsArgumentError);

      await database.close();
      database = AppDatabase(NativeDatabase(file));
      await database.customSelect('SELECT 1').getSingle();
      counter = buildCounter();

      expect(await counter.count('model-v1'), 3);
      expect(await _downloadRows(database), 3);
      expect(await _nonDownloadRows(database), unrelatedBefore);
    },
  );

  test(
    'a Task 8 write normalizes every retained legacy version bound',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final encodedA = base64Url
          .encode(utf8.encode('model-a'))
          .replaceAll('=', '');
      for (var index = 0; index < 4; index += 1) {
        final uuid = '${index + 1}23e4567-e89b-42d3-a456-42661417400$index';
        await database.customInsert(
          'INSERT INTO runtime_flags '
          '("key", bool_value, source, updated_at_utc_ms) VALUES (?, 0, ?, ?)',
          variables: [
            Variable<String>('download_count:$encodedA:$uuid'),
            const Variable<String>('download_counter'),
            Variable<int>(index + 1),
          ],
        );
      }
      await database.customInsert(
        'INSERT INTO runtime_flags '
        '("key", bool_value, source, updated_at_utc_ms) VALUES '
        "('download_count:$encodedA:foreign', 1, 'operator', 50), "
        "('unrelated-download-source', 1, 'download_counter', 51)",
      );
      final foreignBefore = await _nonDownloadRows(database);
      final counter = DownloadCounter(
        database,
        generateEventId: () => 'unused',
        nowUtc: () => DateTime.utc(2026, 8, 11, 12),
        maxRetainedEventsPerVersion: 2,
        maxTrackedVersions: 2,
      );

      await counter.reconcileCompletion('model-b', 'verified-model-b');

      expect(await counter.count('model-a'), 2);
      expect(await counter.count('model-b'), 1);
      expect(await _downloadRows(database), 3);
      expect(await _nonDownloadRows(database), foreignBefore);
    },
  );

  test('oldest model version is evicted at the global version bound', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var event = 0;
    var now = DateTime.utc(2026, 8, 11, 12);
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'event-${++event}',
      nowUtc: () => now = now.add(const Duration(seconds: 1)),
      maxRetainedEventsPerVersion: 2,
      maxTrackedVersions: 2,
    );

    await counter.increment('model-v1');
    await counter.increment('model-v2');
    await counter.increment('model-v3');

    expect(await counter.count('model-v1'), 0);
    expect(await counter.count('model-v2'), 1);
    expect(await counter.count('model-v3'), 1);
    expect(await _downloadRows(database), 2);
  });

  test('clock rollback never evicts the version just incremented', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var event = 0;
    final times = <DateTime>[
      DateTime.utc(2026, 8, 11, 12, 0, 3),
      DateTime.utc(2026, 8, 11, 12, 0, 2),
      DateTime.utc(2026, 8, 11, 12, 0, 1),
    ].iterator;
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'event-${++event}',
      nowUtc: () {
        expect(times.moveNext(), isTrue);
        return times.current;
      },
      maxRetainedEventsPerVersion: 2,
      maxTrackedVersions: 2,
    );

    await counter.increment('model-v1');
    await counter.increment('model-v2');
    await counter.increment('model-v3');

    expect(await counter.count('model-v3'), 1);
    expect(await _downloadRows(database), 2);
  });

  test(
    'clock rollback never discards the just-inserted success event',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var event = 0;
      final times = <DateTime>[
        DateTime.utc(2026, 8, 11, 12, 0, 3),
        DateTime.utc(2026, 8, 11, 12, 0, 2),
        DateTime.utc(2026, 8, 11, 12, 0, 1),
      ].iterator;
      final counter = DownloadCounter(
        database,
        generateEventId: () => 'event-${++event}',
        nowUtc: () {
          expect(times.moveNext(), isTrue);
          return times.current;
        },
        maxRetainedEventsPerVersion: 2,
        maxTrackedVersions: 2,
      );

      await counter.increment('model-v1');
      await counter.increment('model-v1');
      await counter.increment('model-v1');

      final keys = await database
          .customSelect(
            'SELECT "key" FROM runtime_flags WHERE source = ? ORDER BY "key"',
            variables: const [Variable<String>('download_counter')],
          )
          .map((row) => row.read<String>('key'))
          .get();
      expect(keys, hasLength(2));
      expect(keys.singleWhere((key) => key.endsWith(':event-3')), isNotEmpty);
    },
  );
}

Future<List<String>> _nonDownloadRows(AppDatabase database) async =>
    (await database
            .customSelect(
              'SELECT * FROM runtime_flags WHERE NOT '
              '(source = ? AND instr("key", ?) = 1) ORDER BY "key"',
              variables: const [
                Variable<String>('download_counter'),
                Variable<String>('download_count:'),
              ],
            )
            .get())
        .map((row) => row.data.toString())
        .toList();

Future<int> _downloadRows(AppDatabase database) => database
    .customSelect(
      'SELECT COUNT(*) AS count FROM runtime_flags '
      'WHERE source = ? AND instr("key", ?) = 1',
      variables: const [
        Variable<String>('download_counter'),
        Variable<String>('download_count:'),
      ],
    )
    .map((row) => row.read<int>('count'))
    .getSingle();
