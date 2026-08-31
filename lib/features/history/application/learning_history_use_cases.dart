import '../../identity/domain/local_owner_repository.dart';
import '../../learning/domain/lesson_session_state.dart';
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
  });

  final LocalOwnerRepository owners;
  final LearningHistoryReader reader;
  final LearningHistorySessionLauncher sessionLauncher;

  Object get sessionAuthorityIdentity => sessionLauncher.authorityIdentity;

  Future<List<LearningHistoryEntry>> load({int limit = 20}) async {
    final owner = await owners.getOrCreateActiveOwner();
    return reader.list(HistoryFilter(ownerId: owner.id, limit: limit));
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
