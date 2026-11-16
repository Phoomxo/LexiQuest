import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/adaptive_associative_scheduler.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/recall_attempt.dart';

void main() {
  group('B5 Adaptive Associative Scheduler Tests', () {
    final now = DateTime.utc(2026, 7, 27, 10, 0, 0);
    late AdaptiveAssociativeScheduler scheduler;

    setUp(() {
      scheduler = AdaptiveAssociativeScheduler();
    });

    test(
      'Unaided correct recall increases stability more than cued recall',
      () {
        final initial = MemoryState(
          ownerId: 'u1',
          wordKey: 'ephemeral',
          stability: 2.0,
          nextDueAt: now,
        );

        final unaidedAttempt = RecallAttempt(
          attemptId: 'att-1',
          sessionId: 'sess-1',
          wordKey: 'ephemeral',
          recallMode: RecallMode.unaided,
          cueLevel: CueLevel.none,
          correctness: true,
          responseTimeMs: 600,
          confidence: 5,
          occurredAt: now,
        );

        final cuedAttempt = RecallAttempt(
          attemptId: 'att-2',
          sessionId: 'sess-1',
          wordKey: 'ephemeral',
          recallMode: RecallMode.cued,
          cueLevel: CueLevel.associationHint,
          correctness: true,
          responseTimeMs: 600,
          confidence: 3,
          occurredAt: now,
        );

        final updatedUnaided = scheduler.updateMemoryState(
          currentState: initial,
          attempt: unaidedAttempt,
          now: now,
        );

        final updatedCued = scheduler.updateMemoryState(
          currentState: initial,
          attempt: cuedAttempt,
          now: now,
        );

        expect(updatedUnaided.stability, greaterThan(updatedCued.stability));
        expect(
          updatedUnaided.cueDependency,
          lessThan(updatedCued.cueDependency),
        );
      },
    );

    test('Incorrect recall reduces stability and increases lapse count', () {
      final initial = MemoryState(
        ownerId: 'u1',
        wordKey: 'ephemeral',
        stability: 4.0,
        lapseCount: 0,
        nextDueAt: now,
      );

      final failedAttempt = RecallAttempt(
        attemptId: 'att-3',
        sessionId: 'sess-1',
        wordKey: 'ephemeral',
        recallMode: RecallMode.cloze,
        cueLevel: CueLevel.none,
        correctness: false,
        responseTimeMs: 1500,
        confidence: 1,
        occurredAt: now,
      );

      final updated = scheduler.updateMemoryState(
        currentState: initial,
        attempt: failedAttempt,
        now: now,
      );

      expect(updated.stability, lessThan(initial.stability));
      expect(updated.lapseCount, equals(1));
      expect(updated.lastErrorType, equals('recall_failure'));
    });
  });
}
