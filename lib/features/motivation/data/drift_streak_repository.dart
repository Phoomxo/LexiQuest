import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/streak_policy.dart';

/// Drift-backed persistence for [StreakState] and [LearningDayLog].
final class DriftStreakRepository {
  DriftStreakRepository(this._database);

  final db.AppDatabase _database;

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<StreakState> getOrCreate(String ownerId, int nowMs) async {
    final row = await (_database.select(_database.streakStates)
          ..where((t) => t.ownerId.equals(ownerId)))
        .getSingleOrNull();
    if (row != null) return _rowToState(row);

    // First access — create initial row.
    await _database.into(_database.streakStates).insert(
          db.StreakStatesCompanion.insert(
            ownerId: ownerId,
            updatedAtUtcMs: nowMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return StreakState.initial(ownerId: ownerId, nowMs: nowMs);
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> save(StreakState state) async {
    await _database.into(_database.streakStates).insertOnConflictUpdate(
          db.StreakStatesCompanion(
            ownerId: Value(state.ownerId),
            currentStreakDays: Value(state.currentStreakDays),
            longestStreakDays: Value(state.longestStreakDays),
            freezeCount: Value(state.freezeCount),
            lastLearnedAtUtcMs: Value(state.lastLearnedAtUtcMs),
            updatedAtUtcMs: Value(state.updatedAtUtcMs),
          ),
        );
  }

  // ── LearningDayLog ────────────────────────────────────────────────────────

  /// Record that [ownerId] was active on [learningDay] (idempotent).
  ///
  /// [learningDay] must be a date string in `'YYYY-MM-DD'` format.
  Future<void> recordLearningDay({
    required String ownerId,
    required String learningDay,
    required int firstSessionAtUtcMs,
  }) async {
    final id = 'day:$ownerId:$learningDay';
    await _database.into(_database.learningDayLog).insert(
          db.LearningDayLogCompanion.insert(
            id: id,
            ownerId: ownerId,
            learningDay: learningDay,
            firstSessionAtUtcMs: firstSessionAtUtcMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Returns all learning-day entries for [ownerId], newest first.
  Future<List<String>> getLearningDays(String ownerId) async {
    final rows = await (_database.select(_database.learningDayLog)
          ..where((t) => t.ownerId.equals(ownerId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.firstSessionAtUtcMs),
          ]))
        .get();
    return rows.map((r) => r.learningDay).toList(growable: false);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  StreakState _rowToState(db.StreakState row) => StreakState(
        ownerId: row.ownerId,
        currentStreakDays: row.currentStreakDays,
        longestStreakDays: row.longestStreakDays,
        freezeCount: row.freezeCount,
        lastLearnedAtUtcMs: row.lastLearnedAtUtcMs,
        updatedAtUtcMs: row.updatedAtUtcMs,
      );
}
