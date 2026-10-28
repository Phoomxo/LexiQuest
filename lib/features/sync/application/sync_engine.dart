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
    this.retryRecommended = false,
    this.hasMoreWork = false,
  });

  final SyncRunStatus status;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int failures;
  final bool retryRecommended;
  final bool hasMoreWork;
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
  static const int maxBatchesPerRun = 10;
  static const Duration leaseDuration = Duration(minutes: 5);
  static const Duration runLeaseDuration = Duration(minutes: 10);

  final LocalOwnerRepository owners;
  final DriftSyncStore store;
  final SyncGateway gateway;
  final SyncPolicyProvider policyProvider;
  final SyncMutex mutex;
  final SyncBackoff backoff;
  final SyncUtcNow nowUtc;
  final SyncLeaseTokenGenerator generateLeaseToken;
  final SyncJitterSource jitter;
  final Set<String> _permissionRecoveryAttemptedOwners = <String>{};

  Future<SyncRunResult> run() async {
    final owner = await owners.getOrCreateActiveOwner();
    final firebaseUid = owner.firebaseUid?.trim();
    if (firebaseUid == null || firebaseUid.isEmpty) {
      return const SyncRunResult(status: SyncRunStatus.skippedUnauthenticated);
    }
    final policy = await policyProvider();
    if (!policy.enabled) {
      return const SyncRunResult(status: SyncRunStatus.skippedCloudDisabled);
    }
    if (!mutex.tryAcquire(owner.id)) {
      return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
    }
    final runLeaseToken = generateLeaseToken();
    final bool acquiredRunLease;
    try {
      acquiredRunLease = await store.tryAcquireRunLease(
        ownerId: owner.id,
        leaseToken: runLeaseToken,
        nowUtc: _currentUtc(),
        leaseDuration: runLeaseDuration,
      );
    } catch (_) {
      mutex.release(owner.id);
      rethrow;
    }
    if (!acquiredRunLease) {
      mutex.release(owner.id);
      return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
    }

    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;
    var failures = 0;
    var providerUnavailable = false;
    var retryRecommended = false;
    var hasMoreWork = false;

    Future<void> renewRunLease() async {
      if (!await store.renewRunLease(
        ownerId: owner.id,
        leaseToken: runLeaseToken,
        nowUtc: _currentUtc(),
        leaseDuration: runLeaseDuration,
      )) {
        throw const _SyncRunLeaseLost();
      }
    }

    try {
      if (_permissionRecoveryAttemptedOwners.add(owner.id)) {
        await store.requeuePermissionDeniedFailures(
          ownerId: owner.id,
          nowUtc: _currentUtc(),
        );
      }
      for (var batch = 0; batch < maxBatchesPerRun; batch++) {
        await renewRunLease();
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
            await renewRunLease();
            final result = await gateway.push(claim.mutation);
            await renewRunLease();
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
            await renewRunLease();
            failures++;
            retryRecommended = retryRecommended || failure.retryable;
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

        if (providerUnavailable ||
            !await store.hasReadyOperations(
              ownerId: owner.id,
              nowUtc: _currentUtc(),
            )) {
          break;
        }
        if (batch == maxBatchesPerRun - 1) hasMoreWork = true;
      }

      if (!providerUnavailable) {
        for (final collection in SyncCollection.values) {
          try {
            for (var batch = 0; batch < maxBatchesPerRun; batch++) {
              final checkpoint = await store.readCheckpoint(
                owner.id,
                collection,
              );
              await renewRunLease();
              final page = await gateway.pull(
                firebaseUid: firebaseUid,
                collection: collection,
                after: checkpoint,
                limit: pullLimit,
              );
              await renewRunLease();
              final nextCursor = page.nextCursor;
              if (checkpoint != null && nextCursor != null) {
                final timeOrder = nextCursor.serverUpdatedAtUtc.compareTo(
                  checkpoint.serverUpdatedAtUtc,
                );
                if (timeOrder < 0 ||
                    (timeOrder == 0 &&
                        nextCursor.documentId.compareTo(checkpoint.documentId) <
                            0)) {
                  throw const InvalidSyncPayloadFailure();
                }
              }
              if (page.hasMore &&
                  (page.changes.isEmpty ||
                      nextCursor == null ||
                      nextCursor == checkpoint)) {
                throw const InvalidSyncPayloadFailure();
              }
              await store.applyPullPage(
                ownerId: owner.id,
                collection: collection,
                page: page,
              );
              pulled += page.changes.length;
              if (!page.hasMore) break;
              if (batch == maxBatchesPerRun - 1) hasMoreWork = true;
            }
          } on SyncFailure catch (failure) {
            await renewRunLease();
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
        retryRecommended: retryRecommended || hasMoreWork,
        hasMoreWork: hasMoreWork,
      );
    } on _SyncRunLeaseLost {
      return SyncRunResult(
        status: SyncRunStatus.partialFailure,
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
        failures: failures + 1,
        retryRecommended: true,
        hasMoreWork: true,
      );
    } finally {
      await store.releaseRunLease(ownerId: owner.id, leaseToken: runLeaseToken);
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

final class _SyncRunLeaseLost implements Exception {
  const _SyncRunLeaseLost();
}

double _zeroJitter() => 0;
