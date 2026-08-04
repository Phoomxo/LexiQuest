import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

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

    expect(database.schemaVersion, 8);
    expect(
      tableNames,
      containsAll(<String>[
        'local_owners',
        'research_consents',
        'vocabulary_categories',
        'vocabulary_words',
        'vocabulary_imports',
        'vocabulary_import_rows',
        'learning_sessions',
        'answer_attempts',
        'srs_states',
        'reading_progress_entries',
        'reading_events',
        'points_ledger_entries',
        'achievement_unlocks',
        'reward_transactions',
        'owned_reward_items',
        'equipped_reward_items',
        'outbox_operations',
        'sync_checkpoints',
        'sync_conflicts',
        'model_downloads',
      ]),
    );
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
}

Future<void> _insertOwner(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
}
