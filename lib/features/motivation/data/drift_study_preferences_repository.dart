import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/study_preferences.dart';

final class DriftStudyPreferencesRepository {
  const DriftStudyPreferencesRepository(this.database, {required this.nowUtc});

  final db.AppDatabase database;
  final DateTime Function() nowUtc;

  Future<StudyPreferences> load({required String ownerId}) async {
    if (ownerId.trim().isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    final row = await (database.select(
      database.learningPreferences,
    )..where((r) => r.ownerId.equals(ownerId))).getSingleOrNull();
    return _decode(ownerId, row);
  }

  Future<StudyPreferences> saveLearning({
    required String expectedOwnerId,
    required StudyPreferences expected,
    required OnboardingState onboardingState,
    StudyPurpose? purpose,
    int? plannedMinutes,
    StudyMethod? method,
  }) async {
    if (plannedMinutes != null && plannedMinutes <= 0) {
      throw ArgumentError.value(plannedMinutes, 'plannedMinutes');
    }
    return _apply(
      expectedOwnerId,
      expected,
      StudyPreferences(
        ownerId: expected.ownerId,
        onboardingState: onboardingState,
        purpose: purpose,
        plannedMinutes: plannedMinutes,
        method: method,
        goalState: expected.goalState,
        goalCivilDate: expected.goalCivilDate,
        updatedAtUtcMs: expected.updatedAtUtcMs,
      ),
    );
  }

  Future<StudyPreferences> setGoal({
    required String expectedOwnerId,
    required StudyPreferences expected,
    required DateTime civilDate,
  }) async {
    if (!civilDate.isUtc ||
        civilDate !=
            DateTime.utc(civilDate.year, civilDate.month, civilDate.day)) {
      throw ArgumentError.value(
        civilDate,
        'civilDate',
        'must be a UTC civil date',
      );
    }
    return _apply(
      expectedOwnerId,
      expected,
      StudyPreferences(
        ownerId: expected.ownerId,
        onboardingState: expected.onboardingState,
        purpose: expected.purpose,
        plannedMinutes: expected.plannedMinutes,
        method: expected.method,
        goalState: GoalState.active,
        goalCivilDate: civilDate,
        updatedAtUtcMs: expected.updatedAtUtcMs,
      ),
    );
  }

  Future<StudyPreferences> closeGoal({
    required String expectedOwnerId,
    required StudyPreferences expected,
  }) => _apply(
    expectedOwnerId,
    expected,
    StudyPreferences(
      ownerId: expected.ownerId,
      onboardingState: expected.onboardingState,
      purpose: expected.purpose,
      plannedMinutes: expected.plannedMinutes,
      method: expected.method,
      goalState: GoalState.closed,
      goalCivilDate: expected.goalCivilDate,
      updatedAtUtcMs: expected.updatedAtUtcMs,
    ),
  );

  Future<StudyPreferences> _apply(
    String ownerId,
    StudyPreferences expected,
    StudyPreferences desired,
  ) => database.transaction(() async {
    final owners = await (database.select(
      database.localOwners,
    )..where((r) => r.isActive.equals(true))).get();
    if (owners.length != 1 ||
        owners.single.id != ownerId ||
        expected.ownerId != ownerId) {
      throw StateError('Preferences owner changed');
    }
    final current = await load(ownerId: ownerId);
    if (_same(current, desired, includeTime: false)) return current;
    if (!_same(current, expected, includeTime: true)) {
      throw StateError('Preferences changed');
    }
    final now = nowUtc();
    if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
      throw ArgumentError.value(now, 'nowUtc');
    }
    final updated = math.max(
      now.millisecondsSinceEpoch,
      (current.updatedAtUtcMs ?? -1) + 1,
    );
    await database
        .into(database.learningPreferences)
        .insertOnConflictUpdate(
          db.LearningPreferencesCompanion.insert(
            ownerId: ownerId,
            onboardingState: Value(desired.onboardingState.name),
            purpose: Value(desired.purpose?.name),
            plannedMinutes: Value(desired.plannedMinutes),
            learningMethod: Value(switch (desired.method) {
              StudyMethod.reading => 'read',
              StudyMethod.speaking => 'speak',
              null => null,
            }),
            goalCivilDate: Value(
              desired.goalCivilDate?.toIso8601String().substring(0, 10),
            ),
            goalState: Value(desired.goalState.name),
            updatedAtUtcMs: updated,
          ),
        );
    return load(ownerId: ownerId);
  });

  StudyPreferences _decode(String ownerId, db.LearningPreference? row) {
    if (row == null) {
      return StudyPreferences(
        ownerId: ownerId,
        onboardingState: OnboardingState.unset,
        purpose: null,
        plannedMinutes: null,
        method: null,
        goalState: GoalState.unset,
        goalCivilDate: null,
        updatedAtUtcMs: null,
      );
    }
    try {
      final date = row.goalCivilDate == null
          ? null
          : DateTime.parse('${row.goalCivilDate}T00:00:00Z');
      if (date != null &&
          date.toIso8601String().substring(0, 10) != row.goalCivilDate) {
        throw const FormatException();
      }
      final purpose = switch (row.purpose) {
        null => null,
        'travel' => StudyPurpose.travel,
        _ => throw const FormatException(),
      };
      final method = switch (row.learningMethod) {
        null => null,
        'read' => StudyMethod.reading,
        'speak' => StudyMethod.speaking,
        _ => throw const FormatException(),
      };
      final goal = GoalState.values.byName(row.goalState);
      if (goal == GoalState.active && date == null) {
        throw const FormatException();
      }
      return StudyPreferences(
        ownerId: ownerId,
        onboardingState: OnboardingState.values.byName(row.onboardingState),
        purpose: purpose,
        plannedMinutes: row.plannedMinutes,
        method: method,
        goalState: goal,
        goalCivilDate: date,
        updatedAtUtcMs: row.updatedAtUtcMs,
      );
    } on Object {
      throw StateError('Stored study preferences are unavailable');
    }
  }
}

bool _same(
  StudyPreferences a,
  StudyPreferences b, {
  required bool includeTime,
}) =>
    a.ownerId == b.ownerId &&
    a.onboardingState == b.onboardingState &&
    a.purpose == b.purpose &&
    a.plannedMinutes == b.plannedMinutes &&
    a.method == b.method &&
    a.goalState == b.goalState &&
    a.goalCivilDate == b.goalCivilDate &&
    (!includeTime || a.updatedAtUtcMs == b.updatedAtUtcMs);
