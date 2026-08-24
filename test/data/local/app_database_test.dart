import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../../support/current_database_contract.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('current schema creates every field data-spine table', () async {
    final tableNames = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .map((row) => row.read<String>('name'))
        .get();

    expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
    expect(tableNames.toSet(), currentDatabaseTableInventory);
  });

  test('foreign keys reject rows owned by an unknown local owner', () async {
    final write = database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'missing-owner',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );

    await expectLater(write, throwsA(isA<Exception>()));
  });

  test('category natural key prevents owner-scoped duplicates', () async {
    await _insertOwner(database);
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );

    final duplicate = database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-2',
            ownerId: 'owner-1',
            name: ' travel ',
            normalizedName: 'travel',
            createdAtUtcMs: 2,
            updatedAtUtcMs: 2,
          ),
        );

    await expectLater(duplicate, throwsA(isA<Exception>()));
  });

  test(
    'operation and ledger idempotency keys reject replay duplicates',
    () async {
      await _insertOwner(database);
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'operation-1',
              ownerId: 'owner-1',
              entityType: 'word',
              entityId: 'word-1',
              operationKind: 'upsert',
              createdAtUtcMs: 1,
            ),
          );
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            PointsLedgerEntriesCompanion.insert(
              id: 'points-1',
              ownerId: 'owner-1',
              idempotencyKey: 'quiz:session-1',
              entryType: 'award',
              amount: 1,
              occurredAtUtcMs: 1,
            ),
          );

      await expectLater(
        database
            .into(database.outboxOperations)
            .insert(
              OutboxOperationsCompanion.insert(
                operationId: 'operation-1',
                ownerId: 'owner-1',
                entityType: 'word',
                entityId: 'word-1',
                operationKind: 'upsert',
                createdAtUtcMs: 2,
              ),
            ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database
            .into(database.pointsLedgerEntries)
            .insert(
              PointsLedgerEntriesCompanion.insert(
                id: 'points-2',
                ownerId: 'owner-1',
                idempotencyKey: 'quiz:session-1',
                entryType: 'award',
                amount: 1,
                occurredAtUtcMs: 2,
              ),
            ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('persisted UTC epoch timestamps cannot be negative', () async {
    final write = database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-negative-time',
            createdAtUtcMs: -1,
          ),
        );

    await expectLater(write, throwsA(isA<Exception>()));
  });

  test(
    'learning-time rows reject overlap and immutable field mutation',
    () async {
      await _insertOwner(database);
      await database.customInsert('''
      INSERT INTO learning_sessions(
        id, owner_id, activity_type, state, started_at_utc_ms,
        app_version, build_id
      ) VALUES ('session-time', 'owner-1', 'quiz', 'active', 1, 'test', 'test')
    ''');
      await database.customInsert(
        "INSERT INTO local_owners(id, created_at_utc_ms) "
        "VALUES ('owner-2', 2)",
      );
      await database.customInsert('''
      INSERT INTO learning_time_segments(
        id, owner_id, session_id, active_start_offset_ms,
        active_duration_ms, started_at_utc_ms, ended_at_utc_ms,
        timezone_id, timezone_offset_minutes, capture_source
      ) VALUES (
        'segment-time-1', 'owner-1', 'session-time', 0, 1000,
        10, 5, 'Asia/Bangkok', 420, 'automaticLesson'
      )
    ''');

      await expectLater(
        database.customInsert('''
        INSERT INTO learning_time_segments(
          id, owner_id, session_id, active_start_offset_ms,
          active_duration_ms, started_at_utc_ms, ended_at_utc_ms,
          timezone_id, timezone_offset_minutes, capture_source
        ) VALUES (
          'segment-time-overlap', 'owner-1', 'session-time', 500, 1000,
          20, 15, 'Asia/Bangkok', 420, 'automaticLesson'
        )
      '''),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database.customUpdate(
          'UPDATE learning_time_segments SET active_duration_ms = 2000 '
          "WHERE id = 'segment-time-1'",
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database.customUpdate(
          "UPDATE learning_time_segments SET id = 'segment-time-renamed' "
          "WHERE id = 'segment-time-1'",
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database.customUpdate(
          "UPDATE learning_time_segments SET owner_id = 'owner-2' "
          "WHERE id = 'segment-time-1'",
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        database.customInsert('''
        INSERT INTO learning_time_segments(
          id, owner_id, session_id, active_start_offset_ms,
          active_duration_ms, started_at_utc_ms, ended_at_utc_ms,
          timezone_id, timezone_offset_minutes, capture_source
        ) VALUES (
          'segment-time-too-long', 'owner-1', 'session-time', 1000, 300001,
          20, 15, 'Asia/Bangkok', 420, 'automaticLesson'
        )
      '''),
        throwsA(isA<Exception>()),
      );
      expect(
        (await database.select(database.learningTimeSegments).getSingle())
            .activeDurationMs,
        1000,
      );
    },
  );
}

Future<void> _insertOwner(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
}
