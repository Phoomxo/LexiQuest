import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 10, 28);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'guest upgrade succeeds when both owners already have streak state',
    () async {
      await _owner(database, 'guest-owner', active: true);
      await _owner(database, 'account-owner', uid: 'firebase-user');
      for (final owner in ['guest-owner', 'account-owner']) {
        await database
            .into(database.streakStates)
            .insert(
              StreakStatesCompanion.insert(ownerId: owner, updatedAtUtcMs: 1),
            );
      }
      var sequence = 0;
      final repository = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => now,
        generateConflictId: () => 'audit-${sequence++}',
        generateOwnerId: () => 'unused',
      );

      final result = await repository.upgrade(
        activeOwnerId: 'guest-owner',
        firebaseUid: 'firebase-user',
      );

      expect(result.targetOwnerId, 'account-owner');
      expect(await database.select(database.streakStates).get(), hasLength(1));
    },
  );

  test(
    'pulling another account category ID cannot overwrite the retained owner',
    () async {
      await _owner(database, 'owner-a', uid: 'firebase-a');
      await _owner(database, 'owner-b', uid: 'firebase-b', active: true);
      await _category(database, 'shared-category-id', 'owner-a', 'Private A');
      final entity = SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'shared-category-id',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now,
        serverUpdatedAtUtc: now,
        payload: {'name': 'Cloud B', 'normalizedName': 'cloud b'},
      );

      await _applyOrReject(database, 'owner-b', entity, now);

      final retained = await (database.select(
        database.vocabularyCategories,
      )..where((row) => row.id.equals('shared-category-id'))).getSingle();
      expect(retained.ownerId, 'owner-a');
      expect(retained.name, 'Private A');
    },
  );

  test(
    'pulling another account word ID cannot overwrite the retained owner',
    () async {
      await _owner(database, 'owner-a', uid: 'firebase-a');
      await _owner(database, 'owner-b', uid: 'firebase-b', active: true);
      await _category(database, 'category-a', 'owner-a', 'A');
      await _category(database, 'category-b', 'owner-b', 'B');
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'shared-word-id',
              ownerId: 'owner-a',
              categoryId: 'category-a',
              spelling: 'private',
              normalizedSpelling: 'private',
              meaning: 'A',
              normalizedMeaning: 'a',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      final entity = SyncEntity(
        collection: SyncCollection.words,
        entityId: 'shared-word-id',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now,
        serverUpdatedAtUtc: now,
        payload: {
          'categoryId': 'category-b',
          'spelling': 'cloud',
          'meaning': 'B',
          'partOfSpeech': 'noun',
        },
      );

      await _applyOrReject(database, 'owner-b', entity, now);

      final retained = await (database.select(
        database.vocabularyWords,
      )..where((row) => row.id.equals('shared-word-id'))).getSingle();
      expect(retained.ownerId, 'owner-a');
      expect(retained.spelling, 'private');
    },
  );

  test(
    'same-name categories from two offline devices do not abort pull',
    () async {
      await _owner(database, 'owner-a', uid: 'firebase-a', active: true);
      await _category(database, 'device-one-category', 'owner-a', 'Travel');
      final remote = SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'device-two-category',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now,
        serverUpdatedAtUtc: now,
        payload: {'name': 'Travel', 'normalizedName': 'travel'},
      );

      await DriftSyncStore(database).applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        page: PullPage(
          changes: [remote],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: now,
            documentId: remote.entityId,
          ),
          hasMore: false,
        ),
      );

      final categories = await (database.select(
        database.vocabularyCategories,
      )..where((row) => row.ownerId.equals('owner-a'))).get();
      expect(categories, isNotEmpty);
      expect(categories.every((row) => row.normalizedName == 'travel'), isTrue);
    },
  );
}

Future<void> _owner(
  AppDatabase database,
  String id, {
  String? uid,
  bool active = false,
}) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: id,
          firebaseUid: Value(uid),
          createdAtUtcMs: 1,
          isActive: Value(active),
        ),
      );
}

Future<void> _category(
  AppDatabase database,
  String id,
  String owner,
  String name,
) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: id,
          ownerId: owner,
          name: name,
          normalizedName: name.toLowerCase(),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _applyOrReject(
  AppDatabase database,
  String owner,
  SyncEntity entity,
  DateTime now,
) async {
  try {
    await DriftSyncStore(database).applyPullPage(
      ownerId: owner,
      collection: entity.collection,
      page: PullPage(
        changes: [entity],
        nextCursor: SyncCursor(
          serverUpdatedAtUtc: now,
          documentId: entity.entityId,
        ),
        hasMore: false,
      ),
    );
  } on SyncFailure {
    // Rejecting a namespace collision is an acceptable safe outcome.
  }
}
