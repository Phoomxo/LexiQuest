import 'package:timezone/timezone.dart' as timezone;

import '../../motivation/domain/timezone_policy.dart';
import '../domain/learning_goal.dart';
import '../domain/learning_goal_repository.dart';

typedef LearningGoalIdGenerator = String Function();
typedef LearningGoalUtcNow = DateTime Function();

enum LearningGoalDeadlineState { future, today, past }

final class LearningGoalCountdown {
  const LearningGoalCountdown({required this.state, required this.days});

  final LearningGoalDeadlineState state;
  final int days;
}

final class LearningGoalCreateCommand {
  const LearningGoalCreateCommand._(this.goal);

  final LearningGoal goal;
}

final class LearningGoalUseCases {
  const LearningGoalUseCases({
    required this.repository,
    required this.nowUtc,
    required this.generateId,
  });

  final LearningGoalRepository repository;
  final LearningGoalUtcNow nowUtc;
  final LearningGoalIdGenerator generateId;

  Future<List<LearningGoal>> list() => repository.list();

  Future<LearningGoal> create({
    required LearningGoalKind kind,
    required String title,
    required DateTime deadlineAtUtc,
    required LearningGoalTimezoneContext timezone,
    LearningGoalMutationGuard? mutationAllowed,
  }) {
    final command = prepareCreate(
      kind: kind,
      title: title,
      deadlineAtUtc: deadlineAtUtc,
      timezone: timezone,
    );
    return executeCreate(command, mutationAllowed: mutationAllowed);
  }

  LearningGoalCreateCommand prepareCreate({
    required LearningGoalKind kind,
    required String title,
    required DateTime deadlineAtUtc,
    required LearningGoalTimezoneContext timezone,
  }) {
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
    );
  }

  Future<LearningGoal> executeCreate(
    LearningGoalCreateCommand command, {
    LearningGoalMutationGuard? mutationAllowed,
  }) async {
    await repository.save(command.goal, mutationAllowed: mutationAllowed);
    return command.goal;
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
    final today = TimezonePolicy.getLearningDay(now, goal.timezone.timezoneId);
    final deadlineDay = TimezonePolicy.getLearningDay(
      goal.deadlineAtUtc,
      goal.timezone.timezoneId,
    );
    final days = deadlineDay.difference(today).inDays;
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
