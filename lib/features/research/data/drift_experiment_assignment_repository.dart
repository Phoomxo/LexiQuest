import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../sync/domain/sync_entity.dart';
import '../domain/experiment_assignment.dart';

final class DriftExperimentAssignmentRepository {
  DriftExperimentAssignmentRepository(this._database);

  static const int _maxCanonicalRunes = 256;
  static const String _tableName = 'experiment_assignments';

  final AppDatabase _database;

  Future<ExperimentAssignment> getAssignment({
    required String experimentId,
    required int experimentVersion,
    required String ownerId,
  }) async {
    _validateCanonicalText(ownerId, 'ownerId');
    _validateCanonicalText(experimentId, 'experimentId');
    _validateExperimentVersion(experimentVersion);

    final assignment = await _findByLogicalIdentity(
      ownerId: ownerId,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
    );
    if (assignment == null) {
      throw StateError(
        'No experiment assignment exists for the requested identity.',
      );
    }
    if (assignment.id !=
        canonicalAssignmentId(
          ownerId: ownerId,
          experimentId: experimentId,
          experimentVersion: experimentVersion,
        )) {
      throw _conflictFor(assignment);
    }
    if (await _hasQuarantinedConflict(assignment)) {
      throw _conflictFor(assignment);
    }
    return assignment;
  }

  Future<List<ExperimentAssignment>> listAssignmentsForOwner({
    required String ownerId,
  }) async {
    _validateCanonicalText(ownerId, 'ownerId');
    final assignments = await _database
        .customSelect(
          'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms '
          'FROM $_tableName WHERE owner_id = ? '
          'ORDER BY experiment_id, experiment_version, id',
          variables: [Variable<String>(ownerId)],
        )
        .map(_readAssignment)
        .get();
    for (final assignment in assignments) {
      _validateAssignment(assignment);
      if (await _hasQuarantinedConflict(assignment)) {
        throw _conflictFor(assignment);
      }
    }
    return List<ExperimentAssignment>.unmodifiable(assignments);
  }

  Future<bool> matchesAssignmentIdentity({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
    required String candidateAssignmentId,
  }) async {
    _validateCanonicalText(ownerId, 'ownerId');
    _validateCanonicalText(experimentId, 'experimentId');
    _validateExperimentVersion(experimentVersion);
    _validateCanonicalText(candidateAssignmentId, 'candidateAssignmentId');

    final ownerIdentities = <String>{ownerId};
    final owners = await _database.select(_database.localOwners).get();
    LocalOwner? currentOwner;
    for (final owner in owners) {
      if (owner.id == ownerId) {
        currentOwner = owner;
        break;
      }
    }
    final firebaseUid = currentOwner?.firebaseUid;
    if (firebaseUid != null) {
      _validateCanonicalText(firebaseUid, 'firebaseUid');
      if (candidateAssignmentId ==
          canonicalCloudAssignmentId(
            firebaseUid: firebaseUid,
            experimentId: experimentId,
            experimentVersion: experimentVersion,
          )) {
        return true;
      }
    }

    var changed = true;
    var remainingPasses = owners.length + 1;
    while (changed && remainingPasses > 0) {
      changed = false;
      remainingPasses -= 1;
      for (final owner in owners) {
        const prefix = 'mergedInto:';
        if (!owner.accountState.startsWith(prefix)) continue;
        final targetOwnerId = owner.accountState.substring(prefix.length);
        if (ownerIdentities.contains(targetOwnerId) &&
            ownerIdentities.add(owner.id)) {
          changed = true;
        }
      }
    }
    if (changed) {
      throw StateError('Owner assignment identity lineage is cyclic.');
    }
    return ownerIdentities.any(
      (identityOwnerId) =>
          candidateAssignmentId ==
          canonicalAssignmentId(
            ownerId: identityOwnerId,
            experimentId: experimentId,
            experimentVersion: experimentVersion,
          ),
    );
  }

  Future<ExperimentAssignment> assignIfAbsent({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
    required String cohort,
    required String protocolVersion,
    required DateTime assignedAtUtc,
  }) async {
    _validateCanonicalText(ownerId, 'ownerId');
    _validateCanonicalText(experimentId, 'experimentId');
    _validateExperimentVersion(experimentVersion);
    _validateCanonicalText(cohort, 'cohort');
    _validateCanonicalText(protocolVersion, 'protocolVersion');
    _validateAssignedAt(assignedAtUtc);

    final canonicalAssignedAt = DateTime.fromMillisecondsSinceEpoch(
      assignedAtUtc.millisecondsSinceEpoch,
      isUtc: true,
    );
    final candidate = ExperimentAssignment(
      id: canonicalAssignmentId(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
      ),
      ownerId: ownerId,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      cohort: cohort,
      protocolVersion: protocolVersion,
      assignedAtUtc: canonicalAssignedAt,
    );

    return _database.transaction(() async {
      final existing = await _findByLogicalIdentity(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
      );
      if (existing != null) {
        final replay = _resolveReplay(
          candidate: candidate,
          persisted: existing,
        );
        await _ensureOutbox(replay, createIfMissing: false);
        return replay;
      }

      final idCollision = await _findById(candidate.id);
      if (idCollision != null) {
        throw _conflictFor(candidate);
      }

      await _insertAssignment(candidate);

      final persisted = await _findByLogicalIdentity(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
      );
      if (persisted != null) {
        final inserted = _resolveReplay(
          candidate: candidate,
          persisted: persisted,
        );
        await _ensureOutbox(inserted, createIfMissing: true);
        return inserted;
      }

      if (await _findById(candidate.id) != null) {
        throw _conflictFor(candidate);
      }
      throw StateError('Experiment assignment insert produced no row.');
    });
  }

  /// Persists an immutable assignment received from the canonical sync pull.
  ///
  /// This path deliberately creates no outbox operation, preventing a remote
  /// assignment from being echoed back as a new local write.
  Future<ExperimentAssignment> persistRemote(
    ExperimentAssignment assignment,
  ) async {
    _validateAssignment(assignment);
    return _database.transaction(() async {
      final existing = await _findByLogicalIdentity(
        ownerId: assignment.ownerId,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      );
      if (existing != null) {
        return _resolveReplay(candidate: assignment, persisted: existing);
      }
      if (await _findById(assignment.id) != null) {
        throw _conflictFor(assignment);
      }

      await _insertAssignment(assignment);
      final persisted = await _findByLogicalIdentity(
        ownerId: assignment.ownerId,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      );
      if (persisted != null) {
        return _resolveReplay(candidate: assignment, persisted: persisted);
      }
      throw _conflictFor(assignment);
    });
  }

  Future<void> _insertAssignment(ExperimentAssignment assignment) async {
    await _database.customInsert(
      'INSERT OR IGNORE INTO $_tableName('
      'id, owner_id, experiment_id, experiment_version, cohort, '
      'protocol_version, assigned_at_utc_ms'
      ') VALUES (?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(assignment.id),
        Variable<String>(assignment.ownerId),
        Variable<String>(assignment.experimentId),
        Variable<int>(assignment.experimentVersion),
        Variable<String>(assignment.cohort),
        Variable<String>(assignment.protocolVersion),
        Variable<int>(assignment.assignedAtUtc.millisecondsSinceEpoch),
      ],
    );
  }

  Future<void> _ensureOutbox(
    ExperimentAssignment assignment, {
    required bool createIfMissing,
  }) async {
    final entityIds = await _outboxEntityIds(assignment);
    final related =
        await (_database.select(_database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(assignment.ownerId) &
                  row.entityType.equals(
                    SyncCollection.experimentAssignments.entityType,
                  ) &
                  row.entityId.isIn(entityIds),
            ))
            .get();
    if (related.isNotEmpty) {
      if (related.length != 1 ||
          !_outboxMatches(
            related.single,
            assignment,
            allowedEntityIds: entityIds,
          )) {
        throw _conflictFor(assignment);
      }
      return;
    }

    final operationId = canonicalOutboxOperationId(assignment.id);
    final idCollision = await (_database.select(
      _database.outboxOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
    if (idCollision != null) throw _conflictFor(assignment);
    if (!createIfMissing) return;

    await _database
        .into(_database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: operationId,
            ownerId: assignment.ownerId,
            entityType: SyncCollection.experimentAssignments.entityType,
            entityId: assignment.id,
            operationKind: SyncOperationKind.upsert.name,
            payloadVersion: const Value(1),
            baseRevision: const Value(0),
            createdAtUtcMs: assignment.assignedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final persisted = await (_database.select(
      _database.outboxOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
    if (persisted == null ||
        !_outboxMatches(persisted, assignment, allowedEntityIds: entityIds)) {
      throw _conflictFor(assignment);
    }
  }

  bool _outboxMatches(
    OutboxOperation operation,
    ExperimentAssignment assignment, {
    required Set<String> allowedEntityIds,
  }) {
    return operation.operationId ==
            canonicalOutboxOperationId(operation.entityId) &&
        operation.ownerId == assignment.ownerId &&
        operation.entityType ==
            SyncCollection.experimentAssignments.entityType &&
        allowedEntityIds.contains(operation.entityId) &&
        operation.operationKind == SyncOperationKind.upsert.name &&
        operation.payloadVersion == 1 &&
        operation.baseRevision == 0 &&
        operation.createdAtUtcMs ==
            assignment.assignedAtUtc.millisecondsSinceEpoch;
  }

  Future<Set<String>> _outboxEntityIds(ExperimentAssignment assignment) async {
    final identities = <String>{assignment.id};
    final owner = await (_database.select(
      _database.localOwners,
    )..where((row) => row.id.equals(assignment.ownerId))).getSingleOrNull();
    final firebaseUid = owner?.firebaseUid;
    if (firebaseUid != null) {
      _validateCanonicalText(firebaseUid, 'firebaseUid');
      identities.add(
        canonicalCloudAssignmentId(
          firebaseUid: firebaseUid,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
        ),
      );
    }
    return identities;
  }

  Future<bool> _hasQuarantinedConflict(ExperimentAssignment assignment) async {
    final rows =
        await (_database.select(_database.syncConflicts)..where(
              (row) =>
                  row.ownerId.equals(assignment.ownerId) &
                  row.entityType.equals(
                    SyncCollection.experimentAssignments.entityType,
                  ) &
                  row.outcome.equals('quarantined'),
            ))
            .get();
    for (final row in rows) {
      final snapshot = row.localSnapshotJson;
      if (snapshot == null) return true;
      try {
        final decoded = jsonDecode(snapshot);
        if (decoded is! Map) return true;
        final experimentId = decoded['experimentId'];
        final experimentVersion = decoded['experimentVersion'];
        if (experimentId is! String || experimentVersion is! int) return true;
        _validateCanonicalText(experimentId, 'localSnapshot.experimentId');
        _validateExperimentVersion(experimentVersion);
        if (experimentId == assignment.experimentId &&
            experimentVersion == assignment.experimentVersion) {
          return true;
        }
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  Future<ExperimentAssignment?> _findByLogicalIdentity({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
  }) {
    return _database
        .customSelect(
          'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms '
          'FROM $_tableName '
          'WHERE owner_id = ? AND experiment_id = ? '
          'AND experiment_version = ? LIMIT 1',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(experimentId),
            Variable<int>(experimentVersion),
          ],
        )
        .map(_readAssignment)
        .getSingleOrNull();
  }

  Future<ExperimentAssignment?> _findById(String id) {
    return _database
        .customSelect(
          'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms '
          'FROM $_tableName WHERE id = ? LIMIT 1',
          variables: [Variable<String>(id)],
        )
        .map(_readAssignment)
        .getSingleOrNull();
  }

  ExperimentAssignment _readAssignment(QueryRow row) {
    return ExperimentAssignment(
      id: row.read<String>('id'),
      ownerId: row.read<String>('owner_id'),
      experimentId: row.read<String>('experiment_id'),
      experimentVersion: row.read<int>('experiment_version'),
      cohort: row.read<String>('cohort'),
      protocolVersion: row.read<String>('protocol_version'),
      assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('assigned_at_utc_ms'),
        isUtc: true,
      ),
    );
  }

  ExperimentAssignment _resolveReplay({
    required ExperimentAssignment candidate,
    required ExperimentAssignment persisted,
  }) {
    if (persisted == candidate) return persisted;
    throw _conflictFor(candidate);
  }

  ExperimentAssignmentConflict _conflictFor(ExperimentAssignment candidate) {
    return ExperimentAssignmentConflict(
      ownerId: candidate.ownerId,
      experimentId: candidate.experimentId,
      experimentVersion: candidate.experimentVersion,
    );
  }

  static String canonicalAssignmentId({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
  }) {
    final identityBytes = utf8.encode(
      jsonEncode([ownerId, experimentId, experimentVersion]),
    );
    return 'experiment-assignment:${sha256.convert(identityBytes)}';
  }

  static String canonicalCloudAssignmentId({
    required String firebaseUid,
    required String experimentId,
    required int experimentVersion,
  }) {
    return canonicalAssignmentId(
      ownerId: firebaseUid,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
    );
  }

  static String canonicalOutboxOperationId(String assignmentId) =>
      'experimentAssignment:$assignmentId:1';

  void _validateAssignment(ExperimentAssignment assignment) {
    _validateCanonicalText(assignment.id, 'id');
    _validateCanonicalText(assignment.ownerId, 'ownerId');
    _validateCanonicalText(assignment.experimentId, 'experimentId');
    _validateExperimentVersion(assignment.experimentVersion);
    _validateCanonicalText(assignment.cohort, 'cohort');
    _validateCanonicalText(assignment.protocolVersion, 'protocolVersion');
    _validateAssignedAt(assignment.assignedAtUtc);
    if (assignment.id !=
        canonicalAssignmentId(
          ownerId: assignment.ownerId,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
        )) {
      throw _conflictFor(assignment);
    }
  }

  void _validateCanonicalText(String value, String argumentName) {
    if (value.isEmpty ||
        value != value.trim() ||
        value.runes.length > _maxCanonicalRunes) {
      throw ArgumentError.value(value, argumentName, 'must be canonical');
    }
  }

  void _validateExperimentVersion(int experimentVersion) {
    if (experimentVersion <= 0) {
      throw ArgumentError.value(
        experimentVersion,
        'experimentVersion',
        'must be positive',
      );
    }
  }

  void _validateAssignedAt(DateTime assignedAtUtc) {
    if (!assignedAtUtc.isUtc || assignedAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        assignedAtUtc,
        'assignedAtUtc',
        'must be UTC and not before the Unix epoch',
      );
    }
  }
}
