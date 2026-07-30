import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_sync_store.dart';
import '../domain/cloud_sync_policy.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_result.dart';
import 'sync_backoff.dart';
import 'sync_mutex.dart';

typedef SyncPolicyProvider = Future<CloudSyncPolicy> Function();
typedef SyncUtcNow = DateTime Function();
typedef SyncLeaseTokenGenerator = String Function();
typedef SyncJitterSource = double Function();

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
  });

  final SyncRunStatus status;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int failures;
}

final class SyncEngine {
  SyncEngine({
    required this.owners,
    required this.store,
    required this.gateway,
    required this.policyProvider,
    required this.mutex,
    required this.backoff,
    required this.nowUtc,
    required this.generateLeaseToken,
    this.jitter = _zeroJitter,
  });

  static const int pushLimit = 50;
  static const int pullLimit = 100;
  static const Duration leaseDuration = Duration(minutes: 5);

  final LocalOwnerRepository owners;
  final DriftSyncStore store;
  final SyncGateway gateway;
  final SyncPolicyProvider policyProvider;
  final SyncMutex mutex;
  final SyncBackoff backoff;
  final SyncUtcNow nowUtc;
  final SyncLeaseTokenGenerator generateLeaseToken;
  final SyncJitterSource jitter;

  Future<SyncRunResult> run() async {
    final policy = await policyProvider();
    if (!policy.enabled) {
      return const SyncRunResult(status: SyncRunStatus.skippedCloudDisabled);
    }
    final owner = await owners.getOrCreateActiveOwner();
    final firebaseUid = owner.firebaseUid?.trim();
    if (firebaseUid == null || firebaseUid.isEmpty) {
      return const SyncRunResult(status: SyncRunStatus.skippedUnauthenticated);
    }
    if (!mutex.tryAcquire(owner.id)) {
      return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
    }

    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;
    var failures = 0;
    var providerUnavailable = false;
    try {
      final claimed = await store.claimPending(
        ownerId: owner.id,
        firebaseUid: firebaseUid,
        limit: pushLimit,
        leaseToken: generateLeaseToken(),
        leaseDuration: leaseDuration,
        nowUtc: _currentUtc(),
      );
      for (final claim in claimed) {
        try {
          final result = await gateway.push(claim.mutation);
          switch (result) {
            case PushAcknowledged():
              await store.acknowledge(
                operationId: claim.mutation.operationId,
                leaseToken: claim.leaseToken,
                acknowledgement: result,
              );
              pushed++;
            case PushConflict():
              await store.resolvePushConflict(
                claim: claim,
                cloudEntity: result.cloudEntity,
                resolvedAtUtc: _currentUtc(),
              );
              conflicts++;
          }
        } on SyncFailure catch (failure) {
          failures++;
          if (failure.retryable) {
            await store.markRetry(
              operationId: claim.mutation.operationId,
              leaseToken: claim.leaseToken,
              nextAttemptAtUtc: backoff.nextAttemptAt(
                nowUtc: _currentUtc(),
                attemptCount: claim.attemptCount,
                failure: failure,
                jitterUnit: jitter(),
              ),
              failure: failure,
            );
          } else {
            await store.markTerminalFailure(
              operationId: claim.mutation.operationId,
              leaseToken: claim.leaseToken,
              failure: failure,
            );
          }
          providerUnavailable =
              providerUnavailable ||
              failure is OfflineSyncFailure ||
              failure is ProviderUnavailableSyncFailure;
        }
      }

      if (!providerUnavailable) {
        for (final collection in SyncCollection.values) {
          try {
            final checkpoint = await store.readCheckpoint(owner.id, collection);
            final page = await gateway.pull(
              firebaseUid: firebaseUid,
              collection: collection,
              after: checkpoint,
              limit: pullLimit,
            );
            await store.applyPullPage(
              ownerId: owner.id,
              collection: collection,
              page: page,
            );
            pulled += page.changes.length;
          } on SyncFailure {
            failures++;
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
      );
    } finally {
      mutex.release(owner.id);
    }
  }

  DateTime _currentUtc() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}

double _zeroJitter() => 0;
