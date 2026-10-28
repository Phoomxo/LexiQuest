import '../../identity/domain/local_owner_repository.dart';
import '../../learning/domain/lesson_session_state.dart';
import '../../learning/pair_matching/domain/pair_matching_history_projection.dart';
import '../../learning/pair_matching/domain/pair_matching_session_purpose.dart';
import '../domain/learning_history_models.dart';

abstract interface class LearningHistorySessionLauncher {
  Object get authorityIdentity;

  Future<void> start(LessonStartCommand command);
}

/// Read-model orchestration plus a narrow bridge into the existing lesson
/// start authority. History never writes sessions, attempts, or projections.
final class LearningHistoryUseCases {
  const LearningHistoryUseCases({
    required this.owners,
    required this.reader,
    required this.sessionLauncher,
    this.pairReader,
  });

  final LocalOwnerRepository owners;
  final LearningHistoryReader reader;
  final LearningHistorySessionLauncher sessionLauncher;
  final PairMatchingSessionPurposeReader? pairReader;

  Object get sessionAuthorityIdentity => sessionLauncher.authorityIdentity;

  Future<List<LearningHistoryEntry>> load({int limit = 20}) async {
    final owner = await owners.getOrCreateActiveOwner();
    return reader.list(HistoryFilter(ownerId: owner.id, limit: limit));
  }

  /// Loads authenticated terminal Pair projections for the exact sessions
  /// already selected for display. This read grants no replay authority.
  Future<List<PairMatchingHistoryProjection>> loadPairResults(
    Iterable<String> displayedSessionIds,
  ) async {
    final purposeReader = pairReader;
    if (purposeReader == null) {
      return const <PairMatchingHistoryProjection>[];
    }
    final sessionIds = <String>{};
    for (final sessionId in displayedSessionIds) {
      if (sessionId.isEmpty ||
          sessionId != sessionId.trim() ||
          sessionId.length > 256) {
        throw StateError('Pair history session identity is invalid');
      }
      sessionIds.add(sessionId);
    }

    final ownerBefore = await owners.getOrCreateActiveOwner();
    final results = <PairMatchingHistoryProjection>[];
    for (final sessionId in sessionIds) {
      final purpose = await purposeReader.read(
        ownerId: ownerBefore.id,
        sessionId: sessionId,
      );
      if (purpose.unknownMatching) {
        throw StateError('Pair history purpose is unavailable');
      }
      final snapshot = purpose.snapshot;
      if (snapshot == null) {
        continue;
      }
      if (snapshot.engine.plan.learningSessionId != sessionId) {
        throw StateError('Pair history result is unavailable');
      }
      // A strictly authenticated stopped/incomplete session is not a
      // successful result, but does not invalidate other sessions on the page.
      if (snapshot.terminal?.acknowledged != true) continue;
      results.add(PairMatchingHistoryProjection(snapshot));
    }
    final ownerAfter = await owners.getOrCreateActiveOwner();
    if (ownerAfter.id != ownerBefore.id) {
      throw StateError('Pair history owner changed');
    }
    return List<PairMatchingHistoryProjection>.unmodifiable(results);
  }

  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    final command = await reader.replayAsNewSession(
      sourceSessionId,
      replayOperationId: replayOperationId,
    );
    if (command.ownerId != owner.id || command.sessionId == sourceSessionId) {
      throw StateError('history replay does not belong to the active owner');
    }
    await sessionLauncher.start(command);
    return command;
  }
}
