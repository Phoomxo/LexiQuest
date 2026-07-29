import 'package:cloud_functions/cloud_functions.dart';

import 'progress_remote_writer.dart';
import 'progress_repository.dart';

abstract interface class ProgressCallableClient {
  Future<Object?> call(String functionName, Map<String, Object?> data);
}

final class ProgressCallableFailure implements Exception {
  const ProgressCallableFailure(this.code);

  final String code;

  @override
  String toString() => 'ProgressCallableFailure';
}

final class FirebaseProgressCallableClient implements ProgressCallableClient {
  FirebaseProgressCallableClient({this._functions});

  final FirebaseFunctions? _functions;

  @override
  Future<Object?> call(String functionName, Map<String, Object?> data) async {
    try {
      final functions =
          _functions ??
          FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final response = await functions.httpsCallable(functionName).call(data);
      return response.data;
    } on FirebaseFunctionsException catch (error) {
      throw ProgressCallableFailure(error.code);
    } on Object {
      throw const ProgressCallableFailure('unknown');
    }
  }
}

final class FirebaseProgressRemoteWriter implements ProgressRemoteWriter {
  FirebaseProgressRemoteWriter({ProgressCallableClient? client})
    : _client = client ?? FirebaseProgressCallableClient();

  final ProgressCallableClient _client;

  @override
  Future<ProgressRemoteResult> recordProgressSession(
    ProgressSession session,
  ) async {
    final completedAt = session.completedAtUtc;
    if (completedAt == null || session.eventIds.isEmpty) {
      return const ProgressRemoteRejected(ProgressRemoteFailure.invalidRequest);
    }
    try {
      final response = await _client.call('recordProgressSession', {
        'sessionId': session.sessionId,
        'eventIds': session.eventIds,
        'correctAnswers': session.correctAnswers,
        'completedAt': completedAt.toUtc().toIso8601String(),
      });
      if (response is! Map) {
        return const ProgressRemoteRejected(ProgressRemoteFailure.unknown);
      }
      final status = response['status'];
      final totalPoints = response['totalPoints'];
      final gamesPlayed = response['gamesPlayed'];
      if ((status != 'recorded' && status != 'duplicate') ||
          totalPoints is! int ||
          totalPoints < 0 ||
          gamesPlayed is! int ||
          gamesPlayed < 0) {
        return const ProgressRemoteRejected(ProgressRemoteFailure.unknown);
      }
      return ProgressRemoteAccepted(duplicate: status == 'duplicate');
    } on ProgressCallableFailure catch (failure) {
      return ProgressRemoteRejected(_failureFor(failure.code));
    } on Object {
      return const ProgressRemoteRejected(ProgressRemoteFailure.unknown);
    }
  }
}

ProgressRemoteFailure _failureFor(String code) {
  return switch (code) {
    'unauthenticated' => ProgressRemoteFailure.unauthenticated,
    'invalid-argument' ||
    'already-exists' => ProgressRemoteFailure.invalidRequest,
    'unavailable' || 'deadline-exceeded' => ProgressRemoteFailure.unavailable,
    _ => ProgressRemoteFailure.unknown,
  };
}
