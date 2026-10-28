import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/goals/domain/study_plan.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  StudyPlanRevision plan({int minutes = 10, DateTime? now, DateTime? prior}) =>
      StudyPlanRevision.propose(
        operationId: 'op',
        expectedPriorRevision: 0,
        createdAtUtc: now ?? DateTime.utc(2026, 9, 20),
        timezoneId: 'America/New_York',
        availableMinutes: minutes,
        authorityHash: 'authority',
        goalId: 'goal',
        deadlineAtUtc: DateTime.utc(2026, 9, 21),
        priorCreatedAtUtc: prior,
        dueItemIds: List.generate(12, (i) => 'due$i'),
        newItemIds: List.generate(5, (i) => 'new$i'),
      );
  test('PLAN-BUDGET reserves due first and preserves excess as carry-over', () {
    final p = plan();
    expect(p.dueItems.length, 10);
    expect(p.newItems, isEmpty);
    expect(p.carryOver, ['due10', 'due11']);
    expect(p.revision, 1);
  });
  test('zero capacity retains every due item without new work', () {
    final p = plan(minutes: 0);
    expect(p.dueItems, isEmpty);
    expect(p.newItems, isEmpty);
    expect(p.carryOver.length, 12);
  });
  test('spare capacity allocates unique new work only after all due work', () {
    final p = plan(minutes: 15);
    expect(p.dueItems.length, 12);
    expect(p.newItems, ['new0', 'new1', 'new2']);
    expect(p.carryOver, isEmpty);
  });
  test('calendar missed days crosses DST without duration truncation', () {
    final p = plan(
      now: DateTime.utc(2026, 3, 9, 4),
      prior: DateTime.utc(2026, 3, 7, 5),
    );
    expect(p.missedDays, 1);
    expect(p.learningDay, '2026-03-09');
    expect(p.carryOver.length, 2);
  });
  test('past deadline is visible and does not drop due work', () {
    final p = plan(now: DateTime.utc(2026, 9, 23));
    expect(p.deadlinePassed, isTrue);
    expect(p.dueItems.length + p.carryOver.length, 12);
  });
  test('revision payload round trips with immutable collections', () {
    final p = plan();
    final restored = StudyPlanRevision.fromJson(p.toJson());
    expect(restored.payloadHash, p.payloadHash);
    expect(() => restored.dueItems.add('changed'), throwsUnsupportedError);
    final corrupt = p.toJson()..['availableMinutes'] = 0;
    expect(() => StudyPlanRevision.fromJson(corrupt), throwsFormatException);
  });
  test('invalid capacity fails instead of silently clamping', () {
    expect(() => plan(minutes: -1), throwsArgumentError);
    expect(() => plan(minutes: 1441), throwsArgumentError);
  });
  test(
    'proposal factory rejects invalid goal and negative deadline metadata',
    () {
      for (final (goal, deadline) in [
        ('', DateTime.utc(2026)),
        ('goal', DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true)),
      ]) {
        expect(
          () => StudyPlanRevision.propose(
            operationId: 'bad',
            expectedPriorRevision: 0,
            createdAtUtc: DateTime.utc(2026),
            timezoneId: 'UTC',
            availableMinutes: 1,
            authorityHash: 'source',
            goalId: goal,
            deadlineAtUtc: deadline,
            dueItemIds: [],
            newItemIds: [],
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'rehashed malformed archive fails structural and calendar validation',
    () {
      final bad = <Map<String, Object?>>[
        {'operationId': ''},
        {'learningDay': '1900-01-01'},
        {'missedDays': -1},
        {'timezoneId': 'not/a-zone'},
        {'unexpected': true},
        {'revision': 0},
        {'createdAtUtcMs': -1},
        {'goalId': ''},
        {'deadlineAtUtcMs': 'not-a-time'},
        {'deadlinePassed': true},
      ];
      for (final change in bad) {
        final payload = plan().toJson()..remove('payloadHash');
        payload.addAll(change);
        final envelope = {...payload, 'payloadHash': studyPlanHash(payload)};
        expect(
          () => StudyPlanRevision.fromJson(envelope),
          throwsFormatException,
          reason: '$change',
        );
      }
    },
  );
}
