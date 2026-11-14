import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../data/local/app_database.dart' as db;
import '../domain/streak_policy.dart';
import '../domain/timezone_policy.dart';

/// Drift-backed persistence for [StreakState] and [LearningDayLog].
final class DriftStreakRepository {
  DriftStreakRepository(this._database);

  final db.AppDatabase _database;

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<OwnerCalendarRule> calendarRuleAt({
    required String ownerId,
    required int occurredAtUtcMs,
  }) {
    if (ownerId.trim().isEmpty ||
        occurredAtUtcMs < 0 ||
        occurredAtUtcMs > tz.maxTime) {
      throw ArgumentError('Invalid calendar owner or occurrence');
    }
    return _database.transaction(() async {
      final owner = await (_database.select(
        _database.localOwners,
      )..where((row) => row.id.equals(ownerId))).getSingleOrNull();
      if (owner == null || occurredAtUtcMs < owner.createdAtUtcMs) {
        throw StateError('No calendar authority for this owner and occurrence');
      }
      final rules =
          await (_database.select(_database.ownerCalendarEpochs)
                ..where((row) => row.ownerId.equals(ownerId))
                ..orderBy([(row) => OrderingTerm.asc(row.effectiveUtcUs)]))
              .get();
      var selected = rules.where((row) => row.isSelected).toList();
      if (selected.isEmpty) {
        if (rules.any((row) => row.originOwnerId == ownerId)) {
          throw StateError('Retired calendar authority cannot be reactivated');
        }
        final defaultId = 'calendar:utc-default:$ownerId';
        final effective = owner.createdAtUtcMs * 1000;
        await _database
            .into(_database.ownerCalendarEpochs)
            .insert(
              db.OwnerCalendarEpochsCompanion.insert(
                ruleId: defaultId,
                ownerId: ownerId,
                originOwnerId: ownerId,
                effectiveUtcUs: effective,
                ianaId: 'UTC',
                tzdbRevision: bundledTzdbRevision,
                isSelected: true,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        final stored = await (_database.select(
          _database.ownerCalendarEpochs,
        )..where((row) => row.ruleId.equals(defaultId))).getSingleOrNull();
        if (stored == null ||
            stored.ownerId != ownerId ||
            stored.originOwnerId != ownerId ||
            stored.effectiveUtcUs != effective ||
            stored.expiresUtcUs != null ||
            stored.ianaId != 'UTC' ||
            stored.tzdbRevision != bundledTzdbRevision ||
            !stored.isSelected) {
          throw StateError('Default UTC calendar provenance conflict');
        }
        selected = [stored];
      }
      for (var index = 0; index < selected.length; index++) {
        final rule = selected[index];
        if (rule.originOwnerId != ownerId ||
            rule.ruleId.trim().isEmpty ||
            rule.effectiveUtcUs < tz.minTime * 1000 ||
            rule.effectiveUtcUs > tz.maxTime * 1000 ||
            (rule.expiresUtcUs != null &&
                (rule.expiresUtcUs! <= rule.effectiveUtcUs ||
                    rule.expiresUtcUs! > tz.maxTime * 1000))) {
          throw StateError('Invalid calendar authority');
        }
        if (index > 0 &&
            (selected[index - 1].expiresUtcUs == null ||
                selected[index - 1].expiresUtcUs! > rule.effectiveUtcUs)) {
          throw StateError('Selected calendar authorities overlap');
        }
      }
      final occurredUs = occurredAtUtcMs * 1000;
      final matching = selected.where(
        (rule) =>
            rule.effectiveUtcUs <= occurredUs &&
            (rule.expiresUtcUs == null || occurredUs < rule.expiresUtcUs!),
      );
      if (matching.length != 1) {
        throw StateError('No selected calendar authority at the occurrence');
      }
      final rule = matching.single;
      if (rule.tzdbRevision != bundledTzdbRevision ||
          (rule.ianaId != 'UTC' &&
              (!tz.timeZoneDatabase.isInitialized ||
                  !tz.timeZoneDatabase.locations.containsKey(rule.ianaId)))) {
        throw StateError('Calendar timezone authority is unavailable');
      }
      return OwnerCalendarRule(
        ruleId: rule.ruleId,
        originOwnerId: rule.originOwnerId,
        ianaId: rule.ianaId,
        tzdbRevision: rule.tzdbRevision,
        effectiveUtcUs: rule.effectiveUtcUs,
        expiresUtcUs: rule.expiresUtcUs,
      );
    }, requireNew: true);
  }

  Future<StreakState> getOrCreate(String ownerId, int nowMs) async {
    final row = await (_database.select(
      _database.streakStates,
    )..where((t) => t.ownerId.equals(ownerId))).getSingleOrNull();
    if (row != null) return _rowToState(row);

    // First access — create initial row.
    await _database
        .into(_database.streakStates)
        .insert(
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
    await _database
        .into(_database.streakStates)
        .insertOnConflictUpdate(
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
    await _database
        .into(_database.learningDayLog)
        .insert(
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
    final rows =
        await (_database.select(_database.learningDayLog)
              ..where((t) => t.ownerId.equals(ownerId))
              ..orderBy([(t) => OrderingTerm.desc(t.firstSessionAtUtcMs)]))
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
