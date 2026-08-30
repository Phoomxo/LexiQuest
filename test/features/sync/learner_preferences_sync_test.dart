import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  group('f35 learner preference local-first sync', () {
    late AppDatabase database;
    late String ownerGateToken;
    final nowUtc = DateTime.utc(2026, 8, 30, 12);

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      ownerGateToken = 'f35-preference-owner-gate';
      await database.customStatement(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, is_active, created_at_utc_ms) '
        "VALUES ('local:preferences', 'firebase-user-1', 'firebaseBound', 1, 1)",
      );
      await database.customStatement(
        'INSERT INTO learner_preferences '
        '(owner_id, preference_version, goal, available_minutes_per_day, '
        'activity_preference, updated_at_utc_ms) '
        "VALUES ('local:preferences', 1, 'examPreparation', 45, 'quiz', 1000)",
      );
      await database.customStatement(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'payload_version, base_revision, state, attempt_count, '
        'created_at_utc_ms) VALUES '
        "('learnerPreference:local:preferences:1', 'local:preferences', "
        "'learnerPreference', 'local:preferences', 'upsert', 1, 0, "
        "'pending', 0, 1000)",
      );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: ownerGateToken,
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 5),
        ),
        isTrue,
      );
    });

    tearDown(() => database.close());

    test(
      'default off and stale rules leave preference pending unleased',
      () async {
        for (final store in <DriftSyncStore>[
          DriftSyncStore(database),
          DriftSyncStore(
            database,
            learnerPreferenceSyncRollout: const LearnerPreferenceSyncRollout.v1(
              deployedRulesRevision: 'stale-rules',
            ),
          ),
        ]) {
          expect(
            await store.claimPending(
              ownerId: 'local:preferences',
              firebaseUid: 'firebase-user-1',
              limit: 1,
              leaseToken: 'blocked-lease',
              ownerGateToken: ownerGateToken,
              leaseDuration: const Duration(minutes: 1),
              nowUtc: nowUtc,
            ),
            isEmpty,
          );
        }
        final operation = await database
            .customSelect(
              "SELECT state, attempt_count, lease_token FROM outbox_operations "
              "WHERE entity_type = 'learnerPreference'",
            )
            .getSingle();
        expect(operation.read<String>('state'), 'pending');
        expect(operation.read<int>('attempt_count'), 0);
        expect(operation.data['lease_token'], isNull);
      },
    );

    test(
      'enabled claim translates one local preference to canonical cloud v1',
      () async {
        final store = DriftSyncStore(
          database,
          learnerPreferenceSyncRollout: const LearnerPreferenceSyncRollout.v1(
            deployedRulesRevision: learnerPreferenceV1RulesRevision,
          ),
        );

        final claims = await store.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'enabled-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );

        expect(claims, hasLength(1));
        expect(
          claims.single.localOperationId,
          'learnerPreference:local:preferences:1',
        );
        expect(
          claims.single.mutation.operationId,
          LearnerPreferenceSyncPayloadContract.canonicalOperationId(
            payload: _payload(updatedAtUtcMs: 1000),
            baseRevision: 0,
            resultingRevision: 1,
          ),
        );
        expect(
          claims.single.mutation.collection,
          SyncCollection.learnerPreferences,
        );
        expect(claims.single.mutation.entityId, 'current');
        expect(claims.single.mutation.payloadVersion, 1);
        expect(claims.single.mutation.baseRevision, 0);
        expect(claims.single.mutation.localRevision, 1);
        expect(claims.single.mutation.payload, _payload(updatedAtUtcMs: 1000));
      },
    );

    test(
      'same revision different device payloads cannot share a cloud receipt',
      () async {
        final secondDatabase = AppDatabase(NativeDatabase.memory());
        addTearDown(secondDatabase.close);
        await secondDatabase.customStatement(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, is_active, created_at_utc_ms) '
          "VALUES ('local:preferences-device-2', 'firebase-user-1', "
          "'firebaseBound', 1, 1)",
        );
        await secondDatabase.customStatement(
          'INSERT INTO learner_preferences '
          '(owner_id, preference_version, goal, available_minutes_per_day, '
          'activity_preference, updated_at_utc_ms) '
          "VALUES ('local:preferences-device-2', 1, "
          "'conversationConfidence', 30, 'speaking', 1001)",
        );
        await secondDatabase.customStatement(
          'INSERT INTO outbox_operations '
          '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
          'payload_version, base_revision, state, attempt_count, '
          'created_at_utc_ms) VALUES '
          "('learnerPreference:local:preferences-device-2:1', "
          "'local:preferences-device-2', 'learnerPreference', "
          "'local:preferences-device-2', 'upsert', 1, 0, 'pending', 0, 1001)",
        );
        expect(
          await DriftOwnerOperationGate(secondDatabase).tryAcquire(
            token: 'f35-preference-owner-gate-2',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );

        DriftSyncStore store(AppDatabase value) => DriftSyncStore(
          value,
          learnerPreferenceSyncRollout: const LearnerPreferenceSyncRollout.v1(
            deployedRulesRevision: learnerPreferenceV1RulesRevision,
          ),
        );
        final first = await store(database).claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'device-1-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );
        final second = await store(secondDatabase).claimPending(
          ownerId: 'local:preferences-device-2',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'device-2-lease',
          ownerGateToken: 'f35-preference-owner-gate-2',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );

        expect(first, hasLength(1));
        expect(second, hasLength(1));
        expect(
          second.single.mutation.operationId,
          isNot(first.single.mutation.operationId),
        );
        expect(
          first.single.mutation.operationId.length,
          lessThanOrEqualTo(256),
        );
        expect(
          second.single.mutation.operationId.length,
          lessThanOrEqualTo(256),
        );

        final firstStore = store(database);
        expect(
          await firstStore.releaseClaim(
            claim: first.single,
            ownerGateToken: ownerGateToken,
            nowUtc: nowUtc,
          ),
          isTrue,
        );
        final retry = await firstStore.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'device-1-retry-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );
        expect(
          retry.single.mutation.operationId,
          first.single.mutation.operationId,
        );
        expect(retry.single.mutation.payload, first.single.mutation.payload);
      },
    );

    test(
      'two offline edits claim only the latest singleton intent from cloud base',
      () async {
        final repository = DriftLearnerPreferencesRepository(database);
        await repository.save(
          LearnerPreferences(
            ownerId: 'local:preferences',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.vocabularyGrowth,
            availableMinutesPerDay: 25,
            activityPreference: LearnerActivityPreference.vocabulary,
            updatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
          ),
        );
        await repository.save(
          LearnerPreferences(
            ownerId: 'local:preferences',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.conversationConfidence,
            availableMinutesPerDay: 30,
            activityPreference: LearnerActivityPreference.speaking,
            updatedAtUtc: nowUtc.add(const Duration(seconds: 2)),
          ),
        );
        final store = _enabledStore(database);

        final claims = await store.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 2,
          leaseToken: 'latest-only-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc.add(const Duration(seconds: 3)),
        );

        expect(claims, hasLength(1));
        expect(claims.single.mutation.baseRevision, 0);
        expect(claims.single.mutation.localRevision, 1);
        expect(
          claims.single.mutation.payload,
          _payload(
            goal: 'conversationConfidence',
            minutes: 30,
            activity: 'speaking',
            updatedAtUtcMs: nowUtc
                .add(const Duration(seconds: 2))
                .millisecondsSinceEpoch,
          ),
        );
        final states = await database
            .customSelect(
              "SELECT state FROM outbox_operations WHERE entity_type = "
              "'learnerPreference' ORDER BY created_at_utc_ms",
            )
            .get();
        expect(states.map((row) => row.read<String>('state')), [
          'superseded',
          'superseded',
          'inFlight',
        ]);
      },
    );

    test('lost acknowledgement plus newer edit rebases latest intent without '
        'reconstructing the attempted payload', () async {
      final store = _enabledStore(database);
      final firstClaim = (await store.claimPending(
        ownerId: 'local:preferences',
        firebaseUid: 'firebase-user-1',
        limit: 1,
        leaseToken: 'lost-ack-first-lease',
        ownerGateToken: ownerGateToken,
        leaseDuration: const Duration(minutes: 1),
        nowUtc: nowUtc,
      )).single;
      final attempted = await store.beginAttempt(
        claim: firstClaim,
        ownerGateToken: ownerGateToken,
        nowUtc: nowUtc,
      );
      expect(attempted, isNotNull);
      final reserved = attempted!;
      expect(
        await store.markRetry(
          operationId: reserved.localOperationId,
          leaseToken: reserved.leaseToken,
          ownerGateToken: ownerGateToken,
          nowUtc: nowUtc,
          nextAttemptAtUtc: nowUtc.add(const Duration(minutes: 1)),
          failure: const ProviderUnavailableSyncFailure(),
        ),
        isTrue,
      );

      final updatedAt = nowUtc.add(const Duration(seconds: 1));
      await DriftLearnerPreferencesRepository(database).save(
        LearnerPreferences(
          ownerId: 'local:preferences',
          preferenceVersion: 1,
          goal: LearnerPreferenceGoal.conversationConfidence,
          availableMinutesPerDay: 30,
          activityPreference: LearnerActivityPreference.speaking,
          updatedAtUtc: updatedAt,
        ),
      );
      final latestClaim = (await store.claimPending(
        ownerId: 'local:preferences',
        firebaseUid: 'firebase-user-1',
        limit: 1,
        leaseToken: 'lost-ack-latest-lease',
        ownerGateToken: ownerGateToken,
        leaseDuration: const Duration(minutes: 1),
        nowUtc: nowUtc.add(const Duration(minutes: 2)),
      )).single;
      expect(latestClaim.mutation.baseRevision, 0);
      expect(latestClaim.mutation.localRevision, 1);
      expect(
        latestClaim.mutation.payload['updatedAtUtcMs'],
        updatedAt.millisecondsSinceEpoch,
      );
      final attemptedLatest = await store.beginAttempt(
        claim: latestClaim,
        ownerGateToken: ownerGateToken,
        nowUtc: nowUtc.add(const Duration(minutes: 2)),
      );
      expect(attemptedLatest, isNotNull);
      final reservedLatest = attemptedLatest!;

      expect(
        await store.resolvePushConflict(
          claim: reservedLatest,
          ownerGateToken: ownerGateToken,
          cloudEntity: SyncEntity(
            collection: SyncCollection.learnerPreferences,
            entityId: LearnerPreferenceSyncPayloadContract.canonicalEntityId,
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              1000,
              isUtc: true,
            ),
            serverUpdatedAtUtc: nowUtc,
            payload: _payload(updatedAtUtcMs: 1000),
          ),
          resolvedAtUtc: nowUtc.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
      final rebased = (await store.claimPending(
        ownerId: 'local:preferences',
        firebaseUid: 'firebase-user-1',
        limit: 1,
        leaseToken: 'lost-ack-rebased-lease',
        ownerGateToken: ownerGateToken,
        leaseDuration: const Duration(minutes: 1),
        nowUtc: nowUtc.add(const Duration(minutes: 3)),
      )).single;
      expect(
        rebased.localOperationId,
        isNot(reservedLatest.localOperationId),
        reason: 'a changed cloud base is a fresh bounded delivery identity',
      );
      expect(rebased.mutation.baseRevision, 1);
      expect(rebased.mutation.localRevision, 2);
      expect(
        rebased.mutation.payload['updatedAtUtcMs'],
        updatedAt.millisecondsSinceEpoch,
      );
      expect(rebased.mutation.payload['goal'], 'conversationConfidence');

      final oldOperation = await database
          .customSelect(
            'SELECT state FROM outbox_operations WHERE operation_id = ?',
            variables: [Variable<String>(reserved.localOperationId)],
          )
          .getSingle();
      expect(oldOperation.read<String>('state'), 'superseded');
      final operationCounts = await database
          .customSelect(
            "SELECT COUNT(*) AS total, "
            "SUM(CASE WHEN state = 'inFlight' THEN 1 ELSE 0 END) AS active "
            "FROM outbox_operations WHERE entity_type = 'learnerPreference'",
          )
          .getSingle();
      expect(operationCounts.read<int>('total'), 3);
      expect(operationCounts.read<int>('active'), 1);
    });

    test(
      'older singleton pull preserves and rebases a newer retry-waiting intent',
      () async {
        final updatedAt = nowUtc.add(const Duration(seconds: 1));
        await DriftLearnerPreferencesRepository(database).save(
          LearnerPreferences(
            ownerId: 'local:preferences',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.conversationConfidence,
            availableMinutesPerDay: 30,
            activityPreference: LearnerActivityPreference.speaking,
            updatedAtUtc: updatedAt,
          ),
        );
        final store = _enabledStore(database);
        final claim = (await store.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'pull-rebase-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        )).single;
        final attempted = (await store.beginAttempt(
          claim: claim,
          ownerGateToken: ownerGateToken,
          nowUtc: nowUtc,
        ))!;
        final retryAt = nowUtc.add(const Duration(minutes: 2));
        expect(
          await store.markRetry(
            operationId: attempted.localOperationId,
            leaseToken: attempted.leaseToken,
            ownerGateToken: ownerGateToken,
            nowUtc: nowUtc,
            nextAttemptAtUtc: retryAt,
            failure: const ProviderUnavailableSyncFailure(),
          ),
          isTrue,
        );
        final serverTime = nowUtc.add(const Duration(seconds: 2));

        expect(
          await store.applyPullPage(
            ownerId: 'local:preferences',
            collection: SyncCollection.learnerPreferences,
            page: PullPage(
              changes: <SyncEntity>[
                SyncEntity(
                  collection: SyncCollection.learnerPreferences,
                  entityId:
                      LearnerPreferenceSyncPayloadContract.canonicalEntityId,
                  revision: 1,
                  isDeleted: false,
                  payloadVersion: 1,
                  clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                    1000,
                    isUtc: true,
                  ),
                  serverUpdatedAtUtc: serverTime,
                  payload: _payload(updatedAtUtcMs: 1000),
                ),
              ],
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: serverTime,
                documentId:
                    LearnerPreferenceSyncPayloadContract.canonicalEntityId,
              ),
              hasMore: false,
            ),
            ownerGateToken: ownerGateToken,
            nowUtc: nowUtc.add(const Duration(seconds: 2)),
          ),
          isTrue,
        );

        final preference = await database
            .customSelect(
              'SELECT goal, available_minutes_per_day, activity_preference, '
              'updated_at_utc_ms, local_revision, cloud_revision '
              "FROM learner_preferences WHERE owner_id = 'local:preferences'",
            )
            .getSingle();
        expect(preference.read<String>('goal'), 'conversationConfidence');
        expect(preference.read<int>('available_minutes_per_day'), 30);
        expect(preference.read<String>('activity_preference'), 'speaking');
        expect(
          preference.read<int>('updated_at_utc_ms'),
          updatedAt.millisecondsSinceEpoch,
        );
        expect(preference.read<int>('local_revision'), 2);
        expect(preference.read<int>('cloud_revision'), 1);
        expect(
          await store.claimPending(
            ownerId: 'local:preferences',
            firebaseUid: 'firebase-user-1',
            limit: 1,
            leaseToken: 'pull-rebase-too-early',
            ownerGateToken: ownerGateToken,
            leaseDuration: const Duration(minutes: 1),
            nowUtc: retryAt.subtract(const Duration(milliseconds: 1)),
          ),
          isEmpty,
          reason: 'pull rebase must preserve the existing retry backoff',
        );
        final rebased = (await store.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'pull-rebase-due',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: retryAt,
        )).single;
        expect(rebased.localOperationId, isNot(attempted.localOperationId));
        expect(rebased.mutation.baseRevision, 1);
        expect(rebased.mutation.localRevision, 2);
        expect(rebased.mutation.payload['goal'], 'conversationConfidence');
        expect(
          await store.readCheckpoint(
            'local:preferences',
            SyncCollection.learnerPreferences,
          ),
          SyncCursor(
            serverUpdatedAtUtc: serverTime,
            documentId: LearnerPreferenceSyncPayloadContract.canonicalEntityId,
          ),
        );
      },
    );

    test(
      'fresh semantic edit retires an older terminal delivery barrier',
      () async {
        await database.customUpdate(
          "UPDATE outbox_operations SET state = 'permanentFailure', "
          "attempt_count = 5, failure_code = 'providerUnavailable' "
          "WHERE entity_type = 'learnerPreference'",
        );
        final updatedAt = nowUtc.add(const Duration(seconds: 1));
        await DriftLearnerPreferencesRepository(database).save(
          LearnerPreferences(
            ownerId: 'local:preferences',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.vocabularyGrowth,
            availableMinutesPerDay: 25,
            activityPreference: LearnerActivityPreference.vocabulary,
            updatedAtUtc: updatedAt,
          ),
        );

        final claims = await _enabledStore(database).claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'terminal-barrier-new-intent',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc.add(const Duration(seconds: 2)),
        );

        expect(claims, hasLength(1));
        expect(claims.single.mutation.payload['goal'], 'vocabularyGrowth');
        expect(claims.single.mutation.baseRevision, 0);
        expect(claims.single.mutation.localRevision, 1);
        final old = await database
            .customSelect(
              'SELECT state, attempt_count FROM outbox_operations '
              "WHERE operation_id = 'learnerPreference:local:preferences:1'",
            )
            .getSingle();
        expect(old.read<String>('state'), 'superseded');
        expect(old.read<int>('attempt_count'), 5);
      },
    );

    test(
      'fifth-attempt conflict rebase creates a fresh claimable reservation',
      () async {
        final updatedAt = nowUtc.add(const Duration(seconds: 1));
        await DriftLearnerPreferencesRepository(database).save(
          LearnerPreferences(
            ownerId: 'local:preferences',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.conversationConfidence,
            availableMinutesPerDay: 30,
            activityPreference: LearnerActivityPreference.speaking,
            updatedAtUtc: updatedAt,
          ),
        );
        await database.customUpdate(
          "UPDATE outbox_operations SET attempt_count = 4 "
          "WHERE entity_type = 'learnerPreference' AND state = 'pending'",
        );
        final store = _enabledStore(database);
        final claim = (await store.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'fifth-conflict-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc.add(const Duration(seconds: 2)),
        )).single;
        final fifthAttempt = (await store.beginAttempt(
          claim: claim,
          ownerGateToken: ownerGateToken,
          nowUtc: nowUtc.add(const Duration(seconds: 2)),
        ))!;
        expect(fifthAttempt.attemptCount, 5);
        expect(
          await store.resolvePushConflict(
            claim: fifthAttempt,
            ownerGateToken: ownerGateToken,
            cloudEntity: SyncEntity(
              collection: SyncCollection.learnerPreferences,
              entityId: LearnerPreferenceSyncPayloadContract.canonicalEntityId,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                1000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: nowUtc,
              payload: _payload(updatedAtUtcMs: 1000),
            ),
            resolvedAtUtc: nowUtc.add(const Duration(seconds: 2)),
          ),
          isTrue,
        );

        final rebased = (await store.claimPending(
          ownerId: 'local:preferences',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'fresh-rebase-lease',
          ownerGateToken: ownerGateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc.add(const Duration(seconds: 3)),
        )).single;
        expect(rebased.localOperationId, isNot(fifthAttempt.localOperationId));
        expect(rebased.attemptCount, 0);
        expect(rebased.mutation.baseRevision, 1);
        expect(rebased.mutation.localRevision, 2);
        expect(rebased.mutation.payload['goal'], 'conversationConfidence');
        final terminal = await database
            .customSelect(
              'SELECT state, attempt_count FROM outbox_operations '
              'WHERE operation_id = ?',
              variables: [Variable<String>(fifthAttempt.localOperationId)],
            )
            .getSingle();
        expect(terminal.read<String>('state'), 'superseded');
        expect(terminal.read<int>('attempt_count'), 5);
      },
    );

    test(
      'canonical pull updates once without echo and malformed pull rolls back',
      () async {
        final store = DriftSyncStore(
          database,
          learnerPreferenceSyncRollout: const LearnerPreferenceSyncRollout.v1(
            deployedRulesRevision: learnerPreferenceV1RulesRevision,
          ),
        );
        final serverTime = nowUtc.add(const Duration(seconds: 1));
        final page = PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.learnerPreferences,
              entityId: 'current',
              revision: 2,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                2000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: serverTime,
              payload: _payload(
                goal: 'conversationConfidence',
                minutes: 30,
                activity: 'speaking',
                updatedAtUtcMs: 2000,
              ),
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: serverTime,
            documentId: 'current',
          ),
          hasMore: false,
        );

        await store.applyPullPage(
          ownerId: 'local:preferences',
          collection: SyncCollection.learnerPreferences,
          page: page,
          ownerGateToken: ownerGateToken,
          nowUtc: nowUtc,
        );
        await store.applyPullPage(
          ownerId: 'local:preferences',
          collection: SyncCollection.learnerPreferences,
          page: page,
          ownerGateToken: ownerGateToken,
          nowUtc: nowUtc,
        );
        final row = await database
            .customSelect(
              'SELECT goal, available_minutes_per_day, activity_preference, '
              'local_revision, cloud_revision FROM learner_preferences '
              "WHERE owner_id = 'local:preferences'",
            )
            .getSingle();
        expect(row.read<String>('goal'), 'conversationConfidence');
        expect(row.read<int>('available_minutes_per_day'), 30);
        expect(row.read<String>('activity_preference'), 'speaking');
        expect(row.read<int>('local_revision'), 2);
        expect(row.read<int>('cloud_revision'), 2);
        expect(
          await database
              .customSelect(
                "SELECT COUNT(*) AS count FROM outbox_operations "
                "WHERE entity_type = 'learnerPreference'",
              )
              .map((result) => result.read<int>('count'))
              .getSingle(),
          1,
          reason: 'pull replay must not create a preference echo',
        );

        final checkpointBefore = await store.readCheckpoint(
          'local:preferences',
          SyncCollection.learnerPreferences,
        );
        await expectLater(
          store.applyPullPage(
            ownerId: 'local:preferences',
            collection: SyncCollection.learnerPreferences,
            page: PullPage(
              changes: <SyncEntity>[
                SyncEntity(
                  collection: SyncCollection.learnerPreferences,
                  entityId: 'current',
                  revision: 3,
                  isDeleted: false,
                  payloadVersion: 1,
                  clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                    3000,
                    isUtc: true,
                  ),
                  serverUpdatedAtUtc: serverTime.add(
                    const Duration(seconds: 1),
                  ),
                  payload: {
                    ..._payload(updatedAtUtcMs: 3000),
                    'learningStyle': 'visual',
                  },
                ),
              ],
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: serverTime.add(const Duration(seconds: 1)),
                documentId: 'current',
              ),
              hasMore: false,
            ),
            ownerGateToken: ownerGateToken,
            nowUtc: nowUtc,
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
        expect(
          await store.readCheckpoint(
            'local:preferences',
            SyncCollection.learnerPreferences,
          ),
          checkpointBefore,
        );
      },
    );
  });
}

DriftSyncStore _enabledStore(AppDatabase database) => DriftSyncStore(
  database,
  learnerPreferenceSyncRollout: const LearnerPreferenceSyncRollout.v1(
    deployedRulesRevision: learnerPreferenceV1RulesRevision,
  ),
);

Map<String, Object?> _payload({
  String goal = 'examPreparation',
  int minutes = 45,
  String activity = 'quiz',
  required int updatedAtUtcMs,
}) => <String, Object?>{
  'ownerId': 'firebase-user-1',
  'preferenceVersion': 1,
  'goal': goal,
  'availableMinutesPerDay': minutes,
  'activityPreference': activity,
  'updatedAtUtcMs': updatedAtUtcMs,
};
