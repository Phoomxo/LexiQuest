import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../application/learning_layer_adapter.dart';

/// Drift-backed implementation of [AssociativeLearningPort].
///
/// Replaces [InMemoryAssociativeLearningAdapter] in production builds.
/// Data persists across restarts and participates in owner-upgrade migration
/// via [ownerUpgradeInventory] entries `association_records` and
/// `associative_memory_states`.
///
/// Phase 2 D8.3 — schema v10.
final class DriftAssociativeLearningAdapter implements AssociativeLearningPort {
  DriftAssociativeLearningAdapter(this._database);

  final db.AppDatabase _database;

  // ── Associations ───────────────────────────────────────────────────────────

  @override
  Future<void> saveAssociation(AssociationRecord record) async {
    await _database
        .into(_database.associationRecords)
        .insert(
          db.AssociationRecordsCompanion.insert(
            id: record.associationId,
            ownerId: record.ownerId,
            wordKey: record.wordKey,
            type: record.type,
            content: record.content,
            createdAtUtcMs: record.createdAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> saveAssociationAndMemoryState(
    AssociationRecord record,
    AssociativeMemoryState state,
  ) {
    if (record.ownerId != state.ownerId || record.wordKey != state.wordKey) {
      throw ArgumentError('Association and memory-state keys must match.');
    }
    return _database.transaction(() async {
      await saveAssociation(record);
      await updateMemoryState(state);
    });
  }

  @override
  Future<List<AssociationRecord>> getAssociationsForWord(
    String ownerId,
    String wordKey,
  ) async {
    final rows =
        await (_database.select(_database.associationRecords)..where(
              (t) => t.ownerId.equals(ownerId) & t.wordKey.equals(wordKey),
            ))
            .get();
    return rows.map(_rowToAssociation).toList(growable: false);
  }

  @override
  Future<void> deleteAssociation(String associationId) async {
    await (_database.delete(
      _database.associationRecords,
    )..where((t) => t.id.equals(associationId))).go();
  }

  // ── Memory states ──────────────────────────────────────────────────────────

  @override
  Future<AssociativeMemoryState?> getMemoryState(
    String ownerId,
    String wordKey,
  ) async {
    final row =
        await (_database.select(_database.associativeMemoryStates)..where(
              (t) => t.ownerId.equals(ownerId) & t.wordKey.equals(wordKey),
            ))
            .getSingleOrNull();
    return row == null ? null : _rowToMemoryState(row);
  }

  @override
  Future<void> updateMemoryState(AssociativeMemoryState state) async {
    final id = 'ams:${state.ownerId}:${state.wordKey}';
    await _database
        .into(_database.associativeMemoryStates)
        .insert(
          db.AssociativeMemoryStatesCompanion.insert(
            id: id,
            ownerId: state.ownerId,
            wordKey: state.wordKey,
            stability: Value(state.stability),
            difficulty: Value(state.difficulty),
            cueDependency: Value(state.cueDependency),
            lapseCount: Value(state.lapseCount),
            lastReviewedAtUtcMs: Value(
              state.lastReviewedAtUtc?.millisecondsSinceEpoch,
            ),
            nextDueAtUtcMs: state.nextDueAtUtc.millisecondsSinceEpoch,
            algorithmVersion: state.algorithmVersion,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<AssociativeMemoryState>> getAllMemoryStates(
    String ownerId,
  ) async {
    final rows = await (_database.select(
      _database.associativeMemoryStates,
    )..where((t) => t.ownerId.equals(ownerId))).get();
    return rows.map(_rowToMemoryState).toList(growable: false);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  AssociationRecord _rowToAssociation(db.AssociationRecord row) =>
      AssociationRecord(
        associationId: row.id,
        ownerId: row.ownerId,
        wordKey: row.wordKey,
        type: row.type,
        content: row.content,
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.createdAtUtcMs,
          isUtc: true,
        ),
      );

  AssociativeMemoryState _rowToMemoryState(db.AssociativeMemoryState row) =>
      AssociativeMemoryState(
        ownerId: row.ownerId,
        wordKey: row.wordKey,
        stability: row.stability,
        difficulty: row.difficulty,
        cueDependency: row.cueDependency,
        lapseCount: row.lapseCount,
        lastReviewedAtUtc: row.lastReviewedAtUtcMs != null
            ? DateTime.fromMillisecondsSinceEpoch(
                row.lastReviewedAtUtcMs!,
                isUtc: true,
              )
            : null,
        nextDueAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.nextDueAtUtcMs,
          isUtc: true,
        ),
        algorithmVersion: row.algorithmVersion,
      );
}
