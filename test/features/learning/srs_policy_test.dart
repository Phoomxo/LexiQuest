import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/srs_policy.dart';

void main() {
  const policy = BinarySm2SrsPolicy();
  final now = DateTime.utc(2026, 7, 30, 10);

  test('first correct review schedules one day and records repetition', () {
    final next = policy.review(previous: null, isCorrect: true, nowUtc: now);

    expect(next.intervalDays, 1);
    expect(next.repetitions, 1);
    expect(next.lapses, 0);
    expect(next.dueAtUtc, DateTime.utc(2026, 7, 31, 10));
    expect(next.algorithmVersion, BinarySm2SrsPolicy.version);
  });

  test('correct sequence is deterministic and grows after fourteen days', () {
    SrsSnapshot? state;
    final expected = <int>[1, 3, 7, 14, 28];

    for (final interval in expected) {
      state = policy.review(previous: state, isCorrect: true, nowUtc: now);
      expect(state.intervalDays, interval);
    }
  });

  test('incorrect review resets interval and increments lapses', () {
    const previous = SrsSnapshot(
      intervalDays: 14,
      repetitions: 4,
      lapses: 2,
      stability: 14,
      difficulty: 0.25,
      lastReviewAtUtc: null,
      dueAtUtc: null,
      algorithmVersion: BinarySm2SrsPolicy.version,
    );

    final next = policy.review(
      previous: previous,
      isCorrect: false,
      nowUtc: now,
    );

    expect(next.intervalDays, 1);
    expect(next.repetitions, 0);
    expect(next.lapses, 3);
    expect(next.difficulty, greaterThan(previous.difficulty));
  });

  test('rejects a non-UTC clock value', () {
    expect(
      () => policy.review(
        previous: null,
        isCorrect: true,
        nowUtc: DateTime(2026, 7, 30),
      ),
      throwsArgumentError,
    );
  });
}
