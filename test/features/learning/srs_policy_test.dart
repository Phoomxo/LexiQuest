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

  test('long correct sequence saturates at the numerical safety ceiling', () {
    SrsSnapshot? state;

    for (var repetition = 0; repetition < 27; repetition++) {
      state = policy.review(previous: state, isCorrect: true, nowUtc: now);
    }

    expect(state?.intervalDays, 36500);
    expect(state?.repetitions, 27);
    expect(state?.algorithmVersion, 2);

    final continued = policy.review(
      previous: state,
      isCorrect: true,
      nowUtc: now,
    );
    expect(continued.intervalDays, 36500);
    expect(continued.repetitions, 28);
    expect(continued.algorithmVersion, 2);
  });

  test('oversized historical interval saturates before multiplication', () {
    const previous = SrsSnapshot(
      intervalDays: 1 << 62,
      repetitions: 27,
      lapses: 4,
      stability: 1,
      difficulty: 0.4,
      lastReviewAtUtc: null,
      dueAtUtc: null,
      algorithmVersion: 1,
    );

    final next = policy.review(
      previous: previous,
      isCorrect: true,
      nowUtc: now,
    );

    expect(next.intervalDays, 36500);
    expect(next.repetitions, 28);
    expect(next.lapses, 4);
    expect(next.dueAtUtc, now.add(const Duration(days: 36500)));
    expect(next.algorithmVersion, 2);
  });

  test(
    'correct and incorrect sequence resets then regrows deterministically',
    () {
      SrsSnapshot? state;
      final outcomes = <bool>[
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        true,
        true,
      ];
      final expectedIntervals = <int>[1, 3, 7, 14, 28, 1, 1, 3, 7, 14, 28];

      for (var index = 0; index < outcomes.length; index++) {
        state = policy.review(
          previous: state,
          isCorrect: outcomes[index],
          nowUtc: now,
        );
        expect(state.intervalDays, expectedIntervals[index]);
        expect(state.algorithmVersion, 2);
      }

      expect(state?.repetitions, 5);
      expect(state?.lapses, 1);
    },
  );

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
    expect(next.algorithmVersion, 2);
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
