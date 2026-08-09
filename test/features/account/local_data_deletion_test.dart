import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

void main() {
  test('deletion inventory stays aligned with every owner-scoped table', () {
    expect(localDataDeletionInventory.toSet(), ownerUpgradeInventory);
  });

  test(
    'erases one owner transactionally and preserves another owner',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedOwner(database, 'owner-a');
      await _seedOwner(database, 'owner-b');
      final deletedSecretOwnerIds = <String>[];

      final deleted = await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (ownerId) async {
          deletedSecretOwnerIds.add(ownerId);
        },
      ).eraseAll(ownerId: 'owner-a');

      expect(deleted, 8);
      expect(deletedSecretOwnerIds, ['owner-a']);
      expect(await _ownerRows(database, 'research_consents', 'owner-a'), 0);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 0);
      expect(await _ownerRows(database, 'reward_transactions', 'owner-a'), 0);
      expect(await _ownerRows(database, 'owned_reward_items', 'owner-a'), 0);
      expect(await _ownerRows(database, 'equipped_reward_items', 'owner-a'), 0);
      expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 0);
      expect(await _ownerRows(database, 'vocabulary_words', 'owner-a'), 0);
      expect(await _ownerRows(database, 'vocabulary_categories', 'owner-a'), 0);
      expect(await _ownerRows(database, 'research_consents', 'owner-b'), 1);
      expect(await _ownerRows(database, 'ai_usage_events', 'owner-b'), 1);
      expect(await _ownerRows(database, 'reward_transactions', 'owner-b'), 1);
      expect(await _ownerRows(database, 'owned_reward_items', 'owner-b'), 1);
      expect(await _ownerRows(database, 'equipped_reward_items', 'owner-b'), 1);
      expect(await _ownerRows(database, 'vocabulary_imports', 'owner-b'), 1);
      expect(await _ownerRows(database, 'vocabulary_words', 'owner-b'), 1);
      expect(await _ownerRows(database, 'vocabulary_categories', 'owner-b'), 1);
    },
  );

  test('a late delete failure rolls back earlier table deletes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedOwner(database, 'owner-a');
    final deletedSecretOwnerIds = <String>[];
    await database.customStatement('''
      CREATE TRIGGER fail_vocabulary_category_delete
      BEFORE DELETE ON vocabulary_categories
      WHEN OLD.owner_id = 'owner-a'
      BEGIN
        SELECT RAISE(ABORT, 'injected deletion failure');
      END
    ''');

    await expectLater(
      LocalDataDeletion(
        database,
        deleteOwnerSecrets: (ownerId) async {
          deletedSecretOwnerIds.add(ownerId);
        },
      ).eraseAll(ownerId: 'owner-a'),
      throwsA(anything),
    );

    expect(await _ownerRows(database, 'research_consents', 'owner-a'), 1);
    expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_words', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_categories', 'owner-a'), 1);
    expect(deletedSecretOwnerIds, ['owner-a']);
  });

  test('secret erasure failure leaves database rows untouched', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedOwner(database, 'owner-a');

    await expectLater(
      LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) => throw StateError('secure storage failed'),
      ).eraseAll(ownerId: 'owner-a'),
      throwsStateError,
    );

    expect(await _ownerRows(database, 'research_consents', 'owner-a'), 1);
    expect(await _ownerRows(database, 'ai_usage_events', 'owner-a'), 1);
    expect(await _ownerRows(database, 'vocabulary_imports', 'owner-a'), 1);
  });
}

Future<void> _seedOwner(AppDatabase database, String ownerId) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: ownerId, createdAtUtcMs: 1));
  await database
      .into(database.researchConsents)
      .insert(
        ResearchConsentsCompanion.insert(
          id: 'consent:$ownerId',
          ownerId: ownerId,
          consentVersion: 1,
          consentState: 'accepted',
          decidedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.aiUsageEvents)
      .insert(
        AiUsageEventsCompanion.insert(
          eventId: 'usage:$ownerId',
          ownerId: ownerId,
          occurredAtUtcMs: 1,
          providerId: 'gemini',
          model: 'model',
          requestType: 'tutorReply',
          outcome: 'success',
          latencyMs: 1,
        ),
      );
  await database.customInsert(
    'INSERT INTO reward_transactions '
    '(id, owner_id, idempotency_key, transaction_type, amount, item_id, '
    'catalog_version, occurred_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('reward-transaction:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('reward-key:$ownerId'),
      const Variable<String>('purchase'),
      const Variable<int>(-10),
      const Variable<String>('theme-blue'),
      const Variable<int>(1),
    ],
  );
  await database.customInsert(
    'INSERT INTO owned_reward_items '
    '(id, owner_id, item_id, catalog_version, acquired_by_transaction_id, '
    'acquired_at_utc_ms) VALUES (?, ?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('owned-reward:$ownerId'),
      Variable<String>(ownerId),
      const Variable<String>('theme-blue'),
      const Variable<int>(1),
      Variable<String>('reward-transaction:$ownerId'),
    ],
  );
  await database.customInsert(
    'INSERT INTO equipped_reward_items '
    '(id, owner_id, slot, item_id, equipped_at_utc_ms) '
    'VALUES (?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('equipped-reward:$ownerId'),
      Variable<String>(ownerId),
      const Variable<String>('theme'),
      const Variable<String>('theme-blue'),
    ],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
    variables: [
      Variable<String>('category:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('Category $ownerId'),
      Variable<String>('category-$ownerId'),
    ],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    variables: [
      Variable<String>('word:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('category:$ownerId'),
      Variable<String>('word-$ownerId'),
      Variable<String>('word-$ownerId'),
      const Variable<String>('meaning'),
      const Variable<String>('meaning'),
      const Variable<String>('noun'),
    ],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_imports '
    '(id, owner_id, category_id, source_type, source_name, source_hash, '
    'status, created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
    variables: [
      Variable<String>('import:$ownerId'),
      Variable<String>(ownerId),
      Variable<String>('category:$ownerId'),
      const Variable<String>('csv'),
      const Variable<String>('words.csv'),
      Variable<String>('hash:$ownerId'),
      const Variable<String>('complete'),
    ],
  );
}

Future<int> _ownerRows(AppDatabase database, String table, String ownerId) =>
    database
        .customSelect(
          'SELECT COUNT(*) AS count FROM $table WHERE owner_id = ?',
          variables: [Variable<String>(ownerId)],
        )
        .map((row) => row.read<int>('count'))
        .getSingle();
