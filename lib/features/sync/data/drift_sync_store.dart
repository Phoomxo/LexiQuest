import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
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
  DriftSyncStore(this.database);

  static const int maxClaimLimit = 50;
  static const int _maxCandidateMultiplier = 20;

  final db.AppDatabase database;
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

bool? _optionalBool(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) return null;
  if (value is! bool) throw const InvalidSyncPayloadFailure();
  return value;
}
