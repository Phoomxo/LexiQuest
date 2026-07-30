import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

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
        conflicts += await _discardNaturalKeyDuplicates(
          source.id,
          target.id,
          upgradedAt,
        );
        await _moveOwnerRows(source.id, target.id);

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
    await _updateOwner('vocabulary_categories', sourceId, targetId);
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
    await _updateOwner('vocabulary_words', sourceId, targetId);
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
    await _updateOwner('vocabulary_imports', sourceId, targetId);
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
      if (table == 'vocabulary_categories' ||
          table == 'vocabulary_words' ||
          table == 'vocabulary_imports') {
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
