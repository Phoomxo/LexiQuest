import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStore store;
  final now = DateTime.utc(2026, 7, 30, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    await _seedVocabulary(database);
  });

  tearDown(() => database.close());

  test('attempt outbox reconstructs an immutable cloud mutation', () async {
    final learning = DriftLearningRepository(database);
    await learning.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: now,
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 250,
        attemptNumber: 1,
        occurredAtUtc: now,
      ),
    );

    final claim = (await store.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'lease-1',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
      // Phase 0 W12-13: recordAnswer also enqueues srsState outbox.
    )).firstWhere((c) => c.mutation.collection == SyncCollection.attempts);

    expect(claim.mutation.collection, SyncCollection.attempts);
    expect(claim.mutation.localRevision, 1);
    expect(claim.mutation.baseRevision, 0);
    expect(claim.mutation.payload['wordId'], 'word-1');
    expect(claim.mutation.payload['isCorrect'], isTrue);
  });

  test(
    'pulled attempt is set-union idempotent and rebuilds projections',
    () async {
      final entity = SyncEntity(
        collection: SyncCollection.attempts,
        entityId: 'attempt-remote',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now,
        serverUpdatedAtUtc: now.add(const Duration(seconds: 1)),
        payload: <String, Object?>{
          'sessionId': 'session-remote',
          'wordId': 'word-1',
          'promptMode': 'meaningChoice',
          'isCorrect': true,
          'responseTimeMs': 300,
          'attemptNumber': 1,
          'occurredAtUtcMs': now.millisecondsSinceEpoch,
          'providerProvenance': null,
        },
      );
      final page = PullPage(
        changes: [entity],
        nextCursor: SyncCursor(
          serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
          documentId: entity.entityId,
        ),
        hasMore: false,
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: page,
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: page,
      );

      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
    },
  );

  test(
    'historical attempt remains valid after its word is soft deleted',
    () async {
      await (database.update(database.vocabularyWords)
            ..where((row) => row.id.equals('word-1')))
          .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
      final entity = _attemptEntity(
        id: 'attempt-deleted-word',
        sessionId: 'session-deleted-word',
        occurredAt: now,
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(entity),
      );

      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  test('pulled attempt rejects a session id owned by another owner', () async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 2));
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'shared-session',
            ownerId: 'owner-2',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: 1,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
    final entity = _attemptEntity(
      id: 'attempt-cross-owner',
      sessionId: 'shared-session',
      occurredAt: now,
    );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(entity),
      ),
      throwsA(isA<Object>()),
    );

    final foreignSession = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals('shared-session'))).getSingle();
    expect(foreignSession.correctCount, 0);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  test('identical attempt pull repairs a missing SRS projection', () async {
    final entity = _attemptEntity(
      id: 'attempt-repair',
      sessionId: 'session-repair',
      occurredAt: now,
    );
    final page = _page(entity);
    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.attempts,
      page: page,
    );
    await database.delete(database.srsStates).go();

    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.attempts,
      page: page,
    );

    expect(await database.select(database.srsStates).get(), hasLength(1));
  });

  test(
    'reading projection rebuild uses monotonic position and latest time',
    () async {
      final later = _readingEntity(
        id: 'reading-later',
        position: 80,
        occurredAt: now.add(const Duration(minutes: 10)),
      );
      final earlier = _readingEntity(
        id: 'reading-earlier',
        position: 20,
        occurredAt: now,
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.readingEvents,
        page: _page(later),
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.readingEvents,
        page: _page(earlier),
      );

      final progress = await database
          .select(database.readingProgressEntries)
          .getSingle();
      expect(progress.lastPosition, 80);
      expect(
        progress.updatedAtUtcMs,
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
    },
  );

  test('identical reading pull repairs a missing projection', () async {
    final entity = _readingEntity(
      id: 'reading-repair',
      position: 40,
      occurredAt: now,
    );
    final page = _page(entity);
    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.readingEvents,
      page: page,
    );
    await database.delete(database.readingProgressEntries).go();

    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.readingEvents,
      page: page,
    );

    expect(
      await database.select(database.readingProgressEntries).get(),
      hasLength(1),
    );
  });

  test('malformed attempt payload rolls back its pull checkpoint', () async {
    final valid = _attemptEntity(
      id: 'attempt-malformed',
      sessionId: 'session-malformed',
      occurredAt: now,
    );
    final malformed = SyncEntity(
      collection: valid.collection,
      entityId: valid.entityId,
      revision: valid.revision,
      isDeleted: valid.isDeleted,
      payloadVersion: valid.payloadVersion,
      clientUpdatedAtUtc: valid.clientUpdatedAtUtc,
      serverUpdatedAtUtc: valid.serverUpdatedAtUtc,
      payload: <String, Object?>{...valid.payload, 'promptMode': 'x' * 61},
    );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(malformed),
      ),
      throwsA(isA<Object>()),
    );

    expect(await database.select(database.answerAttempts).get(), isEmpty);
    expect(await database.select(database.syncCheckpoints).get(), isEmpty);
  });

  test(
    'conflicting immutable attempt is quarantined without overwrite',
    () async {
      final original = _attemptEntity(
        id: 'attempt-conflict',
        sessionId: 'session-conflict',
        occurredAt: now,
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(original),
      );
      final conflicting = SyncEntity(
        collection: original.collection,
        entityId: original.entityId,
        revision: original.revision,
        isDeleted: original.isDeleted,
        payloadVersion: original.payloadVersion,
        clientUpdatedAtUtc: original.clientUpdatedAtUtc,
        serverUpdatedAtUtc: original.serverUpdatedAtUtc.add(
          const Duration(seconds: 1),
        ),
        payload: <String, Object?>{...original.payload, 'isCorrect': false},
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(conflicting),
      );

      final attempt = await database
          .select(database.answerAttempts)
          .getSingle();
      expect(attempt.isCorrect, isTrue);
      final conflict = await database
          .select(database.syncConflicts)
          .getSingle();
      expect(conflict.outcome, 'quarantined');
      expect(conflict.entityId, original.entityId);
    },
  );

  test('attempt acknowledgement is replay safe', () async {
    final learning = DriftLearningRepository(database);
    await learning.startSession(
      LearningSessionDraft(
        id: 'session-ack',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: now,
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-ack',
        ownerId: 'owner-1',
        sessionId: 'session-ack',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 250,
        attemptNumber: 1,
        occurredAtUtc: now,
      ),
    );
    final claim = (await store.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'lease-ack',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
      // Phase 0 W12-13: recordAnswer now also enqueues a srsState outbox op.
      // Filter to the attempt operation specifically.
    )).firstWhere((c) => c.mutation.collection == SyncCollection.attempts);
    final acknowledgement = PushAcknowledged(
      operationId: claim.mutation.operationId,
      resultingRevision: 1,
      acknowledgedAtUtc: now.add(const Duration(seconds: 1)),
    );

    await store.acknowledge(
      operationId: claim.mutation.operationId,
      leaseToken: claim.leaseToken,
      acknowledgement: acknowledgement,
    );
    await store.acknowledge(
      operationId: claim.mutation.operationId,
      leaseToken: claim.leaseToken,
      acknowledgement: acknowledgement,
    );

    final outbox =
        await (database.select(database.outboxOperations)
              ..where((r) => r.operationId.equals(claim.mutation.operationId)))
            .getSingle();
    expect(outbox.state, 'acknowledged');
    expect(
      outbox.acknowledgedAtUtcMs,
      acknowledgement.acknowledgedAtUtc.millisecondsSinceEpoch,
    );
  });
}

SyncEntity _attemptEntity({
  required String id,
  required String sessionId,
  required DateTime occurredAt,
}) => SyncEntity(
  collection: SyncCollection.attempts,
  entityId: id,
  revision: 1,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: occurredAt,
  serverUpdatedAtUtc: occurredAt.add(const Duration(seconds: 1)),
  payload: <String, Object?>{
    'sessionId': sessionId,
    'wordId': 'word-1',
    'promptMode': 'meaningChoice',
    'isCorrect': true,
    'responseTimeMs': 300,
    'attemptNumber': 1,
    'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
    'providerProvenance': null,
  },
);

SyncEntity _readingEntity({
  required String id,
  required int position,
  required DateTime occurredAt,
}) => SyncEntity(
  collection: SyncCollection.readingEvents,
  entityId: id,
  revision: 1,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: occurredAt,
  serverUpdatedAtUtc: occurredAt.add(const Duration(seconds: 1)),
  payload: <String, Object?>{
    'documentId': 'document-1',
    'documentRevision': 1,
    'eventType': 'checkpoint',
    'position': position,
    'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
  },
);

PullPage _page(SyncEntity entity) => PullPage(
  changes: [entity],
  nextCursor: SyncCursor(
    serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
    documentId: entity.entityId,
  ),
  hasMore: false,
);

Future<void> _seedVocabulary(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
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
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-1',
          ownerId: 'owner-1',
          categoryId: 'category-1',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}
