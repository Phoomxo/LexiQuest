import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  test(
    'sync keeps the word operation identity after a lost ACK and restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-sync-ack-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File.fromUri(directory.uri.resolve('sync.sqlite'));
      var database = AppDatabase(NativeDatabase(file));
      final acceptedAt = DateTime.utc(2026, 11, 15, 9);
      var now = acceptedAt;
      var sequence = 0;
      final remote = _ReceiptGateway(acceptedAt);

      DriftLocalOwnerRepository ownerRepository() => DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner-${++sequence}',
        nowUtc: () => now,
      );

      SyncEngine engine() => SyncEngine(
        owners: ownerRepository(),
        store: DriftSyncStore(database),
        gateway: remote,
        policyProvider: remote.fetchPolicy,
        mutex: SyncMutex(),
        backoff: const SyncBackoff(jitterFraction: 0),
        nowUtc: () => now,
        generateLeaseToken: () => 'lease-${++sequence}',
      );

      Future<OutboxOperation> wordOperation() => (database.select(
        database.outboxOperations,
      )..where((row) => row.entityType.equals('word'))).getSingle();

      try {
        final owners = ownerRepository();
        final localOwner = await owners.getOrCreateActiveOwner();
        await owners.bindFirebaseUid(localOwner.id, _signedInUid);
        final vocabulary = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(database),
          generateId: () => 'vocab-${++sequence}',
          nowUtc: () => now,
        );
        final category = await vocabulary.createCategory('การเดินทาง');
        final word = await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'station',
            meaning: 'สถานี',
            partOfSpeech: 'noun',
          ),
          expectedOwnerId: localOwner.id,
        );
        final queued = await wordOperation();
        expect(queued.state, 'pending');

        final firstRun = await engine().run();
        final waiting = await wordOperation();
        expect(firstRun.status, SyncRunStatus.partialFailure);
        expect(firstRun.retryRecommended, isTrue);
        expect(waiting.operationId, queued.operationId);
        expect(waiting.state, 'retryWaiting');
        expect(waiting.acknowledgedAtUtcMs, isNull);
        expect(remote.appliedWords.single.operationId, queued.operationId);
        expect(remote.appliedWords.single.entityId, word.id);

        await database.close();
        database = AppDatabase(NativeDatabase(file));
        expect(
          (await ownerRepository().getOrCreateActiveOwner()).id,
          localOwner.id,
        );
        final restored = await wordOperation();
        expect(restored.operationId, queued.operationId);
        expect(restored.state, 'retryWaiting');
        expect(restored.nextAttemptAtUtcMs, waiting.nextAttemptAtUtcMs);
        now = DateTime.fromMillisecondsSinceEpoch(
          restored.nextAttemptAtUtcMs!,
          isUtc: true,
        );

        final restartedEngine = engine();
        final retry = await restartedEngine.run();
        final acknowledged = await wordOperation();
        expect(retry.status, SyncRunStatus.completed);
        expect(retry.pushed, 1);
        expect(acknowledged.operationId, queued.operationId);
        expect(acknowledged.state, 'acknowledged');
        expect(
          acknowledged.acknowledgedAtUtcMs,
          acceptedAt.millisecondsSinceEpoch,
        );
        expect(remote.wordRequests.map((request) => request.operationId), [
          queued.operationId,
          queued.operationId,
        ]);
        expect(
          remote.wordRequests.last.payload,
          remote.wordRequests.first.payload,
        );
        expect(remote.wordRequests.last.payload['spelling'], 'station');
        expect(remote.appliedWords, hasLength(1));
        final localWord = await database
            .select(database.vocabularyWords)
            .getSingle();
        expect(localWord.id, word.id);
        expect(localWord.cloudRevision, 1);

        expect((await restartedEngine.run()).pushed, 0);
        expect(remote.wordRequests, hasLength(2));
      } finally {
        await database.close();
      }
    },
  );
}

const _signedInUid = 'synthetic-firebase-owner';

class _ReceiptGateway implements SyncGateway {
  _ReceiptGateway(this.acceptedAt);

  final DateTime acceptedAt;
  final wordRequests = <PushMutation>[];
  final appliedWords = <PushMutation>[];
  final _receipts = <String, PushAcknowledged>{};

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: acceptedAt,
    expiresAtUtc: acceptedAt.add(const Duration(hours: 1)),
  );

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    if (firebaseUid != _signedInUid) throw const UnauthenticatedSyncFailure();
    return PullPage(changes: const [], nextCursor: after, hasMore: false);
  }

  @override
  Future<PushResult> push(PushMutation mutation) async {
    if (mutation.firebaseUid != _signedInUid) {
      throw const UnauthenticatedSyncFailure();
    }
    final isWord = mutation.collection == SyncCollection.words;
    if (isWord) wordRequests.add(mutation);
    final previous = _receipts[mutation.operationId];
    if (previous != null) return previous;
    final receipt = PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: acceptedAt,
    );
    _receipts[mutation.operationId] = receipt;
    if (isWord) {
      appliedWords.add(mutation);
      if (appliedWords.length == 1) throw const OfflineSyncFailure();
    }
    return receipt;
  }
}
