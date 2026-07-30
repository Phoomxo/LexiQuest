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

final class ClaimedSyncOperation {
  const ClaimedSyncOperation({
    required this.leaseToken,
    required this.attemptCount,
    required this.mutation,
  });

  final String leaseToken;
  final int attemptCount;
  final PushMutation mutation;
}

final class DriftSyncStore {
  DriftSyncStore(this.database)
    : projections = DriftLearningProjectionRebuilder(database),
      rewardProjections = DriftRewardProjectionRebuilder(database);

  static const int maxClaimLimit = 50;
  static const int _maxCandidateMultiplier = 20;

  final db.AppDatabase database;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;
  Future<void> _claimGate = Future<void>.value();

  Future<bool> tryAcquireRunLease({
    required String ownerId,
    required String leaseToken,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    _requireUtc(nowUtc, 'nowUtc');
    if (leaseDuration <= Duration.zero) {
      throw ArgumentError.value(
        leaseDuration,
        'leaseDuration',
        'must be positive',
      );
    }
    final key = 'syncRunLease:$canonicalOwnerId';
    final nowMs = nowUtc.millisecondsSinceEpoch;
    final changed = await database.customUpdate(
      '''
      INSERT INTO runtime_flags
        ("key", bool_value, source, updated_at_utc_ms, expires_at_utc_ms)
      VALUES (?, 1, ?, ?, ?)
      ON CONFLICT("key") DO UPDATE SET
        bool_value = 1,
        source = excluded.source,
        updated_at_utc_ms = excluded.updated_at_utc_ms,
        expires_at_utc_ms = excluded.expires_at_utc_ms
      WHERE runtime_flags.bool_value = 0
         OR runtime_flags.expires_at_utc_ms IS NULL
         OR runtime_flags.expires_at_utc_ms <= ?
      ''',
      variables: [
        Variable<String>(key),
        Variable<String>(canonicalLeaseToken),
        Variable<int>(nowMs),
        Variable<int>(nowUtc.add(leaseDuration).millisecondsSinceEpoch),
        Variable<int>(nowMs),
      ],
      updates: {database.runtimeFlags},
    );
    return changed == 1;
  }

  Future<void> releaseRunLease({
    required String ownerId,
    required String leaseToken,
  }) async {
    final key = 'syncRunLease:${_requiredId(ownerId, 'ownerId')}';
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    await (database.delete(database.runtimeFlags)..where(
          (row) => row.key.equals(key) & row.source.equals(canonicalLeaseToken),
        ))
        .go();
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

  Future<List<ClaimedSyncOperation>> claimPending({
    required String ownerId,
    required String firebaseUid,
    required int limit,
    required String leaseToken,
    required Duration leaseDuration,
    required DateTime nowUtc,
  }) {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    final canonicalUid = _requiredId(firebaseUid, 'firebaseUid');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
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
        final candidateLimit = limit * _maxCandidateMultiplier;
        final query = database.select(database.outboxOperations)
          ..where(
            (row) =>
                row.ownerId.equals(canonicalOwnerId) &
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
                  attemptCount: Value(selected.attemptCount + 1),
                  nextAttemptAtUtcMs: const Value(null),
                  leaseToken: Value(canonicalLeaseToken),
                  leaseExpiresAtUtcMs: Value(
                    nowUtc.add(leaseDuration).millisecondsSinceEpoch,
                  ),
                  lastAttemptAtUtcMs: Value(nowMs),
                  failureCode: const Value(null),
                ),
              );

          claimed.add(
            ClaimedSyncOperation(
              leaseToken: canonicalLeaseToken,
              attemptCount: selected.attemptCount + 1,
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

  Future<void> acknowledge({
    required String operationId,
    required String leaseToken,
    required PushAcknowledged acknowledgement,
  }) async {
    final canonicalOperationId = _requiredId(operationId, 'operationId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
    if (acknowledgement.operationId != canonicalOperationId) {
      throw ArgumentError.value(
        acknowledgement.operationId,
        'acknowledgement.operationId',
        'must match operationId',
      );
    }

    await database.transaction(() async {
      final operation =
          await (database.select(database.outboxOperations)
                ..where((row) => row.operationId.equals(canonicalOperationId)))
              .getSingleOrNull();
      if (operation == null) {
        throw StateError('outbox operation was not found');
      }
      if (operation.state == 'acknowledged') return;
      if (operation.state != 'inFlight' ||
          operation.leaseToken != canonicalLeaseToken) {
        throw StateError('outbox operation lease does not match');
      }

      await (database.update(
        database.outboxOperations,
      )..where((row) => row.operationId.equals(canonicalOperationId))).write(
        db.OutboxOperationsCompanion(
          state: const Value('acknowledged'),
          acknowledgedAtUtcMs: Value(
            acknowledgement.acknowledgedAtUtc.millisecondsSinceEpoch,
          ),
          nextAttemptAtUtcMs: const Value(null),
          leaseToken: const Value(null),
          leaseExpiresAtUtcMs: const Value(null),
          failureCode: const Value(null),
        ),
      );
      await _acknowledgeEntity(operation, acknowledgement);
    });
  }

  Future<void> markRetry({
    required String operationId,
    required String leaseToken,
    required DateTime nextAttemptAtUtc,
    required SyncFailure failure,
  }) async {
    final canonicalOperationId = _requiredId(operationId, 'operationId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
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
      throw StateError('outbox operation lease does not match');
    }
    await (database.update(
      database.outboxOperations,
    )..where((row) => row.operationId.equals(canonicalOperationId))).write(
      db.OutboxOperationsCompanion(
        state: const Value('retryWaiting'),
        nextAttemptAtUtcMs: Value(nextAttemptAtUtc.millisecondsSinceEpoch),
        leaseToken: const Value(null),
        leaseExpiresAtUtcMs: const Value(null),
        failureCode: Value(failure.code.name),
      ),
    );
  }

  Future<void> markTerminalFailure({
    required String operationId,
    required String leaseToken,
    required SyncFailure failure,
  }) async {
    final canonicalOperationId = _requiredId(operationId, 'operationId');
    final canonicalLeaseToken = _requiredId(leaseToken, 'leaseToken');
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
      throw StateError('outbox operation lease does not match');
    }
    final state = failure is UnauthenticatedSyncFailure
        ? 'blockedAuth'
        : 'permanentFailure';
    await (database.update(
      database.outboxOperations,
    )..where((row) => row.operationId.equals(canonicalOperationId))).write(
      db.OutboxOperationsCompanion(
        state: Value(state),
        nextAttemptAtUtcMs: const Value(null),
        leaseToken: const Value(null),
        leaseExpiresAtUtcMs: const Value(null),
        failureCode: Value(failure.code.name),
      ),
    );
  }

  Future<void> resolvePushConflict({
    required ClaimedSyncOperation claim,
    required SyncEntity cloudEntity,
    required DateTime resolvedAtUtc,
  }) async {
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

    await database.transaction(() async {
      final operation =
          await (database.select(database.outboxOperations)
                ..where((row) => row.operationId.equals(mutation.operationId)))
              .getSingleOrNull();
      if (operation == null ||
          operation.state != 'inFlight' ||
          operation.leaseToken != claim.leaseToken) {
        throw StateError('outbox operation lease does not match');
      }
      if (cloudEntity.collection == SyncCollection.attempts ||
          cloudEntity.collection == SyncCollection.readingEvents ||
          cloudEntity.collection == SyncCollection.rewardTransactions) {
        await _resolveImmutableConflict(
          operation: operation,
          cloudEntity: cloudEntity,
          resolvedAtUtc: resolvedAtUtc,
        );
        return;
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
          throw const InvalidSyncPayloadFailure();
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
    });
  }

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

  Future<void> applyPullPage({
    required String ownerId,
    required SyncCollection collection,
    required PullPage page,
  }) async {
    final canonicalOwnerId = _requiredId(ownerId, 'ownerId');
    await database.transaction(() async {
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
        }
      }

      final cursor = page.nextCursor;
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
    });
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

bool _requiredBool(Map<String, Object?> payload, String key) {
  final value = _optionalBool(payload, key);
  if (value == null) throw const InvalidSyncPayloadFailure();
  return value;
}
