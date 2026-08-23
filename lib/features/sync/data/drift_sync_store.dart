import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../../runtime/registries/consent_registry.dart';
import '../../events/application/event_v1_to_v2_adapter.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/data/drift_learning_event_store.dart';
import '../../learning/data/drift_learning_projection_rebuilder.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/evidence_policy_rollout.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning/domain/learning_event_context.dart';
import '../../learning/domain/srs_operation_identity.dart';
import '../../research/data/drift_experiment_assignment_repository.dart';
import '../../research/domain/experiment_assignment.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import '../../rewards/domain/economy_transaction_policy.dart';
import '../../rewards/domain/reward_models.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_result.dart';
import '../domain/sync_store.dart';
import 'drift_owner_operation_gate.dart';

final class DriftSyncStore implements SyncStore {
  DriftSyncStore(
    this.database, {
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
    this.payloadRollout = const SyncPayloadRollout.productionDefault(),
    this.researchSyncRollout = const ResearchCollectionSyncRollout.off(),
    this.consentRegistry = const NoOpConsentRegistry(),
  }) : projections = DriftLearningProjectionRebuilder(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database);

  static const int maxClaimLimit = 50;
  static const int maxSendReservations = maxSyncSendReservations;
  static const int maxLegacySrsNormalizationsPerClaim = 20;
  static const int _maxCandidateMultiplier = 20;

  final db.AppDatabase database;
  final SyncPayloadRollout payloadRollout;
  final ResearchCollectionSyncRollout researchSyncRollout;
  final ConsentRegistry consentRegistry;
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
        await database.customUpdate(
          '''
          UPDATE outbox_operations
          SET state = 'permanentFailure',
              next_attempt_at_utc_ms = NULL,
              lease_token = NULL,
              lease_expires_at_utc_ms = NULL,
              failure_code = 'deliveryUnknownAfterReservationLimit'
          WHERE owner_id = ?
            AND state = 'inFlight'
            AND attempt_count >= ?
            AND lease_expires_at_utc_ms IS NOT NULL
            AND lease_expires_at_utc_ms <= ?
          ''',
          variables: [
            Variable<String>(canonicalOwnerId),
            const Variable<int>(maxSendReservations),
            Variable<int>(nowMs),
          ],
          updates: {database.outboxOperations},
        );
        await _normalizeLegacySrsOutbox(
          ownerId: canonicalOwnerId,
          limit: limit < maxLegacySrsNormalizationsPerClaim
              ? limit
              : maxLegacySrsNormalizationsPerClaim,
        );
        final candidatePageSize = limit * _maxCandidateMultiplier;
        final candidates = <db.OutboxOperation>[];
        final eligibleGroups = <String>{};
        var cursorCreatedAtUtcMs = -1;
        var cursorOperationId = '';
        while (eligibleGroups.length < limit) {
          final candidateRows = await database
              .customSelect(
                '''
          SELECT candidate.*
          FROM outbox_operations AS candidate
          WHERE candidate.owner_id = ?
            AND candidate.attempt_count < ?
            AND (
              candidate.state = 'pending'
              OR (
                candidate.state = 'retryWaiting'
                AND (
                  candidate.next_attempt_at_utc_ms IS NULL
                  OR candidate.next_attempt_at_utc_ms <= ?
                )
              )
              OR (
                candidate.state = 'inFlight'
                AND candidate.lease_expires_at_utc_ms IS NOT NULL
                AND candidate.lease_expires_at_utc_ms <= ?
              )
            )
            AND NOT EXISTS (
              SELECT 1
              FROM outbox_operations AS barrier
              WHERE barrier.owner_id = candidate.owner_id
                AND barrier.entity_type = candidate.entity_type
                AND barrier.entity_id = candidate.entity_id
                AND barrier.state = 'permanentFailure'
                AND barrier.attempt_count >= ?
                AND (
                  barrier.created_at_utc_ms < candidate.created_at_utc_ms
                  OR (
                    barrier.created_at_utc_ms = candidate.created_at_utc_ms
                    AND barrier.operation_id < candidate.operation_id
                  )
                )
          )
            AND (
              candidate.created_at_utc_ms > ?
              OR (
                candidate.created_at_utc_ms = ?
                AND candidate.operation_id > ?
              )
            )
          ORDER BY candidate.created_at_utc_ms, candidate.operation_id
          LIMIT ?
          ''',
                variables: [
                  Variable<String>(canonicalOwnerId),
                  const Variable<int>(maxSendReservations),
                  Variable<int>(nowMs),
                  Variable<int>(nowMs),
                  const Variable<int>(maxSendReservations),
                  Variable<int>(cursorCreatedAtUtcMs),
                  Variable<int>(cursorCreatedAtUtcMs),
                  Variable<String>(cursorOperationId),
                  Variable<int>(candidatePageSize),
                ],
                readsFrom: {database.outboxOperations},
              )
              .get();
          if (candidateRows.isEmpty) break;
          final mappedRows = candidateRows
              .map((row) => database.outboxOperations.map(row.data))
              .toList(growable: false);
          final last = mappedRows.last;
          final cursorAdvanced =
              last.createdAtUtcMs > cursorCreatedAtUtcMs ||
              (last.createdAtUtcMs == cursorCreatedAtUtcMs &&
                  last.operationId.compareTo(cursorOperationId) > 0);
          if (!cursorAdvanced) {
            throw StateError('sync claim candidate cursor did not advance');
          }
          cursorCreatedAtUtcMs = last.createdAtUtcMs;
          cursorOperationId = last.operationId;
          for (final candidate in mappedRows) {
            if (await _claimAllowed(candidate, firebaseUid: canonicalUid)) {
              candidates.add(candidate);
              eligibleGroups.add(
                '${candidate.entityType}\u001f${candidate.entityId}',
              );
            }
          }
          if (candidateRows.length < candidatePageSize) break;
        }
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
          final attemptedIndex = group.indexWhere(
            (candidate) => candidate.attemptCount > 0,
          );
          final selected = attemptedIndex < 0
              ? group.last
              : group[attemptedIndex];
          final coalesced = attemptedIndex < 0
              ? group.take(group.length - 1)
              : const Iterable<db.OutboxOperation>.empty();
          final baseRevision = attemptedIndex < 0
              ? group
                    .map((row) => row.baseRevision)
                    .reduce((left, right) => left < right ? left : right)
              : selected.baseRevision;

          for (final superseded in coalesced) {
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
              localOperationId: selected.operationId,
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
          await (database.select(
                database.outboxOperations,
              )..where((row) => row.operationId.equals(claim.localOperationId)))
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
        localOperationId: claim.localOperationId,
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
        Variable<String>(claim.localOperationId),
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
      await _reconcileLaterNeverAttemptedOperations(operation, acknowledgement);
      return true;
    });
  }

  Future<void> _reconcileLaterNeverAttemptedOperations(
    db.OutboxOperation acknowledged,
    PushAcknowledged acknowledgement,
  ) async {
    final sameEntity =
        await (database.select(database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(acknowledged.ownerId) &
                  row.entityType.equals(acknowledged.entityType) &
                  row.entityId.equals(acknowledged.entityId) &
                  row.operationId.equals(acknowledged.operationId).not() &
                  row.attemptCount.equals(0) &
                  (row.state.equals('pending') |
                      row.state.equals('retryWaiting')),
            ))
            .get();
    for (final later in sameEntity.where(
      (candidate) => _operationComesAfter(candidate, acknowledged),
    )) {
      final localRevision = _operationRevision(later);
      if (acknowledgement.resultingRevision >= localRevision) {
        await (database.update(database.outboxOperations)..where(
              (row) =>
                  row.operationId.equals(later.operationId) &
                  row.attemptCount.equals(0) &
                  (row.state.equals('pending') |
                      row.state.equals('retryWaiting')),
            ))
            .write(
              const db.OutboxOperationsCompanion(
                state: Value('superseded'),
                nextAttemptAtUtcMs: Value(null),
                leaseToken: Value(null),
                leaseExpiresAtUtcMs: Value(null),
                failureCode: Value('includedInAcknowledgedReplay'),
              ),
            );
      } else {
        await (database.update(database.outboxOperations)..where(
              (row) =>
                  row.operationId.equals(later.operationId) &
                  row.attemptCount.equals(0) &
                  (row.state.equals('pending') |
                      row.state.equals('retryWaiting')),
            ))
            .write(
              db.OutboxOperationsCompanion(
                baseRevision: Value(acknowledgement.resultingRevision),
              ),
            );
      }
    }
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
    if (cloudEntity.collection == SyncCollection.attempts) {
      _attemptEvidenceContext(cloudEntity);
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
          await (database.select(
                database.outboxOperations,
              )..where((row) => row.operationId.equals(claim.localOperationId)))
              .getSingleOrNull();
      if (operation == null ||
          operation.state != 'inFlight' ||
          operation.leaseToken != claim.leaseToken) {
        return false;
      }
      if (cloudEntity.collection == SyncCollection.attempts ||
          cloudEntity.collection == SyncCollection.readingEvents ||
          cloudEntity.collection == SyncCollection.rewardTransactions ||
          cloudEntity.collection == SyncCollection.achievementUnlocks ||
          cloudEntity.collection == SyncCollection.experimentAssignments) {
        await _resolveImmutableConflict(
          operation: operation,
          claimedPayload: mutation.payload,
          cloudEntity: cloudEntity,
          resolvedAtUtc: resolvedAtUtc,
        );
        return true;
      }

      final localSnapshot = await _localSnapshot(operation);
      final preserveLocalSrsEvidence =
          cloudEntity.collection == SyncCollection.srsStates &&
          await _hasAnswerEvidence(operation.ownerId, operation.entityId);
      final conflictOutcome = preserveLocalSrsEvidence
          ? 'localEvidenceWins'
          : 'cloudWins';
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
              resolutionPolicy: preserveLocalSrsEvidence
                  ? 'immutableAnswerEvidence'
                  : 'highestAcknowledgedRevision',
              outcome: conflictOutcome,
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
        case SyncCollection.experimentAssignments:
          throw const InvalidSyncPayloadFailure();
        case SyncCollection.srsStates:
          // Resolve mutable cache state without overriding local answer evidence.
          await _applySrsState(operation.ownerId, cloudEntity);
      }
      await (database.update(
        database.outboxOperations,
      )..where((row) => row.operationId.equals(operation.operationId))).write(
        db.OutboxOperationsCompanion(
          state: const Value('conflictResolved'),
          leaseToken: const Value(null),
          leaseExpiresAtUtcMs: const Value(null),
          nextAttemptAtUtcMs: const Value(null),
          failureCode: Value(conflictOutcome),
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
    if (collection == SyncCollection.attempts) {
      for (final entity in page.changes) {
        if (entity.collection == SyncCollection.attempts) {
          _attemptEvidenceContext(entity);
        }
      }
    }
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
        final parsedStoredCursor = storedCursor == null
            ? null
            : SyncCursor.parse(storedCursor);
        if (page.changes.isEmpty) {
          final preservesStored = switch ((cursor, parsedStoredCursor)) {
            (null, null) => true,
            (final SyncCursor next, final SyncCursor stored) => next == stored,
            _ => false,
          };
          if (!preservesStored || page.hasMore) {
            throw const InvalidSyncCursorFailure();
          }
          return true;
        }
        if (page.changes.any((entity) => entity.collection != collection)) {
          throw const InvalidSyncPayloadFailure();
        }
        final finalChange = page.changes.last;
        final deliveredCursor = SyncCursor(
          serverUpdatedAtUtc: finalChange.serverUpdatedAtUtc,
          documentId: finalChange.entityId,
        );
        if (cursor == null || cursor != deliveredCursor) {
          throw const InvalidSyncCursorFailure();
        }
        if (storedCursor != null) {
          final cursorComparison = _compareCursors(cursor, parsedStoredCursor!);
          if (cursorComparison < 0) {
            throw const InvalidSyncCursorFailure();
          }
          if (cursorComparison == 0) {
            if (page.hasMore) throw const InvalidSyncCursorFailure();
            return true;
          }
        }

        for (final entity in page.changes) {
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
            case SyncCollection.experimentAssignments:
              await _applyExperimentAssignment(canonicalOwnerId, entity);
          }
        }

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

  Future<bool> _claimAllowed(
    db.OutboxOperation operation, {
    required String firebaseUid,
  }) async {
    if (operation.entityType ==
        SyncCollection.experimentAssignments.entityType) {
      return _catalogAllowsExperimentAssignmentClaim(
        operation,
        firebaseUid: firebaseUid,
      );
    }
    if (operation.entityType != SyncCollection.attempts.entityType) {
      return true;
    }

    final attempt =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.id.equals(operation.entityId) &
                  row.ownerId.equals(operation.ownerId),
            ))
            .getSingleOrNull();
    if (attempt == null) throw const InvalidSyncPayloadFailure();
    final payloadVersion = _attemptPayloadVersionFor(attempt, payloadRollout);
    if (payloadVersion != 2) return true;
    final payload = _attemptPayload(attempt, payloadVersion: payloadVersion);
    final context = AnswerAttemptSyncPayloadContract.requireEvidenceContext(
      payloadVersion: payloadVersion,
      payload: payload,
    );
    if (!_hasResearchAssignmentIdentity(context)) return true;
    return await _validatedPersistedEvidenceAssignment(
          ownerId: operation.ownerId,
          context: context,
          occurredAtUtc: _utc(attempt.occurredAtUtcMs),
          unavailableAsNull: true,
        ) !=
        null;
  }

  Future<void> _normalizeLegacySrsOutbox({
    required String ownerId,
    required int limit,
  }) async {
    // One owner-scoped grouped scan repairs at most [limit] words per claim.
    // The cap prevents reopen normalization from creating an unbounded write
    // transaction; additional legacy words are repaired by later runs.
    final missing = await database
        .customSelect(
          '''
      WITH revisions AS (
        SELECT state.word_id AS word_id,
               COUNT(attempt.id) AS revision,
               MAX(attempt.occurred_at_utc_ms) AS latest_occurred_at_utc_ms,
               (
                 SELECT latest.id
                 FROM answer_attempts AS latest
                 WHERE latest.owner_id = state.owner_id
                   AND latest.word_id = state.word_id
                 ORDER BY latest.occurred_at_utc_ms DESC, latest.id DESC
                 LIMIT 1
               ) AS latest_attempt_id
        FROM srs_states AS state
        JOIN answer_attempts AS attempt
          ON attempt.owner_id = state.owner_id
         AND attempt.word_id = state.word_id
        WHERE state.owner_id = ?
        GROUP BY state.word_id
      )
      SELECT word_id, revision, latest_attempt_id, latest_occurred_at_utc_ms
      FROM revisions
      WHERE revision > 0
        AND NOT EXISTS (
          SELECT 1
          FROM outbox_operations AS operation
          WHERE operation.owner_id = ?
            AND operation.entity_type = 'srsState'
            AND operation.entity_id = revisions.word_id
            AND (
              operation.operation_id LIKE
                'srsState:v2:%:r' || CAST(revisions.revision AS TEXT)
              OR operation.operation_id =
                'srsState:' || revisions.word_id ||
                ':' || CAST(revisions.revision AS TEXT)
              OR operation.base_revision + 1 >= revisions.revision
            )
        )
      ORDER BY latest_occurred_at_utc_ms, word_id
      LIMIT ?
      ''',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(ownerId),
            Variable<int>(limit),
          ],
          readsFrom: {
            database.srsStates,
            database.answerAttempts,
            database.outboxOperations,
          },
        )
        .get();
    for (final row in missing) {
      final revision = row.read<int>('revision');
      final attemptId = row.read<String>('latest_attempt_id');
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: SrsOperationIdentity.create(
                ownerId: ownerId,
                wordId: row.read<String>('word_id'),
                answerAttemptId: attemptId,
                revision: revision,
              ),
              ownerId: ownerId,
              entityType: 'srsState',
              entityId: row.read<String>('word_id'),
              operationKind: 'upsert',
              baseRevision: Value(revision - 1),
              createdAtUtcMs: row.read<int>('latest_occurred_at_utc_ms'),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<bool> _catalogAllowsExperimentAssignmentClaim(
    db.OutboxOperation operation, {
    required String firebaseUid,
  }) async {
    if (!researchSyncRollout.allowsExperimentAssignmentClaims) {
      return false;
    }
    final assignment = await _experimentAssignmentForOperation(
      operation,
      firebaseUid: firebaseUid,
    );
    if (assignment == null) {
      return false;
    }

    try {
      final mapping = researchSyncRollout.protocolModeCatalog!
          .lookupForAssignment(
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
            protocolVersion: assignment.protocolVersion,
          );
      if (mapping == null) {
        return false;
      }
      final consent = await consentRegistry.snapshot(
        purpose: ConsentPurpose.researchDataUpload,
        ownerId: operation.ownerId,
        consentVersion: mapping.consentVersion,
      );
      final decisionUtc = consent.decisionUtc;
      return consent.purpose == ConsentPurpose.researchDataUpload &&
          consent.ownerId == operation.ownerId &&
          consent.consentVersion == mapping.consentVersion &&
          consent.state == ConsentState.granted &&
          decisionUtc != null &&
          decisionUtc.isUtc &&
          decisionUtc.millisecondsSinceEpoch >= 0 &&
          consent.withdrawalUtc == null;
    } on Object {
      return false;
    }
  }

  Future<db.ExperimentAssignmentRow?> _experimentAssignmentForOperation(
    db.OutboxOperation operation, {
    required String firebaseUid,
  }) async {
    if (operation.operationKind != SyncOperationKind.upsert.name ||
        operation.payloadVersion != 1 ||
        operation.baseRevision != 0) {
      return null;
    }
    final assignments = await (database.select(
      database.experimentAssignments,
    )..where((row) => row.ownerId.equals(operation.ownerId))).get();
    db.ExperimentAssignmentRow? match;
    for (final assignment in assignments) {
      final cloudId =
          DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
            firebaseUid: firebaseUid,
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
          );
      if (operation.entityId != assignment.id &&
          operation.entityId != cloudId) {
        continue;
      }
      final expectedOperationId =
          DriftExperimentAssignmentRepository.canonicalOutboxOperationId(
            operation.entityId,
          );
      if (operation.operationId != expectedOperationId || match != null) {
        return null;
      }
      match = assignment;
    }
    return match;
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
        final payloadVersion = _attemptPayloadVersionFor(
          attempt,
          payloadRollout,
        );
        final payload = await _attemptPayloadForCloud(
          attempt,
          ownerId: operation.ownerId,
          firebaseUid: firebaseUid,
          payloadVersion: payloadVersion,
        );
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.attempts,
          entityId: attempt.id,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: payloadVersion,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: _utc(attempt.occurredAtUtcMs),
          payload: payload,
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
        final payload = _rewardTransactionPayload(transaction);
        if (transaction.sourceEventId != null &&
            await _rewardSourceCollision(
                  ownerId: operation.ownerId,
                  entityId: transaction.id,
                  sourceEventId: transaction.sourceEventId!,
                ) !=
                null) {
          throw const InvalidSyncPayloadFailure();
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
          payload: payload,
        );
      case 'srsState':
        final srs =
            await (database.select(database.srsStates)..where(
                  (row) =>
                      row.wordId.equals(operation.entityId) &
                      row.ownerId.equals(operation.ownerId),
                ))
                .getSingleOrNull();
        if (srs == null) throw StateError('outbox srsState was not found');
        final localRevision = await _srsLocalRevision(operation);
        return PushMutation(
          operationId: operation.operationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.srsStates,
          entityId: srs.wordId, // stable entity identifier
          operationKind: SyncOperationKind.upsert,
          payloadVersion: operation.payloadVersion,
          baseRevision: baseRevision,
          localRevision: localRevision,
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
      case 'experimentAssignment':
        final row = await _experimentAssignmentForOperation(
          operation,
          firebaseUid: firebaseUid,
        );
        if (row == null ||
            operation.operationKind != SyncOperationKind.upsert.name ||
            operation.payloadVersion != 1 ||
            baseRevision != 0) {
          throw const InvalidSyncPayloadFailure();
        }
        final assignment = await DriftExperimentAssignmentRepository(database)
            .getAssignment(
              ownerId: row.ownerId,
              experimentId: row.experimentId,
              experimentVersion: row.experimentVersion,
            );
        final payload = _experimentAssignmentPayload(
          assignment,
          firebaseUid: firebaseUid,
        );
        final cloudEntityId =
            DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
              firebaseUid: firebaseUid,
              experimentId: assignment.experimentId,
              experimentVersion: assignment.experimentVersion,
            );
        final cloudOperationId =
            DriftExperimentAssignmentRepository.canonicalOutboxOperationId(
              cloudEntityId,
            );
        ExperimentAssignmentSyncPayloadContract.requireCanonical(
          payload: payload,
          expectedEntityId: cloudEntityId,
          expectedOwnerId: firebaseUid,
          expectedAssignedAtUtcMs:
              assignment.assignedAtUtc.millisecondsSinceEpoch,
        );
        return PushMutation(
          operationId: cloudOperationId,
          firebaseUid: firebaseUid,
          collection: SyncCollection.experimentAssignments,
          entityId: cloudEntityId,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: 1,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: assignment.assignedAtUtc,
          payload: payload,
        );
      default:
        throw const InvalidSyncPayloadFailure();
    }
  }

  Future<int> _srsLocalRevision(db.OutboxOperation operation) async {
    final attemptCount = database.answerAttempts.id.count();
    final attemptQuery = database.selectOnly(database.answerAttempts)
      ..addColumns([attemptCount])
      ..where(
        database.answerAttempts.ownerId.equals(operation.ownerId) &
            database.answerAttempts.wordId.equals(operation.entityId),
      );
    final durableAttempts =
        (await attemptQuery.getSingle()).read(attemptCount) ?? 0;
    final operations =
        await (database.select(database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(operation.ownerId) &
                  row.entityType.equals('srsState') &
                  row.entityId.equals(operation.entityId),
            ))
            .get();
    var revision = durableAttempts;
    for (final candidate in operations) {
      final candidateRevision = _operationRevision(candidate);
      if (candidateRevision > revision) revision = candidateRevision;
    }
    final minimumRevision = operation.baseRevision + 1;
    return revision < minimumRevision ? minimumRevision : revision;
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
        // SRS revisions live in the durable operation rather than cache rows.
        return;
      case 'achievementUnlock':
        // Immutable unlock; no revision tracking needed.
        return;
      case 'experimentAssignment':
        // Immutable research audit evidence has no mutable cloud revision.
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
        return _attemptPayload(
          attempt,
          payloadVersion: _attemptPayloadVersionFor(attempt, payloadRollout),
        );
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
      case 'experimentAssignment':
        final owner =
            await (database.select(
                  database.localOwners,
                )..where((candidate) => candidate.id.equals(operation.ownerId)))
                .getSingle();
        final firebaseUid = owner.firebaseUid;
        if (firebaseUid == null) throw const InvalidSyncPayloadFailure();
        final row = await _experimentAssignmentForOperation(
          operation,
          firebaseUid: firebaseUid,
        );
        if (row == null) throw const InvalidSyncPayloadFailure();
        return _experimentAssignmentRowPayload(row, firebaseUid: firebaseUid);
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

  Future<Map<String, Object?>> _attemptPayloadForCloud(
    db.AnswerAttempt attempt, {
    required String ownerId,
    required String firebaseUid,
    required int payloadVersion,
  }) async {
    final payload = _attemptPayload(attempt, payloadVersion: payloadVersion);
    if (payloadVersion != 2) return payload;

    final context = AnswerAttemptSyncPayloadContract.requireEvidenceContext(
      payloadVersion: payloadVersion,
      payload: payload,
    );
    if (!_hasResearchAssignmentIdentity(context)) return payload;

    final boundUid = await _boundFirebaseUid(
      ownerId,
      expectedFirebaseUid: firebaseUid,
    );
    final assignment = await _requirePersistedEvidenceAssignment(
      ownerId: ownerId,
      context: context,
      occurredAtUtc: _utc(attempt.occurredAtUtcMs),
    );
    final repository = DriftExperimentAssignmentRepository(database);
    final localIdentityApproved = await repository.matchesAssignmentIdentity(
      ownerId: ownerId,
      experimentId: assignment.experimentId,
      experimentVersion: assignment.experimentVersion,
      candidateAssignmentId: context.assignmentId!,
    );
    if (!localIdentityApproved) throw const InvalidSyncPayloadFailure();

    final cloudAssignmentId =
        DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
          firebaseUid: boundUid,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
        );
    return _attemptPayloadWithAssignmentId(
      payload,
      context: context,
      assignmentId: cloudAssignmentId,
    );
  }

  Future<({SyncEntity entity, ExperimentAssignment? assignment})>
  _attemptEntityForLocalPersistence(String ownerId, SyncEntity entity) async {
    if (entity.payloadVersion != 2) {
      return (entity: entity, assignment: null);
    }

    final context = _attemptEvidenceContext(entity);
    if (!_hasResearchAssignmentIdentity(context)) {
      return (entity: entity, assignment: null);
    }

    final firebaseUid = await _boundFirebaseUid(ownerId);
    final experimentId = context.experimentId!;
    final experimentVersion = context.experimentVersion!;
    final cloudAssignmentId =
        DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
          firebaseUid: firebaseUid,
          experimentId: experimentId,
          experimentVersion: experimentVersion,
        );
    if (context.assignmentId != cloudAssignmentId) {
      throw const InvalidSyncPayloadFailure();
    }

    final occurredAtUtcMs = entity.payload['occurredAtUtcMs'];
    if (occurredAtUtcMs is! int || occurredAtUtcMs < 0) {
      throw const InvalidSyncPayloadFailure();
    }
    final assignment = await _requirePersistedEvidenceAssignment(
      ownerId: ownerId,
      context: context,
      occurredAtUtc: _utc(occurredAtUtcMs),
    );
    final localPayload = _attemptPayloadWithAssignmentId(
      entity.payload,
      context: context,
      assignmentId: assignment.id,
    );
    return (
      entity: SyncEntity(
        collection: entity.collection,
        entityId: entity.entityId,
        revision: entity.revision,
        isDeleted: entity.isDeleted,
        payloadVersion: entity.payloadVersion,
        clientUpdatedAtUtc: entity.clientUpdatedAtUtc,
        serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
        payload: localPayload,
      ),
      assignment: assignment,
    );
  }

  Future<ExperimentAssignment> _requirePersistedEvidenceAssignment({
    required String ownerId,
    required EvidenceContext context,
    required DateTime occurredAtUtc,
  }) async {
    final assignment = await _validatedPersistedEvidenceAssignment(
      ownerId: ownerId,
      context: context,
      occurredAtUtc: occurredAtUtc,
      unavailableAsNull: false,
    );
    if (assignment == null) throw const InvalidSyncPayloadFailure();
    return assignment;
  }

  Future<ExperimentAssignment?> _validatedPersistedEvidenceAssignment({
    required String ownerId,
    required EvidenceContext context,
    required DateTime occurredAtUtc,
    required bool unavailableAsNull,
  }) async {
    try {
      context.validate();
      _requireUtc(occurredAtUtc, 'occurredAtUtc');
      final experimentId = context.experimentId;
      final experimentVersion = context.experimentVersion;
      final cohort = context.cohort;
      final protocolVersion = context.protocolVersion;
      final consentVersion = context.researchConsentVersion;
      if (!_hasResearchAssignmentIdentity(context) ||
          experimentId == null ||
          experimentVersion == null ||
          cohort == null ||
          protocolVersion == null ||
          consentVersion == null) {
        throw const InvalidSyncPayloadFailure();
      }

      final ExperimentAssignment assignment;
      try {
        assignment = await DriftExperimentAssignmentRepository(database)
            .getAssignment(
              ownerId: ownerId,
              experimentId: experimentId,
              experimentVersion: experimentVersion,
            );
      } on ExperimentAssignmentConflict {
        if (unavailableAsNull) return null;
        throw const InvalidSyncPayloadFailure();
      } on StateError {
        if (unavailableAsNull) return null;
        throw const InvalidSyncPayloadFailure();
      }
      if (assignment.ownerId != ownerId ||
          assignment.experimentId != experimentId ||
          assignment.experimentVersion != experimentVersion ||
          assignment.cohort != cohort ||
          assignment.protocolVersion != protocolVersion ||
          !assignment.assignedAtUtc.isUtc ||
          assignment.assignedAtUtc.millisecondsSinceEpoch < 0 ||
          assignment.assignedAtUtc.isAfter(occurredAtUtc)) {
        throw const InvalidSyncPayloadFailure();
      }

      final consents =
          await (database.select(database.researchConsents)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.consentVersion.equals(consentVersion),
              ))
              .get();
      if (consents.isEmpty) {
        if (unavailableAsNull) return null;
        throw const InvalidSyncPayloadFailure();
      }
      if (consents.length != 1) throw const InvalidSyncPayloadFailure();
      final consent = consents.single;
      final decisionUtcMs = consent.decidedAtUtcMs;
      if (decisionUtcMs < 0 ||
          decisionUtcMs > assignment.assignedAtUtc.millisecondsSinceEpoch) {
        throw const InvalidSyncPayloadFailure();
      }
      if (consent.consentState != 'accepted' ||
          consent.withdrawnAtUtcMs != null) {
        if (unavailableAsNull) return null;
        throw const InvalidSyncPayloadFailure();
      }
      return assignment;
    } on InvalidSyncPayloadFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  Future<String> _boundFirebaseUid(
    String ownerId, {
    String? expectedFirebaseUid,
  }) async {
    final owner = await (database.select(
      database.localOwners,
    )..where((candidate) => candidate.id.equals(ownerId))).getSingleOrNull();
    final firebaseUid = owner?.firebaseUid;
    if (firebaseUid == null ||
        (expectedFirebaseUid != null && firebaseUid != expectedFirebaseUid)) {
      throw const InvalidSyncPayloadFailure();
    }
    try {
      return _requiredId(firebaseUid, 'firebaseUid');
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  Future<void> _applyAttempt(String ownerId, SyncEntity entity) async {
    _requireImmutableEntity(entity, SyncCollection.attempts);
    final localized = await _attemptEntityForLocalPersistence(ownerId, entity);
    final localEntity = localized.entity;
    final evidenceContext = _attemptEvidenceContext(localEntity);
    final existing =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.id.equals(entity.entityId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await _handleExistingImmutable(
        ownerId: ownerId,
        entity: localEntity,
        localPayload: _attemptPayload(
          existing,
          payloadVersion: localEntity.payloadVersion,
        ),
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
    final payload = localEntity.payload;
    final sessionId = _requiredString(payload, 'sessionId');
    final wordId = _requiredString(payload, 'wordId');
    final promptMode = _requiredString(payload, 'promptMode');
    final responseTimeMs = _optionalInt(payload, 'responseTimeMs');
    final attemptNumber = _requiredInt(payload, 'attemptNumber');
    final occurredAtUtcMs = _requiredInt(payload, 'occurredAtUtcMs');
    final providerProvenance = _optionalString(payload, 'providerProvenance');
    final evidenceContextJson = jsonEncode(evidenceContext.toJson());
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
      evidenceClass: evidenceContext.evidenceClass.name,
      evidenceContextJson: evidenceContextJson,
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
    EventEnvelopeV2? sourceEvent;
    if (localEntity.payloadVersion == 2) {
      final assignment = localized.assignment;
      if (assignment == null) throw const InvalidSyncPayloadFailure();
      sourceEvent = _syncedAttemptSourceEvent(
        attemptId: localEntity.entityId,
        ownerId: ownerId,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: promptMode,
        isCorrect: isCorrect,
        attemptNumber: attemptNumber,
        occurredAtUtc: _utc(occurredAtUtcMs),
        evidenceContext: evidenceContext,
        assignment: assignment,
      );
    }
    await database
        .into(database.answerAttempts)
        .insert(
          db.AnswerAttemptsCompanion.insert(
            id: localEntity.entityId,
            ownerId: ownerId,
            sessionId: sessionId,
            wordId: wordId,
            promptMode: promptMode,
            isCorrect: isCorrect,
            responseTimeMs: Value(responseTimeMs),
            attemptNumber: attemptNumber,
            occurredAtUtcMs: occurredAtUtcMs,
            providerProvenance: Value(providerProvenance),
            evidenceClass: Value(evidenceContext.evidenceClass.name),
            evidenceContextJson: Value(evidenceContextJson),
          ),
        );
    if (sourceEvent != null) {
      await projections.evidenceDecisions.append(sourceEvent);
    }
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
    final fields = _decodeRewardTransactionPayload(
      entity.payload,
      expectedOccurredAtUtcMs: entity.clientUpdatedAtUtc.millisecondsSinceEpoch,
    );
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

    final idempotencyCollision =
        await (database.select(database.rewardTransactions)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.idempotencyKey.equals(fields.idempotencyKey),
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
    final sourceEventId = fields.sourceEventId;
    if (sourceEventId != null) {
      final sourceCollision = await _rewardSourceCollision(
        ownerId: ownerId,
        entityId: entity.entityId,
        sourceEventId: sourceEventId,
      );
      if (sourceCollision != null) {
        await _recordImmutableConflict(
          ownerId: ownerId,
          entity: entity,
          localPayload: _rewardTransactionPayload(sourceCollision),
          resolvedAtUtc: entity.serverUpdatedAtUtc,
        );
        return;
      }
    }

    await database
        .into(database.rewardTransactions)
        .insert(
          db.RewardTransactionsCompanion.insert(
            id: entity.entityId,
            ownerId: ownerId,
            idempotencyKey: fields.idempotencyKey,
            transactionType: fields.transactionType,
            amount: fields.amount,
            itemId: Value(fields.itemId),
            catalogVersion: fields.catalogVersion,
            sourceEventId: Value(fields.sourceEventId),
            occurredAtUtcMs: fields.occurredAtUtcMs,
          ),
        );
    await rewardProjections.rebuild(ownerId);
  }

  Future<db.RewardTransaction?> _rewardSourceCollision({
    required String ownerId,
    required String entityId,
    required String sourceEventId,
  }) {
    return (database.select(database.rewardTransactions)
          ..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.sourceEventId.equals(sourceEventId) &
                row.id.equals(entityId).not(),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  /// Apply a pulled [SyncCollection.srsStates] entity.
  ///
  /// Local immutable answer evidence is authoritative. When such evidence is
  /// present the projection is rebuilt from it; the cloud cache is used only
  /// when this owner has no local answer evidence for the word.
  Future<void> _applySrsState(String ownerId, SyncEntity entity) async {
    _requireMutableSrsEntity(entity);
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

    if (await _hasAnswerEvidence(ownerId, wordId)) {
      await projections.rebuildWord(ownerId: ownerId, wordId: wordId);
      return;
    }

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

  Future<bool> _hasAnswerEvidence(String ownerId, String wordId) async {
    final evidence =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
              )
              ..limit(1))
            .getSingleOrNull();
    return evidence != null;
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

  Future<void> _applyExperimentAssignment(
    String ownerId,
    SyncEntity entity,
  ) async {
    final owner = await (database.select(
      database.localOwners,
    )..where((candidate) => candidate.id.equals(ownerId))).getSingleOrNull();
    final firebaseUid = owner?.firebaseUid;
    var localPayload = <String, Object?>{};
    final localById =
        await (database.select(database.experimentAssignments)..where(
              (candidate) =>
                  candidate.id.equals(entity.entityId) &
                  candidate.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (localById != null) {
      localPayload = _experimentAssignmentRowPayload(
        localById,
        firebaseUid: firebaseUid ?? ownerId,
      );
    }

    try {
      _requireImmutableEntity(entity, SyncCollection.experimentAssignments);
      if (firebaseUid == null) throw const InvalidSyncPayloadFailure();
      ExperimentAssignmentSyncPayloadContract.requireCanonical(
        payload: entity.payload,
        expectedEntityId: entity.entityId,
        expectedOwnerId: firebaseUid,
        expectedAssignedAtUtcMs:
            entity.clientUpdatedAtUtc.millisecondsSinceEpoch,
      );
      final experimentId = entity.payload['experimentId']! as String;
      final experimentVersion = entity.payload['experimentVersion']! as int;
      final cloudAssignmentId =
          DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
            firebaseUid: firebaseUid,
            experimentId: experimentId,
            experimentVersion: experimentVersion,
          );
      if (entity.entityId != cloudAssignmentId ||
          entity.payload['assignmentId'] != cloudAssignmentId) {
        throw const InvalidSyncPayloadFailure();
      }
      final localAssignmentId =
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: ownerId,
            experimentId: experimentId,
            experimentVersion: experimentVersion,
          );
      final localByIdentity =
          await (database.select(database.experimentAssignments)..where(
                (candidate) =>
                    candidate.ownerId.equals(ownerId) &
                    candidate.experimentId.equals(experimentId) &
                    candidate.experimentVersion.equals(experimentVersion),
              ))
              .getSingleOrNull();
      if (localByIdentity != null) {
        localPayload = _experimentAssignmentRowPayload(
          localByIdentity,
          firebaseUid: firebaseUid,
        );
      }
      final assignment = ExperimentAssignment(
        id: localAssignmentId,
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
        cohort: entity.payload['cohort']! as String,
        protocolVersion: entity.payload['protocolVersion']! as String,
        assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          entity.payload['assignedAtUtcMs']! as int,
          isUtc: true,
        ),
      );
      final persisted = await DriftExperimentAssignmentRepository(
        database,
      ).persistRemote(assignment);
      if (persisted != assignment) {
        throw ExperimentAssignmentConflict(
          ownerId: ownerId,
          experimentId: experimentId,
          experimentVersion: experimentVersion,
        );
      }
      await _resolvePendingImmutableOutbox(
        ownerId: ownerId,
        entity: entity,
        failureCode: 'identicalCloudEvidence',
        additionalEntityId: localAssignmentId,
      );
    } on SyncFailure {
      await _recordImmutableConflict(
        ownerId: ownerId,
        entity: entity,
        localPayload: localPayload,
        resolvedAtUtc: entity.serverUpdatedAtUtc,
      );
    } on ExperimentAssignmentConflict {
      await _recordImmutableConflict(
        ownerId: ownerId,
        entity: entity,
        localPayload: localPayload,
        resolvedAtUtc: entity.serverUpdatedAtUtc,
      );
    } on ArgumentError {
      await _recordImmutableConflict(
        ownerId: ownerId,
        entity: entity,
        localPayload: localPayload,
        resolvedAtUtc: entity.serverUpdatedAtUtc,
      );
    }
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
    required Map<String, Object?> claimedPayload,
    required SyncEntity cloudEntity,
    required DateTime resolvedAtUtc,
  }) async {
    if (_jsonEquivalent(claimedPayload, cloudEntity.payload)) {
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
    final localPayload = await _localSnapshot(operation);
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
    String? additionalEntityId,
  }) async {
    await (database.update(database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals(entity.collection.entityType) &
              (row.entityId.equals(entity.entityId) |
                  (additionalEntityId == null
                      ? const Constant<bool>(false)
                      : row.entityId.equals(additionalEntityId))) &
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
      case SyncCollection.experimentAssignments:
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

Map<String, Object?> _attemptPayload(
  db.AnswerAttempt attempt, {
  required int payloadVersion,
}) {
  final context = _storedAttemptEvidenceContext(attempt);
  final payload = <String, Object?>{
    'sessionId': attempt.sessionId,
    'wordId': attempt.wordId,
    'promptMode': attempt.promptMode,
    'isCorrect': attempt.isCorrect,
    'responseTimeMs': attempt.responseTimeMs,
    'attemptNumber': attempt.attemptNumber,
    'occurredAtUtcMs': attempt.occurredAtUtcMs,
    'providerProvenance': attempt.providerProvenance,
  };
  switch (payloadVersion) {
    case 1:
      if (context.classificationSource !=
          EvidenceClassificationSource.legacyInferred) {
        throw const InvalidSyncPayloadFailure();
      }
      break;
    case 2:
      if (context.classificationSource !=
          EvidenceClassificationSource.declared) {
        throw const InvalidSyncPayloadFailure();
      }
      payload['evidenceClass'] = context.evidenceClass.name;
      payload['evidenceContext'] = context.toJson();
      break;
    default:
      throw const UnsupportedSyncSchemaFailure();
  }
  AnswerAttemptSyncPayloadContract.requireEvidenceContext(
    payloadVersion: payloadVersion,
    payload: payload,
  );
  return payload;
}

bool _hasResearchAssignmentIdentity(EvidenceContext context) {
  return context.classificationSource ==
          EvidenceClassificationSource.declared &&
      context.rolloutMode != EvidencePolicyRolloutMode.legacy;
}

Map<String, Object?> _attemptPayloadWithAssignmentId(
  Map<String, Object?> payload, {
  required EvidenceContext context,
  required String assignmentId,
}) {
  try {
    final translatedContext = EvidenceContext.fromJson(<String, Object?>{
      ...context.toJson(),
      'assignmentId': assignmentId,
    });
    final translatedPayload = <String, Object?>{
      ...payload,
      'evidenceContext': translatedContext.toJson(),
    };
    final validated = AnswerAttemptSyncPayloadContract.requireEvidenceContext(
      payloadVersion: 2,
      payload: translatedPayload,
    );
    if (validated.evidenceClass != context.evidenceClass ||
        translatedPayload['evidenceClass'] != context.evidenceClass.name) {
      throw const InvalidSyncPayloadFailure();
    }
    return Map<String, Object?>.unmodifiable(translatedPayload);
  } on InvalidSyncPayloadFailure {
    rethrow;
  } catch (_) {
    throw const InvalidSyncPayloadFailure();
  }
}

int _attemptPayloadVersionFor(
  db.AnswerAttempt attempt,
  SyncPayloadRollout payloadRollout,
) {
  final context = _storedAttemptEvidenceContext(attempt);
  switch (context.classificationSource) {
    case EvidenceClassificationSource.legacyInferred:
      return 1;
    case EvidenceClassificationSource.declared:
      if (payloadRollout.writeVersionFor(SyncCollection.attempts) < 2) {
        throw const InvalidSyncPayloadFailure();
      }
      return 2;
  }
}

EvidenceContext _storedAttemptEvidenceContext(db.AnswerAttempt attempt) {
  try {
    final decoded = jsonDecode(attempt.evidenceContextJson);
    if (decoded is! Map) throw const FormatException();
    final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
    if (attempt.evidenceClass != context.evidenceClass.name) {
      throw const FormatException();
    }
    return context;
  } catch (_) {
    throw const InvalidSyncPayloadFailure();
  }
}

EvidenceContext _attemptEvidenceContext(SyncEntity entity) {
  return AnswerAttemptSyncPayloadContract.requireEvidenceContext(
    payloadVersion: entity.payloadVersion,
    payload: entity.payload,
  );
}

EventEnvelopeV2 _syncedAttemptSourceEvent({
  required String attemptId,
  required String ownerId,
  required String sessionId,
  required String wordId,
  required String promptMode,
  required bool isCorrect,
  required int attemptNumber,
  required DateTime occurredAtUtc,
  required EvidenceContext evidenceContext,
  required ExperimentAssignment assignment,
}) {
  final consentVersion = evidenceContext.researchConsentVersion;
  final experimentId = evidenceContext.experimentId;
  final cohort = evidenceContext.cohort;
  if (consentVersion == null || experimentId == null || cohort == null) {
    throw const InvalidSyncPayloadFailure();
  }
  if (assignment.id != evidenceContext.assignmentId ||
      assignment.experimentId != experimentId ||
      assignment.experimentVersion != evidenceContext.experimentVersion ||
      assignment.cohort != cohort ||
      assignment.protocolVersion != evidenceContext.protocolVersion ||
      !assignment.assignedAtUtc.isUtc ||
      assignment.assignedAtUtc.isAfter(occurredAtUtc)) {
    throw const InvalidSyncPayloadFailure();
  }
  final eventContext = LearningEventContext(
    consentContext: ConsentContext(
      researchConsentVersion: consentVersion,
      aiConsentGranted: false,
      voiceConsentGranted: false,
      socialConsentGranted: false,
    ),
    experimentContext: ExperimentContext(
      experimentId: experimentId,
      variantId: cohort,
      assignedAtUtc: assignment.assignedAtUtc,
    ),
    protocolId: evidenceContext.protocolId,
    protocolVersion: evidenceContext.protocolVersion,
    experimentVersion: evidenceContext.experimentVersion,
    assignmentId: evidenceContext.assignmentId,
    featureContractIdentity: FeatureContractIdentity(
      revision: evidenceContext.featureContractRevision,
      semanticHash: evidenceContext.featureContractHash,
    ),
  );
  try {
    return const EventV1ToV2Adapter(
      appVersion: 'synced',
      buildId: 'synced',
    ).adaptFromCommand(
      sourceEvidenceId: attemptId,
      ownerId: ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      attemptNumber: attemptNumber,
      occurredAtUtc: occurredAtUtc,
      evidenceContext: evidenceContext,
      learningEventContext: eventContext,
    );
  } catch (_) {
    throw const InvalidSyncPayloadFailure();
  }
}

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
  final payload = <String, Object?>{
    'idempotencyKey': transaction.idempotencyKey,
    'transactionType': transaction.transactionType,
    'amount': transaction.amount,
    'itemId': transaction.itemId,
    'slot': item?.slot,
    'catalogVersion': transaction.catalogVersion,
    'sourceEventId': transaction.sourceEventId,
    'occurredAtUtcMs': transaction.occurredAtUtcMs,
  };
  _decodeRewardTransactionPayload(
    payload,
    expectedOccurredAtUtcMs: transaction.occurredAtUtcMs,
  );
  return payload;
}

const Set<String> _rewardTransactionPayloadKeys = <String>{
  'idempotencyKey',
  'transactionType',
  'amount',
  'itemId',
  'slot',
  'catalogVersion',
  'sourceEventId',
  'occurredAtUtcMs',
};

_RewardTransactionFields _decodeRewardTransactionPayload(
  Map<String, Object?> payload, {
  required int expectedOccurredAtUtcMs,
}) {
  if (payload.length != _rewardTransactionPayloadKeys.length ||
      !_rewardTransactionPayloadKeys.every(payload.containsKey)) {
    throw const InvalidSyncPayloadFailure();
  }
  final idempotencyKey = _requiredCanonicalRewardId(payload, 'idempotencyKey');
  final transactionType = _requiredString(payload, 'transactionType');
  final amount = _requiredInt(payload, 'amount');
  final itemId = _optionalString(payload, 'itemId');
  final slot = _optionalString(payload, 'slot');
  final catalogVersion = _requiredInt(payload, 'catalogVersion');
  final sourceEventId = _optionalString(payload, 'sourceEventId');
  final occurredAtUtcMs = _requiredInt(payload, 'occurredAtUtcMs');
  if (occurredAtUtcMs < 0 ||
      occurredAtUtcMs != expectedOccurredAtUtcMs ||
      !const EconomyTransactionPolicy().isValid(
        transactionType: transactionType,
        amount: amount,
        itemId: itemId,
        slot: slot,
        catalogVersion: catalogVersion,
        sourceEventId: sourceEventId,
      )) {
    throw const InvalidSyncPayloadFailure();
  }
  return _RewardTransactionFields(
    idempotencyKey: idempotencyKey,
    transactionType: transactionType,
    amount: amount,
    itemId: itemId,
    catalogVersion: catalogVersion,
    sourceEventId: sourceEventId,
    occurredAtUtcMs: occurredAtUtcMs,
  );
}

String _requiredCanonicalRewardId(Map<String, Object?> payload, String key) {
  final value = _requiredString(payload, key);
  if (value.trim() != value || value.runes.length > 256) {
    throw const InvalidSyncPayloadFailure();
  }
  return value;
}

final class _RewardTransactionFields {
  const _RewardTransactionFields({
    required this.idempotencyKey,
    required this.transactionType,
    required this.amount,
    required this.itemId,
    required this.catalogVersion,
    required this.sourceEventId,
    required this.occurredAtUtcMs,
  });

  final String idempotencyKey;
  final String transactionType;
  final int amount;
  final String? itemId;
  final int catalogVersion;
  final String? sourceEventId;
  final int occurredAtUtcMs;
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

Map<String, Object?> _experimentAssignmentPayload(
  ExperimentAssignment assignment, {
  required String firebaseUid,
}) => <String, Object?>{
  'assignmentId':
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: firebaseUid,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      ),
  'ownerId': firebaseUid,
  'experimentId': assignment.experimentId,
  'experimentVersion': assignment.experimentVersion,
  'cohort': assignment.cohort,
  'protocolVersion': assignment.protocolVersion,
  'assignedAtUtcMs': assignment.assignedAtUtc.millisecondsSinceEpoch,
};

Map<String, Object?> _experimentAssignmentRowPayload(
  db.ExperimentAssignmentRow assignment, {
  required String firebaseUid,
}) => <String, Object?>{
  'assignmentId':
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: firebaseUid,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      ),
  'ownerId': firebaseUid,
  'experimentId': assignment.experimentId,
  'experimentVersion': assignment.experimentVersion,
  'cohort': assignment.cohort,
  'protocolVersion': assignment.protocolVersion,
  'assignedAtUtcMs': assignment.assignedAtUtcMs,
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

void _requireMutableSrsEntity(SyncEntity entity) {
  if (entity.collection != SyncCollection.srsStates ||
      entity.revision < 1 ||
      entity.isDeleted ||
      entity.payload['wordId'] is! String ||
      entity.payload['wordId'] != entity.entityId) {
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

bool _operationComesAfter(
  db.OutboxOperation candidate,
  db.OutboxOperation reference,
) {
  final createdComparison = candidate.createdAtUtcMs.compareTo(
    reference.createdAtUtcMs,
  );
  if (createdComparison != 0) return createdComparison > 0;
  return candidate.operationId.compareTo(reference.operationId) > 0;
}

int _operationRevision(db.OutboxOperation operation) {
  final srsRevision = SrsOperationIdentity.tryParseRevision(
    operation.operationId,
  );
  if (srsRevision != null) return srsRevision;
  if (operation.entityType == 'srsState') {
    return operation.baseRevision + 1;
  }
  for (final segment in operation.operationId.split(':').reversed) {
    final revision = int.tryParse(segment);
    if (revision != null && revision > 0) return revision;
  }
  return operation.baseRevision + 1;
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
