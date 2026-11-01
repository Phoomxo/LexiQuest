import 'package:timezone/timezone.dart' as timezone;
import 'package:uuid/uuid.dart';

import '../data/drift_streak_repository.dart';
import '../domain/motivation_snapshot.dart';
import '../domain/streak_policy.dart';

typedef StreakUtcNow = DateTime Function();

final class StreakUseCases {
  StreakUseCases({
    required this.repository,
    required this.nowUtc,
    String Function()? generateId,
  }) : generateId = generateId ?? const Uuid().v4;
  final DriftStreakRepository repository;
  final StreakUtcNow nowUtc;
  final String Function() generateId;

  Future<MotivationSnapshot> load({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.read(
    expectedOwnerId: expectedOwnerId,
    nowUtc: _now(),
    stillCurrent: stillCurrent,
  );

  Future<StreakState> getCurrentStreak({
    String? expectedOwnerId,
    bool Function()? stillCurrent,
  }) async => (await load(
    expectedOwnerId: expectedOwnerId ?? await repository.readActiveOwnerId(),
    stillCurrent: stillCurrent ?? () => true,
  )).state;

  Future<void> reconcileRewards({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.rewards.reconcile(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
  );

  FreezeProtectionIntent prepareProtection({
    required MotivationSnapshot snapshot,
    required String protectedDay,
    required bool Function() stillCurrent,
  }) {
    final day = motivationCivilDay(protectedDay);
    final previous = motivationDayLabel(day.subtract(const Duration(days: 1)));
    final sources =
        snapshot.learningDays
            .where(
              (fact) =>
                  fact.learningDay == previous &&
                  fact.timezoneId == snapshot.timezoneId,
            )
            .toList()
          ..sort((a, b) => a.occurredAtUtc.compareTo(b.occurredAtUtc));
    if (sources.isEmpty || snapshot.protectedDays.contains(protectedDay)) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    final at = _now();
    final today = motivationCivilDay(
      motivationDayLabel(
        timezone.TZDateTime.from(at, timezone.getLocation(snapshot.timezoneId)),
      ),
    );
    if (today.difference(day).inDays != 1) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    final id = generateId();
    if (id.trim().isEmpty || id.length > 240) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    return FreezeProtectionIntent(
      id: 'freeze:$id',
      ownerId: snapshot.ownerId,
      protectedDay: protectedDay,
      timezoneId: snapshot.timezoneId,
      sourceAttemptId: sources.first.sourceAttemptId,
      occurredAtUtc: at,
      stillCurrent: stillCurrent,
    );
  }

  Future<MotivationSnapshot> protect(FreezeProtectionIntent intent) async {
    await repository.rewards.protect(intent);
    return load(
      expectedOwnerId: intent.ownerId,
      stillCurrent: intent.stillCurrent,
    );
  }

  DateTime _now() {
    final now = nowUtc();
    if (!now.isUtc || now.millisecondsSinceEpoch < 0) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    return now;
  }
}
