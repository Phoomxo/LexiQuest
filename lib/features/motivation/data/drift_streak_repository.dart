import 'package:timezone/timezone.dart' as timezone;

import '../../../data/local/app_database.dart' as db;
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning_profile/domain/learning_timezone.dart';
import '../../quest/data/drift_quest_repository.dart';
import '../../rewards/data/drift_motivation_reward_repository.dart';
import '../domain/motivation_snapshot.dart';
import 'drift_learning_day_recorder.dart';
import 'drift_motivation_scope.dart';

final class DriftStreakRepository {
  DriftStreakRepository(
    this.database, {
    DriftOwnerWriteCoordinator? ownerWrites,
    DriftQuestRepository? quests,
    DateTime Function()? nowUtc,
  }) {
    this.ownerWrites =
        ownerWrites ??
        DriftOwnerWriteCoordinator(database, nowUtc: nowUtc ?? _utcNow);
    if (!identical(database, this.ownerWrites.database)) {
      throw ArgumentError('Streak reads require the canonical owner database');
    }
    rewards = DriftMotivationRewardRepository(
      database,
      ownerWrites: this.ownerWrites,
      quests:
          quests ??
          DriftQuestRepository(
            database,
            ownerWrites: this.ownerWrites,
            nowUtc: nowUtc ?? _utcNow,
          ),
      nowUtc: nowUtc ?? _utcNow,
    );
  }
  final db.AppDatabase database;
  late final DriftOwnerWriteCoordinator ownerWrites;
  late final DriftMotivationRewardRepository rewards;

  Future<String> readActiveOwnerId() async {
    final rows =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (rows.length != 1) {
      throw const MotivationException(MotivationFailureCode.ownerChanged);
    }
    return rows.single.id;
  }

  Future<MotivationSnapshot> read({
    required String expectedOwnerId,
    required DateTime nowUtc,
    required bool Function() stillCurrent,
  }) => withMotivationOwner(
    database,
    ownerWrites,
    expectedOwnerId,
    stillCurrent,
    (_) => readForProjection(ownerId: expectedOwnerId, nowUtc: nowUtc),
  );

  Future<MotivationSnapshot> readForProjection({
    required String ownerId,
    required DateTime nowUtc,
  }) => database.transaction(() async {
    if (!nowUtc.isUtc || nowUtc.millisecondsSinceEpoch < 0) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    final profile = await (database.select(
      database.learningProfiles,
    )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull();
    final String zone;
    try {
      zone = requireLearningTimezone(profile?.learningTimezoneId ?? 'UTC');
    } on FormatException {
      throw const MotivationException(MotivationFailureCode.unavailable);
    }
    final days = await readCanonicalLearningDays(
      database,
      ownerId: ownerId,
      nowUtc: nowUtc,
    );
    final totals = await rewards.readForProjection(
      ownerId: ownerId,
      atUtc: nowUtc,
    );
    final today = motivationDayLabel(
      timezone.TZDateTime.from(nowUtc, timezone.getLocation(zone)),
    );
    return MotivationSnapshot(
      ownerId: ownerId,
      state: projectCanonicalStreak(
        ownerId: ownerId,
        learningDays: days,
        protectedDays: totals.protectedDays,
        today: today,
        freezeCount: totals.freezeCount,
      ),
      timezoneId: zone,
      usedUtcFallback:
          profile?.learningTimezoneId == null || days.any((day) => !day.pinned),
      learningDays: days,
      protectedDays: totals.protectedDays,
      questXp: totals.questXp,
    );
  });

  Future<List<String>> getLearningDays(
    String ownerId, {
    DateTime? nowUtc,
  }) async =>
      (await read(
          expectedOwnerId: ownerId,
          nowUtc: nowUtc ?? _utcNow(),
          stillCurrent: () => true,
        )).learningDays.map((day) => day.learningDay).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
}

DateTime _utcNow() => DateTime.now().toUtc();
