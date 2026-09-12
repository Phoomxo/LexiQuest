import '../data/pair_matching_checkpoint_codec.dart';
import 'pair_matching_launch.dart';
import 'pair_active_clock.dart';
import 'pair_star_policy.dart';
import 'pair_matching_engine.dart';

final class PairMatchingHistoryProjection {
  PairMatchingHistoryProjection(PairMatchingCheckpointSnapshot snapshot)
    : sessionId = snapshot.engine.plan.learningSessionId,
      firstAnswers = _answerCounts(snapshot.engine, repair: false),
      repairAnswers = _answerCounts(snapshot.engine, repair: true),
      terminalAtUtc = snapshot.terminal?.atUtc,
      purpose = snapshot.engine.plan.sessionPurpose,
      sourceSessionId = snapshot.engine.plan.sourceSessionId,
      result = PairStarPolicy.project(
        snapshot.engine,
        terminalAcknowledged: snapshot.terminal?.acknowledged ?? false,
      ),
      timer =
          snapshot.timer ??
          PairTimerState.initial(snapshot.engine.plan.timerPreset),
      reviewNext =
          snapshot.engine.supportedWordIds.isNotEmpty ||
          snapshot.engine.attempts.any((a) => !a.isCorrect);
  final PairSessionPurpose purpose;
  final String sessionId;
  final DateTime? terminalAtUtc;
  final String? sourceSessionId;
  final PairStarResult result;
  final PairTimerState timer;
  final bool reviewNext;
  final ({int correct, int total}) firstAnswers, repairAnswers;
}

// Rebuildable presentation facts. Subsequent attempts cannot replace the first
// submitted answer for a word or modify canonical scores/evidence/rewards.
({int correct, int total}) _answerCounts(
  PairMatchingState state, {
  required bool repair,
}) {
  final seen = <String>{};
  var correct = 0;
  var total = 0;
  for (final attempt in state.attempts) {
    final first = seen.add(attempt.promptWordId);
    if (first == repair) continue;
    total++;
    if (attempt.isCorrect) correct++;
  }
  return (correct: correct, total: total);
}

/// Rebuildable selectors over terminal canonical results. Replay never competes
/// for normal latest/best and remains grouped by its direct immutable source.
final class PairMatchingHistoryOverview {
  PairMatchingHistoryOverview(Iterable<PairMatchingHistoryProjection> entries) {
    final sorted = entries.where((e) => e.terminalAtUtc != null).toList()
      ..sort((a, b) {
        final order = b.terminalAtUtc!.compareTo(a.terminalAtUtc!);
        return order != 0 ? order : a.sessionId.compareTo(b.sessionId);
      });
    final normal = sorted
        .where((e) => e.purpose == PairSessionPurpose.learning)
        .toList();
    latestNormal = normal.isEmpty ? null : normal.first;
    final scored = normal.where((e) => e.result.stars != null).toList();
    bestNormal = scored.isEmpty
        ? null
        : scored.reduce((a, b) => b.result.stars! > a.result.stars! ? b : a);
    final replay = <String, List<PairMatchingHistoryProjection>>{};
    for (final item in sorted.where(
      (e) => e.purpose == PairSessionPurpose.practiceReplay,
    )) {
      replay.putIfAbsent(item.sourceSessionId!, () => []).add(item);
    }
    replaysBySource = Map.unmodifiable({
      for (final entry in replay.entries)
        entry.key: List<PairMatchingHistoryProjection>.unmodifiable(
          entry.value,
        ),
    });
  }
  late final PairMatchingHistoryProjection? latestNormal;
  late final PairMatchingHistoryProjection? bestNormal;
  late final Map<String, List<PairMatchingHistoryProjection>> replaysBySource;
  PairMatchingHistoryProjection? latestReplayFor(String sourceSessionId) =>
      replaysBySource[sourceSessionId]?.first;
  PairMatchingHistoryProjection? bestReplayFor(String sourceSessionId) {
    final scored =
        (replaysBySource[sourceSessionId] ??
                const <PairMatchingHistoryProjection>[])
            .where((e) => e.result.stars != null)
            .toList();
    return scored.isEmpty
        ? null
        : scored.reduce((a, b) => b.result.stars! > a.result.stars! ? b : a);
  }
}
