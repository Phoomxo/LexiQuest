import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../learning/data/drift_learning_projection_rebuilder.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import '../../rewards/domain/reward_models.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_result.dart';
import '../domain/sync_store.dart';
import 'drift_owner_operation_gate.dart';

final class DriftSyncStore implements SyncStore {
  DriftSyncStore(this.database)
    : projections = DriftLearningProjectionRebuilder(database),
      rewardProjections = DriftRewardProjectionRebuilder(database);

  static const int maxClaimLimit = 50;
  static const int maxSendReservations = maxSyncSendReservations;
  static const int _maxCandidateMultiplier = 20;

  final db.AppDatabase database;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;
  Future<void> _claimGate = Future<void>.value();
  var _standalonePullSequence = 0;

  Future<bool> tryAcquireRunLease({
    required String ownerId,
    required String leaseToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) {
    _requiredId(ownerId, 'ownerId');
    return DriftOwnerOperationGate(database).tryAcquire(
      token: leaseToken,
      nowUtc: nowUtc,
      leaseDuration: leaseDuration,
    );
  }

  Future<void> releaseRunLease({
    required String ownerId,
    required String leaseToken,
  }) {
    _requiredId(ownerId, 'ownerId');
    return DriftOwnerOperationGate(database).release(token: leaseToken);
  }

  Future<int> requeuePermissionDeniedFailures({
    required String ownerId,
    required DateTime nowUtc,
  }) {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    _requireUtc(nowUtc, 'nowUtc');
    return database.customUpdate(
      '''
      UPDATE outbox_operations
      SET state = 'retryWaiting',
          next_attempt_at_utc_ms = ?,
          lease_token = NULL,
          lease_expires_at_utc_ms = NULL,
          failure_code = NULL
      WHERE owner_id = ?
        AND state = 'permanentFailure'
        AND failure_code = ?
      ''',
      variables: [
        Variable<int>(nowUtc.millisecondsSinceEpoch),
        Variable<String>(canonicalOwnerId),
        Variable<String>(SyncFailureCode.permissionDenied.name),
      ],
      updates: {database.outboxOperations},
    );
  }

  @override
  Future<List<ClaimedSyncOperation>> claimPending({
    required String ownerId,
    required String firebaseUid,
    required int limit,
    required String leaseToken,
    required String ownerGateToken,
    required Duration leaseDuration,
    required DateTime nowUtc,
  }) {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    final canonicalUid = _requiredId(firebaseUid, 'firebaseUid');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    if (limit < 1 || limit > maxClaimLimit) {
      throw RangeError.range(limit, 1, maxClaimLimit, 'limit');
    }
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError.value(
        leaseDuration,
        'leaseDuration',
        'must be positive',
      );
    }
    _requireUtc(nowUtc, 'nowUtc');

    return _serializeClaim(() {
      return database.transaction(() async {
        final nowMs = nowUtc.millisecondsSinceEpoch;
        final fenced = await database.customUpdate(
          '''
          UPDATE runtime_flags
          SET updated_at_utc_ms = updated_at_utc_ms
          WHERE "key" = ?
            AND bool_value = 1
            AND source = ?
            AND expires_at_utc_ms IS NOT NULL
            AND expires_at_utc_ms > ?
          ''',
          variables: [
            const Variable<String>(DriftOwnerOperationGate.gateKey),
            Variable<String>(canonicalOwnerGateToken),
            Variable<int>(nowMs),
          ],
          updates: {database.runtimeFlags},
        );
        if (fenced != 1) return const <ClaimedSyncOperation>[];
        final candidateLimit = limit * _maxCandidateMultiplier;
        final query = database.select(database.outboxOperations)
          ..where(
            (row) =>
                row.ownerId.equals(canonicalOwnerId) &
                row.attemptCount.isSmallerThanValue(maxSendReservations) &
                (row.state.equals('pending') |
                    (row.state.equals('retryWaiting') &
                        (row.nextAttemptAtUtcMs.isNull() |
                            row.nextAttemptAtUtcMs.isSmallerOrEqualValue(
                              nowMs,
                            ))) |
                    (row.state.equals('inFlight') &
                        row.leaseExpiresAtUtcMs.isNotNull() &
                        row.leaseExpiresAtUtcMs.isSmallerOrEqualValue(nowMs))),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.createdAtUtcMs),
            (row) => OrderingTerm.asc(row.operationId),
          ])
          ..limit(candidateLimit);
        final candidates = await query.get();
        if (candidates.isEmpty) return const <ClaimedSyncOperation>[];

        final groups = <String, List<db.OutboxOperation>>{};
        for (final candidate in candidates) {
          final key = '${candidate.entityType}\u001f${candidate.entityId}';
          groups.putIfAbsent(key, () => <db.OutboxOperation>[]).add(candidate);
        }

        final selectedGroups = groups.values.take(limit);
        final claimed = <ClaimedSyncOperation>[];
        for (final group in selectedGroups) {
          group.sort((left, right) {
            final time = left.createdAtUtcMs.compareTo(right.createdAtUtcMs);
            return time != 0
                ? time
                : left.operationId.compareTo(right.operationId);
          });
          final selected = group.last;
          final baseRevision = group
              .map((row) => row.baseRevision)
              .reduce((left, right) => left < right ? left : right);

          for (final superseded in group.take(group.length - 1)) {
            await (database.update(database.outboxOperations)..where(
                  (row) => row.operationId.equals(superseded.operationId),
                ))
                .write(
                  const db.OutboxOperationsCompanion(
                    state: Value('superseded'),
                    failureCode: Value('coalesced'),
                    leaseToken: Value(null),
                    leaseExpiresAtUtcMs: Value(null),
                  ),
                );
          }

          await (database.update(database.outboxOperations)
                ..where((row) => row.operationId.equals(selected.operationId)))
              .write(
                db.OutboxOperationsCompanion(
                  state: const Value('inFlight'),
                  baseRevision: Value(baseRevision),
                  leaseToken: Value(canonicalLeaseToken),
                  leaseExpiresAtUtcMs: Value(
                    nowUtc.add(leaseDuration).millisecondsSinceEpoch,
                  ),
                ),
              );

          claimed.add(
            ClaimedSyncOperation(
              leaseToken: canonicalLeaseToken,
              attemptCount: selected.attemptCount,
              releaseState: _releaseStateFor(selected),
              mutation: await _reconstructMutation(
                selected,
                firebaseUid: canonicalUid,
                baseRevision: baseRevision,
              ),
            ),
          );
        }
        return List<ClaimedSyncOperation>.unmodifiable(claimed);
      });
    });
  }

  @override
  Future<ClaimedSyncOperation?> beginAttempt({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  }) {
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    _requireUtc(nowUtc, 'nowUtc');
    return database.transaction(() async {
      final operation =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals(claim.mutation.operationId),
              ))
              .getSingleOrNull();
      if (operation == null ||
          operation.state != 'inFlight' ||
          operation.leaseToken != claim.leaseToken ||
          operation.attemptCount >= maxSendReservations) {
        return null;
      }
      final reservedCount = operation.attemptCount + 1;
      final changed = await database.customUpdate(
        '''
        UPDATE outbox_operations
        SET attempt_count = ?, last_attempt_at_utc_ms = ?
        WHERE operation_id = ?
          AND state = 'inFlight'
          AND lease_token = ?
          AND attempt_count = ?
          AND EXISTS (
            SELECT 1 FROM runtime_flags
            WHERE "key" = ?
              AND bool_value = 1
              AND source = ?
              AND expires_at_utc_ms IS NOT NULL
              AND expires_at_utc_ms > ?
          )
        ''',
        variables: [
          Variable<int>(reservedCount),
          Variable<int>(nowUtc.millisecondsSinceEpoch),
          Variable<String>(operation.operationId),
          Variable<String>(claim.leaseToken),
          Variable<int>(operation.attemptCount),
          const Variable<String>(DriftOwnerOperationGate.gateKey),
          Variable<String>(canonicalOwnerGateToken),
          Variable<int>(nowUtc.millisecondsSinceEpoch),
        ],
        updates: {database.outboxOperations},
      );
      if (changed != 1) return null;
      return ClaimedSyncOperation(
        leaseToken: claim.leaseToken,
        attemptCount: reservedCount,
        releaseState: claim.releaseState,
        mutation: claim.mutation,
      );
    });
  }

  @override
  Future<bool> releaseClaim({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  }) async {
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    _requireUtc(nowUtc, 'nowUtc');
    final changed = await database.customUpdate(
      '''
      UPDATE outbox_operations
      SET state = ?, lease_token = NULL, lease_expires_at_utc_ms = NULL
      WHERE operation_id = ?
        AND state = 'inFlight'
        AND lease_token = ?
        AND EXISTS (
          SELECT 1 FROM runtime_flags
          WHERE "key" = ?
            AND bool_value = 1
            AND source = ?
            AND expires_at_utc_ms IS NOT NULL
            AND expires_at_utc_ms > ?
        )
      ''',
      variables: [
        Variable<String>(claim.releaseState),
        Variable<String>(claim.mutation.operationId),
        Variable<String>(claim.leaseToken),
        const Variable<String>(DriftOwnerOperationGate.gateKey),
        Variable<String>(canonicalOwnerGateToken),
        Variable<int>(nowUtc.millisecondsSinceEpoch),
      ],
      updates: {database.outboxOperations},
    );
    return changed == 1;
  }

  @override
  Future<bool> acknowledge({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required PushAcknowledged acknowledgement,
  }) async {
    final canonicalOperationId = _requiredId(operationId, 'operationId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    _requireUtc(nowUtc, 'nowUtc');
    if (acknowledgement.operationId != canonicalOperationId) {
      throw ArgumentError.value(
        acknowledgement.operationId,
        'acknowledgement.operationId',
        'must match operationId',
      );
    }

    return database.transaction(() async {
      final operation =
          await (database.select(database.outboxOperations)
                ..where((row) => row.operationId.equals(canonicalOperationId)))
              .getSingleOrNull();
      if (operation == null) {
        return false;
      }
      if (!await _isOwnerGateOwned(canonicalOwnerGateToken, nowUtc)) {
        return false;
      }
      if (operation.state == 'acknowledged') return true;
      if (operation.state != 'inFlight' ||
          operation.leaseToken != canonicalLeaseToken) {
        return false;
      }

      final changed = await database.customUpdate(
        '''
        UPDATE outbox_operations
        SET state = 'acknowledged',
            acknowledged_at_utc_ms = ?,
            next_attempt_at_utc_ms = NULL,
            lease_token = NULL,
            lease_expires_at_utc_ms = NULL,
            failure_code = NULL
        WHERE operation_id = ?
          AND state = 'inFlight'
          AND lease_token = ?
          AND EXISTS (
            SELECT 1 FROM runtime_flags
            WHERE "key" = ?
              AND bool_value = 1
              AND source = ?
              AND expires_at_utc_ms IS NOT NULL
              AND expires_at_utc_ms > ?
          )
        ''',
        variables: [
          Variable<int>(
            acknowledgement.acknowledgedAtUtc.millisecondsSinceEpoch,
          ),
          Variable<String>(canonicalOperationId),
          Variable<String>(canonicalLeaseToken),
          const Variable<String>(DriftOwnerOperationGate.gateKey),
          Variable<String>(canonicalOwnerGateToken),
          Variable<int>(nowUtc.millisecondsSinceEpoch),
        ],
        updates: {database.outboxOperations},
      );
      if (changed != 1) return false;
      await _acknowledgeEntity(operation, acknowledgement);
      return true;
    });
  }

  Future<bool> _isOwnerGateOwned(String token, DateTime nowUtc) async {
    final row = await database
        .customSelect(
          '''
      SELECT 1 AS owned
      FROM runtime_flags
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      LIMIT 1
      ''',
          variables: [
            const Variable<String>(DriftOwnerOperationGate.gateKey),
            Variable<String>(token),
            Variable<int>(nowUtc.millisecondsSinceEpoch),
          ],
          readsFrom: {database.runtimeFlags},
        )
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<bool> markRetry({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required DateTime nextAttemptAtUtc,
    required SyncFailure failure,
  }) async {
    final canonicalOperationId = _requiredId(operationId, 'operationId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    _requireUtc(nowUtc, 'nowUtc');
    _requireUtc(nextAttemptAtUtc, 'nextAttemptAtUtc');
    if (!failure.retryable) {
      throw ArgumentError.value(failure, 'failure', 'must be retryable');
    }

    final operation =
        await (database.select(database.outboxOperations)
              ..where((row) => row.operationId.equals(canonicalOperationId)))
            .getSingleOrNull();
    if (operation == null ||
        operation.state != 'inFlight' ||
        operation.leaseToken != canonicalLeaseToken) {
      return false;
    }
    final exhausted = operation.attemptCount >= maxSendReservations;
    final changed = await database.customUpdate(
      '''
      UPDATE outbox_operations
      SET state = ?,
          next_attempt_at_utc_ms = ?,
          lease_token = NULL,
          lease_expires_at_utc_ms = NULL,
          failure_code = ?
      WHERE operation_id = ?
        AND state = 'inFlight'
        AND lease_token = ?
        AND EXISTS (
          SELECT 1 FROM runtime_flags
          WHERE "key" = ?
            AND bool_value = 1
            AND source = ?
            AND expires_at_utc_ms IS NOT NULL
            AND expires_at_utc_ms > ?
        )
      ''',
      variables: [
        Variable<String>(exhausted ? 'permanentFailure' : 'retryWaiting'),
        Variable<int>(
          exhausted ? null : nextAttemptAtUtc.millisecondsSinceEpoch,
        ),
        Variable<String>(failure.code.name),
        Variable<String>(canonicalOperationId),
        Variable<String>(canonicalLeaseToken),
        const Variable<String>(DriftOwnerOperationGate.gateKey),
        Variable<String>(canonicalOwnerGateToken),
        Variable<int>(nowUtc.millisecondsSinceEpoch),
      ],
      updates: {database.outboxOperations},
    );
    return changed == 1;
  }

  @override
  Future<bool> markTerminalFailure({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required SyncFailure failure,
  }) async {
    final canonicalOperationId = _requiredId(operationId, 'operationId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    _requireUtc(nowUtc, 'nowUtc');
    if (failure.retryable) {
      throw ArgumentError.value(failure, 'failure', 'must not be retryable');
    }
    final operation =
        await (database.select(database.outboxOperations)
              ..where((row) => row.operationId.equals(canonicalOperationId)))
            .getSingleOrNull();
    if (operation == null ||
        operation.state != 'inFlight' ||
        operation.leaseToken != canonicalLeaseToken) {
      return false;
    }
    final state = failure is UnauthenticatedSyncFailure
        ? 'blockedAuth'
        : 'permanentFailure';
    final changed = await database.customUpdate(
      '''
      UPDATE outbox_operations
      SET state = ?,
          next_attempt_at_utc_ms = NULL,
          lease_token = NULL,
          lease_expires_at_utc_ms = NULL,
          failure_code = ?
      WHERE operation_id = ?
        AND state = 'inFlight'
        AND lease_token = ?
        AND EXISTS (
          SELECT 1 FROM runtime_flags
          WHERE "key" = ?
            AND bool_value = 1
            AND source = ?
            AND expires_at_utc_ms IS NOT NULL
            AND expires_at_utc_ms > ?
        )
      ''',
      variables: [
        Variable<String>(state),
        Variable<String>(failure.code.name),
        Variable<String>(canonicalOperationId),
        Variable<String>(canonicalLeaseToken),
        const Variable<String>(DriftOwnerOperationGate.gateKey),
        Variable<String>(canonicalOwnerGateToken),
        Variable<int>(nowUtc.millisecondsSinceEpoch),
      ],
      updates: {database.outboxOperations},
    );
    return changed == 1;
  }

  @override
  Future<bool> resolvePushConflict({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required SyncEntity cloudEntity,
    required DateTime resolvedAtUtc,
  }) async {
    final canonicalOwnerGateToken = _requiredId(
      ownerGateToken,
      'ownerGateToken',
    );
    _requireUtc(resolvedAtUtc, 'resolvedAtUtc');
    final mutation = claim.mutation;
    if (mutation.collection != cloudEntity.collection ||
        mutation.entityId != cloudEntity.entityId) {
      throw ArgumentError.value(
        cloudEntity.entityId,
        'cloudEntity',
        'must identify the claimed entity',
      );
    }

    return database.transaction(() async {
      final fenced = await database.customUpdate(
        '''
        UPDATE runtime_flags
        SET updated_at_utc_ms = updated_at_utc_ms
        WHERE "key" = ?
          AND bool_value = 1
          AND source = ?
          AND expires_at_utc_ms IS NOT NULL
          AND expires_at_utc_ms > ?
        ''',
        variables: [
          const Variable<String>(DriftOwnerOperationGate.gateKey),
          Variable<String>(canonicalOwnerGateToken),
          Variable<int>(resolvedAtUtc.millisecondsSinceEpoch),
        ],
        updates: {database.runtimeFlags},
      );
      if (fenced != 1) return false;
      final operation =
          await (database.select(database.outboxOperations)
                ..where((row) => row.operationId.equals(mutation.operationId)))
              .getSingleOrNull();
      if (operation == null ||
          operation.state != 'inFlight' ||
          operation.leaseToken != claim.leaseToken) {
        return false;
      }
      if (cloudEntity.collection == SyncCollection.attempts ||
          cloudEntity.collection == SyncCollection.readingEvents ||
          cloudEntity.collection == SyncCollection.rewardTransactions ||
          cloudEntity.collection == SyncCollection.achievementUnlocks) {
        await _resolveImmutableConflict(
          operation: operation,
          cloudEntity: cloudEntity,
          resolvedAtUtc: resolvedAtUtc,
        );
        return true;
      }

      final localSnapshot = await _localSnapshot(operation);
      final cloudSnapshot = <String, Object?>{
        'collection': cloudEntity.collection.wireName,
        'entityId': cloudEntity.entityId,
        'revision': cloudEntity.revision,
        'isDeleted': cloudEntity.isDeleted,
        'payloadVersion': cloudEntity.payloadVersion,
        'clientUpdatedAtUtcMs':
            cloudEntity.clientUpdatedAtUtc.millisecondsSinceEpoch,
        'serverUpdatedAtUtcMicros':
            cloudEntity.serverUpdatedAtUtc.microsecondsSinceEpoch,
        'payload': cloudEntity.payload,
      };
      await database
          .into(database.syncConflicts)
          .insert(
            db.SyncConflictsCompanion.insert(
              id: 'conflict:${operation.operationId}:${cloudEntity.revision}',
              ownerId: operation.ownerId,
              entityType: operation.entityType,
              entityId: operation.entityId,
              localRevision: mutation.localRevision,
              cloudRevision: cloudEntity.revision,
              resolutionPolicy: 'highestAcknowledgedRevision',
              outcome: 'cloudWins',
              localSnapshotJson: Value(jsonEncode(localSnapshot)),
              cloudSnapshotJson: Value(jsonEncode(cloudSnapshot)),
              resolvedAtUtcMs: resolvedAtUtc.millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      switch (cloudEntity.collection) {
        case SyncCollection.categories:
          await _applyCategory(
            operation.ownerId,
            cloudEntity,
            handlePendingConflict: false,
          );
        case SyncCollection.words:
          await _applyWord(
            operation.ownerId,
            cloudEntity,
            handlePendingConflict: false,
          );
        case SyncCollection.attempts:
        case SyncCollection.readingEvents:
        case SyncCollection.rewardTransactions:
        case SyncCollection.achievementUnlocks:
          throw const InvalidSyncPayloadFailure();
        case SyncCollection.srsStates:
          // SRS states are last-write-wins; apply server state directly.
          await _applySrsState(operation.ownerId, cloudEntity);
      }
      await (database.update(
        database.outboxOperations,
      )..where((row) => row.operationId.equals(operation.operationId))).write(
        const db.OutboxOperationsCompanion(
          state: Value('conflictResolved'),
          leaseToken: Value(null),
          leaseExpiresAtUtcMs: Value(null),
          nextAttemptAtUtcMs: Value(null),
          failureCode: Value('cloudWins'),
        ),
      );
      return true;
    });
  }

  @override
  Future<SyncCursor?> readCheckpoint(
    String ownerId,
    SyncCollection collection,
  ) async {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    final row =
        await (database.select(database.syncCheckpoints)..where(
              (candidate) =>
                  candidate.ownerId.equals(canonicalOwnerId) &
                  candidate.collectionName.equals(collection.wireName),
            ))
            .getSingleOrNull();
    final cursor = row?.serverCursor;
    return cursor == null ? null : SyncCursor.parse(cursor);
  }

  @override
  Future<bool> applyPullPage({
    required String ownerId,
    required SyncCollection collection,
    required PullPage page,
    String? ownerGateToken,
    DateTime? nowUtc,
  }) async {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    final effectiveNowUtc = nowUtc ?? DateTime.now().toUtc();
    final standaloneToken = ownerGateToken == null
        ? 'standalone-pull:${identityHashCode(this)}:${_standalonePullSequence++}'
        : null;
    final effectiveOwnerGateToken = ownerGateToken ?? standaloneToken!;
    final canonicalOwnerGateToken = _requiredId(
      effectiveOwnerGateToken,
      'ownerGateToken',
    );
    _requireUtc(effectiveNowUtc, 'nowUtc');
    if (standaloneToken != null &&
        !await DriftOwnerOperationGate(database).tryAcquire(
          token: standaloneToken,
          nowUtc: effectiveNowUtc,
          leaseDuration: const Duration(minutes: 1),
        )) {
      return false;
    }
    try {
      return await database.transaction(() async {
        final fenced = await database.customUpdate(
          '''
        UPDATE runtime_flags
        SET updated_at_utc_ms = updated_at_utc_ms
        WHERE "key" = ?
          AND bool_value = 1
          AND source = ?
          AND expires_at_utc_ms IS NOT NULL
          AND expires_at_utc_ms > ?
        ''',
          variables: [
            const Variable<String>(DriftOwnerOperationGate.gateKey),
            Variable<String>(canonicalOwnerGateToken),
            Variable<int>(effectiveNowUtc.millisecondsSinceEpoch),
          ],
          updates: {database.runtimeFlags},
        );
        if (fenced != 1) return false;
        final cursor = page.nextCursor;
        if (page.hasMore && cursor == null) {
          throw const InvalidSyncCursorFailure();
        }
        final checkpoint =
            await (database.select(database.syncCheckpoints)..where(
                  (candidate) =>
                      candidate.ownerId.equals(canonicalOwnerId) &
                      candidate.collectionName.equals(collection.wireName),
                ))
                .getSingleOrNull();
        final storedCursor = checkpoint?.serverCursor;
        if (cursor != null && storedCursor != null) {
          final cursorComparison = _compareCursors(
            cursor,
            SyncCursor.parse(storedCursor),
          );
          if (cursorComparison < 0) {
            throw const InvalidSyncCursorFailure();
          }
          if (cursorComparison == 0) {
            if (page.hasMore) throw const InvalidSyncCursorFailure();
            return true;
          }
        }

        for (final entity in page.changes) {
          if (entity.collection != collection) {
            throw const InvalidSyncPayloadFailure();
          }
          switch (collection) {
            case SyncCollection.categories:
              await _applyCategory(canonicalOwnerId, entity);
            case SyncCollection.words:
              await _applyWord(canonicalOwnerId, entity);
            case SyncCollection.attempts:
              await _applyAttempt(canonicalOwnerId, entity);
            case SyncCollection.readingEvents:
              await _applyReadingEvent(canonicalOwnerId, entity);
            case SyncCollection.rewardTransactions:
              await _applyRewardTransaction(canonicalOwnerId, entity);
            case SyncCollection.srsStates:
              await _applySrsState(canonicalOwnerId, entity);
            case SyncCollection.achievementUnlocks:
              await _applyAchievementUnlock(canonicalOwnerId, entity);
          }
        }

        if (cursor != null) {
          await database
              .into(database.syncCheckpoints)
              .insertOnConflictUpdate(
                db.SyncCheckpointsCompanion.insert(
                  id: '$canonicalOwnerId:${collection.wireName}',
                  ownerId: canonicalOwnerId,
                  collectionName: collection.wireName,
                  serverCursor: Value(cursor.toJsonString()),
                  lastSuccessAtUtcMs: Value(
                    cursor.serverUpdatedAtUtc.millisecondsSinceEpoch,
                  ),
                ),
              );
        }
        return true;
      });
    } finally {
      if (standaloneToken != null) {
        await DriftOwnerOperationGate(database).release(token: standaloneToken);
      }
    }
  }

  Future<T> _serializeClaim<T>(Future<T> Function() operation) async {
    final previous = _claimGate;
    final completer = Completer<void>();
    _claimGate = completer.future;
    try {
      await previous;
      return await operation();
    } finally {
      completer.complete();
    }
  }

  Future<PushMutation> _reconstructMutation(
    db.OutboxOperation operation, {
    required String firebaseUid,
    required int baseRevision,
  }) async {
    switch (operation.entityType) {
      case 'category':
        final category =
            await (database.select(database.vocabularyCategories)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (category == null) {
          throw StateError('outbox category was not found');
        }
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.categories,
          entityId: category.id,
          operationKind: _operationKind(operation.operationKind),
          payloadVersion: operation.payloadVersion,
          baseRevision: baseRevision,
          localRevision: category.localRevision,
          clientUpdatedAtUtc: _utc(category.updatedAtUtcMs),
          payload: <String, Object?>{
            'name': category.name,
            'normalizedName': category.normalizedName,
            'sortOrder': category.sortOrder,
            'isDeleted': category.isDeleted,
            'createdAtUtcMs': category.createdAtUtcMs,
            'updatedAtUtcMs': category.updatedAtUtcMs,
          },
        );
      case 'word':
        final word =
            await (database.select(database.vocabularyWords)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (word == null) {
          throw StateError('outbox word was not found');
        }
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.words,
          entityId: word.id,
          operationKind: _operationKind(operation.operationKind),
          payloadVersion: operation.payloadVersion,
          baseRevision: baseRevision,
          localRevision: word.localRevision,
          clientUpdatedAtUtc: _utc(word.updatedAtUtcMs),
          payload: <String, Object?>{
            'categoryId': word.categoryId,
            'spelling': word.spelling,
            'normalizedSpelling': word.normalizedSpelling,
            'meaning': word.meaning,
            'normalizedMeaning': word.normalizedMeaning,
            'partOfSpeech': word.partOfSpeech,
            'cefrLevel': word.cefrLevel,
            'source': word.source,
            'isGlobal': word.isGlobal,
            'isDeleted': word.isDeleted,
            'createdAtUtcMs': word.createdAtUtcMs,
            'updatedAtUtcMs': word.updatedAtUtcMs,
          },
        );
      case 'attempt':
        final attempt =
            await (database.select(database.answerAttempts)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (attempt == null) {
          throw StateError('outbox attempt was not found');
        }
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.attempts,
          entityId: attempt.id,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: operation.payloadVersion,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: _utc(attempt.occurredAtUtcMs),
          payload: <String, Object?>{
            'sessionId': attempt.sessionId,
            'wordId': attempt.wordId,
            'promptMode': attempt.promptMode,
            'isCorrect': attempt.isCorrect,
            'responseTimeMs': attempt.responseTimeMs,
            'attemptNumber': attempt.attemptNumber,
            'occurredAtUtcMs': attempt.occurredAtUtcMs,
            'providerProvenance': attempt.providerProvenance,
          },
        );
      case 'readingEvent':
        final event =
            await (database.select(database.readingEvents)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (event == null) {
          throw StateError('outbox reading event was not found');
        }
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.readingEvents,
          entityId: event.id,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: operation.payloadVersion,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: _utc(event.occurredAtUtcMs),
          payload: <String, Object?>{
            'documentId': event.documentId,
            'documentRevision': event.documentRevision,
            'eventType': event.eventType,
            'position': event.position,
            'occurredAtUtcMs': event.occurredAtUtcMs,
          },
        );
      case 'rewardTransaction':
        final transaction =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (transaction == null) {
          throw StateError('outbox reward transaction was not found');
        }
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.rewardTransactions,
          entityId: transaction.id,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: operation.payloadVersion,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: _utc(transaction.occurredAtUtcMs),
          payload: _rewardTransactionPayload(transaction),
        );
      case 'srsState':
        // Entity ID for srsState outbox is the wordId (unique per owner-word).
        final srs =
            await (database.select(database.srsStates)..where(
                  (row) =>
                      row.wordId.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (srs == null) throw StateError('outbox srsState was not found');
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.srsStates,
          entityId: srs.wordId, // stable entity identifier
          operationKind: SyncOperationKind.upsert,
          payloadVersion: operation.payloadVersion,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: srs.lastReviewAtUtcMs != null
              ? _utc(srs.lastReviewAtUtcMs!)
              : DateTime.fromMillisecondsSinceEpoch(
                  operation.createdAtUtcMs,
                  isUtc: true,
                ),
          payload: _srsStatePayload(srs),
        );
      case 'achievementUnlock':
        final unlock =
            await (database.select(database.achievementUnlocks)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (unlock == null) {
          throw StateError('outbox achievementUnlock was not found');
        }
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.achievementUnlocks,
          entityId: unlock.id,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: operation.payloadVersion,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: _utc(unlock.unlockedAtUtcMs),
          payload: _achievementUnlockPayload(unlock),
        );
      default:
        throw const InvalidSyncPayloadFailure();
    }
  }

  Future<void> _acknowledgeEntity(
    db.OutboxOperation operation,
    PushAcknowledged acknowledgement,
  ) async {
    final acknowledgedMs =
        acknowledgement.acknowledgedAtUtc.millisecondsSinceEpoch;
    switch (operation.entityType) {
      case 'category':
        await (database.update(database.vocabularyCategories)..where(
              (row) =>
                  row.id.equals(operation.entityId) &
                  row.ownerId.equals(operation.ownerId),
            ))
            .write(
              db.VocabularyCategoriesCompanion(
                cloudRevision: Value(acknowledgement.resultingRevision),
                lastAcknowledgedAtUtcMs: Value(acknowledgedMs),
                serverUpdatedAtUtcMs: Value(acknowledgedMs),
              ),
            );
      case 'word':
        await (database.update(database.vocabularyWords)..where(
              (row) =>
                  row.id.equals(operation.entityId) &
                  row.ownerId.equals(operation.ownerId),
            ))
            .write(
              db.VocabularyWordsCompanion(
                cloudRevision: Value(acknowledgement.resultingRevision),
                lastAcknowledgedAtUtcMs: Value(acknowledgedMs),
                serverUpdatedAtUtcMs: Value(acknowledgedMs),
              ),
            );
      case 'attempt':
      case 'readingEvent':
      case 'rewardTransaction':
        // Immutable evidence has no mutable cloud revision columns. The
        // acknowledged outbox row is the durable local receipt.
        return;
      case 'srsState':
        // SRS states are last-write-wins; no cloud revision columns.
        return;
      case 'achievementUnlock':
        // Immutable unlock; no revision tracking needed.
        return;
      default:
        throw const InvalidSyncPayloadFailure();
    }
  }

  Future<Map<String, Object?>> _localSnapshot(
    db.OutboxOperation operation,
  ) async {
    switch (operation.entityType) {
      case 'category':
        final category =
            await (database.select(database.vocabularyCategories)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return <String, Object?>{
          'entityId': category.id,
          'localRevision': category.localRevision,
          'cloudRevision': category.cloudRevision,
          'name': category.name,
          'normalizedName': category.normalizedName,
          'sortOrder': category.sortOrder,
          'isDeleted': category.isDeleted,
          'updatedAtUtcMs': category.updatedAtUtcMs,
        };
      case 'word':
        final word =
            await (database.select(database.vocabularyWords)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return <String, Object?>{
          'entityId': word.id,
          'localRevision': word.localRevision,
          'cloudRevision': word.cloudRevision,
          'categoryId': word.categoryId,
          'spelling': word.spelling,
          'meaning': word.meaning,
          'partOfSpeech': word.partOfSpeech,
          'isDeleted': word.isDeleted,
          'updatedAtUtcMs': word.updatedAtUtcMs,
        };
      case 'attempt':
        final attempt =
            await (database.select(database.answerAttempts)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return _attemptPayload(attempt);
      case 'readingEvent':
        final event =
            await (database.select(database.readingEvents)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return _readingEventPayload(event);
      case 'rewardTransaction':
        final transaction =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return _rewardTransactionPayload(transaction);
      case 'srsState':
        final srs =
            await (database.select(database.srsStates)..where(
                  (row) =>
                      row.wordId.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return _srsStatePayload(srs);
      case 'achievementUnlock':
        final unlock =
            await (database.select(database.achievementUnlocks)..where(
                  (row) =>
                      row.id.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingle();
        return _achievementUnlockPayload(unlock);
      default:
        throw const InvalidSyncPayloadFailure();
    }
  }

  Future<void> _applyCategory(
    String ownerId,
    SyncEntity entity, {
    bool handlePendingConflict = true,
  }) async {
    if (handlePendingConflict && !await _preparePullApply(ownerId, entity)) {
      return;
    }
    final payload = entity.payload;
    final name = _requiredString(payload, 'name');
    final normalizedName =
        _optionalString(payload, 'normalizedName') ?? name.toLowerCase();
    final createdAtUtcMs =
        _optionalInt(payload, 'createdAtUtcMs') ??
        entity.clientUpdatedAtUtc.millisecondsSinceEpoch;
    await database
        .into(database.vocabularyCategories)
        .insertOnConflictUpdate(
          db.VocabularyCategoriesCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            name: name,
            normalizedName: normalizedName,
            sortOrder: Value(_optionalInt(payload, 'sortOrder') ?? 0),
            localRevision: Value(entity.revision),
            cloudRevision: Value(entity.revision),
            lastAcknowledgedAtUtcMs: Value(
              entity.serverUpdatedAtUtc.millisecondsSinceEpoch,
            ),
            serverUpdatedAtUtcMs: Value(
              entity.serverUpdatedAtUtc.millisecondsSinceEpoch,
            ),
            isDeleted: Value(entity.isDeleted),
            createdAtUtcMs: createdAtUtcMs,
            updatedAtUtcMs: entity.clientUpdatedAtUtc.millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> _applyWord(
    String ownerId,
    SyncEntity entity, {
    bool handlePendingConflict = true,
  }) async {
    if (handlePendingConflict && !await _preparePullApply(ownerId, entity)) {
      return;
    }
    final payload = entity.payload;
    final spelling = _requiredString(payload, 'spelling');
    final meaning = _requiredString(payload, 'meaning');
    final createdAtUtcMs =
        _optionalInt(payload, 'createdAtUtcMs') ??
        entity.clientUpdatedAtUtc.millisecondsSinceEpoch;
    await database
        .into(database.vocabularyWords)
        .insertOnConflictUpdate(
          db.VocabularyWordsCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            categoryId: _requiredString(payload, 'categoryId'),
            spelling: spelling,
            normalizedSpelling:
                _optionalString(payload, 'normalizedSpelling') ??
                spelling.toLowerCase(),
            meaning: meaning,
            normalizedMeaning:
                _optionalString(payload, 'normalizedMeaning') ??
                meaning.toLowerCase(),
            partOfSpeech: _requiredString(payload, 'partOfSpeech'),
            cefrLevel: Value(_optionalString(payload, 'cefrLevel')),
            source: Value(_optionalString(payload, 'source') ?? 'manual'),
            isGlobal: Value(_optionalBool(payload, 'isGlobal') ?? false),
            localRevision: Value(entity.revision),
            cloudRevision: Value(entity.revision),
            lastAcknowledgedAtUtcMs: Value(
              entity.serverUpdatedAtUtc.millisecondsSinceEpoch,
            ),
            serverUpdatedAtUtcMs: Value(
              entity.serverUpdatedAtUtc.millisecondsSinceEpoch,
            ),
            isDeleted: Value(entity.isDeleted),
            createdAtUtcMs: createdAtUtcMs,
            updatedAtUtcMs: entity.clientUpdatedAtUtc.millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> _applyAttempt(String ownerId, SyncEntity entity) async {
    _requireImmutableEntity(entity, SyncCollection.attempts);
    final existing =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.id.equals(entity.entityId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await _handleExistingImmutable(
        ownerId: ownerId,
        entity: entity,
        localPayload: _attemptPayload(existing),
      );
      await projections.rebuildWord(ownerId: ownerId, wordId: existing.wordId);
      await projections.rebuildSession(
        ownerId: ownerId,
        sessionId: existing.sessionId,
      );
      await projections.rebuildAchievements(ownerId);
      await rewardProjections.rebuild(ownerId);
      return;
    }
    final payload = entity.payload;
    final sessionId = _requiredString(payload, 'sessionId');
    final wordId = _requiredString(payload, 'wordId');
    final promptMode = _requiredString(payload, 'promptMode');
    final responseTimeMs = _optionalInt(payload, 'responseTimeMs');
    final attemptNumber = _requiredInt(payload, 'attemptNumber');
    final occurredAtUtcMs = _requiredInt(payload, 'occurredAtUtcMs');
    final providerProvenance = _optionalString(payload, 'providerProvenance');
    if (!LearningEvidenceContract.validAttempt(
      id: entity.entityId,
      ownerId: ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      occurredAtUtcMs: occurredAtUtcMs,
      providerProvenance: providerProvenance,
    )) {
      throw const InvalidSyncPayloadFailure();
    }
    final word =
        await (database.select(database.vocabularyWords)..where(
              (row) => row.id.equals(wordId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (word == null) throw const InvalidSyncPayloadFailure();

    final session = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
    if (session != null && session.ownerId != ownerId) {
      throw const InvalidSyncPayloadFailure();
    }
    if (session == null) {
      await database
          .into(database.learningSessions)
          .insert(
            db.LearningSessionsCompanion.insert(
              id: sessionId,
              ownerId: ownerId,
              activityType: 'syncedEvidence',
              state: 'syncedEvidence',
              startedAtUtcMs: occurredAtUtcMs,
              appVersion: 'unknown',
              buildId: 'synced',
            ),
          );
    }
    final isCorrect = _requiredBool(payload, 'isCorrect');
    await database
        .into(database.answerAttempts)
        .insert(
          db.AnswerAttemptsCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            sessionId: sessionId,
            wordId: wordId,
            promptMode: promptMode,
            isCorrect: isCorrect,
            responseTimeMs: Value(responseTimeMs),
            attemptNumber: attemptNumber,
            occurredAtUtcMs: occurredAtUtcMs,
            providerProvenance: Value(providerProvenance),
          ),
        );
    await projections.rebuildWord(ownerId: ownerId, wordId: wordId);
    await projections.rebuildSession(ownerId: ownerId, sessionId: sessionId);
    await projections.rebuildAchievements(ownerId);
    await rewardProjections.rebuild(ownerId);
  }

  Future<void> _applyReadingEvent(String ownerId, SyncEntity entity) async {
    _requireImmutableEntity(entity, SyncCollection.readingEvents);
    final existing =
        await (database.select(database.readingEvents)..where(
              (row) =>
                  row.id.equals(entity.entityId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await _handleExistingImmutable(
        ownerId: ownerId,
        entity: entity,
        localPayload: _readingEventPayload(existing),
      );
      await projections.rebuildReading(
        ownerId: ownerId,
        documentId: existing.documentId,
        documentRevision: existing.documentRevision,
      );
      return;
    }
    final payload = entity.payload;
    final documentId = _requiredString(payload, 'documentId');
    final documentRevision = _requiredInt(payload, 'documentRevision');
    final eventType = _requiredString(payload, 'eventType');
    final position = _optionalInt(payload, 'position');
    final occurredAtUtcMs = _requiredInt(payload, 'occurredAtUtcMs');
    if (!LearningEvidenceContract.validReading(
      eventId: entity.entityId,
      ownerId: ownerId,
      documentId: documentId,
      documentRevision: documentRevision,
      eventType: eventType,
      position: position,
      occurredAtUtcMs: occurredAtUtcMs,
    )) {
      throw const InvalidSyncPayloadFailure();
    }
    await database
        .into(database.readingEvents)
        .insert(
          db.ReadingEventsCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            documentId: documentId,
            documentRevision: Value(documentRevision),
            eventType: eventType,
            position: Value(position),
            occurredAtUtcMs: occurredAtUtcMs,
          ),
        );
    await projections.rebuildReading(
      ownerId: ownerId,
      documentId: documentId,
      documentRevision: documentRevision,
    );
  }

  Future<void> _applyRewardTransaction(
    String ownerId,
    SyncEntity entity,
  ) async {
    _requireImmutableEntity(entity, SyncCollection.rewardTransactions);
    final existing =
        await (database.select(database.rewardTransactions)..where(
              (row) =>
                  row.id.equals(entity.entityId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await _handleExistingImmutable(
        ownerId: ownerId,
        entity: entity,
        localPayload: _rewardTransactionPayload(existing),
      );
      await rewardProjections.rebuild(ownerId);
      return;
    }

    final payload = entity.payload;
    final idempotencyKey = _requiredString(payload, 'idempotencyKey');
    final transactionType = _requiredString(payload, 'transactionType');
    final amount = _requiredInt(payload, 'amount');
    final itemId = _requiredString(payload, 'itemId');
    final slot = _requiredString(payload, 'slot');
    final catalogVersion = _requiredInt(payload, 'catalogVersion');
    final sourceEventId = _optionalString(payload, 'sourceEventId');
    final occurredAtUtcMs = _requiredInt(payload, 'occurredAtUtcMs');
    final item = RewardCatalog.byId(itemId);
    if (item == null ||
        catalogVersion != RewardCatalog.version ||
        item.catalogVersion != catalogVersion ||
        item.slot != slot ||
        (transactionType == 'purchase' && amount != -item.price) ||
        (transactionType == 'equip' && amount != 0) ||
        (transactionType != 'purchase' && transactionType != 'equip') ||
        occurredAtUtcMs < 0) {
      throw const InvalidSyncPayloadFailure();
    }

    final idempotencyCollision =
        await (database.select(database.rewardTransactions)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.idempotencyKey.equals(idempotencyKey),
            ))
            .getSingleOrNull();
    if (idempotencyCollision != null) {
      await _recordImmutableConflict(
        ownerId: ownerId,
        entity: entity,
        localPayload: _rewardTransactionPayload(idempotencyCollision),
        resolvedAtUtc: entity.serverUpdatedAtUtc,
      );
      return;
    }

    await database
        .into(database.rewardTransactions)
        .insert(
          db.RewardTransactionsCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            idempotencyKey: idempotencyKey,
            transactionType: transactionType,
            amount: amount,
            itemId: Value(itemId),
            catalogVersion: catalogVersion,
            sourceEventId: Value(sourceEventId),
            occurredAtUtcMs: occurredAtUtcMs,
          ),
        );
    await rewardProjections.rebuild(ownerId);
  }

  /// Apply a pulled [SyncCollection.srsStates] entity.
  ///
  /// Uses last-write-wins semantics: the server state unconditionally
  /// replaces the local projection.  SRS states are derived projections so
  /// the local rebuild will overwrite on the next review anyway.
  Future<void> _applySrsState(String ownerId, SyncEntity entity) async {
    _requireImmutableEntity(entity, SyncCollection.srsStates);
    final payload = entity.payload;
    final wordId = _requiredString(payload, 'wordId');
    final stability = _requiredDouble(payload, 'stability');
    final difficulty = _requiredDouble(payload, 'difficulty');
    final intervalDays = _requiredInt(payload, 'intervalDays');
    final repetitions = _requiredInt(payload, 'repetitions');
    final lapses = _requiredInt(payload, 'lapses');
    final lastReviewAtUtcMs = _optionalInt(payload, 'lastReviewAtUtcMs');
    final dueAtUtcMs = _requiredInt(payload, 'dueAtUtcMs');
    final algorithmVersion = _requiredInt(payload, 'algorithmVersion');

    // Verify word belongs to owner.
    final word =
        await (database.select(database.vocabularyWords)
              ..where((r) => r.id.equals(wordId) & r.ownerId.equals(ownerId)))
            .getSingleOrNull();
    if (word == null) throw const InvalidSyncPayloadFailure();

    // Upsert: server state replaces local.
    final existing =
        await (database.select(database.srsStates)..where(
              (r) => r.wordId.equals(wordId) & r.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();

    if (existing != null) {
      await (database.update(
        database.srsStates,
      )..where((r) => r.id.equals(existing.id))).write(
        db.SrsStatesCompanion(
          stability: Value(stability),
          difficulty: Value(difficulty),
          intervalDays: Value(intervalDays),
          repetitions: Value(repetitions),
          lapses: Value(lapses),
          lastReviewAtUtcMs: Value(lastReviewAtUtcMs),
          dueAtUtcMs: Value(dueAtUtcMs),
          algorithmVersion: Value(algorithmVersion),
        ),
      );
    } else {
      await database
          .into(database.srsStates)
          .insert(
            db.SrsStatesCompanion.insert(
              id: entity.entityId,
              ownerId: ownerId,
              wordId: wordId,
              stability: Value(stability),
              difficulty: Value(difficulty),
              intervalDays: Value(intervalDays),
              repetitions: Value(repetitions),
              lapses: Value(lapses),
              lastReviewAtUtcMs: Value(lastReviewAtUtcMs),
              dueAtUtcMs: dueAtUtcMs,
              algorithmVersion: algorithmVersion,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  /// Apply a pulled [SyncCollection.achievementUnlocks] entity.
  ///
  /// Immutable append-only: insertOrIgnore.  Once an achievement is unlocked
  /// it can never be revoked, so an existing row is authoritative.
  Future<void> _applyAchievementUnlock(
    String ownerId,
    SyncEntity entity,
  ) async {
    _requireImmutableEntity(entity, SyncCollection.achievementUnlocks);
    final existing =
        await (database.select(database.achievementUnlocks)..where(
              (r) => r.id.equals(entity.entityId) & r.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await _handleExistingImmutable(
        ownerId: ownerId,
        entity: entity,
        localPayload: _achievementUnlockPayload(existing),
      );
      return;
    }
    final payload = entity.payload;
    final achievementId = _requiredString(payload, 'achievementId');
    final definitionVersion = _requiredInt(payload, 'definitionVersion');
    final sourceEventId = _requiredString(payload, 'sourceEventId');
    final unlockedAtUtcMs = _requiredInt(payload, 'unlockedAtUtcMs');

    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: sourceEventId,
            unlockedAtUtcMs: unlockedAtUtcMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _handleExistingImmutable({
    required String ownerId,
    required SyncEntity entity,
    required Map<String, Object?> localPayload,
  }) async {
    if (_jsonEquivalent(localPayload, entity.payload)) {
      await _resolvePendingImmutableOutbox(
        ownerId: ownerId,
        entity: entity,
        failureCode: 'identicalCloudEvidence',
      );
      return;
    }
    await _recordImmutableConflict(
      ownerId: ownerId,
      entity: entity,
      localPayload: localPayload,
      resolvedAtUtc: entity.serverUpdatedAtUtc,
    );
  }

  Future<void> _resolveImmutableConflict({
    required db.OutboxOperation operation,
    required SyncEntity cloudEntity,
    required DateTime resolvedAtUtc,
  }) async {
    final localPayload = await _localSnapshot(operation);
    if (_jsonEquivalent(localPayload, cloudEntity.payload)) {
      await (database.update(
        database.outboxOperations,
      )..where((row) => row.operationId.equals(operation.operationId))).write(
        const db.OutboxOperationsCompanion(
          state: Value('conflictResolved'),
          leaseToken: Value(null),
          leaseExpiresAtUtcMs: Value(null),
          nextAttemptAtUtcMs: Value(null),
          failureCode: Value('identicalCloudEvidence'),
        ),
      );
      return;
    }
    await _recordImmutableConflict(
      ownerId: operation.ownerId,
      entity: cloudEntity,
      localPayload: localPayload,
      resolvedAtUtc: resolvedAtUtc,
    );
    await (database.update(
      database.outboxOperations,
    )..where((row) => row.operationId.equals(operation.operationId))).write(
      const db.OutboxOperationsCompanion(
        state: Value('permanentFailure'),
        leaseToken: Value(null),
        leaseExpiresAtUtcMs: Value(null),
        nextAttemptAtUtcMs: Value(null),
        failureCode: Value('immutableConflictQuarantined'),
      ),
    );
  }

  Future<void> _recordImmutableConflict({
    required String ownerId,
    required SyncEntity entity,
    required Map<String, Object?> localPayload,
    required DateTime resolvedAtUtc,
  }) async {
    await database
        .into(database.syncConflicts)
        .insert(
          db.SyncConflictsCompanion.insert(
            id:
                'conflict:immutable:${entity.collection.wireName}:'
                '${entity.entityId}:${entity.revision}',
            ownerId: ownerId,
            entityType: entity.collection.entityType,
            entityId: entity.entityId,
            localRevision: 1,
            cloudRevision: entity.revision,
            resolutionPolicy: 'immutableEventId',
            outcome: 'quarantined',
            localSnapshotJson: Value(jsonEncode(localPayload)),
            cloudSnapshotJson: Value(jsonEncode(entity.payload)),
            resolvedAtUtcMs: resolvedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _resolvePendingImmutableOutbox({
    required String ownerId,
    required SyncEntity entity,
    required String failureCode,
  }) async {
    await (database.update(database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals(entity.collection.entityType) &
              row.entityId.equals(entity.entityId) &
              row.state.isNotIn(const [
                'acknowledged',
                'superseded',
                'conflictResolved',
              ]),
        ))
        .write(
          db.OutboxOperationsCompanion(
            state: const Value('conflictResolved'),
            leaseToken: const Value(null),
            leaseExpiresAtUtcMs: const Value(null),
            nextAttemptAtUtcMs: const Value(null),
            failureCode: Value(failureCode),
          ),
        );
  }

  Future<bool> _preparePullApply(String ownerId, SyncEntity entity) async {
    late final int localRevision;
    late final int cloudRevision;
    late final int? serverUpdatedAtUtcMs;
    late final Map<String, Object?> localSnapshot;

    switch (entity.collection) {
      case SyncCollection.categories:
        final current =
            await (database.select(database.vocabularyCategories)..where(
                  (row) =>
                      row.id.equals(entity.entityId) &
                      row.ownerId.equals(ownerId),
                ))
                .getSingleOrNull();
        if (current == null) return true;
        localRevision = current.localRevision;
        cloudRevision = current.cloudRevision;
        serverUpdatedAtUtcMs = current.serverUpdatedAtUtcMs;
        localSnapshot = <String, Object?>{
          'entityId': current.id,
          'localRevision': current.localRevision,
          'cloudRevision': current.cloudRevision,
          'name': current.name,
          'normalizedName': current.normalizedName,
          'sortOrder': current.sortOrder,
          'isDeleted': current.isDeleted,
          'updatedAtUtcMs': current.updatedAtUtcMs,
        };
      case SyncCollection.words:
        final current =
            await (database.select(database.vocabularyWords)..where(
                  (row) =>
                      row.id.equals(entity.entityId) &
                      row.ownerId.equals(ownerId),
                ))
                .getSingleOrNull();
        if (current == null) return true;
        localRevision = current.localRevision;
        cloudRevision = current.cloudRevision;
        serverUpdatedAtUtcMs = current.serverUpdatedAtUtcMs;
        localSnapshot = <String, Object?>{
          'entityId': current.id,
          'localRevision': current.localRevision,
          'cloudRevision': current.cloudRevision,
          'categoryId': current.categoryId,
          'spelling': current.spelling,
          'meaning': current.meaning,
          'partOfSpeech': current.partOfSpeech,
          'isDeleted': current.isDeleted,
          'updatedAtUtcMs': current.updatedAtUtcMs,
        };
      case SyncCollection.attempts:
      case SyncCollection.readingEvents:
      case SyncCollection.rewardTransactions:
      case SyncCollection.srsStates:
      case SyncCollection.achievementUnlocks:
        throw const InvalidSyncPayloadFailure();
    }

    final incomingServerMs = entity.serverUpdatedAtUtc.millisecondsSinceEpoch;
    if (entity.revision < cloudRevision ||
        (entity.revision == cloudRevision &&
            serverUpdatedAtUtcMs != null &&
            incomingServerMs <= serverUpdatedAtUtcMs)) {
      return false;
    }
    if (localRevision <= cloudRevision) return true;

    final cloudSnapshot = <String, Object?>{
      'collection': entity.collection.wireName,
      'entityId': entity.entityId,
      'revision': entity.revision,
      'isDeleted': entity.isDeleted,
      'payloadVersion': entity.payloadVersion,
      'clientUpdatedAtUtcMs': entity.clientUpdatedAtUtc.millisecondsSinceEpoch,
      'serverUpdatedAtUtcMicros':
          entity.serverUpdatedAtUtc.microsecondsSinceEpoch,
      'payload': entity.payload,
    };
    await database
        .into(database.syncConflicts)
        .insert(
          db.SyncConflictsCompanion.insert(
            id:
                'conflict:pull:${entity.collection.wireName}:'
                '${entity.entityId}:$localRevision:${entity.revision}',
            ownerId: ownerId,
            entityType: entity.collection == SyncCollection.categories
                ? 'category'
                : 'word',
            entityId: entity.entityId,
            localRevision: localRevision,
            cloudRevision: entity.revision,
            resolutionPolicy: 'highestAcknowledgedRevision',
            outcome: 'cloudWins',
            localSnapshotJson: Value(jsonEncode(localSnapshot)),
            cloudSnapshotJson: Value(jsonEncode(cloudSnapshot)),
            resolvedAtUtcMs: incomingServerMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await (database.update(database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityId.equals(entity.entityId) &
              row.entityType.equals(
                entity.collection == SyncCollection.categories
                    ? 'category'
                    : 'word',
              ) &
              (row.state.equals('pending') |
                  row.state.equals('retryWaiting') |
                  row.state.equals('inFlight') |
                  row.state.equals('blockedAuth')),
        ))
        .write(
          const db.OutboxOperationsCompanion(
            state: Value('conflictResolved'),
            leaseToken: Value(null),
            leaseExpiresAtUtcMs: Value(null),
            nextAttemptAtUtcMs: Value(null),
            failureCode: Value('cloudWins'),
          ),
        );
    return true;
  }
}

Map<String, Object?> _attemptPayload(db.AnswerAttempt attempt) =>
    <String, Object?>{
      'sessionId': attempt.sessionId,
      'wordId': attempt.wordId,
      'promptMode': attempt.promptMode,
      'isCorrect': attempt.isCorrect,
      'responseTimeMs': attempt.responseTimeMs,
      'attemptNumber': attempt.attemptNumber,
      'occurredAtUtcMs': attempt.occurredAtUtcMs,
      'providerProvenance': attempt.providerProvenance,
    };

Map<String, Object?> _readingEventPayload(db.ReadingEvent event) =>
    <String, Object?>{
      'documentId': event.documentId,
      'documentRevision': event.documentRevision,
      'eventType': event.eventType,
      'position': event.position,
      'occurredAtUtcMs': event.occurredAtUtcMs,
    };

Map<String, Object?> _rewardTransactionPayload(
  db.RewardTransaction transaction,
) {
  final item = transaction.itemId == null
      ? null
      : RewardCatalog.byId(transaction.itemId!);
  return <String, Object?>{
    'idempotencyKey': transaction.idempotencyKey,
    'transactionType': transaction.transactionType,
    'amount': transaction.amount,
    'itemId': transaction.itemId,
    'slot': item?.slot,
    'catalogVersion': transaction.catalogVersion,
    'sourceEventId': transaction.sourceEventId,
    'occurredAtUtcMs': transaction.occurredAtUtcMs,
  };
}

Map<String, Object?> _srsStatePayload(db.SrsState srs) => <String, Object?>{
  'wordId': srs.wordId,
  'stability': srs.stability,
  'difficulty': srs.difficulty,
  'intervalDays': srs.intervalDays,
  'repetitions': srs.repetitions,
  'lapses': srs.lapses,
  'lastReviewAtUtcMs': srs.lastReviewAtUtcMs,
  'dueAtUtcMs': srs.dueAtUtcMs,
  'algorithmVersion': srs.algorithmVersion,
};

Map<String, Object?> _achievementUnlockPayload(db.AchievementUnlock unlock) =>
    <String, Object?>{
      'achievementId': unlock.achievementId,
      'definitionVersion': unlock.definitionVersion,
      'sourceEventId': unlock.sourceEventId,
      'unlockedAtUtcMs': unlock.unlockedAtUtcMs,
    };

void _requireImmutableEntity(
  SyncEntity entity,
  SyncCollection expectedCollection,
) {
  if (entity.collection != expectedCollection ||
      entity.revision != 1 ||
      entity.isDeleted) {
    throw const InvalidSyncPayloadFailure();
  }
}

bool _jsonEquivalent(Object? left, Object? right) {
  if (identical(left, right) || left == right) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquivalent(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_jsonEquivalent(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

int _compareCursors(SyncCursor left, SyncCursor right) {
  final timestampComparison = left.serverUpdatedAtUtc.compareTo(
    right.serverUpdatedAtUtc,
  );
  if (timestampComparison != 0) return timestampComparison;
  return left.documentId.compareTo(right.documentId);
}

String _releaseStateFor(db.OutboxOperation operation) {
  if (operation.state == 'pending' || operation.state == 'retryWaiting') {
    return operation.state;
  }
  if (operation.state == 'inFlight') {
    return operation.nextAttemptAtUtcMs != null || operation.failureCode != null
        ? 'retryWaiting'
        : 'pending';
  }
  throw StateError('outbox operation is not claimable');
}

SyncOperationKind _operationKind(String value) => switch (value) {
  'upsert' => SyncOperationKind.upsert,
  'delete' => SyncOperationKind.delete,
  _ => throw const InvalidSyncPayloadFailure(),
};

DateTime _utc(int epochMilliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(epochMilliseconds, isUtc: true);

void _requireUtc(DateTime value, String field) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, field, 'must be UTC');
  }
}

String _requiredId(String value, String field) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 256) {
    throw ArgumentError.value(value, field, 'must contain 1-256 characters');
  }
  return canonical;
}

String _requiredString(Map<String, Object?> payload, String key) {
  final value = _optionalString(payload, key);
  if (value == null || value.trim().isEmpty) {
    throw const InvalidSyncPayloadFailure();
  }
  return value;
}

String? _optionalString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) return null;
  if (value is! String) throw const InvalidSyncPayloadFailure();
  return value;
}

int? _optionalInt(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) return null;
  if (value is! int) throw const InvalidSyncPayloadFailure();
  return value;
}

int _requiredInt(Map<String, Object?> payload, String key) {
  final value = _optionalInt(payload, key);
  if (value == null) throw const InvalidSyncPayloadFailure();
  return value;
}

bool? _optionalBool(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) return null;
  if (value is! bool) throw const InvalidSyncPayloadFailure();
  return value;
}

double _requiredDouble(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is double) return value;
  if (value is int) return value.toDouble();
  throw const InvalidSyncPayloadFailure();
}

bool _requiredBool(Map<String, Object?> payload, String key) {
  final value = _optionalBool(payload, key);
  if (value == null) throw const InvalidSyncPayloadFailure();
  return value;
}
