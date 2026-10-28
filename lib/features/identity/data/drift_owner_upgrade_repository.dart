import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../learning/data/drift_learning_projection_rebuilder.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import '../domain/owner_upgrade.dart';

typedef OwnerUpgradeUtcNow = DateTime Function();
typedef OwnerUpgradeIdGenerator = String Function();

final class DriftOwnerUpgradeRepository implements OwnerUpgradeRepository {
  DriftOwnerUpgradeRepository(
    this._database, {
    required this.nowUtc,
    required this.generateConflictId,
    required this.generateOwnerId,
  });

  final db.AppDatabase _database;
  final OwnerUpgradeUtcNow nowUtc;
  final OwnerUpgradeIdGenerator generateConflictId;
  final OwnerUpgradeIdGenerator generateOwnerId;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) {
    final sourceId = _requiredId(activeOwnerId, 'activeOwnerId');
    final uid = _requiredId(firebaseUid, 'firebaseUid');
    return _serialized(
      () => _database.transaction(() async {
        final source = await _ownerById(sourceId);
        if (source == null || !source.isActive) {
          throw StateError('active local owner was not found');
        }
        if (source.firebaseUid == uid) {
          return OwnerUpgradeResult(
            targetOwnerId: source.id,
            mode: OwnerUpgradeMode.alreadyBound,
            conflictCount: 0,
          );
        }

        final target = await _ownerByFirebaseUid(uid);
        final upgradedAt = _requireUtc(nowUtc()).millisecondsSinceEpoch;
        if (target == null) {
          await _requeueOwnerForNewCloudNamespace(source.id, upgradedAt);
          await (_database.update(
            _database.localOwners,
          )..where((row) => row.id.equals(source.id))).write(
            db.LocalOwnersCompanion(
              firebaseUid: Value(uid),
              accountState: const Value('firebaseBound'),
              upgradedAtUtcMs: Value(upgradedAt),
            ),
          );
          return OwnerUpgradeResult(
            targetOwnerId: source.id,
            mode: OwnerUpgradeMode.anonymousBound,
            conflictCount: 0,
          );
        }

        var conflicts = 0;
        conflicts += await _mergeCategories(source.id, target.id, upgradedAt);
        conflicts += await _mergeWords(source.id, target.id, upgradedAt);
        await _makeImportKeysUnique(source.id, target.id);
        conflicts += await _makeRewardKeysUnique(
          source.id,
          target.id,
          upgradedAt,
        );
        conflicts += await _discardNaturalKeyDuplicates(
          source.id,
          target.id,
          upgradedAt,
        );
        await _requeueOwnerForNewCloudNamespace(source.id, upgradedAt);
        await _moveOwnerRows(source.id, target.id);
        await _rebuildLearningProjections(target.id);
        await DriftRewardProjectionRebuilder(_database).rebuild(target.id);

        await _database.customUpdate(
          'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
        );
        await _database.customUpdate(
          'UPDATE local_owners '
          'SET is_active = 1, account_state = ?, upgraded_at_utc_ms = ? '
          'WHERE id = ?',
          variables: [
            const Variable<String>('firebaseBound'),
            Variable<int>(upgradedAt),
            Variable<String>(target.id),
          ],
          updates: {_database.localOwners},
        );
        await _database.customUpdate(
          'UPDATE local_owners '
          'SET account_state = ?, upgraded_at_utc_ms = ? WHERE id = ?',
          variables: [
            Variable<String>('mergedInto:${target.id}'),
            Variable<int>(upgradedAt),
            Variable<String>(source.id),
          ],
          updates: {_database.localOwners},
        );
        return OwnerUpgradeResult(
          targetOwnerId: target.id,
          mode: OwnerUpgradeMode.mergedExisting,
          conflictCount: conflicts,
        );
      }),
    );
  }

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    return _serialized(
      () => _database.transaction(() async {
        final ownerId = 'local:${_requiredId(generateOwnerId(), 'ownerId')}';
        final createdAt = _requireUtc(nowUtc()).millisecondsSinceEpoch;
        await _database.customUpdate(
          'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
          updates: {_database.localOwners},
        );
        await _database
            .into(_database.localOwners)
            .insert(
              db.LocalOwnersCompanion.insert(
                id: ownerId,
                createdAtUtcMs: createdAt,
              ),
            );
        return OwnerUpgradeResult(
          targetOwnerId: ownerId,
          mode: OwnerUpgradeMode.localGuestCreated,
          conflictCount: 0,
        );
      }),
    );
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    final previous = _requiredId(previousOwnerId, 'previousOwnerId');
    final guest = _requiredId(guestOwnerId, 'guestOwnerId');
    return _serialized(
      () => _database.transaction(() async {
        final guestRow = await _ownerById(guest);
        final previousRow = await _ownerById(previous);
        if (guestRow == null ||
            previousRow == null ||
            !guestRow.isActive ||
            guestRow.firebaseUid != null) {
          throw StateError('logout rollback state is no longer safe');
        }
        await (_database.delete(
          _database.localOwners,
        )..where((row) => row.id.equals(guest))).go();
        await (_database.update(_database.localOwners)
              ..where((row) => row.id.equals(previous)))
            .write(const db.LocalOwnersCompanion(isActive: Value(true)));
      }),
    );
  }

  Future<int> _mergeCategories(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.name AS guest_name, target.name AS target_name
      FROM vocabulary_categories guest
      JOIN vocabulary_categories target
        ON target.owner_id = ?
       AND target.normalized_name = guest.normalized_name
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetCategoryId = collision.read<String>('target_id');
      await _database.customUpdate(
        'UPDATE vocabulary_words SET category_id = ? WHERE category_id = ?',
        variables: [
          Variable<String>(targetCategoryId),
          Variable<String>(guestId),
        ],
        updates: {_database.vocabularyWords},
      );
      await _database.customUpdate(
        'UPDATE vocabulary_imports SET category_id = ? WHERE category_id = ?',
        variables: [
          Variable<String>(targetCategoryId),
          Variable<String>(guestId),
        ],
        updates: {_database.vocabularyImports},
      );
      await _retireDuplicateOutbox(sourceId, 'category', guestId);
      await _remapEntityReferences('category', guestId, targetCategoryId);
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'category',
        entityId: targetCategoryId,
        localSnapshot: <String, Object?>{
          'id': guestId,
          'name': collision.read<String>('guest_name'),
        },
        targetSnapshot: <String, Object?>{
          'id': targetCategoryId,
          'name': collision.read<String>('target_name'),
        },
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM vocabulary_categories WHERE id = ?',
        variables: [Variable<String>(guestId)],
        updates: {_database.vocabularyCategories},
      );
    }
    return collisions.length;
  }

  Future<int> _mergeWords(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.spelling AS guest_spelling,
             target.spelling AS target_spelling
      FROM vocabulary_words guest
      JOIN vocabulary_words target
        ON target.owner_id = ?
       AND target.category_id = guest.category_id
       AND target.normalized_spelling = guest.normalized_spelling
       AND target.normalized_meaning = guest.normalized_meaning
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetWordId = collision.read<String>('target_id');
      await _database.customUpdate(
        'UPDATE answer_attempts SET word_id = ? WHERE word_id = ?',
        variables: [Variable<String>(targetWordId), Variable<String>(guestId)],
        updates: {_database.answerAttempts},
      );
      await _database.customUpdate(
        'UPDATE vocabulary_import_rows SET word_id = ? WHERE word_id = ?',
        variables: [Variable<String>(targetWordId), Variable<String>(guestId)],
        updates: {_database.vocabularyImportRows},
      );
      await _database.customUpdate(
        'UPDATE srs_states SET word_id = ? WHERE word_id = ?',
        variables: [Variable<String>(targetWordId), Variable<String>(guestId)],
        updates: {_database.srsStates},
      );
      await _retireDuplicateOutbox(sourceId, 'word', guestId);
      await _remapEntityReferences('word', guestId, targetWordId);
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'word',
        entityId: targetWordId,
        localSnapshot: <String, Object?>{
          'id': guestId,
          'spelling': collision.read<String>('guest_spelling'),
        },
        targetSnapshot: <String, Object?>{
          'id': targetWordId,
          'spelling': collision.read<String>('target_spelling'),
        },
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM vocabulary_words WHERE id = ?',
        variables: [Variable<String>(guestId)],
        updates: {_database.vocabularyWords},
      );
    }
    return collisions.length;
  }

  Future<void> _makeImportKeysUnique(String sourceId, String targetId) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, guest.source_hash AS source_hash
      FROM vocabulary_imports guest
      JOIN vocabulary_imports target
        ON target.owner_id = ?
       AND target.category_id = guest.category_id
       AND target.source_hash = guest.source_hash
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final id = collision.read<String>('guest_id');
      final hash = collision.read<String>('source_hash');
      await _database.customUpdate(
        'UPDATE vocabulary_imports SET source_hash = ? WHERE id = ?',
        variables: [Variable<String>('$hash:merged:$id'), Variable<String>(id)],
        updates: {_database.vocabularyImports},
      );
    }
  }

  Future<int> _makeRewardKeysUnique(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.idempotency_key AS idempotency_key
      FROM reward_transactions guest
      JOIN reward_transactions target
        ON target.owner_id = ?
       AND target.idempotency_key = guest.idempotency_key
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetTransactionId = collision.read<String>('target_id');
      final key = collision.read<String>('idempotency_key');
      final suffix = guestId.length > 220
          ? guestId.substring(guestId.length - 220)
          : guestId;
      await (_database.update(
        _database.rewardTransactions,
      )..where((row) => row.id.equals(guestId))).write(
        db.RewardTransactionsCompanion(idempotencyKey: Value('merged:$suffix')),
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'rewardTransaction',
        entityId: targetTransactionId,
        localSnapshot: <String, Object?>{'id': guestId, 'idempotencyKey': key},
        targetSnapshot: <String, Object?>{
          'id': targetTransactionId,
          'idempotencyKey': key,
        },
        resolvedAt: resolvedAt,
      );
    }
    return collisions.length;
  }

  Future<int> _discardNaturalKeyDuplicates(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    var conflicts = 0;
    for (final specification in const <_DuplicateSpecification>[
      _DuplicateSpecification(
        table: 'research_consents',
        entityType: 'researchConsent',
        join: 'target.consent_version = guest.consent_version',
      ),
      _DuplicateSpecification(
        table: 'srs_states',
        entityType: 'srsState',
        join: 'target.word_id = guest.word_id',
      ),
      _DuplicateSpecification(
        table: 'reading_progress_entries',
        entityType: 'readingProgress',
        join:
            'target.document_id = guest.document_id AND '
            'target.document_revision = guest.document_revision',
      ),
      _DuplicateSpecification(
        table: 'points_ledger_entries',
        entityType: 'pointsLedger',
        join: 'target.idempotency_key = guest.idempotency_key',
      ),
      _DuplicateSpecification(
        table: 'achievement_unlocks',
        entityType: 'achievement',
        join:
            'target.achievement_id = guest.achievement_id AND '
            'target.definition_version = guest.definition_version',
      ),
      _DuplicateSpecification(
        table: 'equipped_reward_items',
        entityType: 'equippedReward',
        join: 'target.slot = guest.slot',
      ),
      _DuplicateSpecification(
        table: 'owned_reward_items',
        entityType: 'ownedReward',
        join: 'target.item_id = guest.item_id',
      ),
      _DuplicateSpecification(
        table: 'sync_checkpoints',
        entityType: 'syncCheckpoint',
        join: 'target.collection_name = guest.collection_name',
      ),
    ]) {
      final duplicates = await _database
          .customSelect(
            '''
        SELECT guest.id AS guest_id, target.id AS target_id
        FROM ${specification.table} guest
        JOIN ${specification.table} target
          ON target.owner_id = ? AND ${specification.join}
        WHERE guest.owner_id = ?
        ORDER BY guest.id
        ''',
            variables: [Variable<String>(targetId), Variable<String>(sourceId)],
          )
          .get();
      for (final duplicate in duplicates) {
        final guestId = duplicate.read<String>('guest_id');
        final targetEntityId = duplicate.read<String>('target_id');
        await _recordMergeConflict(
          ownerId: targetId,
          entityType: specification.entityType,
          entityId: targetEntityId,
          localSnapshot: <String, Object?>{'id': guestId},
          targetSnapshot: <String, Object?>{'id': targetEntityId},
          resolvedAt: resolvedAt,
        );
        await _database.customUpdate(
          'DELETE FROM ${specification.table} WHERE id = ?',
          variables: [Variable<String>(guestId)],
        );
        conflicts += 1;
      }
    }
    return conflicts;
  }

  Future<void> _moveOwnerRows(String sourceId, String targetId) async {
    for (final table in ownerUpgradeInventory) {
      await _updateOwner(table, sourceId, targetId);
    }
    await _database.customUpdate(
      "UPDATE outbox_operations "
      "SET state = 'pending', lease_token = NULL, lease_expires_at_utc_ms = NULL "
      "WHERE owner_id = ? AND state = 'blockedAuth'",
      variables: [Variable<String>(targetId)],
      updates: {_database.outboxOperations},
    );
  }

  Future<void> _requeueOwnerForNewCloudNamespace(
    String ownerId,
    int rehomedAtUtcMs,
  ) async {
    await (_database.update(
      _database.vocabularyCategories,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.VocabularyCategoriesCompanion(
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await (_database.update(
      _database.vocabularyWords,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.VocabularyWordsCompanion(
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await (_database.update(
      _database.syncCheckpoints,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.SyncCheckpointsCompanion(
        serverCursor: Value(null),
        lastSuccessAtUtcMs: Value(null),
      ),
    );

    for (final specification in const <_RehomeSpecification>[
      _RehomeSpecification(
        table: 'vocabulary_categories',
        entityType: 'category',
        hasSoftDelete: true,
      ),
      _RehomeSpecification(
        table: 'vocabulary_words',
        entityType: 'word',
        hasSoftDelete: true,
      ),
      _RehomeSpecification(table: 'answer_attempts', entityType: 'attempt'),
      _RehomeSpecification(table: 'reading_events', entityType: 'readingEvent'),
      _RehomeSpecification(
        table: 'reward_transactions',
        entityType: 'rewardTransaction',
      ),
    ]) {
      final rows = await _database
          .customSelect(
            'SELECT id${specification.hasSoftDelete ? ', is_deleted' : ''} '
            'FROM ${specification.table} WHERE owner_id = ? ORDER BY id',
            variables: [Variable<String>(ownerId)],
          )
          .get();
      for (final row in rows) {
        final entityId = row.read<String>('id');
        final changed = await _database.customUpdate(
          "UPDATE outbox_operations SET base_revision = 0, state = 'pending', "
          'attempt_count = 0, next_attempt_at_utc_ms = NULL, '
          'lease_token = NULL, lease_expires_at_utc_ms = NULL, '
          'last_attempt_at_utc_ms = NULL, acknowledged_at_utc_ms = NULL, '
          'failure_code = NULL '
          'WHERE owner_id = ? AND entity_type = ? AND entity_id = ?',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(specification.entityType),
            Variable<String>(entityId),
          ],
          updates: {_database.outboxOperations},
        );
        if (changed > 0) continue;
        final generated = _requiredId(generateConflictId(), 'operationId');
        await _database
            .into(_database.outboxOperations)
            .insert(
              db.OutboxOperationsCompanion.insert(
                operationId: _requiredId('rehome:$generated', 'operationId'),
                ownerId: ownerId,
                entityType: specification.entityType,
                entityId: entityId,
                operationKind:
                    specification.hasSoftDelete &&
                        row.read<int>('is_deleted') != 0
                    ? 'delete'
                    : 'upsert',
                createdAtUtcMs: rehomedAtUtcMs,
              ),
            );
      }
    }
  }

  Future<void> _rebuildLearningProjections(String ownerId) async {
    final rebuilder = DriftLearningProjectionRebuilder(_database);
    final wordRows = await _database
        .customSelect(
          'SELECT DISTINCT word_id FROM answer_attempts '
          'WHERE owner_id = ? ORDER BY word_id',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    for (final row in wordRows) {
      await rebuilder.rebuildWord(
        ownerId: ownerId,
        wordId: row.read<String>('word_id'),
      );
    }

    final sessionRows = await _database
        .customSelect(
          'SELECT DISTINCT session_id FROM answer_attempts '
          'WHERE owner_id = ? ORDER BY session_id',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    for (final row in sessionRows) {
      await rebuilder.rebuildSession(
        ownerId: ownerId,
        sessionId: row.read<String>('session_id'),
      );
    }
    await rebuilder.rebuildAchievements(ownerId);

    final readingRows = await _database
        .customSelect(
          'SELECT DISTINCT document_id, document_revision FROM reading_events '
          'WHERE owner_id = ? ORDER BY document_id, document_revision',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    for (final row in readingRows) {
      await rebuilder.rebuildReading(
        ownerId: ownerId,
        documentId: row.read<String>('document_id'),
        documentRevision: row.read<int>('document_revision'),
      );
    }
  }

  Future<void> _updateOwner(String table, String sourceId, String targetId) {
    return _database.customUpdate(
      'UPDATE $table SET owner_id = ? WHERE owner_id = ?',
      variables: [Variable<String>(targetId), Variable<String>(sourceId)],
    );
  }

  Future<void> _remapEntityReferences(
    String entityType,
    String sourceEntityId,
    String targetEntityId,
  ) async {
    await _database.customUpdate(
      'UPDATE outbox_operations SET entity_id = ? '
      'WHERE entity_type = ? AND entity_id = ?',
      variables: [
        Variable<String>(targetEntityId),
        Variable<String>(entityType),
        Variable<String>(sourceEntityId),
      ],
      updates: {_database.outboxOperations},
    );
    await _database.customUpdate(
      'UPDATE sync_conflicts SET entity_id = ? '
      'WHERE entity_type = ? AND entity_id = ?',
      variables: [
        Variable<String>(targetEntityId),
        Variable<String>(entityType),
        Variable<String>(sourceEntityId),
      ],
      updates: {_database.syncConflicts},
    );
  }

  Future<void> _retireDuplicateOutbox(
    String ownerId,
    String entityType,
    String entityId,
  ) {
    return (_database.update(_database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals(entityType) &
              row.entityId.equals(entityId),
        ))
        .write(
          const db.OutboxOperationsCompanion(
            state: Value('superseded'),
            nextAttemptAtUtcMs: Value(null),
            leaseToken: Value(null),
            leaseExpiresAtUtcMs: Value(null),
            failureCode: Value('guestUpgradeDuplicate'),
          ),
        );
  }

  Future<void> _recordMergeConflict({
    required String ownerId,
    required String entityType,
    required String entityId,
    required Map<String, Object?> localSnapshot,
    required Map<String, Object?> targetSnapshot,
    required int resolvedAt,
  }) async {
    final conflictId = _requiredId(generateConflictId(), 'conflictId');
    await _database.customInsert(
      '''
      INSERT INTO sync_conflicts
        (id, owner_id, entity_type, entity_id, local_revision, cloud_revision,
         resolution_policy, outcome, local_snapshot_json,
         cloud_snapshot_json, resolved_at_utc_ms)
      VALUES (?, ?, ?, ?, 0, 0, 'guestUpgradeTargetWins',
              'targetRetained', ?, ?, ?)
      ''',
      variables: [
        Variable<String>(conflictId),
        Variable<String>(ownerId),
        Variable<String>(entityType),
        Variable<String>(entityId),
        Variable<String>(jsonEncode(localSnapshot)),
        Variable<String>(jsonEncode(targetSnapshot)),
        Variable<int>(resolvedAt),
      ],
      updates: {_database.syncConflicts},
    );
  }

  Future<db.LocalOwner?> _ownerById(String id) {
    return (_database.select(
      _database.localOwners,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<db.LocalOwner?> _ownerByFirebaseUid(String uid) {
    return (_database.select(
      _database.localOwners,
    )..where((row) => row.firebaseUid.equals(uid))).getSingleOrNull();
  }

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _writeGate;
    final completer = Completer<void>();
    _writeGate = completer.future;
    try {
      await previous;
      return await operation();
    } finally {
      completer.complete();
    }
  }
}

final class _DuplicateSpecification {
  const _DuplicateSpecification({
    required this.table,
    required this.entityType,
    required this.join,
  });

  final String table;
  final String entityType;
  final String join;
}

final class _RehomeSpecification {
  const _RehomeSpecification({
    required this.table,
    required this.entityType,
    this.hasSoftDelete = false,
  });

  final String table;
  final String entityType;
  final bool hasSoftDelete;
}

String _requiredId(String value, String field) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 256) {
    throw ArgumentError.value(value, field, 'must contain 1-256 characters');
  }
  return canonical;
}

DateTime _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
  }
  return value;
}
