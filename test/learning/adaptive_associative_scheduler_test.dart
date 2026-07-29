import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/adaptive_associative_scheduler.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/recall_attempt.dart';

final _reviewedAt = DateTime.utc(2026, 7, 29, 8);

SchedulingEvidence _evidence({
  bool correct = true,
  double normalizedLatency = 0.25,
  RecallCueLevel cueLevel = RecallCueLevel.none,
  int confidence = 4,
  bool? transferResult = true,
  int lapseHistory = 0,
  MemoryState? previousState,
  DateTime? reviewedAtUtc,
}) {
  return SchedulingEvidence(
    ownerId: 'owner-a',
    wordKey: 'resilient',
    correct: correct,
    normalizedLatency: normalizedLatency,
    cueLevel: cueLevel,
    confidence: confidence,
    transferResult: transferResult,
    lapseHistory: lapseHistory,
    reviewedAtUtc: reviewedAtUtc ?? _reviewedAt,
    previousState: previousState,
  );
}

void _expectSameDecision(SchedulingDecision first, SchedulingDecision second) {
  expect(second.algorithmVersion, first.algorithmVersion);
  expect(second.nextDueAtUtc, first.nextDueAtUtc);
  expect(second.recommendedTask, first.recommendedTask);
  expect(second.reasonCode, first.reasonCode);
  expect(second.memoryState.ownerId, first.memoryState.ownerId);
  expect(second.memoryState.wordKey, first.memoryState.wordKey);
  expect(second.memoryState.strength, first.memoryState.strength);
  expect(second.memoryState.cueDependency, first.memoryState.cueDependency);
  expect(second.memoryState.stability, first.memoryState.stability);
  expect(second.memoryState.difficulty, first.memoryState.difficulty);
  expect(second.memoryState.lapseCount, first.memoryState.lapseCount);
  expect(second.memoryState.nextDueAtUtc, first.memoryState.nextDueAtUtc);
}

void main() {
  const scheduler = AdaptiveAssociativeScheduler();

  test('associative-v1 is deterministic for identical evidence', () {
    final first = scheduler.schedule(_evidence());
    final second = scheduler.schedule(_evidence());

    _expectSameDecision(first, second);
    expect(first.algorithmVersion, 'associative-v1');
    expect(first.nextDueAtUtc.isAfter(_reviewedAt), isTrue);
  });

  test('unaided recall outweighs cued recognition', () {
    final unaided = scheduler.schedule(
      _evidence(cueLevel: RecallCueLevel.none),
    );
    final cued = scheduler.schedule(
      _evidence(cueLevel: RecallCueLevel.fullDefinition),
    );

    expect(unaided.nextDueAtUtc.isAfter(cued.nextDueAtUtc), isTrue);
    expect(
      unaided.memoryState.cueDependency,
      lessThan(cued.memoryState.cueDependency),
    );
  });

  test('successful transfer outweighs failed transfer', () {
    final successful = scheduler.schedule(_evidence(transferResult: true));
    final failed = scheduler.schedule(_evidence(transferResult: false));

    expect(successful.nextDueAtUtc.isAfter(failed.nextDueAtUtc), isTrue);
    expect(
      successful.recommendedTask,
      RecommendedAssociativeTask.transferPractice,
    );
  });

  test('lapse schedules recovery and increments lapse history', () {
    final prior = scheduler.schedule(_evidence()).memoryState;
    final decision = scheduler.schedule(
      _evidence(
        correct: false,
        transferResult: false,
        lapseHistory: prior.lapseCount,
        previousState: prior,
        reviewedAtUtc: _reviewedAt.add(const Duration(days: 1)),
      ),
    );

    expect(decision.reasonCode, SchedulingReasonCode.lapseRecovery);
    expect(
      decision.recommendedTask,
      RecommendedAssociativeTask.supportedReading,
    );
    expect(decision.memoryState.lapseCount, prior.lapseCount + 1);
    expect(decision.memoryState.stability, lessThan(prior.stability));
    expect(
      decision.nextDueAtUtc,
      _reviewedAt.add(const Duration(days: 1, minutes: 10)),
    );
  });

  test('finite extreme latency values never create invalid intervals', () {
    for (final latency in [-1e12, 0.0, 1e12]) {
      final decision = scheduler.schedule(
        _evidence(normalizedLatency: latency),
      );

      expect(decision.memoryState.stability.isFinite, isTrue);
      expect(decision.memoryState.stability, isNonNegative);
      expect(decision.nextDueAtUtc.isAfter(_reviewedAt), isTrue);
      expect(
        decision.nextDueAtUtc.difference(_reviewedAt),
        lessThanOrEqualTo(const Duration(days: 365)),
      );
    }
  });

  test('non-finite evidence fails before producing a projection', () {
    expect(
      () => scheduler.schedule(_evidence(normalizedLatency: double.nan)),
      throwsArgumentError,
    );
    expect(
      () => scheduler.schedule(_evidence(normalizedLatency: double.infinity)),
      throwsArgumentError,
    );
  });

  test('replaying ordered evidence rebuilds the same projection', () {
    final events = [
      _evidence(
        correct: false,
        transferResult: false,
        reviewedAtUtc: _reviewedAt,
      ),
      _evidence(
        cueLevel: RecallCueLevel.associationHint,
        transferResult: true,
        lapseHistory: 1,
        reviewedAtUtc: _reviewedAt.add(const Duration(days: 1)),
      ),
      _evidence(
        reviewedAtUtc: _reviewedAt.add(const Duration(days: 3)),
        lapseHistory: 1,
      ),
    ];
    const rebuilder = SchedulingProjectionRebuilder(scheduler);

    final first = rebuilder.rebuild(events);
    final second = rebuilder.rebuild(events);

    _expectSameDecision(first, second);
    expect(first.memoryState.lapseCount, 1);
  });
}
