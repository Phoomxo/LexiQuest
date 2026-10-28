import 'dart:async';
import 'dart:math' as math;

import '../domain/media_practice_contracts.dart';

final class SpeechPracticeUseCases {
  SpeechPracticeUseCases(this.gateway);

  final SpeechRecognitionGateway gateway;
  Future<void> _operationTail = Future<void>.value();
  int _nextSessionId = 0;
  SpeechPracticeSession? _activeSession;
  SpeechPracticeSession? _legacySession;

  bool get isListening => gateway.isListening;

  SpeechPracticeSession acquireSession() {
    final previous = _activeSession;
    final session = SpeechPracticeSession._(this, ++_nextSessionId);
    _activeSession = session;
    if (previous?._engaged == true || gateway.isListening) {
      // The takeover barrier is serialized ahead of the new session's start.
      // It therefore cleans the superseded recognizer without ever cancelling
      // a newer listening operation.
      _enqueue<void>(gateway.cancel).ignore();
    }
    return session;
  }

  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    final session = _legacySession;
    final currentSession = session != null && session.isCurrent
        ? session
        : (_legacySession = acquireSession());
    await currentSession.start(
      locale: locale,
      onEvent: onEvent,
      onFailure: onFailure,
      onStatus: onStatus,
    );
  }

  Future<bool> _startSession({
    required SpeechPracticeSession session,
    required int attempt,
    required String locale,
    required SpeechEventCallback onEvent,
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) {
    return _enqueue<bool>(() async {
      if (!session._accepts(attempt)) return false;
      final permission = await gateway.requestPermission();
      if (!session._accepts(attempt)) return false;
      switch (permission) {
        case MediaPermissionState.granted:
          break;
        case MediaPermissionState.permanentlyDenied:
          throw const SpeechPracticeException(
            SpeechFailureCode.permissionPermanentlyDenied,
          );
        case MediaPermissionState.denied:
        case MediaPermissionState.restricted:
          throw const SpeechPracticeException(
            SpeechFailureCode.permissionDenied,
          );
        case MediaPermissionState.unavailable:
          throw const SpeechPracticeException(SpeechFailureCode.unavailable);
      }
      await gateway.initialize(
        onFailure: (failure) {
          if (!session._accepts(attempt)) return;
          session._engaged = false;
          onFailure(failure);
        },
        onStatus: (status) {
          if (session._accepts(attempt)) onStatus(status);
        },
      );
      if (!session._accepts(attempt)) return false;
      await gateway.start(
        locale: locale,
        onEvent: (event) {
          if (!session._accepts(attempt)) return;
          if (event.isFinal) session._engaged = false;
          onEvent(event);
        },
      );
      final stillCurrent = session._accepts(attempt);
      if (stillCurrent && !gateway.isListening) session._engaged = false;
      return stillCurrent;
    });
  }

  Future<void> stop() => _legacySession?.stop() ?? Future<void>.value();

  Future<void> cancel() => _legacySession?.cancel() ?? Future<void>.value();

  Future<void> dispose() async {
    final active = _activeSession;
    if (active != null) {
      final shouldCancel = active._engaged || gateway.isListening;
      active._released = true;
      active._attempt += 1;
      active._engaged = false;
      _activeSession = null;
      if (shouldCancel) {
        await _enqueue<void>(gateway.cancel);
      } else {
        // A superseded session may still own an uninterruptible permission,
        // initialization, or start operation ahead of this idle active
        // session. Disposal is the runtime-owner barrier, so it must not
        // return until that serialized work and its takeover cleanup drain.
        await _operationTail;
      }
    } else if (gateway.isListening) {
      await _enqueue<void>(gateway.cancel);
    } else {
      await _operationTail;
    }
  }

  bool _isCurrent(SpeechPracticeSession session) =>
      identical(_activeSession, session);

  Future<void> _stopSession(SpeechPracticeSession session) {
    if (!_isCurrent(session)) return Future<void>.value();
    final shouldStop = session._engaged || gateway.isListening;
    session._attempt += 1;
    session._engaged = false;
    if (!shouldStop) return Future<void>.value();
    return _enqueue<void>(gateway.stop);
  }

  Future<void> _cancelSession(SpeechPracticeSession session) {
    if (!_isCurrent(session)) return Future<void>.value();
    final shouldCancel = session._engaged || gateway.isListening;
    session._attempt += 1;
    session._engaged = false;
    if (!shouldCancel) return Future<void>.value();
    return _enqueue<void>(gateway.cancel);
  }

  Future<void> _releaseSession(SpeechPracticeSession session) {
    if (!_isCurrent(session)) return Future<void>.value();
    final shouldCancel = session._engaged || gateway.isListening;
    session._attempt += 1;
    session._engaged = false;
    _activeSession = null;
    if (!shouldCancel) return Future<void>.value();
    return _enqueue<void>(gateway.cancel);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completion = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completion.complete(await operation());
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }

  TranscriptPronunciationAssessment assess({
    required String target,
    required SpeechRecognitionEvent event,
  }) {
    final canonicalTarget = _canonical(target);
    final canonicalTranscript = _canonical(event.transcript);
    if (canonicalTarget.isEmpty || canonicalTranscript.isEmpty) {
      return TranscriptPronunciationAssessment(
        target: target,
        transcript: event.transcript,
        similarityPercent: 0,
        isExactMatch: false,
        method: 'transcript-edit-distance-v1',
        engine: event.engine,
        locale: event.locale,
        occurredAtUtc: event.recognizedAtUtc,
      );
    }
    final distance = _levenshtein(canonicalTarget, canonicalTranscript);
    final denominator = math.max(
      canonicalTarget.runes.length,
      canonicalTranscript.runes.length,
    );
    final score = ((1 - (distance / denominator)) * 100).clamp(0, 100).round();
    return TranscriptPronunciationAssessment(
      target: target,
      transcript: event.transcript,
      similarityPercent: score,
      isExactMatch: canonicalTarget == canonicalTranscript,
      method: 'transcript-edit-distance-v1',
      engine: event.engine,
      locale: event.locale,
      occurredAtUtc: event.recognizedAtUtc,
    );
  }

  static String _canonical(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static int _levenshtein(String left, String right) {
    final a = left.runes.toList(growable: false);
    final b = right.runes.toList(growable: false);
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var row = 0; row < a.length; row += 1) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = row + 1;
      for (var column = 0; column < b.length; column += 1) {
        final substitution = previous[column] + (a[row] == b[column] ? 0 : 1);
        current[column + 1] = math.min(
          math.min(current[column] + 1, previous[column + 1] + 1),
          substitution,
        );
      }
      previous = current;
    }
    return previous.last;
  }
}

/// An opaque ownership handle for one speech-recognition consumer.
///
/// Operations from a superseded or released session are no-ops. Callback
/// delivery is additionally fenced by a per-session attempt epoch.
final class SpeechPracticeSession {
  SpeechPracticeSession._(this._owner, this._sessionId);

  final SpeechPracticeUseCases _owner;
  final int _sessionId;
  int _attempt = 0;
  bool _engaged = false;
  bool _released = false;

  bool get isCurrent => !_released && _owner._isCurrent(this);

  bool get isListening => isCurrent && _owner.gateway.isListening;

  Future<bool> start({
    required String locale,
    required SpeechEventCallback onEvent,
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    if (_released || !isCurrent) return false;
    final attempt = ++_attempt;
    _engaged = true;
    try {
      return await _owner._startSession(
        session: this,
        attempt: attempt,
        locale: locale,
        onEvent: onEvent,
        onFailure: onFailure,
        onStatus: onStatus,
      );
    } on Object {
      if (_accepts(attempt)) _engaged = false;
      rethrow;
    }
  }

  Future<void> stop() => _owner._stopSession(this);

  Future<void> cancel() => _owner._cancelSession(this);

  Future<void> release() {
    if (_released) return Future<void>.value();
    _released = true;
    return _owner._releaseSession(this);
  }

  bool _accepts(int attempt) =>
      !_released && _attempt == attempt && _owner._isCurrent(this);

  @override
  String toString() => 'SpeechPracticeSession($_sessionId)';
}
