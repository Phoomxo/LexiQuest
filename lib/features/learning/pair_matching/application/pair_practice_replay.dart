import '../data/drift_pair_matching_session_purpose_reader.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_matching_plan.dart';
import '../domain/pair_matching_session_purpose.dart';
import 'pair_matching_atomic_start.dart';

/// Explicit new-session operation; callers retain its exact bytes for retry.
final class PairPracticeReplay {
  const PairPracticeReplay({required this.reader, required this.start});
  final DriftPairMatchingSessionPurposeReader reader;
  final PairMatchingAtomicStartAdapter start;
  Future<PairMatchingStartOperation> prepare({
    required String ownerId,
    required String sourceSessionId,
    required String launchOperationId,
    required DateTime createdAtUtc,
    required String appVersion,
    required String buildId,
  }) async {
    final source = (await reader.read(
      ownerId: ownerId,
      sessionId: sourceSessionId,
    )).snapshot;
    if (source == null ||
        source.terminal?.acknowledged != true ||
        !source.engine.complete) {
      throw StateError('Pair replay requires an authenticated terminal source');
    }
    final prior = source.engine.plan;
    if (createdAtUtc.isBefore(source.terminal!.atUtc)) {
      throw StateError('Replay predates its source');
    }
    var seed = int.parse(
      pairHash('$launchOperationId:replay').substring(0, 7),
      radix: 16,
    );
    if (seed == prior.shuffleSeed) seed = (seed + 1) & 0x7fffffff;
    return PairMatchingStartOperation(
      plan: PairMatchingPlanV1(
        ownerId: ownerId,
        orderedLexicalItems: prior.orderedLexicalItems,
        direction: prior.direction,
        density: prior.density,
        shuffleSeed: seed,
        timerPreset: prior.timerPreset,
        allowlistVersion: prior.allowlistVersion,
        learningSessionId: pairSessionId(ownerId, launchOperationId),
        entryKind: prior.entryKind,
        sourceSnapshotId: prior.sourceSnapshotId,
        createdAtUtc: createdAtUtc,
        sessionPurpose: PairSessionPurpose.practiceReplay,
        sourceSessionId: sourceSessionId,
      ),
      launchOperationId: launchOperationId,
      appVersion: appVersion,
      buildId: buildId,
      configuration: PairMatchingSessionPurpose.projectConfigurationOwner(
        PairMatchingStartOperation.fromStableSerialization(
          source.startOperation,
        ).configuration,
        ownerId,
      ),
    );
  }
}
