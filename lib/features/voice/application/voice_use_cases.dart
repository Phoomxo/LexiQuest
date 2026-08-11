import 'dart:async';

import '../../../voice/voice_models.dart';
import '../../../voice/voice_provider.dart';

VoiceProvider _retainVoiceProvider(VoiceProvider value) => value;

Future<void> Function() _retainVoiceDisposer(Future<void> Function() value) =>
    value;

/// Runtime-owned, provider-neutral speech synthesis boundary.
///
/// The composition root supplies both the provider and its exact disposer.
/// Route consumers receive only opaque [VoiceSession] ownership handles.
final class VoiceUseCases {
  VoiceUseCases({
    required VoiceProvider provider,
    required Future<void> Function() disposeProvider,
    this.operationTimeout = const Duration(seconds: 30),
    this.cleanupTimeout = const Duration(seconds: 2),
  }) : _provider = _retainVoiceProvider(provider),
       _disposeProvider = _retainVoiceDisposer(disposeProvider) {
    if (operationTimeout <= Duration.zero || cleanupTimeout <= Duration.zero) {
      throw ArgumentError.value(
        operationTimeout <= Duration.zero ? operationTimeout : cleanupTimeout,
        operationTimeout <= Duration.zero
            ? 'operationTimeout'
            : 'cleanupTimeout',
        'must be positive',
      );
    }
  }

  final VoiceProvider _provider;
  final Future<void> Function() _disposeProvider;
  final Duration operationTimeout;
  final Duration cleanupTimeout;

  final Set<Future<void>> _providerOperations = <Future<void>>{};
  Future<void> _controlTail = Future<void>.value();
  VoiceSession? _activeSession;
  int _nextSessionId = 0;
  int _ownershipEpoch = 0;
  int _providerGeneration = 0;
  bool _providerMayNeedStop = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  VoiceSession acquireSession() {
    if (_disposed) throw _unavailableFailure;

    _activeSession?._invalidate();
    final ownershipEpoch = ++_ownershipEpoch;
    final session = VoiceSession._(this, ++_nextSessionId, ownershipEpoch);
    _activeSession = session;

    // Every new owner observes the already-queued control tail. When playback
    // may still exist, the latest owner also installs its own conditional stop.
    final takeover = _providerMayNeedStop
        ? _enqueueConditionalStop(
            session: session,
            ownershipEpoch: ownershipEpoch,
            providerGeneration: _providerGeneration,
          )
        : _controlTail;
    session._captureTakeover(takeover);
    return session;
  }

  bool _isCurrent(VoiceSession session) =>
      !_disposed && identical(_activeSession, session);

  Future<VoicePlaybackResult> _speak(
    VoiceSession session,
    _VoiceAttempt attempt,
    VoiceRequest request,
  ) {
    attempt.timeoutTimer = Timer(
      operationTimeout,
      () => _timeOut(session, attempt),
    );
    unawaited(_launchSpeak(session, attempt, request));
    return attempt.completer.future;
  }

  Future<void> _launchSpeak(
    VoiceSession session,
    _VoiceAttempt attempt,
    VoiceRequest request,
  ) async {
    try {
      await attempt.barrier;
    } on Object catch (_, stackTrace) {
      if (session._accepts(attempt)) {
        _settleError(session, attempt, _cleanupFailure, stackTrace);
      } else {
        _settleCancelled(session, attempt, stackTrace);
      }
      return;
    }

    if (attempt.cleanupFailed) {
      if (session._accepts(attempt)) {
        _settleError(session, attempt, _cleanupFailure, StackTrace.current);
      }
      return;
    }

    if (!session._accepts(attempt)) {
      _settleCancelled(session, attempt, StackTrace.current);
      return;
    }

    final providerGeneration = ++_providerGeneration;
    attempt.providerGeneration = providerGeneration;
    _providerMayNeedStop = true;

    final providerFuture = Future<VoicePlaybackResult>.sync(
      () => _provider.speak(request),
    );
    late final Future<void> tracked;
    tracked = providerFuture
        .then<void>(
          (result) =>
              _providerSucceeded(session, attempt, providerGeneration, result),
          onError: (Object error, StackTrace stackTrace) {
            _providerFailed(
              session,
              attempt,
              providerGeneration,
              error,
              stackTrace,
            );
          },
        )
        .whenComplete(() => _providerOperations.remove(tracked));
    _providerOperations.add(tracked);
  }

  void _providerSucceeded(
    VoiceSession session,
    _VoiceAttempt attempt,
    int providerGeneration,
    VoicePlaybackResult result,
  ) {
    final accepted = session._accepts(attempt);
    if (!accepted || providerGeneration != _providerGeneration) return;

    // A successful speak Future means playback has started, not that playback
    // is over. Keep provider ownership until stop/release/takeover.
    _providerMayNeedStop = true;
    _settleValue(session, attempt, result);
  }

  void _providerFailed(
    VoiceSession session,
    _VoiceAttempt attempt,
    int providerGeneration,
    Object error,
    StackTrace stackTrace,
  ) {
    final accepted = session._accepts(attempt);
    if (!accepted || providerGeneration != _providerGeneration) return;

    _providerMayNeedStop = false;
    _settleError(
      session,
      attempt,
      error is VoiceFailure ? error : _unknownFailure,
      stackTrace,
    );
  }

  void _timeOut(VoiceSession session, _VoiceAttempt attempt) {
    if (!session._accepts(attempt)) return;

    // Complete the public operation at the absolute deadline. Cleanup is
    // deliberately separate so a blocked stop cannot let a late success win.
    _settleError(session, attempt, _timeoutFailure, StackTrace.current);
    final providerGeneration = attempt.providerGeneration;
    if (providerGeneration == null) return;
    unawaited(
      _enqueueConditionalStop(
        session: session,
        ownershipEpoch: session._ownershipEpoch,
        providerGeneration: providerGeneration,
        activityEpoch: attempt.activityEpoch,
      ).then<void>((_) {}, onError: (_) {}),
    );
  }

  Future<void> _stopSession(VoiceSession session) {
    if (!session.isCurrent) return Future<void>.value();

    session._cancelAttempt();
    final activityEpoch = ++session._activityEpoch;
    if (!_providerMayNeedStop) return Future<void>.value();
    return _normalizeControlFailure(
      _enqueueConditionalStop(
        session: session,
        ownershipEpoch: session._ownershipEpoch,
        providerGeneration: _providerGeneration,
        activityEpoch: activityEpoch,
      ),
    );
  }

  Future<void> _releaseSession(VoiceSession session) {
    if (!session.isCurrent) {
      session._invalidate();
      return Future<void>.value();
    }

    session._invalidate();
    _activeSession = null;
    final releasedOwnershipEpoch = ++_ownershipEpoch;
    if (!_providerMayNeedStop) return Future<void>.value();
    final providerGeneration = _providerGeneration;
    return _normalizeControlFailure(
      _enqueueControl(() async {
        if (_disposed ||
            _ownershipEpoch != releasedOwnershipEpoch ||
            _activeSession != null ||
            !_providerMayNeedStop ||
            _providerGeneration != providerGeneration) {
          return;
        }
        await _provider.stop();
        if (!_disposed &&
            _ownershipEpoch == releasedOwnershipEpoch &&
            _activeSession == null &&
            _providerGeneration == providerGeneration) {
          _providerMayNeedStop = false;
        }
      }),
    );
  }

  Future<void> _enqueueConditionalStop({
    required VoiceSession session,
    required int ownershipEpoch,
    required int providerGeneration,
    int? activityEpoch,
  }) => _enqueueControl(() async {
    if (_disposed ||
        _ownershipEpoch != ownershipEpoch ||
        !identical(_activeSession, session) ||
        !_providerMayNeedStop ||
        _providerGeneration != providerGeneration ||
        (activityEpoch != null && session._activityEpoch != activityEpoch)) {
      return;
    }
    await _provider.stop();
    if (!_disposed &&
        _ownershipEpoch == ownershipEpoch &&
        identical(_activeSession, session) &&
        _providerGeneration == providerGeneration &&
        (activityEpoch == null || session._activityEpoch == activityEpoch)) {
      _providerMayNeedStop = false;
    }
  });

  Future<void> _enqueueControl(Future<void> Function() operation) {
    final result = _controlTail.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _controlTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _normalizeControlFailure(Future<void> operation) async {
    try {
      // Bound only the caller-facing view. The serialized control tail keeps
      // waiting so uncertain playback remains fail-closed and no replacement
      // can speak over a provider whose stop acknowledgement never arrived.
      await operation.timeout(cleanupTimeout);
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(_cleanupFailure, stackTrace);
    }
  }

  Future<void> _barrierForAttempt(
    VoiceSession session,
    int activityEpoch,
    bool isFirstAttempt,
  ) {
    if (isFirstAttempt || !_providerMayNeedStop) {
      return session._takeoverBarrier;
    }
    final raw = _enqueueConditionalStop(
      session: session,
      ownershipEpoch: session._ownershipEpoch,
      providerGeneration: _providerGeneration,
      activityEpoch: activityEpoch,
    );
    return raw;
  }

  void _settleValue(
    VoiceSession session,
    _VoiceAttempt attempt,
    VoicePlaybackResult result,
  ) {
    if (!session._detach(attempt)) return;
    attempt.timeoutTimer?.cancel();
    attempt.completer.complete(result);
  }

  void _settleError(
    VoiceSession session,
    _VoiceAttempt attempt,
    VoiceFailure failure,
    StackTrace stackTrace,
  ) {
    if (!session._detach(attempt)) return;
    attempt.timeoutTimer?.cancel();
    attempt.completer.completeError(failure, stackTrace);
  }

  void _settleCancelled(
    VoiceSession session,
    _VoiceAttempt attempt,
    StackTrace stackTrace,
  ) {
    if (attempt.completer.isCompleted) return;
    session._detach(attempt);
    attempt.timeoutTimer?.cancel();
    attempt.completer.completeError(_cancelledFailure, stackTrace);
  }

  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    _disposed = true;
    _ownershipEpoch++;
    _activeSession?._invalidate();
    _activeSession = null;

    // No later control work can be accepted after [_disposed] is set. Drain
    // the frozen stop tail before releasing the managed provider stack.
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> awaitCleanup(Future<void> operation) async {
      try {
        await operation.timeout(cleanupTimeout);
      } on Object catch (_, stackTrace) {
        firstError ??= _cleanupFailure;
        firstStackTrace ??= stackTrace;
      }
    }

    final frozenControlTail = _controlTail;
    await awaitCleanup(frozenControlTail);

    // The composition-owned disposer is always invoked even when a queued
    // provider stop is stuck. Its own resource stack receives the same bound.
    await awaitCleanup(Future<void>.sync(_disposeProvider));

    final operations = _providerOperations.toList(growable: false);
    if (operations.isNotEmpty) {
      await awaitCleanup(
        Future.wait(
          operations.map(
            (operation) => operation.then<void>((_) {}, onError: (_) {}),
          ),
        ),
      );
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}

/// Opaque route ownership handle for voice playback.
final class VoiceSession {
  VoiceSession._(this._owner, this._sessionId, this._ownershipEpoch);

  final VoiceUseCases _owner;
  final int _sessionId;
  final int _ownershipEpoch;
  late final Future<void> _takeoverBarrier;
  int _nextAttemptId = 0;
  int _activityEpoch = 0;
  bool _released = false;
  _VoiceAttempt? _activeAttempt;

  bool get isCurrent => !_released && _owner._isCurrent(this);

  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    if (!isCurrent) return Future<VoicePlaybackResult>.error(_cancelledFailure);

    _cancelAttempt();
    final activityEpoch = ++_activityEpoch;
    final attempt = _VoiceAttempt(
      id: ++_nextAttemptId,
      activityEpoch: activityEpoch,
    );
    final rawBarrier = _owner._barrierForAttempt(
      this,
      activityEpoch,
      attempt.id == 1,
    );
    attempt.barrier = rawBarrier.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        attempt.cleanupFailed = true;
      },
    );
    _activeAttempt = attempt;
    return _owner._speak(this, attempt, request);
  }

  Future<void> stop() => _owner._stopSession(this);

  Future<void> release() {
    if (_released) return Future<void>.value();
    return _owner._releaseSession(this);
  }

  bool _accepts(_VoiceAttempt attempt) =>
      isCurrent &&
      identical(_activeAttempt, attempt) &&
      !attempt.completer.isCompleted;

  bool _detach(_VoiceAttempt attempt) {
    if (!identical(_activeAttempt, attempt) || attempt.completer.isCompleted) {
      return false;
    }
    _activeAttempt = null;
    return true;
  }

  void _cancelAttempt() {
    final attempt = _activeAttempt;
    if (attempt == null) return;
    _activeAttempt = null;
    attempt.timeoutTimer?.cancel();
    if (!attempt.completer.isCompleted) {
      attempt.completer.completeError(_cancelledFailure, StackTrace.current);
    }
  }

  void _invalidate() {
    if (_released) return;
    _released = true;
    _activityEpoch++;
    _cancelAttempt();
  }

  void _captureTakeover(Future<void> rawBarrier) {
    _takeoverBarrier = rawBarrier;
    // Eager acquisition cleanup is allowed to finish before a route speaks.
    // Attach a consuming observer now so a failed stop is never an unhandled
    // zone error; an eventual attempt still observes the original failure.
    unawaited(rawBarrier.then<void>((_) {}, onError: (_, _) {}));
  }

  @override
  String toString() => 'VoiceSession($_sessionId)';
}

final class _VoiceAttempt {
  _VoiceAttempt({required this.id, required this.activityEpoch});

  final int id;
  final int activityEpoch;
  final Completer<VoicePlaybackResult> completer =
      Completer<VoicePlaybackResult>();
  Timer? timeoutTimer;
  int? providerGeneration;
  late Future<void> barrier;
  bool cleanupFailed = false;
}

const _cancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'Voice playback was cancelled.',
);

const _timeoutFailure = VoiceFailure(
  category: VoiceFailureCategory.timeout,
  message: 'Voice playback timed out.',
);

const _unavailableFailure = VoiceFailure(
  category: VoiceFailureCategory.providerDisabled,
  message: 'Voice playback is unavailable.',
);

const _cleanupFailure = VoiceFailure(
  category: VoiceFailureCategory.cleanupIncomplete,
  message: 'The previous voice playback could not be stopped.',
);

const _unknownFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Voice playback is unavailable.',
);
