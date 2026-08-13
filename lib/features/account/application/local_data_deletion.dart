import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../identity/domain/owner_lifecycle_manifest.dart';

typedef DeleteOwnerSecrets = Future<void> Function(String ownerId);
typedef DeleteOwnerSecretsFenced =
    Future<void> Function(String ownerId, String operationToken);
typedef FenceOwnerOperation = Future<void> Function(String operationToken);
typedef CoordinateLocalDataErasure =
    Future<int> Function(
      String ownerId,
      Future<int> Function(String operationToken) operation,
    );

abstract interface class LocalDataEraser {
  Future<int> eraseAll({required String ownerId});
}

/// The manifest-owned, child-before-parent physical deletion order.
const List<String> localDataDeletionInventory =
    ownerLifecyclePhysicalDeletionOrder;

/// Erases all local data for the active owner.
///
/// This implements the participant's right-to-erasure: all learning sessions,
/// answer attempts, SRS states, reading data, reward transactions, quest
/// instances, streak data, events, and speech evidence are deleted.
///
/// Vocabulary and import metadata are included; this API must never perform a
/// partial learning-history reset under the name `eraseAll`.
///
/// Cross-store failure policy is privacy-first: secure BYOK values are erased
/// before SQLite work starts. A later SQLite failure rolls database changes
/// back but cannot restore the key; the participant must configure it again.
class LocalDataDeletion implements LocalDataEraser {
  LocalDataDeletion(
    this._database, {
    required this.deleteOwnerSecrets,
    this.deleteOwnerSecretsFenced,
    this.fenceOwnerOperation,
    this.coordinate,
  }) {
    if (coordinate != null && fenceOwnerOperation == null) {
      throw ArgumentError(
        'Coordinated local erasure requires an atomic database lease fence.',
      );
    }
  }

  final db.AppDatabase _database;
  final DeleteOwnerSecrets deleteOwnerSecrets;
  final DeleteOwnerSecretsFenced? deleteOwnerSecretsFenced;
  final FenceOwnerOperation? fenceOwnerOperation;
  final CoordinateLocalDataErasure? coordinate;

  /// Deletes all owner-scoped data for [ownerId].
  ///
  /// Returns the count of rows deleted across all tables.
  @override
  Future<int> eraseAll({required String ownerId}) async {
    final normalizedOwnerId = ownerId.trim();
    if (normalizedOwnerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must not be empty');
    }
    final coordinator = coordinate;
    if (coordinator != null) {
      return coordinator(
        normalizedOwnerId,
        (operationToken) => _eraseAllCoordinated(
          ownerId: normalizedOwnerId,
          operationToken: operationToken,
        ),
      );
    }
    await deleteOwnerSecrets(normalizedOwnerId);
    return _database.transaction(
      () => _eraseAllInTransaction(ownerId: normalizedOwnerId),
    );
  }

  Future<int> _eraseAllCoordinated({
    required String ownerId,
    required String operationToken,
  }) async {
    final fencedDelete = deleteOwnerSecretsFenced;
    if (fencedDelete == null) {
      await deleteOwnerSecrets(ownerId);
    } else {
      await fencedDelete(ownerId, operationToken);
    }
    return _database.transaction(() async {
      // This must be the transaction's first statement so a replacement owner
      // operation cannot race the first irreversible SQLite delete.
      await fenceOwnerOperation!(operationToken);
      return _eraseAllInTransaction(ownerId: ownerId);
    });
  }

  Future<int> _eraseAllInTransaction({required String ownerId}) async {
    var total = 0;
    for (final tableName in localDataDeletionInventory) {
      total += await _deleteManifestAction(
        tableName: tableName,
        ownerId: ownerId,
      );
    }
    return total;
  }

  Future<int> _deleteManifestAction({
    required String tableName,
    required String ownerId,
  }) {
    switch (tableName) {
      case 'runtime_flags':
        // The fenced secure-store eraser owns the target participant's
        // credential pointer and intent namespaces. Every other runtime flag
        // is global state and must remain byte-identical.
        return Future<int>.value(0);
      case 'vocabulary_import_rows':
        return _database.customUpdate(
          'DELETE FROM vocabulary_import_rows WHERE import_id IN '
          '(SELECT id FROM vocabulary_imports WHERE owner_id = ?)',
          variables: [Variable<String>(ownerId)],
          updates: {_database.vocabularyImportRows},
        );
      case 'quest_objective_progress':
        return _database.customUpdate(
          'DELETE FROM quest_objective_progress WHERE instance_id IN '
          '(SELECT instance_id FROM quest_instances WHERE owner_id = ?)',
          variables: [Variable<String>(ownerId)],
          updates: {_database.questObjectiveProgress},
        );
      case 'local_owners':
        return _database.customUpdate(
          'DELETE FROM local_owners WHERE id = ?',
          variables: [Variable<String>(ownerId)],
          updates: {_database.localOwners},
        );
      default:
        if (!ownerLifecycleDirectOwnerTableNames.contains(tableName)) {
          throw StateError(
            'Unimplemented owner lifecycle deletion action: $tableName',
          );
        }
        final table = _database.allTables.singleWhere(
          (candidate) => candidate.actualTableName == tableName,
        );
        return _database.customUpdate(
          'DELETE FROM "$tableName" WHERE owner_id = ?',
          variables: [Variable<String>(ownerId)],
          updates: {table},
        );
    }
  }
}
