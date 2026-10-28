import 'progress_remote_writer.dart';
import 'progress_repository.dart';

sealed class ProgressSyncResult {
  const ProgressSyncResult();
}

final class ProgressSyncCompleted extends ProgressSyncResult {
  const ProgressSyncCompleted({required this.synchronizedSessions});

  final int synchronizedSessions;

  @override
  bool operator ==(Object other) {
    return other is ProgressSyncCompleted &&
        other.synchronizedSessions == synchronizedSessions;
  }

  @override
  int get hashCode => synchronizedSessions.hashCode;
}

final class ProgressSyncIncomplete extends ProgressSyncResult {
  const ProgressSyncIncomplete({
    required this.synchronizedSessions,
    required this.failure,
  });

  final int synchronizedSessions;
  final ProgressRemoteFailure failure;

  @override
  bool operator ==(Object other) {
    return other is ProgressSyncIncomplete &&
        other.synchronizedSessions == synchronizedSessions &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(synchronizedSessions, failure);
}

final class ProgressSyncService {
  const ProgressSyncService({
    required this.repository,
    required this.remoteWriter,
  });

  final ProgressRepository repository;
  final ProgressRemoteWriter remoteWriter;

  Future<ProgressSyncResult> synchronize() async {
    final List<ProgressSession> sessions;
    try {
      sessions = await repository.pendingSessions();
    } on Object {
      return const ProgressSyncIncomplete(
        synchronizedSessions: 0,
        failure: ProgressRemoteFailure.localPersistence,
      );
    }
    var synchronizedSessions = 0;
    for (final session in sessions) {
      final ProgressRemoteResult remoteResult;
      try {
        remoteResult = await remoteWriter.recordProgressSession(session);
      } on Object {
        return ProgressSyncIncomplete(
          synchronizedSessions: synchronizedSessions,
          failure: ProgressRemoteFailure.unknown,
        );
      }
      if (remoteResult case ProgressRemoteRejected(:final failure)) {
        return ProgressSyncIncomplete(
          synchronizedSessions: synchronizedSessions,
          failure: failure,
        );
      }
      try {
        await repository.acknowledgeSession(session.sessionId);
      } on Object {
        return ProgressSyncIncomplete(
          synchronizedSessions: synchronizedSessions,
          failure: ProgressRemoteFailure.localPersistence,
        );
      }
      synchronizedSessions++;
    }
    return ProgressSyncCompleted(synchronizedSessions: synchronizedSessions);
  }
}
