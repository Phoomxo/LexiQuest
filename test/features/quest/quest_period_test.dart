import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_period.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  test('daily periods use the pinned local calendar across DST', () {
    for (final entry in [
      (
        DateTime.utc(2026, 3, 8, 5),
        DateTime.utc(2026, 3, 9, 4),
        'daily:2026-03-08',
      ),
      (
        DateTime.utc(2026, 11, 1, 4),
        DateTime.utc(2026, 11, 2, 5),
        'daily:2026-11-01',
      ),
    ]) {
      final period = QuestPeriod.forAssignment(
        definition: definition(),
        assignedAtUtc: entry.$1,
        timezoneId: 'America/New_York',
      );
      expect(period.policy, QuestPeriodPolicy.localCalendarV1);
      expect(period.key, entry.$3);
      expect(period.timezoneId, 'America/New_York');
      expect(period.startAtUtc, entry.$1);
      expect(period.endAtUtc, entry.$2);
      expect(period.deadlineAtUtc, entry.$2);
    }
  });

  test('weekly period starts Monday and spans calendar DST change', () {
    final period = QuestPeriod.forAssignment(
      definition: definition(type: QuestType.weekly),
      assignedAtUtc: DateTime.utc(2026, 3, 8, 7),
      timezoneId: 'America/New_York',
    );
    expect(period.key, 'weekly:2026-03-02');
    expect(period.startAtUtc, DateTime.utc(2026, 3, 2, 5));
    expect(period.endAtUtc, DateTime.utc(2026, 3, 9, 4));
  });

  test('explicit duration is capped by the local calendar boundary', () {
    final assigned = DateTime.utc(2026, 8, 4, 16, 30);
    final period = QuestPeriod.forAssignment(
      definition: definition(expiresIn: const Duration(hours: 1)),
      assignedAtUtc: assigned,
      timezoneId: 'Asia/Bangkok',
    );
    expect(period.key, 'daily:2026-08-04');
    expect(period.deadlineAtUtc, DateTime.utc(2026, 8, 4, 17));
  });

  test(
    'one-shot without duration has stable once identity and no deadline',
    () {
      final period = QuestPeriod.forAssignment(
        definition: definition(type: QuestType.milestone),
        assignedAtUtc: DateTime.utc(2026, 8, 4),
        timezoneId: 'Asia/Bangkok',
      );
      expect(period.key, 'once');
      expect(period.endAtUtc, isNull);
      expect(period.deadlineAtUtc, isNull);
    },
  );

  test('invalid duration and local timestamp are rejected', () {
    for (final duration in [Duration.zero, const Duration(milliseconds: -1)]) {
      expect(
        () => QuestPeriod.forAssignment(
          definition: definition(expiresIn: duration),
          assignedAtUtc: DateTime.utc(2026, 8, 4),
          timezoneId: 'Asia/Bangkok',
        ),
        throwsA(isA<ArgumentError>()),
      );
    }
    expect(
      () => QuestPeriod.forAssignment(
        definition: definition(),
        assignedAtUtc: DateTime(2026, 8, 4),
        timezoneId: 'Asia/Bangkok',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

QuestDefinition definition({
  QuestType type = QuestType.daily,
  Duration? expiresIn,
}) => QuestDefinition(
  questId: 'synthetic-period',
  catalogVersion: 1,
  title: 'Synthetic',
  description: 'Synthetic period fixture',
  type: type,
  objectives: const [
    QuestObjective(
      objectiveId: 'answer',
      description: 'Answer',
      targetCount: 1,
      criteria: ObjectiveCriteria(eventType: 'QuizCompleted'),
    ),
  ],
  reward: const RewardSpec(xpAmount: 5),
  expiresIn: expiresIn,
);
