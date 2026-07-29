import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/progress/progress_remote_writer.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';
import 'package:vocab_learning_app/progress/progress_sync_service.dart';

final _completedAt = DateTime.utc(2026, 7, 29, 10);

ProgressSession _session(String id) {
  return ProgressSession(
    sessionId: id,
    correctAnswers: 1,
    wrongAnswers: 0,
    eventIds: ['$id-event'],
    completedAtUtc: _completedAt,
  );
}

void main() {
  test('acknowledges recorded and duplicate sessions exactly once', () async {
    final repository = _StubProgressRepository([
      _session('session-1'),
      _session('session-2'),
    ]);
    final writer = _StubRemoteWriter({
      'session-1': const ProgressRemoteAccepted(duplicate: false),
      'session-2': const ProgressRemoteAccepted(duplicate: true),
    });
    final service = ProgressSyncService(
      repository: repository,
      remoteWriter: writer,
    );

    final result = await service.synchronize();

    expect(result, const ProgressSyncCompleted(synchronizedSessions: 2));
    expect(writer.calls, ['session-1', 'session-2']);
    expect(repository.acknowledged, ['session-1', 'session-2']);
    expect(await repository.pendingSessions(), isEmpty);
  });

  test('stops after first typed failure without retrying', () async {
    final repository = _StubProgressRepository([
      _session('session-1'),
      _session('session-2'),
    ]);
    final writer = _StubRemoteWriter({
      'session-1': const ProgressRemoteRejected(
        ProgressRemoteFailure.unavailable,
      ),
      'session-2': const ProgressRemoteAccepted(duplicate: false),
    });
    final service = ProgressSyncService(
      repository: repository,
      remoteWriter: writer,
    );

    final result = await service.synchronize();

    expect(
      result,
      const ProgressSyncIncomplete(
        synchronizedSessions: 0,
        failure: ProgressRemoteFailure.unavailable,
      ),
    );
    expect(writer.calls, ['session-1']);
    expect(repository.acknowledged, isEmpty);
    expect(await repository.pendingSessions(), hasLength(2));
  });

  test('ack failure remains typed and does not send later sessions', () async {
    final repository = _StubProgressRepository([
      _session('session-1'),
      _session('session-2'),
    ])..failAcknowledgement = true;
    final writer = _StubRemoteWriter({
      'session-1': const ProgressRemoteAccepted(duplicate: false),
      'session-2': const ProgressRemoteAccepted(duplicate: false),
    });
    final service = ProgressSyncService(
      repository: repository,
      remoteWriter: writer,
    );

    final result = await service.synchronize();

    expect(
      result,
      const ProgressSyncIncomplete(
        synchronizedSessions: 0,
        failure: ProgressRemoteFailure.localPersistence,
      ),
    );
    expect(writer.calls, ['session-1']);
    expect(await repository.pendingSessions(), hasLength(2));
  });

  test('local outbox read failure is typed without calling remote', () async {
    final repository = _StubProgressRepository(const [])
      ..failPendingRead = true;
    final writer = _StubRemoteWriter(const {});
    final service = ProgressSyncService(
      repository: repository,
      remoteWriter: writer,
    );

    final result = await service.synchronize();

    expect(
      result,
      const ProgressSyncIncomplete(
        synchronizedSessions: 0,
        failure: ProgressRemoteFailure.localPersistence,
      ),
    );
    expect(writer.calls, isEmpty);
  });

  test('unexpected remote exception is typed and not retried', () async {
    final repository = _StubProgressRepository([_session('session-1')]);
    final writer = _StubRemoteWriter(const {})..throwUnexpected = true;
    final service = ProgressSyncService(
      repository: repository,
      remoteWriter: writer,
    );

    final result = await service.synchronize();

    expect(
      result,
      const ProgressSyncIncomplete(
        synchronizedSessions: 0,
        failure: ProgressRemoteFailure.unknown,
      ),
    );
    expect(writer.calls, ['session-1']);
    expect(repository.acknowledged, isEmpty);
  });
}

final class _StubRemoteWriter implements ProgressRemoteWriter {
  _StubRemoteWriter(this.results);

  final Map<String, ProgressRemoteResult> results;
  final List<String> calls = [];
  bool throwUnexpected = false;

  @override
  Future<ProgressRemoteResult> recordProgressSession(
    ProgressSession session,
  ) async {
    calls.add(session.sessionId);
    if (throwUnexpected) throw StateError('unexpected remote failure');
    return results[session.sessionId]!;
  }
}

final class _StubProgressRepository implements ProgressRepository {
  _StubProgressRepository(List<ProgressSession> sessions)
    : _pending = [...sessions];

  final List<ProgressSession> _pending;
  final List<String> acknowledged = [];
  bool failAcknowledgement = false;
  bool failPendingRead = false;

  @override
  Future<void> acknowledgeSession(String sessionId) async {
    if (failAcknowledgement) {
      throw StateError('local write failed');
    }
    acknowledged.add(sessionId);
    _pending.removeWhere((session) => session.sessionId == sessionId);
  }

  @override
  Future<List<ProgressSession>> pendingSessions() async {
    if (failPendingRead) throw StateError('local read failed');
    return [..._pending];
  }

  @override
  Future<ProgressSnapshot> readSnapshot() async => const ProgressSnapshot(
    totalPoints: 0,
    totalCorrectAnswers: 0,
    totalWrongAnswers: 0,
    gamesPlayed: 0,
  );

  @override
  Future<void> recordSession(ProgressSession session) async {
    _pending.add(session);
  }
}
