import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/progress/firebase_progress_remote_writer.dart';
import 'package:vocab_learning_app/progress/progress_remote_writer.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';

final _completedAt = DateTime.utc(2026, 7, 29, 10);

ProgressSession _session() {
  return ProgressSession(
    sessionId: 'session-1',
    correctAnswers: 2,
    wrongAnswers: 1,
    eventIds: const ['event-1', 'event-2', 'event-3'],
    completedAtUtc: _completedAt,
  );
}

void main() {
  test('sends only the locked callable payload', () async {
    final client = _StubCallableClient({
      'status': 'recorded',
      'totalPoints': 2,
      'gamesPlayed': 1,
    });
    final writer = FirebaseProgressRemoteWriter(client: client);

    final result = await writer.recordProgressSession(_session());

    expect(result, isA<ProgressRemoteAccepted>());
    expect((result as ProgressRemoteAccepted).duplicate, isFalse);
    expect(client.functionName, 'recordProgressSession');
    expect(client.data, {
      'sessionId': 'session-1',
      'eventIds': ['event-1', 'event-2', 'event-3'],
      'correctAnswers': 2,
      'completedAt': '2026-07-29T10:00:00.000Z',
    });
  });

  test('maps duplicate acknowledgement to accepted', () async {
    final writer = FirebaseProgressRemoteWriter(
      client: _StubCallableClient({
        'status': 'duplicate',
        'totalPoints': 2,
        'gamesPlayed': 1,
      }),
    );

    final result = await writer.recordProgressSession(_session());

    expect((result as ProgressRemoteAccepted).duplicate, isTrue);
  });

  test('invalid success shape fails closed', () async {
    final writer = FirebaseProgressRemoteWriter(
      client: _StubCallableClient({'status': 'unexpected'}),
    );

    final result = await writer.recordProgressSession(_session());

    expect(
      (result as ProgressRemoteRejected).failure,
      ProgressRemoteFailure.unknown,
    );
  });

  test(
    'typed callable failures map without leaking provider details',
    () async {
      final cases = <String, ProgressRemoteFailure>{
        'unauthenticated': ProgressRemoteFailure.unauthenticated,
        'invalid-argument': ProgressRemoteFailure.invalidRequest,
        'already-exists': ProgressRemoteFailure.invalidRequest,
        'unavailable': ProgressRemoteFailure.unavailable,
        'deadline-exceeded': ProgressRemoteFailure.unavailable,
        'internal': ProgressRemoteFailure.unknown,
      };

      for (final entry in cases.entries) {
        final writer = FirebaseProgressRemoteWriter(
          client: _StubCallableClient(
            null,
            failure: ProgressCallableFailure(entry.key),
          ),
        );

        final result = await writer.recordProgressSession(_session());

        expect(
          (result as ProgressRemoteRejected).failure,
          entry.value,
          reason: entry.key,
        );
      }
    },
  );
}

final class _StubCallableClient implements ProgressCallableClient {
  _StubCallableClient(this.response, {this.failure});

  final Object? response;
  final Object? failure;
  String? functionName;
  Map<String, Object?>? data;

  @override
  Future<Object?> call(String functionName, Map<String, Object?> data) async {
    this.functionName = functionName;
    this.data = data;
    if (failure case final failure?) {
      throw failure;
    }
    return response;
  }
}
