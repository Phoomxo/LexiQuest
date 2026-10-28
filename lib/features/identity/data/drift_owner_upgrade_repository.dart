import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../learning/data/drift_learning_projection_rebuilder.dart';
import '../../research/domain/experiment_assignment.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import '../domain/owner_upgrade.dart';
import 'drift_owner_write_coordinator.dart';

typedef OwnerUpgradeUtcNow = DateTime Function();
typedef OwnerUpgradeIdGenerator = String Function();

final class DriftOwnerUpgradeRepository implements OwnerUpgradeRepository {
  DriftOwnerUpgradeRepository(
    this._database, {
    required this.nowUtc,
    required this.generateConflictId,
    required this.generateOwnerId,
  }) : _ownerWrites = DriftOwnerWriteCoordinator(_database, nowUtc: nowUtc);

  final db.AppDatabase _database;
  final DriftOwnerWriteCoordinator _ownerWrites;
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
        await _ownerWrites.requireOwnerUnfenced(sourceId);
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
        if (target != null) {
          await _ownerWrites.requireOwnerUnfenced(target.id);
        }
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

        await _requireActiveOwnersUnfenced();
        await _requireTransferableResearchOwner(source.id);
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
        await _mergeExperimentAssignments(source.id, target.id);
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
        await _ownerWrites.requireOwnerUnfenced(ownerId);
        await _requireActiveOwnersUnfenced();
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
        await _ownerWrites.requireOwnerUnfenced(guest);
        await _ownerWrites.requireOwnerUnfenced(previous);
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

  Future<void> _requireActiveOwnersUnfenced() async {
    final activeOwners = await (_database.select(
      _database.localOwners,
    )..where((row) => row.isActive.equals(true))).get();
    for (final owner in activeOwners) {
      await _ownerWrites.requireOwnerUnfenced(owner.id);
    }
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
      await _remapEntityReferences(
        sourceId,
        'category',
        guestId,
        targetCategoryId,
      );
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
      await _remapEntityReferences(sourceId, 'word', guestId, targetWordId);
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
      _DuplicateSpecification(
        table: 'quest_instances',
        idColumn: 'instance_id',
        entityType: 'questInstance',
        join: 'target.quest_id = guest.quest_id',
      ),
      _DuplicateSpecification(
        table: 'streak_states',
        idColumn: 'owner_id',
        entityType: 'streakState',
        join: '1 = 1',
      ),
      _DuplicateSpecification(
        table: 'learning_day_log',
        entityType: 'learningDay',
        join: 'target.learning_day = guest.learning_day',
      ),
      _DuplicateSpecification(
        table: 'association_records',
        entityType: 'associationRecord',
        join: 'target.word_key = guest.word_key AND target.type = guest.type',
      ),
      _DuplicateSpecification(
        table: 'associative_memory_states',
        entityType: 'associativeMemoryState',
        join: 'target.word_key = guest.word_key',
      ),
    ]) {
      final duplicates = await _database
          .customSelect(
            '''
        SELECT guest.${specification.idColumn} AS guest_id,
               target.${specification.idColumn} AS target_id
        FROM ${specification.table} guest
        JOIN ${specification.table} target
          ON target.owner_id = ? AND ${specification.join}
        WHERE guest.owner_id = ?
        ORDER BY guest.${specification.idColumn}
        ''',
            variables: [Variable<String>(targetId), Variable<String>(sourceId)],
          )
          .get();
      for (final duplicate in duplicates) {
        final guestId = duplicate.read<String>('guest_id');
        final targetEntityId = duplicate.read<String>('target_id');
        final guestRow = await _database
            .customSelect(
              'SELECT * FROM ${specification.table} '
              'WHERE ${specification.idColumn} = ? AND owner_id = ?',
              variables: [
                Variable<String>(guestId),
                Variable<String>(sourceId),
              ],
            )
            .getSingle();
        final targetRow = await _database
            .customSelect(
              'SELECT * FROM ${specification.table} '
              'WHERE ${specification.idColumn} = ? AND owner_id = ?',
              variables: [
                Variable<String>(targetEntityId),
                Variable<String>(targetId),
              ],
            )
            .getSingle();
        final guestSnapshot = <String, Object?>{
          'id': guestId,
          ...guestRow.data,
        };
        final targetSnapshot = <String, Object?>{
          'id': targetEntityId,
          ...targetRow.data,
        };
        if (specification.table == 'quest_instances') {
          final objectives = await _database
              .customSelect(
                'SELECT * FROM quest_objective_progress WHERE instance_id = ? ORDER BY id',
                variables: [Variable<String>(guestId)],
              )
              .get();
          guestSnapshot['objectiveProgress'] = objectives
              .map((row) => row.data)
              .toList(growable: false);
        }
        await _recordMergeConflict(
          ownerId: targetId,
          entityType: specification.entityType,
          entityId: targetEntityId,
          localSnapshot: guestSnapshot,
          targetSnapshot: targetSnapshot,
          resolvedAt: resolvedAt,
        );
        await _database.customUpdate(
          'DELETE FROM ${specification.table} '
          'WHERE ${specification.idColumn} = ? AND owner_id = ?',
          variables: [Variable<String>(guestId), Variable<String>(sourceId)],
        );
        conflicts += 1;
      }
    }
    return conflicts;
  }

  Future<void> _requireTransferableResearchOwner(String sourceId) async {
    final signed = await _database
        .customSelect(
          'SELECT 1 FROM research_participation_permits WHERE owner_id = ? LIMIT 1',
          variables: [Variable<String>(sourceId)],
        )
        .getSingleOrNull();
    if (signed != null) {
      throw StateError(
        'Changing a signed research owner requires re-enrollment',
      );
    }
  }

  Future<void> _mergeExperimentAssignments(
    String sourceId,
    String targetId,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT * FROM experiment_assignments WHERE owner_id IN (?, ?) '
          'ORDER BY owner_id, experiment_id, experiment_version',
          variables: [Variable<String>(sourceId), Variable<String>(targetId)],
        )
        .get();
    final source = <QueryRow>[];
    final target = <(String, int), QueryRow>{};
    for (final row in rows) {
      final owner = row.read<String>('owner_id');
      final experiment = row.read<String>('experiment_id');
      final version = row.read<int>('experiment_version');
      if (experiment.trim().isEmpty ||
          version <= 0 ||
          row.read<String>('cohort').trim().isEmpty ||
          row.read<String>('protocol_version').trim().isEmpty ||
          row.read<int>('assigned_at_utc_ms') < 0 ||
          row.read<String>('id') !=
              experimentAssignmentId(
                ownerId: owner,
                experimentId: experiment,
                experimentVersion: version,
              )) {
        throw StateError('invalid persisted experiment assignment');
      }
      if (owner == sourceId) {
        source.add(row);
      } else {
        target[(experiment, version)] = row;
      }
    }
    for (final row in source) {
      final experiment = row.read<String>('experiment_id');
      final version = row.read<int>('experiment_version');
      final id = experimentAssignmentId(
        ownerId: targetId,
        experimentId: experiment,
        experimentVersion: version,
      );
      final duplicate = target[(experiment, version)];
      final occupied = await _database
          .customSelect(
            'SELECT owner_id FROM experiment_assignments WHERE id = ?',
            variables: [Variable<String>(id)],
          )
          .getSingleOrNull();
      if (occupied != null &&
          (occupied.read<String>('owner_id') != targetId ||
              duplicate == null)) {
        throw StateError('experiment assignment ID belongs to another fact');
      }
      if (duplicate != null) {
        if (row.read<String>('cohort') != duplicate.read<String>('cohort') ||
            row.read<String>('protocol_version') !=
                duplicate.read<String>('protocol_version') ||
            row.read<int>('assigned_at_utc_ms') !=
                duplicate.read<int>('assigned_at_utc_ms')) {
          throw StateError(
            'experiment assignment facts conflict during owner merge',
          );
        }
        await _database.customUpdate(
          'DELETE FROM experiment_assignments WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(row.read<String>('id')),
            Variable<String>(sourceId),
          ],
          updates: {_database.experimentAssignments},
        );
      } else {
        await _database.customUpdate(
          'UPDATE experiment_assignments SET id = ?, owner_id = ? '
          'WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(id),
            Variable<String>(targetId),
            Variable<String>(row.read<String>('id')),
            Variable<String>(sourceId),
          ],
          updates: {_database.experimentAssignments},
        );
      }
    }
  }

  Future<void> _moveOwnerRows(String sourceId, String targetId) async {
    for (final table in ownerUpgradeInventory) {
      if (table == 'experiment_assignments' ||
          table == 'research_participation_permits') {
        continue;
      }
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
            'FROM ${specification.table} WHERE owner_id = ? '
            '${specification.entityType == 'rewardTransaction' ? "AND transaction_type IN ('purchase', 'equip') " : ''}'
            'ORDER BY id',
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
    String ownerId,
    String entityType,
    String sourceEntityId,
    String targetEntityId,
  ) async {
    await _database.customUpdate(
      'UPDATE outbox_operations SET entity_id = ? '
      'WHERE owner_id = ? AND entity_type = ? AND entity_id = ?',
      variables: [
        Variable<String>(targetEntityId),
        Variable<String>(ownerId),
        Variable<String>(entityType),
        Variable<String>(sourceEntityId),
      ],
      updates: {_database.outboxOperations},
    );
    await _database.customUpdate(
      'UPDATE sync_conflicts SET entity_id = ? '
      'WHERE owner_id = ? AND entity_type = ? AND entity_id = ? '
      "AND resolution_policy <> 'naturalKeyLocalTarget'",
      variables: [
        Variable<String>(targetEntityId),
        Variable<String>(ownerId),
        Variable<String>(entityType),
        Variable<String>(sourceEntityId),
      ],
      updates: {_database.syncConflicts},
    );
    final aliases =
        await (_database.select(_database.syncConflicts)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.entityType.equals(entityType) &
                  row.resolutionPolicy.equals('naturalKeyLocalTarget'),
            ))
            .get();
    for (final alias in aliases) {
      final snapshotText = alias.localSnapshotJson;
      if (snapshotText == null) continue;
      final snapshot = jsonDecode(snapshotText) as Map<String, dynamic>;
      if (snapshot['canonicalEntityId'] != sourceEntityId) continue;
      snapshot['canonicalEntityId'] = targetEntityId;
      await (_database.update(_database.syncConflicts)..where(
            (row) => row.id.equals(alias.id) & row.ownerId.equals(ownerId),
          ))
          .write(
            db.SyncConflictsCompanion(
              localSnapshotJson: Value(jsonEncode(snapshot)),
            ),
          );
    }
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
    this.idColumn = 'id',
  });

  final String table;
  final String entityType;
  final String join;
  final String idColumn;
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
