import 'dart:math';
import 'memory_state.dart';
import 'recall_attempt.dart';

class AdaptiveAssociativeScheduler {
  final String algorithmVersion;

  AdaptiveAssociativeScheduler({this.algorithmVersion = 'v1.0.0'});

  MemoryState updateMemoryState({
    required MemoryState currentState,
    required RecallAttempt attempt,
    required DateTime now,
  }) {
    double newStability = currentState.stability;
    double newDifficulty = currentState.difficulty;
    double newCueDependency = currentState.cueDependency;
    int newLapseCount = currentState.lapseCount;

    // Adjust cue dependency based on cue usage
    if (attempt.cueLevel != CueLevel.none) {
      newCueDependency = (newCueDependency + 0.15).clamp(0.0, 1.0);
    } else {
      newCueDependency = (newCueDependency - 0.1).clamp(0.0, 1.0);
    }

    if (attempt.correctness) {
      // Correct recall increases stability; bonus for unaided & high confidence
      double recallFactor = attempt.cueLevel == CueLevel.none ? 1.4 : 1.1;
      if (attempt.confidence >= 4) recallFactor += 0.2;

      newStability = (newStability * recallFactor).clamp(0.5, 365.0);
      newDifficulty = (newDifficulty - 0.1).clamp(1.0, 10.0);
    } else {
      // Incorrect recall drops stability and increases lapse
      newLapseCount += 1;
      newStability = max(0.5, newStability * 0.5);
      newDifficulty = (newDifficulty + 0.3).clamp(1.0, 10.0);
    }

    final intervalDays = max(1, newStability.round());
    final nextDue = now.add(Duration(days: intervalDays));

    return MemoryState(
      ownerId: currentState.ownerId,
      wordKey: currentState.wordKey,
      strength: newStability,
      cueDependency: newCueDependency,
      stability: newStability,
      difficulty: newDifficulty,
      lapseCount: newLapseCount,
      lastReviewedAt: now,
      nextDueAt: nextDue,
      lastErrorType: attempt.correctness ? null : 'recall_failure',
      algorithmVersion: algorithmVersion,
    );
  }
}
