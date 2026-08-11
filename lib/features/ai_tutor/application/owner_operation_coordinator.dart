import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../sync/domain/owner_operation_gate.dart';
import '../domain/ai_tutor_contracts.dart';

typedef ActiveAiOwnerId = Future<String> Function();
typedef OwnerGateTokenGenerator = String Function();
typedef OwnerGateDelay =
    Future<void> Function(Duration duration, AiCancellation cancellation);
typedef RecoverPendingAiUsage =
    Future<int> Function(
      DateTime cutoffUtc, {
      required DateTime recoveredAtUtc,
    });

/// Pins owner-scoped AI work behind the process-wide Task 5 operation gate.
final class OwnerOperationCoordinator {
  OwnerOperationCoordinator({
    required this.gate,
    required this.activeOwnerId,
    DateTime Function()? nowUtc,
    OwnerGateTokenGenerator? generateToken,
    OwnerGateDelay? delay,
    this.recoverPending,
    this.leaseDuration = const Duration(minutes: 1),
    this.heartbeatInterval = const Duration(seconds: 20),
    this.retryInterval = const Duration(milliseconds: 50),
    this.waitTimeout = const Duration(seconds: 5),
    this.stalePendingAge = const Duration(minutes: 2),
  }) : nowUtc = nowUtc ?? _defaultNowUtc,
       generateToken = generateToken ?? const Uuid().v4,
       delay = delay ?? _defaultDelay {
    if (leaseDuration <= Duration.zero ||
        heartbeatInterval <= Duration.zero ||
        retryInterval <= Duration.zero ||
        waitTimeout <= Duration.zero ||
        stalePendingAge <= Duration.zero ||
        heartbeatInterval >= leaseDuration) {
      throw ArgumentError('Invalid owner-operation timing configuration.');
    }
  }

  final OwnerOperationGate gate;
  final ActiveAiOwnerId activeOwnerId;
  final DateTime Function() nowUtc;
  final OwnerGateTokenGenerator generateToken;
  final OwnerGateDelay delay;
  final RecoverPendingAiUsage? recoverPending;
  final Duration leaseDuration;
  final Duration heartbeatInterval;
  final Duration retryInterval;
  final Duration waitTimeout;
  final Duration stalePendingAge;

  static final Object _leaseZoneKey = Object();

  static String? get currentLeaseToken =>
      (Zone.current[_leaseZoneKey] as _OwnerLease?)?.token;

  Future<T> run<T>(
    AiCancellation cancellation,
    Future<T> Function(String ownerId) body,
  ) async {
    _throwIfCancelled(cancellation);
    final token = generateToken().trim();
    if (token.isEmpty) {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    final deadline = _utcNow().add(waitTimeout);
    var acquired = false;
    while (!acquired) {
      _throwIfCancelled(cancellation);
      try {
        acquired = await gate.tryAcquire(
          token: token,
          nowUtc: _utcNow(),
          leaseDuration: leaseDuration,
        );
      } on Object {
        throw const AiTutorException(AiFailureCode.localPersistence);
      }
      if (acquired) break;
      if (!_utcNow().isBefore(deadline)) {
        throw const AiTutorException(AiFailureCode.timeout);
      }
      await delay(retryInterval, cancellation);
    }

    final lease = _OwnerLease(token: token, cancellation: cancellation);
    final stopHeartbeat = Completer<void>();
    final heartbeat = _heartbeat(lease, stopHeartbeat);
    try {
      return await runZoned(() async {
        _throwIfCancelled(cancellation);
        final recoveredAtUtc = _utcNow();
        try {
          await recoverPending?.call(
            recoveredAtUtc.subtract(stalePendingAge),
            recoveredAtUtc: recoveredAtUtc,
          );
        } on Object {
          throw const AiTutorException(AiFailureCode.localPersistence);
        }
        String ownerId;
        try {
          ownerId = (await activeOwnerId()).trim();
        } on Object {
          throw const AiTutorException(AiFailureCode.localPersistence);
        }
        if (ownerId.isEmpty) {
          throw const AiTutorException(AiFailureCode.localPersistence);
        }
        _throwIfCancelled(cancellation);
        final operation = Future<T>.sync(() => body(ownerId))
            .then<_OwnerOperationOutcome<T>>(
              _OwnerOperationValue<T>.new,
              onError: (Object error, StackTrace stackTrace) =>
                  _OwnerOperationError<T>(error, stackTrace),
            );
        final first = await Future.any<_OwnerOperationSignal<T>>(
          <Future<_OwnerOperationSignal<T>>>[
            operation,
            lease.lost.future.then<_OwnerOperationSignal<T>>(
              (_) => const _OwnerOperationInterrupted(),
            ),
            cancellation.whenCancelled.then<_OwnerOperationSignal<T>>(
              (_) => const _OwnerOperationInterrupted(),
            ),
          ],
        );
        final interrupted = first is _OwnerOperationInterrupted;
        final outcome = interrupted
            ? await operation
            : first as _OwnerOperationOutcome<T>;
        if ((interrupted || cancellation.isCancelled || lease.lostLease) &&
            !lease.resultCommitted) {
          throw const AiTutorException(AiFailureCode.cancelled);
        }
        if (outcome case _OwnerOperationError<T>(
          :final error,
          :final stackTrace,
        )) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        final result = (outcome as _OwnerOperationValue<T>).value;
        if (!lease.resultCommitted && !await canFinalizeCurrentOperation()) {
          cancellation.cancel();
          throw const AiTutorException(AiFailureCode.cancelled);
        }
        return result;
      }, zoneValues: <Object, Object>{_leaseZoneKey: lease});
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      lease.stopHeartbeat();
      try {
        await heartbeat.then<void>((_) {}, onError: (_) {});
      } finally {
        try {
          await gate.release(token: token);
        } on Object {
          // A failed release expires by lease; never replace the operation's
          // typed result or provider-neutral failure during cleanup.
        }
      }
    }
  }

  /// Fences a journal terminal write against heartbeat/lease loss.
  Future<bool> canFinalizeCurrentOperation() async {
    final lease = Zone.current[_leaseZoneKey] as _OwnerLease?;
    if (lease == null || lease.lostLease) return false;
    try {
      final owned = await gate.isOwned(token: lease.token, nowUtc: _utcNow());
      if (!owned) lease.markLost();
      return owned;
    } on Object {
      lease.markLost();
      return false;
    }
  }

  Future<void> requireCurrentLease() async {
    if (!await canFinalizeCurrentOperation()) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
  }

  String get currentOperationVersion {
    final lease = Zone.current[_leaseZoneKey] as _OwnerLease?;
    if (lease == null || lease.lostLease) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    return lease.token;
  }

  /// Declares that the operation has crossed an irreversible provider/result
  /// boundary. The lease still fences all writes; this marker only prevents a
  /// later cleanup-time lease observation from discarding an already-paid
  /// result.
  void markCurrentOperationResultCommitted() {
    final lease = Zone.current[_leaseZoneKey] as _OwnerLease?;
    if (lease == null) {
      throw StateError('No owner operation is active.');
    }
    lease.resultCommitted = true;
  }

  Future<void> _heartbeat(_OwnerLease lease, Completer<void> stop) async {
    while (!stop.isCompleted && !lease.lostLease) {
      try {
        await Future.any<void>(<Future<void>>[
          delay(heartbeatInterval, lease.heartbeatCancellation),
          stop.future,
        ]);
      } on AiTutorException catch (error) {
        if (error.code == AiFailureCode.cancelled &&
            lease.heartbeatCancellation.isCancelled) {
          return;
        }
        rethrow;
      }
      if (stop.isCompleted || lease.lostLease) return;
      try {
        final renewed = await gate.renew(
          token: lease.token,
          nowUtc: _utcNow(),
          leaseDuration: leaseDuration,
        );
        if (!renewed) {
          lease.markLost();
          return;
        }
      } on Object {
        lease.markLost();
        return;
      }
    }
  }

  DateTime _utcNow() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    return value;
  }
}

final class _OwnerLease {
  _OwnerLease({required this.token, required this.cancellation});

  final String token;
  final AiCancellation cancellation;
  final AiCancellation heartbeatCancellation = AiCancellation();
  final Completer<void> lost = Completer<void>();
  bool lostLease = false;
  bool resultCommitted = false;

  void markLost() {
    if (lostLease) return;
    lostLease = true;
    cancellation.cancel();
    heartbeatCancellation.cancel();
    lost.complete();
  }

  void stopHeartbeat() => heartbeatCancellation.cancel();
}

sealed class _OwnerOperationSignal<T> {
  const _OwnerOperationSignal();
}

sealed class _OwnerOperationOutcome<T> extends _OwnerOperationSignal<T> {
  const _OwnerOperationOutcome();
}

final class _OwnerOperationValue<T> extends _OwnerOperationOutcome<T> {
  const _OwnerOperationValue(this.value);

  final T value;
}

final class _OwnerOperationError<T> extends _OwnerOperationOutcome<T> {
  const _OwnerOperationError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _OwnerOperationInterrupted<T> extends _OwnerOperationSignal<T> {
  const _OwnerOperationInterrupted();
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();

Future<void> _defaultDelay(Duration duration, AiCancellation cancellation) {
  if (cancellation.isCancelled) {
    return Future<void>.error(const AiTutorException(AiFailureCode.cancelled));
  }
  final completer = Completer<void>();
  final timer = Timer(duration, completer.complete);
  cancellation.whenCancelled.then((_) {
    timer.cancel();
    if (!completer.isCompleted) {
      completer.completeError(const AiTutorException(AiFailureCode.cancelled));
    }
  });
  return completer.future;
}

void _throwIfCancelled(AiCancellation cancellation) {
  if (cancellation.isCancelled) {
    throw const AiTutorException(AiFailureCode.cancelled);
  }
}
