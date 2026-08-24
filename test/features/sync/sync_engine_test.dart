import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';

void main() {
  late AppDatabase database;
  late SyncStore store;
  late _OwnerRepository owners;
  late _FakeGateway gateway;
  late DateTime nowUtc;
  late int leaseCounter;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    nowUtc = DateTime.utc(2026, 7, 30, 9);
    leaseCounter = 0;
    owners = _OwnerRepository(
      identity.LocalOwner(
        id: 'owner-a',
        firebaseUid: 'firebase-a',
        createdAtUtc: nowUtc,
      ),
    );
    gateway = _FakeGateway(nowUtc);
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-a',
            firebaseUid: const Value('firebase-a'),
            accountState: const Value('firebaseBound'),
            createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  SyncEngine engine({
    bool cloudEnabled = true,
    SyncMutex? mutex,
    OwnerOperationGate? ownerGate,
    SyncHeartbeatDelay? heartbeatDelay,
    Duration requestTimeout = const Duration(seconds: 30),
  }) {
    return SyncEngine(
      owners: owners,
      store: store,
      gateway: gateway,
      policyProvider: () async => CloudSyncPolicy(
        enabled: cloudEnabled,
        source: CloudSyncPolicySource.cache,
        fetchedAtUtc: nowUtc,
        expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
      ),
      ownerGate: ownerGate ?? DriftOwnerOperationGate(database),
      mutex: mutex ?? SyncMutex(),
      backoff: const SyncBackoff(jitterFraction: 0),
      nowUtc: () => nowUtc,
      generateLeaseToken: () => 'lease-${++leaseCounter}',
      heartbeatDelay: heartbeatDelay ?? Future<void>.delayed,
      requestTimeout: requestTimeout,
    );
  }

  test('cloud kill switch leaves pending local work untouched', () async {
    await _seedCategoryOperation(database);

    final result = await engine(cloudEnabled: false).run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.skippedCloudDisabled);
    expect(gateway.pushCalls, 0);
    expect(operation.state, 'pending');
  });

  test('owner without Firebase UID skips without claiming work', () async {
    owners.owner = identity.LocalOwner(id: 'owner-a', createdAtUtc: nowUtc);
    await _seedCategoryOperation(database);

    final result = await engine().run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.skippedUnauthenticated);
    expect(operation.state, 'pending');
  });

  test('rereads authoritative owner identity after gate acquisition', () async {
    await _seedCategoryOperation(database);
    owners.owner = identity.LocalOwner(
      id: 'owner-a',
      firebaseUid: 'firebase-before-gate',
      createdAtUtc: nowUtc,
    );
    final ownerGate = _CallbackOwnerOperationGate(
      DriftOwnerOperationGate(database),
      onTryAcquire: () {
        owners.owner = identity.LocalOwner(
          id: 'owner-a',
          firebaseUid: 'firebase-after-gate',
          createdAtUtc: nowUtc,
        );
      },
    );

    final result = await engine(ownerGate: ownerGate).run();

    expect(result.status, SyncRunStatus.completed);
    expect(owners.reads, 1, reason: 'the authoritative read is post-gate');
    expect(gateway.pushedMutations.single.firebaseUid, 'firebase-after-gate');
  });

  test(
    'offline work retries then applies exactly once after reconnect',
    () async {
      await _seedCategoryOperation(database);
      gateway.pushFailure = const OfflineSyncFailure();
      final syncEngine = engine();

      final offlineResult = await syncEngine.run();
      var operation = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(offlineResult.status, SyncRunStatus.partialFailure);
      expect(operation.state, 'retryWaiting');
      expect(operation.nextAttemptAtUtcMs, isNotNull);

      nowUtc = DateTime.fromMillisecondsSinceEpoch(
        operation.nextAttemptAtUtcMs!,
        isUtc: true,
      );
      gateway.pushFailure = null;
      final onlineResult = await syncEngine.run();
      operation = await database.select(database.outboxOperations).getSingle();
      final replayResult = await syncEngine.run();

      expect(onlineResult.status, SyncRunStatus.completed);
      expect(operation.state, 'acknowledged');
      expect(gateway.appliedOperationIds, {'category:travel:1:upsert'});
      expect(replayResult.pushed, 0);
      expect(gateway.appliedOperationIds, hasLength(1));
    },
  );

  test(
    'a fresh engine never automatically requeues permission denial',
    () async {
      await _seedCategoryOperation(database);
      gateway.pushFailure = const PermissionDeniedSyncFailure();

      final deniedResult = await engine().run();
      var operation = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(deniedResult.status, SyncRunStatus.partialFailure);
      expect(operation.state, 'permanentFailure');
      expect(operation.failureCode, SyncFailureCode.permissionDenied.name);

      gateway.pushFailure = null;
      final freshResult = await engine().run();
      operation = await database.select(database.outboxOperations).getSingle();

      expect(freshResult.pushed, 0);
      expect(operation.state, 'permanentFailure');
      expect(operation.failureCode, SyncFailureCode.permissionDenied.name);
      expect(gateway.pushCalls, 1);
      expect(gateway.appliedOperationIds, isEmpty);
    },
  );

  test('invalid push payload cannot clear its outbox operation', () async {
    await _seedCategoryOperation(database);
    gateway.pushFailure = const InvalidSyncPayloadFailure();

    final result = await engine().run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.partialFailure);
    expect(result.pushed, 0);
    expect(operation.state, 'permanentFailure');
    expect(operation.failureCode, SyncFailureCode.invalidPayload.name);
    expect(operation.acknowledgedAtUtcMs, isNull);
    expect(gateway.appliedOperationIds, isEmpty);
  });

  test(
    'withdrawal at the push fence restores an unattempted pending report',
    () async {
      await DriftResearchConsentRepository(database).decide(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: nowUtc,
      );
      await database.customInsert('''
        INSERT INTO content_quality_reports(
          id, owner_id, content_type, content_id, content_revision,
          reason_code, comment, submitted_at_utc_ms
        ) VALUES (
          'report:push-fence', 'owner-a', 'lexicalMetadata', 'word:station',
          3, 'audio', NULL, 2000
        )
      ''');
      await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES (
          'contentQualityReport:report:push-fence:1', 'owner-a',
          'contentQualityReport', 'report:push-fence', 'upsert', 1, 0,
          'pending', 0, 2000
        )
      ''');
      store = DriftSyncStore(
        database,
        consentRegistry: DriftConsentRegistry(database),
        contentQualityReportSyncRollout:
            const ContentQualityReportSyncRollout.v1(
              deployedRulesRevision: contentQualityReportV1RulesRevision,
              consentVersion: 1,
            ),
      );
      gateway.onPush = (_) async {
        await DriftResearchConsentRepository(database).decide(
          ownerId: 'owner-a',
          version: 1,
          accepted: false,
          decidedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        );
        throw const ContentReportConsentWithdrawnSyncFailure();
      };

      final result = await engine().run();
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();

      expect(result.status, SyncRunStatus.completed);
      expect(result.failures, 0);
      expect(operation.state, 'pending');
      expect(operation.attemptCount, 0);
      expect(operation.lastAttemptAtUtcMs, isNull);
      expect(operation.leaseToken, isNull);
      expect(operation.failureCode, isNull);
      expect(gateway.appliedOperationIds, isEmpty);
    },
  );

  test(
    'mismatched acknowledgement cannot clear its outbox operation',
    () async {
      await _seedCategoryOperation(database);
      gateway.onPush = (mutation) async => PushAcknowledged(
        operationId: 'mismatched:${mutation.operationId}',
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );

      await expectLater(engine().run(), throwsA(isA<ArgumentError>()));
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();

      expect(operation.state, isNot('acknowledged'));
      expect(operation.acknowledgedAtUtcMs, isNull);
    },
  );

  test(
    'only the exact cloud acknowledgement translates to the local operation',
    () async {
      await _seedCategoryOperation(database);
      final translatingStore = _CloudIdentitySyncStore(
        store,
        localOperationId: 'category:travel:1:upsert',
        cloudOperationId: 'cloud:category:travel:1:upsert',
      );
      store = translatingStore;
      gateway.onPush = (mutation) async => PushAcknowledged(
        operationId: 'wrong:${mutation.operationId}',
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );

      await expectLater(engine().run(), throwsA(isA<ArgumentError>()));
      var operation = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(
        gateway.pushedMutations.single.operationId,
        translatingStore.cloudOperationId,
      );
      expect(translatingStore.acknowledgeCalls, 0);
      expect(operation.operationId, translatingStore.localOperationId);
      expect(operation.state, isNot('acknowledged'));
      expect(operation.acknowledgedAtUtcMs, isNull);

      nowUtc = nowUtc.add(const Duration(minutes: 6));
      gateway.onPush = (mutation) async => PushAcknowledged(
        operationId: mutation.operationId,
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );

      final retry = await engine().run();
      operation = await database.select(database.outboxOperations).getSingle();
      expect(retry.status, SyncRunStatus.completed);
      expect(retry.pushed, 1);
      expect(translatingStore.acknowledgeCalls, 1);
      expect(
        translatingStore.lastAcknowledgementOperationId,
        translatingStore.localOperationId,
      );
      expect(operation.state, 'acknowledged');
      expect(operation.acknowledgedAtUtcMs, isNotNull);
    },
  );

  test('push conflict records evidence and selects cloud state', () async {
    await _seedCategoryOperation(database);
    gateway.pushResult = PushConflict(
      SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'category:travel',
        revision: 2,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: nowUtc,
        serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        payload: const <String, Object?>{'name': 'Cloud Travel'},
      ),
    );

    final result = await engine().run();
    final category = await database
        .select(database.vocabularyCategories)
        .getSingle();
    final conflicts = await database.select(database.syncConflicts).get();

    expect(result.conflicts, 1);
    expect(category.name, 'Cloud Travel');
    expect(conflicts, hasLength(1));
  });

  test('push timeout becomes a retryable partial failure', () async {
    await _seedCategoryOperation(database);
    final neverCompletes = Completer<PushResult>();
    gateway.onPush = (_) => neverCompletes.future;

    final result = await engine(
      requestTimeout: const Duration(milliseconds: 10),
    ).run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.partialFailure);
    expect(result.failures, 1);
    expect(result.retryRecommended, isTrue);
    expect(operation.state, 'retryWaiting');
    expect(operation.failureCode, SyncFailureCode.providerUnavailable.name);
  });

  test('separate foreground and background isolates cannot overlap', () async {
    await _seedCategoryOperation(database);
    final pushEntered = Completer<void>();
    final releasePush = Completer<void>();
    gateway.onPush = (mutation) async {
      pushEntered.complete();
      await releasePush.future;
      return PushAcknowledged(
        operationId: mutation.operationId,
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );
    };
    final foregroundEngine = engine(mutex: SyncMutex());
    final backgroundEngine = engine(mutex: SyncMutex());

    final firstRun = foregroundEngine.run();
    await pushEntered.future;
    final secondResult = await backgroundEngine.run();
    releasePush.complete();
    final firstResult = await firstRun;

    expect(secondResult.status, SyncRunStatus.alreadyRunning);
    expect(firstResult.status, SyncRunStatus.completed);
    expect(gateway.appliedOperationIds, hasLength(1));
  });

  test('heartbeat keeps a blocked run fenced beyond nominal expiry', () async {
    await _seedCategoryOperation(database);
    final pushEntered = Completer<void>();
    final releasePush = Completer<void>();
    gateway.onPush = (mutation) async {
      if (!pushEntered.isCompleted) {
        pushEntered.complete();
        await releasePush.future;
      }
      return PushAcknowledged(
        operationId: mutation.operationId,
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );
    };
    final initialNow = nowUtc;
    final heartbeatScheduler = _ManualHeartbeatScheduler();
    final trackingGate = _TrackingOwnerOperationGate(
      DriftOwnerOperationGate(database),
    );
    final firstEngine = engine(
      mutex: SyncMutex(),
      ownerGate: trackingGate,
      heartbeatDelay: heartbeatScheduler.wait,
    );
    final secondEngine = engine(mutex: SyncMutex());
    final firstRun = firstEngine.run();
    await pushEntered.future;
    expect(heartbeatScheduler.delays.single, SyncEngine.heartbeatInterval);
    expect(
      heartbeatScheduler.delays.single,
      lessThanOrEqualTo(
        Duration(microseconds: SyncEngine.runLeaseDuration.inMicroseconds ~/ 3),
      ),
    );
    nowUtc = nowUtc.add(heartbeatScheduler.delays.single);
    heartbeatScheduler.elapseNext();
    await trackingGate.firstRenewed.future;
    nowUtc = initialNow.add(SyncEngine.runLeaseDuration);

    try {
      final secondResult = await secondEngine.run();
      expect(secondResult.status, SyncRunStatus.alreadyRunning);
      expect(gateway.pushCalls, 1);
    } finally {
      releasePush.complete();
      await firstRun.catchError(
        (Object _) => const SyncRunResult(status: SyncRunStatus.partialFailure),
      );
    }
  });

  test(
    'lease loss fences late push completion and all later gateway work',
    () async {
      await _seedCategoryOperation(database);
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'category:work',
              ownerId: 'owner-a',
              name: 'Work',
              normalizedName: 'work',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'category:work:1:upsert',
              ownerId: 'owner-a',
              entityType: 'category',
              entityId: 'category:work',
              operationKind: 'upsert',
              createdAtUtcMs: 1,
            ),
          );
      final pushEntered = Completer<void>();
      final releasePush = Completer<void>();
      gateway.onPush = (mutation) async {
        if (!pushEntered.isCompleted) {
          pushEntered.complete();
          await releasePush.future;
        }
        return PushAcknowledged(
          operationId: mutation.operationId,
          resultingRevision: mutation.localRevision,
          acknowledgedAtUtc: nowUtc,
        );
      };
      final heartbeatScheduler = _ManualHeartbeatScheduler();
      final losingGate = _LosingOwnerOperationGate(
        DriftOwnerOperationGate(database),
      );
      final run = engine(
        ownerGate: losingGate,
        heartbeatDelay: heartbeatScheduler.wait,
      ).run();
      await pushEntered.future;
      nowUtc = nowUtc.add(SyncEngine.heartbeatInterval);
      heartbeatScheduler.elapseNext();
      await losingGate.lost.future;
      releasePush.complete();

      await run;

      final firstOperation =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals('category:travel:1:upsert'),
              ))
              .getSingle();
      expect(gateway.pushCalls, 1);
      expect(gateway.pullCalls, 0);
      expect(firstOperation.state, isNot('acknowledged'));
      expect(firstOperation.acknowledgedAtUtcMs, isNull);
    },
  );

  test(
    'acknowledgement predicate loss stops before pull or local completion',
    () async {
      await _seedCategoryOperation(database);
      gateway.onPush = (mutation) async {
        await DriftOwnerOperationGate(database).release(token: 'lease-1');
        return PushAcknowledged(
          operationId: mutation.operationId,
          resultingRevision: mutation.localRevision,
          acknowledgedAtUtc: nowUtc,
        );
      };

      final result = await engine().run();
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();

      expect(result.status, SyncRunStatus.partialFailure);
      expect(result.pushed, 0);
      expect(result.failures, 1);
      expect(gateway.pushCalls, 1);
      expect(gateway.pullCalls, 0);
      expect(operation.state, 'inFlight');
      expect(operation.acknowledgedAtUtcMs, isNull);
    },
  );

  test(
    'five durable send reservations exhaust retryable work before a sixth call',
    () async {
      await _seedCategoryOperation(database);
      gateway.pushFailure = const OfflineSyncFailure();
      final syncEngine = engine();

      for (var reservation = 1; reservation <= 5; reservation++) {
        await syncEngine.run();
        final row = await database
            .select(database.outboxOperations)
            .getSingle();
        expect(row.attemptCount, reservation);
        if (reservation < 5) {
          expect(row.state, 'retryWaiting');
          nowUtc = DateTime.fromMillisecondsSinceEpoch(
            row.nextAttemptAtUtcMs!,
            isUtc: true,
          );
        }
      }
      final exhausted = await database
          .select(database.outboxOperations)
          .getSingle();
      final callsAtExhaustion = gateway.pushCalls;

      await engine().run();

      expect(callsAtExhaustion, 5);
      expect(gateway.pushCalls, callsAtExhaustion);
      expect(exhausted.state, 'permanentFailure');
      expect(exhausted.failureCode, SyncFailureCode.offline.name);
    },
  );

  for (final remoteAppliedBeforeLostAck in <bool>[false, true]) {
    test('fifth reservation ambiguity blocks later same-entity work '
        'when remoteApplied=$remoteAppliedBeforeLostAck', () async {
      await _seedCategoryOperation(database);
      gateway.onPush = (mutation) async {
        if (gateway.pushCalls == 5 && remoteAppliedBeforeLostAck) {
          gateway.appliedOperationIds.add(mutation.operationId);
        }
        throw const OfflineSyncFailure();
      };

      for (var reservation = 1; reservation <= 5; reservation++) {
        await engine().run();
        final row =
            await (database.select(database.outboxOperations)..where(
                  (candidate) =>
                      candidate.operationId.equals('category:travel:1:upsert'),
                ))
                .getSingle();
        if (reservation < 5) {
          nowUtc = DateTime.fromMillisecondsSinceEpoch(
            row.nextAttemptAtUtcMs!,
            isUtc: true,
          );
        }
      }

      await (database.update(
        database.vocabularyCategories,
      )..where((row) => row.id.equals('category:travel'))).write(
        VocabularyCategoriesCompanion(
          name: const Value('Latest travel'),
          normalizedName: const Value('latest travel'),
          localRevision: const Value(2),
          updatedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
        ),
      );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'category:travel:2:upsert',
              ownerId: 'owner-a',
              entityType: 'category',
              entityId: 'category:travel',
              operationKind: 'upsert',
              baseRevision: const Value(1),
              createdAtUtcMs: 2,
            ),
          );
      await _seedAdditionalCategoryOperation(
        database,
        id: 'category:unrelated',
        operationId: 'category:unrelated:1:upsert',
        createdAtUtcMs: 3,
      );
      gateway.onPush = (mutation) async => PushAcknowledged(
        operationId: mutation.operationId,
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );

      final afterExhaustion = await engine().run();
      final rows = await database.select(database.outboxOperations).get();
      int callsFor(String operationId) => gateway.pushedMutations
          .where((mutation) => mutation.operationId == operationId)
          .length;

      expect(afterExhaustion.pushed, 1);
      expect(callsFor('category:travel:1:upsert'), 5);
      expect(callsFor('category:travel:2:upsert'), 0);
      expect(callsFor('category:unrelated:1:upsert'), 1);
      expect(
        rows
            .singleWhere((row) => row.operationId == 'category:travel:1:upsert')
            .state,
        'permanentFailure',
      );
      expect(
        rows
            .singleWhere((row) => row.operationId == 'category:travel:2:upsert')
            .state,
        'pending',
      );
      expect(
        rows
            .singleWhere(
              (row) => row.operationId == 'category:unrelated:1:upsert',
            )
            .state,
        'acknowledged',
      );
      expect(
        gateway.appliedOperationIds.contains('category:travel:1:upsert'),
        remoteAppliedBeforeLostAck,
      );
    });
  }

  test(
    'first permanent failure stops pushes and pulls and releases unstarted rows',
    () async {
      await _seedCategoryOperation(database);
      await _seedAdditionalCategoryOperation(
        database,
        id: 'category:retry',
        operationId: 'category:retry:3:upsert',
        createdAtUtcMs: 1,
      );
      await _seedAdditionalCategoryOperation(
        database,
        id: 'category:pending',
        operationId: 'category:pending:1:upsert',
        createdAtUtcMs: 2,
      );
      await (database.update(database.outboxOperations)
            ..where((row) => row.operationId.equals('category:retry:3:upsert')))
          .write(
            OutboxOperationsCompanion(
              state: const Value('retryWaiting'),
              attemptCount: const Value(2),
              nextAttemptAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
              failureCode: Value(SyncFailureCode.quota.name),
            ),
          );
      gateway.pushFailure = const PermissionDeniedSyncFailure();

      final result = await engine().run();

      final rows = await database.select(database.outboxOperations).get();
      final attempted = rows.singleWhere(
        (row) => row.operationId == 'category:travel:1:upsert',
      );
      final retry = rows.singleWhere(
        (row) => row.operationId == 'category:retry:3:upsert',
      );
      final pending = rows.singleWhere(
        (row) => row.operationId == 'category:pending:1:upsert',
      );
      expect(result.failures, 1);
      expect(gateway.pushCalls, 1);
      expect(gateway.pullCalls, 0);
      expect(attempted.state, 'permanentFailure');
      expect(attempted.attemptCount, 1);
      expect(attempted.failureCode, SyncFailureCode.permissionDenied.name);
      expect(retry.state, 'retryWaiting');
      expect(retry.attemptCount, 2);
      expect(retry.nextAttemptAtUtcMs, nowUtc.millisecondsSinceEpoch);
      expect(retry.failureCode, SyncFailureCode.quota.name);
      expect(retry.leaseToken, isNull);
      expect(pending.state, 'pending');
      expect(pending.attemptCount, 0);
      expect(pending.leaseToken, isNull);
      expect(rows.where((row) => row.state == 'inFlight'), isEmpty);
    },
  );

  test('advancing hasMore pull commits and recommends another run', () async {
    final cursor = SyncCursor(
      serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
      documentId: 'category:remote',
    );
    gateway.onPull = (collection, after) {
      if (collection != SyncCollection.categories) {
        return PullPage(
          changes: const <SyncEntity>[],
          nextCursor: after,
          hasMore: false,
        );
      }
      return PullPage(
        changes: <SyncEntity>[
          SyncEntity(
            collection: SyncCollection.categories,
            entityId: 'category:remote',
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: nowUtc,
            serverUpdatedAtUtc: cursor.serverUpdatedAtUtc,
            payload: const <String, Object?>{'name': 'Remote'},
          ),
        ],
        nextCursor: cursor,
        hasMore: true,
      );
    };

    final result = await engine().run();

    final category = await (database.select(
      database.vocabularyCategories,
    )..where((row) => row.id.equals('category:remote'))).getSingle();
    expect(result.status, SyncRunStatus.completed);
    expect(result.pulled, 1);
    expect(result.retryRecommended, isTrue);
    expect(category.name, 'Remote');
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      cursor,
    );
  });

  test('each sync collection is pulled exactly once per run', () async {
    final result = await engine().run();

    expect(result.status, SyncRunStatus.completed);
    expect(gateway.pulledCollections, hasLength(SyncCollection.values.length));
    for (final collection in SyncCollection.values) {
      expect(
        gateway.pulledCollections.where((value) => value == collection),
        hasLength(1),
      );
    }
  });

  test('first permanent pull failure stops all later collections', () async {
    gateway.onPull = (_, _) => throw const PermissionDeniedSyncFailure();

    final result = await engine().run();

    expect(result.status, SyncRunStatus.partialFailure);
    expect(result.failures, 1);
    expect(result.retryRecommended, isFalse);
    expect(gateway.pullCalls, 1);
    expect(gateway.pulledCollections, [SyncCollection.categories]);
  });
}

final class _ManualHeartbeatScheduler {
  final List<Duration> delays = <Duration>[];
  final List<Completer<void>> _scheduled = <Completer<void>>[];

  Future<void> wait(Duration delay) {
    delays.add(delay);
    final scheduled = Completer<void>();
    _scheduled.add(scheduled);
    return scheduled.future;
  }

  void elapseNext() {
    _scheduled.firstWhere((item) => !item.isCompleted).complete();
  }
}

final class _TrackingOwnerOperationGate implements OwnerOperationGate {
  _TrackingOwnerOperationGate(this.delegate);

  final OwnerOperationGate delegate;
  final Completer<void> firstRenewed = Completer<void>();

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.tryAcquire(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final result = await delegate.renew(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
    if (!firstRenewed.isCompleted) firstRenewed.complete();
    return result;
  }

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

final class _LosingOwnerOperationGate implements OwnerOperationGate {
  _LosingOwnerOperationGate(this.delegate);

  final OwnerOperationGate delegate;
  final Completer<void> lost = Completer<void>();

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.tryAcquire(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    await delegate.release(token: token);
    if (!lost.isCompleted) lost.complete();
    return false;
  }

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

final class _CallbackOwnerOperationGate implements OwnerOperationGate {
  _CallbackOwnerOperationGate(this.delegate, {required this.onTryAcquire});

  final OwnerOperationGate delegate;
  final void Function() onTryAcquire;

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) {
    onTryAcquire();
    return delegate.tryAcquire(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
  }

  @override
  Future<bool> isOwned({required String token, required DateTime nowUtc}) =>
      delegate.isOwned(token: token, nowUtc: nowUtc);

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) => delegate.renew(
    token: token,
    nowUtc: nowUtc,
    leaseDuration: leaseDuration,
  );

  @override
  Future<void> release({required String token}) =>
      delegate.release(token: token);
}

final class _OwnerRepository implements LocalOwnerRepository {
  _OwnerRepository(this.owner);

  identity.LocalOwner owner;
  int reads = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    reads += 1;
    return owner;
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async {
    owner = identity.LocalOwner(
      id: owner.id,
      firebaseUid: firebaseUid,
      createdAtUtc: owner.createdAtUtc,
      upgradedAtUtc: owner.upgradedAtUtc,
    );
    return owner;
  }
}

final class _CloudIdentitySyncStore implements SyncStore {
  _CloudIdentitySyncStore(
    this.delegate, {
    required this.localOperationId,
    required this.cloudOperationId,
  });

  final SyncStore delegate;
  final String localOperationId;
  final String cloudOperationId;
  int acknowledgeCalls = 0;
  String? lastAcknowledgementOperationId;

  @override
  Future<List<ClaimedSyncOperation>> claimPending({
    required String ownerId,
    required String firebaseUid,
    required int limit,
    required String leaseToken,
    required String ownerGateToken,
    required Duration leaseDuration,
    required DateTime nowUtc,
  }) async {
    final claims = await delegate.claimPending(
      ownerId: ownerId,
      firebaseUid: firebaseUid,
      limit: limit,
      leaseToken: leaseToken,
      ownerGateToken: ownerGateToken,
      leaseDuration: leaseDuration,
      nowUtc: nowUtc,
    );
    return claims.map(_translate).toList(growable: false);
  }

  @override
  Future<ClaimedSyncOperation?> beginAttempt({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  }) async {
    final begun = await delegate.beginAttempt(
      claim: claim,
      ownerGateToken: ownerGateToken,
      nowUtc: nowUtc,
    );
    return begun == null ? null : _translate(begun);
  }

  @override
  Future<bool> acknowledge({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required PushAcknowledged acknowledgement,
  }) {
    acknowledgeCalls += 1;
    lastAcknowledgementOperationId = acknowledgement.operationId;
    return delegate.acknowledge(
      operationId: operationId,
      leaseToken: leaseToken,
      ownerGateToken: ownerGateToken,
      nowUtc: nowUtc,
      acknowledgement: acknowledgement,
    );
  }

  @override
  Future<bool> markRetry({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required DateTime nextAttemptAtUtc,
    required SyncFailure failure,
  }) => delegate.markRetry(
    operationId: operationId,
    leaseToken: leaseToken,
    ownerGateToken: ownerGateToken,
    nowUtc: nowUtc,
    nextAttemptAtUtc: nextAttemptAtUtc,
    failure: failure,
  );

  @override
  Future<bool> markTerminalFailure({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required SyncFailure failure,
  }) => delegate.markTerminalFailure(
    operationId: operationId,
    leaseToken: leaseToken,
    ownerGateToken: ownerGateToken,
    nowUtc: nowUtc,
    failure: failure,
  );

  @override
  Future<bool> releaseClaim({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  }) => delegate.releaseClaim(
    claim: claim,
    ownerGateToken: ownerGateToken,
    nowUtc: nowUtc,
  );

  @override
  Future<bool> cancelContentReportAttemptForConsentWithdrawal({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  }) => delegate.cancelContentReportAttemptForConsentWithdrawal(
    claim: claim,
    ownerGateToken: ownerGateToken,
    nowUtc: nowUtc,
  );

  @override
  Future<bool> resolvePushConflict({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required SyncEntity cloudEntity,
    required DateTime resolvedAtUtc,
  }) => delegate.resolvePushConflict(
    claim: claim,
    ownerGateToken: ownerGateToken,
    cloudEntity: cloudEntity,
    resolvedAtUtc: resolvedAtUtc,
  );

  @override
  Future<SyncCursor?> readCheckpoint(
    String ownerId,
    SyncCollection collection,
  ) => delegate.readCheckpoint(ownerId, collection);

  @override
  Future<bool> applyPullPage({
    required String ownerId,
    required SyncCollection collection,
    required PullPage page,
    required String ownerGateToken,
    required DateTime nowUtc,
  }) => delegate.applyPullPage(
    ownerId: ownerId,
    collection: collection,
    page: page,
    ownerGateToken: ownerGateToken,
    nowUtc: nowUtc,
  );

  ClaimedSyncOperation _translate(ClaimedSyncOperation claim) {
    final mutation = claim.mutation;
    if (mutation.operationId == cloudOperationId) return claim;
    if (mutation.operationId != localOperationId ||
        claim.localOperationId != localOperationId) {
      throw StateError('unexpected operation identity in test store');
    }
    return ClaimedSyncOperation(
      leaseToken: claim.leaseToken,
      attemptCount: claim.attemptCount,
      releaseState: claim.releaseState,
      releaseAttemptCount: claim.releaseAttemptCount,
      releaseLastAttemptAtUtc: claim.releaseLastAttemptAtUtc,
      localOperationId: localOperationId,
      mutation: PushMutation(
        operationId: cloudOperationId,
        firebaseUid: mutation.firebaseUid,
        collection: mutation.collection,
        entityId: mutation.entityId,
        operationKind: mutation.operationKind,
        payloadVersion: mutation.payloadVersion,
        baseRevision: mutation.baseRevision,
        localRevision: mutation.localRevision,
        clientUpdatedAtUtc: mutation.clientUpdatedAtUtc,
        payload: mutation.payload,
      ),
    );
  }
}

final class _FakeGateway implements SyncGateway {
  _FakeGateway(this.nowUtc);

  DateTime nowUtc;
  int pushCalls = 0;
  int pullCalls = 0;
  SyncFailure? pushFailure;
  PushResult? pushResult;
  Future<PushResult> Function(PushMutation mutation)? onPush;
  PullPage Function(SyncCollection collection, SyncCursor? after)? onPull;
  final Set<String> appliedOperationIds = <String>{};
  final List<PushMutation> pushedMutations = <PushMutation>[];
  final List<SyncCollection> pulledCollections = <SyncCollection>[];

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    pullCalls++;
    pulledCollections.add(collection);
    final handler = onPull;
    if (handler != null) return handler(collection, after);
    return PullPage(changes: const [], nextCursor: after, hasMore: false);
  }

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushCalls++;
    pushedMutations.add(mutation);
    final handler = onPush;
    if (handler != null) {
      final result = await handler(mutation);
      appliedOperationIds.add(mutation.operationId);
      return result;
    }
    final failure = pushFailure;
    if (failure != null) throw failure;
    final result =
        pushResult ??
        PushAcknowledged(
          operationId: mutation.operationId,
          resultingRevision: mutation.localRevision,
          acknowledgedAtUtc: nowUtc,
        );
    if (result is PushAcknowledged) {
      appliedOperationIds.add(mutation.operationId);
    }
    return result;
  }
}

Future<void> _seedCategoryOperation(AppDatabase database) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:travel',
          ownerId: 'owner-a',
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 0,
          updatedAtUtcMs: 0,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: 'category:travel:1:upsert',
          ownerId: 'owner-a',
          entityType: 'category',
          entityId: 'category:travel',
          operationKind: 'upsert',
          createdAtUtcMs: 0,
        ),
      );
}

Future<void> _seedAdditionalCategoryOperation(
  AppDatabase database, {
  required String id,
  required String operationId,
  required int createdAtUtcMs,
}) async {
  final name = id.split(':').last;
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: id,
          ownerId: 'owner-a',
          name: name,
          normalizedName: name,
          createdAtUtcMs: createdAtUtcMs,
          updatedAtUtcMs: createdAtUtcMs,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: operationId,
          ownerId: 'owner-a',
          entityType: 'category',
          entityId: id,
          operationKind: 'upsert',
          createdAtUtcMs: createdAtUtcMs,
        ),
      );
}
