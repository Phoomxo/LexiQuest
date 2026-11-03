import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/srs_policy.dart';

void main() {
  const policy = BinarySm2SrsPolicy();
  var checks = 0;
  for (final clock in [
    DateTime.utc(2026, 11, 3),
    DateTime.utc(-200000, 1, 1, 0, 0, 0, 1),
    DateTime.utc(275760, 9, 12, 0, 0, 0, 0, 1),
    DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true),
  ]) {
    SrsSnapshot? state;
    for (var attempt = 0; attempt < 100; attempt++) {
      final next = policy.review(previous: state, isCorrect: true, nowUtc: clock);
      if (next.dueAtUtc == null ||
          next.dueAtUtc!.isBefore(clock) ||
          (state != null && next.dueAtUtc!.isBefore(state.dueAtUtc!)) ||
          next.repetitions != attempt + 1 ||
          !next.stability.isFinite) {
        throw StateError('Invalid SRS boundary at $clock, attempt $attempt');
      }
      state = next;
      checks++;
    }
  }
  // ignore: avoid_print
  print('SRS boundary verification passed: $checks reviews');
}
