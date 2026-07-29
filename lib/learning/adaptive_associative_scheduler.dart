import 'dart:math' as math;

import 'memory_state.dart';
import 'recall_attempt.dart';

enum RecommendedAssociativeTask {
  supportedReading,
  unaidedRecall,
  transferPractice,
}

enum SchedulingReasonCode {
  lapseRecovery,
  supportedConsolidation,
  unaidedRecallStrengthened,
  transferMastery,
}

final class SchedulingEvidence {
  SchedulingEvidence({
    required this.ownerId,
    required this.wordKey,
    required this.correct,
    required this.normalizedLatency,
    required this.cueLevel,
    required this.confidence,
    required this.transferResult,
    required this.lapseHistory,
    required DateTime reviewedAtUtc,
    this.previousState,
  }) : reviewedAtUtc = reviewedAtUtc.toUtc() {
    if (ownerId.trim().isEmpty || wordKey.trim().isEmpty) {
      throw ArgumentError('Scheduling identifiers must be non-empty.');
    }
    if (!normalizedLatency.isFinite) {
      throw ArgumentError.value(
        normalizedLatency,
        'normalizedLatency',
        'must be finite',
      );
    }
    if (confidence < 1 || confidence > 5) {
      throw ArgumentError.value(confidence, 'confidence', 'must be 1 to 5');
    }
    if (lapseHistory < 0) {
      throw ArgumentError.value(
        lapseHistory,
        'lapseHistory',
        'must be non-negative',
      );
    }
    final prior = previousState;
    if (prior != null &&
        (prior.ownerId != ownerId || prior.wordKey != wordKey)) {
      throw ArgumentError('Previous state must describe the same owner/word.');
    }
  }

  final String ownerId;
  final String wordKey;
  final bool correct;
  final double normalizedLatency;
  final RecallCueLevel cueLevel;
  final int confidence;
  final bool? transferResult;
  final int lapseHistory;
  final DateTime reviewedAtUtc;
  final MemoryState? previousState;

  SchedulingEvidence withPreviousState(MemoryState? state) {
    return SchedulingEvidence(
      ownerId: ownerId,
      wordKey: wordKey,
      correct: correct,
      normalizedLatency: normalizedLatency,
      cueLevel: cueLevel,
      confidence: confidence,
      transferResult: transferResult,
      lapseHistory: lapseHistory,
      reviewedAtUtc: reviewedAtUtc,
      previousState: state,
    );
  }
}

final class SchedulingDecision {
  const SchedulingDecision({
    required this.memoryState,
    required this.nextDueAtUtc,
    required this.recommendedTask,
    required this.reasonCode,
    required this.algorithmVersion,
  });

  final MemoryState memoryState;
  final DateTime nextDueAtUtc;
  final RecommendedAssociativeTask recommendedTask;
  final SchedulingReasonCode reasonCode;
  final String algorithmVersion;
}

final class AdaptiveAssociativeScheduler {
  const AdaptiveAssociativeScheduler();

  static const algorithmVersion = 'associative-v1';

  SchedulingDecision schedule(SchedulingEvidence evidence) {
    final previous = evidence.previousState;
    final priorStrength = previous?.strength ?? 0;
    final priorStability = math.max(previous?.stability ?? 1, 0.25);
    final priorDifficulty = previous?.difficulty ?? 5;
    final priorCueDependency = previous?.cueDependency ?? 0.5;
    final priorLapses = math.max(
      previous?.lapseCount ?? 0,
      evidence.lapseHistory,
    );

    final latencyQuality = 1 - evidence.normalizedLatency.clamp(0, 1);
    final cueQuality = switch (evidence.cueLevel) {
      RecallCueLevel.none => 1.0,
      RecallCueLevel.highlight => 0.7,
      RecallCueLevel.associationHint => 0.4,
      RecallCueLevel.fullDefinition => 0.1,
    };
    final confidenceQuality = (evidence.confidence - 1) / 4;
    final transferQuality = switch (evidence.transferResult) {
      true => 1.0,
      false => 0.0,
      null => 0.5,
    };
    final lapsePenalty = math.min(priorLapses * 0.02, 0.2);
    final quality =
        ((evidence.correct ? 0.4 : 0.0) +
                cueQuality * 0.2 +
                confidenceQuality * 0.15 +
                latencyQuality * 0.1 +
                transferQuality * 0.15 -
                lapsePenalty)
            .clamp(0.0, 1.0);

    late final double stability;
    late final double strength;
    late final double difficulty;
    late final double cueDependency;
    late final int lapseCount;
    late final Duration interval;
    late final RecommendedAssociativeTask task;
    late final SchedulingReasonCode reason;
    String? lastErrorType;

    if (!evidence.correct) {
      stability = math.max(priorStability * 0.45, 0.25);
      strength = math.max(0, priorStrength - 0.5);
      difficulty = (priorDifficulty + 0.8).clamp(0.0, 10.0);
      cueDependency = (priorCueDependency + 0.15).clamp(0.0, 1.0);
      lapseCount = priorLapses + 1;
      interval = const Duration(minutes: 10);
      task = RecommendedAssociativeTask.supportedReading;
      reason = SchedulingReasonCode.lapseRecovery;
      lastErrorType = 'recall_lapse';
    } else {
      final intervalDays = quality >= 0.8
          ? priorStability * (2 + quality * 2)
          : quality >= 0.6
          ? math.max(1, priorStability * (1 + quality))
          : 0.5;
      final boundedDays = intervalDays.clamp(1 / 144, 365).toDouble();
      interval = Duration(
        microseconds: (boundedDays * Duration.microsecondsPerDay).round(),
      );
      stability = math
          .max(priorStability, boundedDays)
          .clamp(0.25, 365)
          .toDouble();
      strength = math.max(0, priorStrength + quality);
      difficulty = (priorDifficulty - (quality - 0.5)).clamp(0.0, 10.0);
      cueDependency = (priorCueDependency * 0.7 + (1 - cueQuality) * 0.3).clamp(
        0.0,
        1.0,
      );
      lapseCount = priorLapses;
      if (quality >= 0.8 && evidence.transferResult == true) {
        task = RecommendedAssociativeTask.transferPractice;
        reason = SchedulingReasonCode.transferMastery;
      } else if (quality >= 0.6) {
        task = RecommendedAssociativeTask.unaidedRecall;
        reason = SchedulingReasonCode.unaidedRecallStrengthened;
      } else {
        task = RecommendedAssociativeTask.supportedReading;
        reason = SchedulingReasonCode.supportedConsolidation;
      }
    }

    final nextDueAt = evidence.reviewedAtUtc.add(interval);
    final memoryState = MemoryState(
      ownerId: evidence.ownerId,
      wordKey: evidence.wordKey,
      strength: strength,
      cueDependency: cueDependency,
      stability: stability,
      difficulty: difficulty,
      lapseCount: lapseCount,
      lastReviewedAtUtc: evidence.reviewedAtUtc,
      nextDueAtUtc: nextDueAt,
      lastErrorType: lastErrorType,
      algorithmVersion: algorithmVersion,
      updatedAtUtc: evidence.reviewedAtUtc,
    );
    return SchedulingDecision(
      memoryState: memoryState,
      nextDueAtUtc: nextDueAt,
      recommendedTask: task,
      reasonCode: reason,
      algorithmVersion: algorithmVersion,
    );
  }
}

final class SchedulingProjectionRebuilder {
  const SchedulingProjectionRebuilder(this.scheduler);

  final AdaptiveAssociativeScheduler scheduler;

  SchedulingDecision rebuild(List<SchedulingEvidence> orderedEvidence) {
    if (orderedEvidence.isEmpty) {
      throw ArgumentError.value(
        orderedEvidence,
        'orderedEvidence',
        'must not be empty',
      );
    }
    SchedulingDecision? decision;
    DateTime? previousReview;
    for (final evidence in orderedEvidence) {
      if (previousReview != null &&
          evidence.reviewedAtUtc.isBefore(previousReview)) {
        throw ArgumentError('Scheduling evidence must be chronological.');
      }
      decision = scheduler.schedule(
        evidence.withPreviousState(decision?.memoryState),
      );
      previousReview = evidence.reviewedAtUtc;
    }
    return decision!;
  }
}
