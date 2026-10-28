import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 10, 28);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'local-category',
            ownerId: 'owner',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  });
  tearDown(() => database.close());

  SyncEntity entity(
    SyncCollection collection,
    String id,
    Map<String, Object?> payload, {
    bool deleted = false,
    int revision = 1,
  }) => SyncEntity(
    collection: collection,
    entityId: id,
    revision: revision,
    isDeleted: deleted,
    payloadVersion: 1,
    clientUpdatedAtUtc: now,
    serverUpdatedAtUtc: now.add(Duration(seconds: revision)),
    payload: payload,
  );

  Future<void> apply(SyncEntity value) =>
      DriftSyncStore(database).applyPullPage(
        ownerId: 'owner',
        collection: value.collection,
        page: PullPage(
          changes: [value],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: value.serverUpdatedAtUtc,
            documentId: value.entityId,
          ),
          hasMore: false,
        ),
      );

  Future<void> categoryAlias() => apply(
    entity(SyncCollection.categories, 'remote-category', {
      'name': 'Travel',
      'normalizedName': 'travel',
    }),
  );

  test(
    'same-name category keeps child words across store restart and replay',
    () async {
      await categoryAlias();
      final word = entity(SyncCollection.words, 'remote-word', {
        'categoryId': 'remote-category',
        'spelling': 'station',
        'meaning': 'synthetic',
        'partOfSpeech': 'noun',
      });
      await apply(word);
      await categoryAlias();
      await apply(word);
      final categories = await database
          .select(database.vocabularyCategories)
          .get();
      expect(categories.single.id, 'local-category');
      expect(categories.single.localRevision, 1);
      expect(categories.single.cloudRevision, 0);
      expect(categories.single.updatedAtUtcMs, 1);
      final words = await database.select(database.vocabularyWords).get();
      expect(words.single.categoryId, 'local-category');
      expect(words.single.id, 'remote-word');
      final receipt = await database.select(database.syncConflicts).getSingle();
      expect(receipt.entityId, 'remote-category');
      expect(jsonDecode(receipt.localSnapshotJson!), {
        'canonicalEntityId': 'local-category',
      });
      expect(jsonDecode(receipt.cloudSnapshotJson!), {
        'revision': 1,
        'isDeleted': false,
        'clientUpdatedAtUtcMs': now.millisecondsSinceEpoch,
        'serverUpdatedAtUtcMicros': now
            .add(const Duration(seconds: 1))
            .microsecondsSinceEpoch,
        'payload': {'name': 'Travel', 'normalizedName': 'travel'},
      });
    },
  );

  test(
    'word alias preserves attempts and SRS without replay conflicts',
    () async {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'local-word',
              ownerId: 'owner',
              categoryId: 'local-category',
              spelling: 'station',
              normalizedSpelling: 'station',
              meaning: 'synthetic',
              normalizedMeaning: 'synthetic',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await categoryAlias();
      await apply(
        entity(SyncCollection.words, 'remote-word', {
          'categoryId': 'remote-category',
          'spelling': 'station',
          'meaning': 'synthetic',
          'partOfSpeech': 'noun',
        }),
      );
      final attempt = entity(SyncCollection.attempts, 'remote-attempt', {
        'sessionId': 'remote-session',
        'wordId': 'remote-word',
        'promptMode': 'meaningChoice',
        'isCorrect': true,
        'responseTimeMs': 100,
        'attemptNumber': 1,
        'occurredAtUtcMs': now.millisecondsSinceEpoch,
        'providerProvenance': null,
      });
      await apply(attempt);
      await apply(attempt);
      await apply(
        entity(SyncCollection.srsStates, 'remote-word', {
          'wordId': 'remote-word',
          'stability': 2.5,
          'difficulty': 5.0,
          'intervalDays': 3,
          'repetitions': 1,
          'lapses': 0,
          'lastReviewAtUtcMs': now.millisecondsSinceEpoch,
          'dueAtUtcMs': now.add(const Duration(days: 3)).millisecondsSinceEpoch,
          'algorithmVersion': 1,
        }),
      );
      expect(
        (await database.select(database.vocabularyWords).get()).single.id,
        'local-word',
      );
      expect(
        (await database.select(database.answerAttempts).get()).single.wordId,
        'local-word',
      );
      expect(
        (await database.select(database.srsStates).get()).single.wordId,
        'local-word',
      );
      final conflicts = await database.select(database.syncConflicts).get();
      expect(
        conflicts.every(
          (row) => row.resolutionPolicy == 'naturalKeyLocalTarget',
        ),
        isTrue,
      );
      final wordReceipt = conflicts.singleWhere(
        (row) => row.entityType == 'word',
      );
      expect(jsonDecode(wordReceipt.localSnapshotJson!), {
        'canonicalEntityId': 'local-word',
      });
      expect((jsonDecode(wordReceipt.cloudSnapshotJson!) as Map)['payload'], {
        'categoryId': 'remote-category',
        'spelling': 'station',
        'meaning': 'synthetic',
        'partOfSpeech': 'noun',
      });
      final retainedWord = await database
          .select(database.vocabularyWords)
          .getSingle();
      expect(retainedWord.localRevision, 1);
      expect(retainedWord.cloudRevision, 0);
      expect(retainedWord.updatedAtUtcMs, 1);
    },
  );

  test(
    'remote alias deletion cannot delete the retained local category',
    () async {
      await categoryAlias();
      await apply(
        entity(
          SyncCollection.categories,
          'remote-category',
          {'name': 'Travel', 'normalizedName': 'travel'},
          deleted: true,
          revision: 2,
        ),
      );
      expect(
        (await database.select(database.vocabularyCategories).get())
            .single
            .isDeleted,
        isFalse,
      );
      final receipt = await database.select(database.syncConflicts).getSingle();
      expect(receipt.cloudRevision, 2);
      expect(
        (jsonDecode(receipt.cloudSnapshotJson!) as Map)['isDeleted'],
        isTrue,
      );
      await categoryAlias();
      expect(
        (await database.select(database.syncConflicts).getSingle())
            .cloudRevision,
        2,
      );
    },
  );

  for (final snapshotWordId in ['remote-word', 'local-word']) {
    test(
      '$snapshotWordId SRS keeps baseline and all merged answer evidence',
      () async {
        await database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'local-word',
                ownerId: 'owner',
                categoryId: 'local-category',
                spelling: 'station',
                normalizedSpelling: 'station',
                meaning: 'synthetic',
                normalizedMeaning: 'synthetic',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        await categoryAlias();
        await apply(
          entity(SyncCollection.words, 'remote-word', {
            'categoryId': 'remote-category',
            'spelling': 'station',
            'meaning': 'synthetic',
            'partOfSpeech': 'noun',
          }),
        );
        final partialSnapshot =
            entity(SyncCollection.srsStates, snapshotWordId, {
              'wordId': snapshotWordId,
              'stability': 2.5,
              'difficulty': 5.0,
              'intervalDays': 3,
              'repetitions': 1,
              'lapses': 0,
              'lastReviewAtUtcMs': now.millisecondsSinceEpoch,
              'dueAtUtcMs': now
                  .add(const Duration(days: 3))
                  .millisecondsSinceEpoch,
              'algorithmVersion': 1,
            });
        await apply(partialSnapshot);
        expect(
          (await database.select(database.srsStates).getSingle()).repetitions,
          1,
        );

        for (var index = 0; index < 2; index++) {
          await apply(
            entity(SyncCollection.attempts, 'merged-attempt-$index', {
              'sessionId': 'merged-session-$index',
              'wordId': index == 0 ? 'local-word' : 'remote-word',
              'promptMode': 'meaningChoice',
              'isCorrect': true,
              'responseTimeMs': 100,
              'attemptNumber': 1,
              'occurredAtUtcMs': now
                  .add(Duration(days: index))
                  .millisecondsSinceEpoch,
              'providerProvenance': null,
            }),
          );
        }
        final merged = await database.select(database.srsStates).getSingle();
        expect(merged.repetitions, 2);
        await apply(partialSnapshot);
        await apply(partialSnapshot);
        final retained = await database.select(database.srsStates).getSingle();
        expect(retained.repetitions, 2);
        expect(retained.dueAtUtcMs, merged.dueAtUtcMs);
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(2),
        );
        final receipts = await database.select(database.syncConflicts).get();
        expect(
          receipts.every(
            (row) => row.resolutionPolicy == 'naturalKeyLocalTarget',
          ),
          isTrue,
        );
      },
    );
  }

  test('ordinary SRS import keeps server snapshot semantics', () async {
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'ordinary-word',
            ownerId: 'owner',
            categoryId: 'local-category',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'synthetic',
            normalizedMeaning: 'synthetic',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (var index = 0; index < 2; index++) {
      await apply(
        entity(SyncCollection.attempts, 'ordinary-attempt-$index', {
          'sessionId': 'ordinary-session-$index',
          'wordId': 'ordinary-word',
          'promptMode': 'meaningChoice',
          'isCorrect': true,
          'responseTimeMs': 100,
          'attemptNumber': 1,
          'occurredAtUtcMs': now
              .add(Duration(days: index))
              .millisecondsSinceEpoch,
          'providerProvenance': null,
        }),
      );
    }
    expect(
      (await database.select(database.srsStates).getSingle()).repetitions,
      2,
    );
    await apply(
      entity(SyncCollection.srsStates, 'ordinary-word', {
        'wordId': 'ordinary-word',
        'stability': 2.5,
        'difficulty': 5.0,
        'intervalDays': 3,
        'repetitions': 1,
        'lapses': 0,
        'lastReviewAtUtcMs': now.millisecondsSinceEpoch,
        'dueAtUtcMs': now.add(const Duration(days: 3)).millisecondsSinceEpoch,
        'algorithmVersion': 1,
      }),
    );
    expect(
      (await database.select(database.srsStates).getSingle()).repetitions,
      1,
    );
    expect(await database.select(database.syncConflicts).get(), isEmpty);
  });

  test('a pulled word cannot refer to another owner category', () async {
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(id: 'other-owner', createdAtUtcMs: 1),
        );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'private-category',
            ownerId: 'other-owner',
            name: 'Private',
            normalizedName: 'private',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await expectLater(
      apply(
        entity(SyncCollection.words, 'foreign-reference', {
          'categoryId': 'private-category',
          'spelling': 'station',
          'meaning': 'synthetic',
          'partOfSpeech': 'noun',
        }),
      ),
      throwsA(isA<InvalidSyncPayloadFailure>()),
    );
    expect(await database.select(database.vocabularyWords).get(), isEmpty);
  });
}
