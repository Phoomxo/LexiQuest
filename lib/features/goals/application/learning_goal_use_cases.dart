import 'package:timezone/timezone.dart' as timezone;

import '../../motivation/domain/timezone_policy.dart';
import '../domain/learning_goal.dart';
import '../domain/learning_goal_repository.dart';

typedef LearningGoalIdGenerator = String Function();
typedef LearningGoalUtcNow = DateTime Function();
typedef LearningGoalActiveOwnerId = Future<String> Function();
typedef LearningGoalLearningDay =
    DateTime Function(DateTime utcInstant, String timezoneId);

enum LearningGoalDeadlineState { future, today, past }

final class LearningGoalCountdown {
  const LearningGoalCountdown({required this.state, required this.days});

  final LearningGoalDeadlineState state;
  final int days;
}

final class LearningGoalCreateCommand {
  const LearningGoalCreateCommand._(this.goal, this.expectedOwnerId);

  final LearningGoal goal;
  final String expectedOwnerId;
}

final class LearningGoalUseCases {
  const LearningGoalUseCases({
    required this.repository,
    required this.nowUtc,
    required this.generateId,
    required this.activeOwnerId,
    this.learningDay = TimezonePolicy.getLearningDay,
  });

  final LearningGoalRepository repository;
  final LearningGoalUtcNow nowUtc;
  final LearningGoalIdGenerator generateId;
  final LearningGoalActiveOwnerId activeOwnerId;
  final LearningGoalLearningDay learningDay;

  Future<List<LearningGoal>> list() => repository.list();

  Future<LearningGoal> create({
    required LearningGoalKind kind,
    required String title,
    required DateTime deadlineAtUtc,
    required LearningGoalTimezoneContext timezone,
    LearningGoalMutationGuard? mutationAllowed,
  }) async {
    final command = await prepareCreate(
      kind: kind,
      title: title,
      deadlineAtUtc: deadlineAtUtc,
      timezone: timezone,
    );
    return executeCreate(command, mutationAllowed: mutationAllowed);
  }

  Future<LearningGoalCreateCommand> prepareCreate({
    required LearningGoalKind kind,
    required String title,
    required DateTime deadlineAtUtc,
    required LearningGoalTimezoneContext timezone,
    String? expectedOwnerId,
  }) async {
    final ownerId = await activeOwnerId();
    if (ownerId.isEmpty || ownerId.trim() != ownerId) {
      throw const LearningGoalOwnerChanged();
    }
    if (expectedOwnerId != null && expectedOwnerId != ownerId) {
      throw const LearningGoalOwnerChanged();
    }
    final now = nowUtc();
    return LearningGoalCreateCommand._(
      LearningGoal(
        id: generateId(),
        kind: kind,
        title: title,
        deadlineAtUtc: deadlineAtUtc,
        timezone: timezone,
        status: LearningGoalStatus.active,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
      ownerId,
    );
  }

  Future<LearningGoal> executeCreate(
    LearningGoalCreateCommand command, {
    LearningGoalMutationGuard? mutationAllowed,
  }) async {
    await repository.save(
      command.goal,
      mutationAllowed: mutationAllowed,
      expectedOwnerId: command.expectedOwnerId,
    );
    return command.goal;
  }

  Future<LearningGoalCreateCommand> prepareUpdate(
    LearningGoal goal, {
    required String expectedOwnerId,
    required LearningGoalKind kind,
    required String title,
    required DateTime deadlineAtUtc,
    required LearningGoalTimezoneContext timezone,
    bool isDeleted = false,
  }) async {
    if (await activeOwnerId() != expectedOwnerId) {
      throw const LearningGoalOwnerChanged();
    }
    final now = nowUtc();
    return LearningGoalCreateCommand._(
      goal.copyWith(
        kind: kind,
        title: title,
        deadlineAtUtc: deadlineAtUtc,
        timezone: timezone,
        isDeleted: isDeleted,
        updatedAtUtc: now.isAfter(goal.updatedAtUtc)
            ? now
            : goal.updatedAtUtc.add(const Duration(milliseconds: 1)),
      ),
      expectedOwnerId,
    );
  }

  Future<LearningGoal> updateStatus(
    LearningGoal goal,
    LearningGoalStatus status, {
    LearningGoalMutationGuard? mutationAllowed,
  }) async {
    if (status == goal.status) return goal;
    final now = nowUtc();
    final updatedAt = now.isAfter(goal.updatedAtUtc)
        ? now
        : goal.updatedAtUtc.add(const Duration(milliseconds: 1));
    final updated = goal.copyWith(status: status, updatedAtUtc: updatedAt);
    await repository.save(updated, mutationAllowed: mutationAllowed);
    return updated;
  }

  LearningGoalCountdown countdown(LearningGoal goal) {
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    final today = learningDay(now, goal.timezone.timezoneId);
    final deadlineDay = learningDay(
      goal.deadlineAtUtc,
      goal.timezone.timezoneId,
    );
    final todayOrdinal = DateTime.utc(today.year, today.month, today.day);
    final deadlineOrdinal = DateTime.utc(
      deadlineDay.year,
      deadlineDay.month,
      deadlineDay.day,
    );
    final days = deadlineOrdinal.difference(todayOrdinal).inDays;
    return LearningGoalCountdown(
      state: days < 0
          ? LearningGoalDeadlineState.past
          : days == 0
          ? LearningGoalDeadlineState.today
          : LearningGoalDeadlineState.future,
      days: days.abs(),
    );
  }

  static LearningGoalTimezoneContext timezoneContext(
    String timezoneId,
    DateTime occurredAtUtc,
  ) {
    final location = timezone.getLocation(timezoneId);
    final local = timezone.TZDateTime.from(occurredAtUtc, location);
    return LearningGoalTimezoneContext(
      timezoneId: timezoneId,
      utcOffsetMinutes: local.timeZoneOffset.inMinutes,
    );
  }
}
