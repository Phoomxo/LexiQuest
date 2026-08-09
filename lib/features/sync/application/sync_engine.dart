import 'dart:async';

import '../../identity/domain/local_owner_repository.dart';
import '../domain/cloud_sync_policy.dart';
import '../domain/owner_operation_gate.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_result.dart';
import '../domain/sync_store.dart';
import 'sync_backoff.dart';
import 'sync_mutex.dart';

typedef SyncPolicyProvider = Future<CloudSyncPolicy> Function();
typedef SyncUtcNow = DateTime Function();
typedef SyncLeaseTokenGenerator = String Function();
typedef SyncJitterSource = double Function();
typedef SyncHeartbeatDelay = Future<void> Function(Duration delay);

enum SyncRunStatus {
  completed,
  partialFailure,
  skippedCloudDisabled,
  skippedUnauthenticated,
  alreadyRunning,
}

final class SyncRunResult {
  const SyncRunResult({
    required this.status,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.failures = 0,
    this.retryRecommended = false,
  });

  final SyncRunStatus status;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int failures;
  final bool retryRecommended;
}

final class SyncEngine {
  SyncEngine({
    required this.owners,
    required this.store,
    required this.gateway,
    required this.policyProvider,
    required this.ownerGate,
    required this.mutex,
    required this.backoff,
    required this.nowUtc,
    required this.generateLeaseToken,
    this.jitter = _zeroJitter,
    this.heartbeatDelay = _defaultHeartbeatDelay,
    this.requestTimeout = const Duration(seconds: 30),
  });

  static const int pushLimit = 50;
  static const int pullLimit = 100;
  static const Duration leaseDuration = Duration(minutes: 5);
  static const Duration runLeaseDuration = Duration(minutes: 10);
  static const Duration heartbeatInterval = Duration(minutes: 3);

  final LocalOwnerRepository owners;
  final SyncStore store;
  final SyncGateway gateway;
  final SyncPolicyProvider policyProvider;
  final OwnerOperationGate ownerGate;
  final SyncMutex mutex;
  final SyncBackoff backoff;
  final SyncUtcNow nowUtc;
  final SyncLeaseTokenGenerator generateLeaseToken;
  final SyncJitterSource jitter;
  final SyncHeartbeatDelay heartbeatDelay;
  final Duration requestTimeout;

  Future<SyncRunResult> run() async {
    final policy = await policyProvider();
    if (!policy.enabled) {
      return const SyncRunResult(status: SyncRunStatus.skippedCloudDisabled);
    }
    const mutexKey = 'ownerOperationGate';
    if (!mutex.tryAcquire(mutexKey)) {
      return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
    }
    final runLeaseToken = generateLeaseToken();
    final bool acquiredRunLease;
    try {
      acquiredRunLease = await ownerGate.tryAcquire(
        token: runLeaseToken,
        nowUtc: _currentUtc(),
        leaseDuration: runLeaseDuration,
      );
    } catch (_) {
      mutex.release(mutexKey);
      rethrow;
    }
    if (!acquiredRunLease) {
      mutex.release(mutexKey);
      return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
    }
    var gateOwned = true;
    final stopHeartbeat = Completer<void>();
    final heartbeat = _runHeartbeat(
      runLeaseToken,
      stopHeartbeat,
      () => gateOwned = false,
    );

    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;
    var failures = 0;
    var providerUnavailable = false;
    var retryRecommended = false;
    var permanentFailure = false;
    try {
      final owner = await owners.getOrCreateActiveOwner();
      final firebaseUid = owner.firebaseUid?.trim();
      if (firebaseUid == null || firebaseUid.isEmpty) {
        return const SyncRunResult(
          status: SyncRunStatus.skippedUnauthenticated,
        );
      }
      final claimed = await store.claimPending(
        ownerId: owner.id,
        firebaseUid: firebaseUid,
        limit: pushLimit,
        leaseToken: generateLeaseToken(),
        ownerGateToken: runLeaseToken,
        leaseDuration: leaseDuration,
        nowUtc: _currentUtc(),
      );
      var releaseFrom = claimed.length;
      for (var index = 0; index < claimed.length; index++) {
        final leasedClaim = claimed[index];
        if (!gateOwned) {
          failures++;
          releaseFrom = index;
          break;
        }
        final claim = await store.beginAttempt(
          claim: leasedClaim,
          ownerGateToken: runLeaseToken,
          nowUtc: _currentUtc(),
        );
        if (claim == null) {
          failures++;
          releaseFrom = index;
          break;
        }
        try {
          final result = await _withRequestTimeout(
            gateway.push(claim.mutation),
          );
          if (!gateOwned) {
            failures++;
            releaseFrom = index + 1;
            break;
          }
          switch (result) {
            case PushAcknowledged():
              final acknowledged = await store.acknowledge(
                operationId: claim.mutation.operationId,
                leaseToken: claim.leaseToken,
                ownerGateToken: runLeaseToken,
                nowUtc: _currentUtc(),
                acknowledgement: result,
              );
              if (acknowledged) {
                pushed++;
              } else {
                gateOwned = false;
                failures++;
                releaseFrom = index + 1;
              }
            case PushConflict():
              final resolved = await store.resolvePushConflict(
                claim: claim,
                ownerGateToken: runLeaseToken,
                cloudEntity: result.cloudEntity,
                resolvedAtUtc: _currentUtc(),
              );
              if (resolved) {
                conflicts++;
              } else {
                gateOwned = false;
                failures++;
                releaseFrom = index + 1;
              }
          }
          if (!gateOwned) break;
        } on SyncFailure catch (failure) {
          failures++;
          if (failure.retryable) {
            final marked = await store.markRetry(
              operationId: claim.mutation.operationId,
              leaseToken: claim.leaseToken,
              ownerGateToken: runLeaseToken,
              nowUtc: _currentUtc(),
              nextAttemptAtUtc: backoff.nextAttemptAt(
                nowUtc: _currentUtc(),
                attemptCount: claim.attemptCount,
                failure: failure,
                jitterUnit: jitter(),
              ),
              failure: failure,
            );
            if (marked) {
              retryRecommended =
                  retryRecommended ||
                  claim.attemptCount < maxSyncSendReservations;
            } else {
              gateOwned = false;
              releaseFrom = index + 1;
            }
          } else {
            final marked = await store.markTerminalFailure(
              operationId: claim.mutation.operationId,
              leaseToken: claim.leaseToken,
              ownerGateToken: runLeaseToken,
              nowUtc: _currentUtc(),
              failure: failure,
            );
            permanentFailure = marked;
            if (!marked) gateOwned = false;
            releaseFrom = index + 1;
          }
          providerUnavailable =
              providerUnavailable ||
              failure is OfflineSyncFailure ||
              failure is ProviderUnavailableSyncFailure;
          if (permanentFailure || !gateOwned) break;
        }
      }

      for (final unstarted in claimed.skip(releaseFrom)) {
        await store.releaseClaim(
          claim: unstarted,
          ownerGateToken: runLeaseToken,
          nowUtc: _currentUtc(),
        );
      }

      if (!providerUnavailable && !permanentFailure && gateOwned) {
        for (final collection in SyncCollection.values) {
          if (!gateOwned) break;
          try {
            final checkpoint = await store.readCheckpoint(owner.id, collection);
            final page = await _withRequestTimeout(
              gateway.pull(
                firebaseUid: firebaseUid,
                collection: collection,
                after: checkpoint,
                limit: pullLimit,
              ),
            );
            if (!gateOwned) {
              failures++;
              break;
            }
            final applied = await store.applyPullPage(
              ownerId: owner.id,
              collection: collection,
              page: page,
              ownerGateToken: runLeaseToken,
              nowUtc: _currentUtc(),
            );
            if (!applied) {
              gateOwned = false;
              failures++;
              break;
            }
            pulled += page.changes.length;
            retryRecommended = retryRecommended || page.hasMore;
          } on SyncFailure catch (failure) {
            failures++;
            retryRecommended = retryRecommended || failure.retryable;
          }
        }
      }

      return SyncRunResult(
        status: failures == 0
            ? SyncRunStatus.completed
            : SyncRunStatus.partialFailure,
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
        failures: failures,
        retryRecommended: retryRecommended,
      );
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      await heartbeat;
      await ownerGate.release(token: runLeaseToken);
      mutex.release(mutexKey);
    }
  }

  Future<void> _runHeartbeat(
    String token,
    Completer<void> stop,
    void Function() onLost,
  ) async {
    while (true) {
      try {
        await Future.any<void>(<Future<void>>[
          heartbeatDelay(heartbeatInterval),
          stop.future,
        ]);
      } catch (_) {
        onLost();
        return;
      }
      if (stop.isCompleted) return;
      try {
        final renewed = await ownerGate.renew(
          token: token,
          nowUtc: _currentUtc(),
          leaseDuration: runLeaseDuration,
        );
        if (!renewed) {
          onLost();
          return;
        }
      } catch (_) {
        onLost();
        return;
      }
    }
  }

  DateTime _currentUtc() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }

  Future<T> _withRequestTimeout<T>(Future<T> operation) {
    return operation.timeout(
      requestTimeout,
      onTimeout: () => throw const ProviderUnavailableSyncFailure(),
    );
  }
}

double _zeroJitter() => 0;

Future<void> _defaultHeartbeatDelay(Duration delay) =>
    Future<void>.delayed(delay);
