import 'dart:math' as math;

import 'learning_models.dart';

abstract interface class SrsPolicy {
  SrsSnapshot review({
    required SrsSnapshot? previous,
    required bool isCorrect,
    required DateTime nowUtc,
  });
}

/// Versioned binary SM-2-compatible policy for correctness-only evidence.
///
/// The fixed early intervals avoid pretending that a binary quiz answer carries
/// the richer 0-5 quality signal required by full SM-2.
final class BinarySm2SrsPolicy implements SrsPolicy {
  const BinarySm2SrsPolicy();

  static const int version = 1;
  static const List<int> _earlyIntervals = <int>[1, 3, 7, 14];

  @override
  SrsSnapshot review({
    required SrsSnapshot? previous,
    required bool isCorrect,
    required DateTime nowUtc,
  }) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    final prior = previous;
    final priorDifficulty = prior?.difficulty ?? 0.3;
    final repetitions = isCorrect ? (prior?.repetitions ?? 0) + 1 : 0;
    final interval = isCorrect
        ? repetitions <= _earlyIntervals.length
              ? _earlyIntervals[repetitions - 1]
              : math.max(1, (prior?.intervalDays ?? 14) * 2)
        : 1;
    final difficulty = isCorrect
        ? math.max(0.1, priorDifficulty - 0.03)
        : math.min(1.0, priorDifficulty + 0.12);
    return SrsSnapshot(
      intervalDays: interval,
      repetitions: repetitions,
      lapses: (prior?.lapses ?? 0) + (isCorrect ? 0 : 1),
      stability: interval.toDouble(),
      difficulty: difficulty,
      lastReviewAtUtc: nowUtc,
      dueAtUtc: nowUtc.add(Duration(days: interval)),
      algorithmVersion: version,
    );
  }
}
