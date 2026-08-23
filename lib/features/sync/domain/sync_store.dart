import 'sync_entity.dart';
import 'sync_failure.dart';
import 'sync_result.dart';

const int maxSyncSendReservations = 5;

final class ClaimedSyncOperation {
  ClaimedSyncOperation({
    required String leaseToken,
    required int attemptCount,
    required String releaseState,
    required PushMutation mutation,
    String? localOperationId,
  }) : this._(
         leaseToken: leaseToken,
         attemptCount: attemptCount,
         releaseState: releaseState,
         mutation: mutation,
         localOperationId: localOperationId ?? mutation.operationId,
       );

  const ClaimedSyncOperation._({
    required this.leaseToken,
    required this.attemptCount,
    required this.releaseState,
    required this.mutation,
    required this.localOperationId,
  });

  final String leaseToken;
  final int attemptCount;
  final String releaseState;
  final PushMutation mutation;

  /// Durable local outbox identity. It may differ from the cloud operation ID
  /// when an owner-bound assignment is translated to a Firebase namespace.
  final String localOperationId;
}

abstract interface class SyncStore {
  Future<List<ClaimedSyncOperation>> claimPending({
    required String ownerId,
    required String firebaseUid,
    required int limit,
    required String leaseToken,
    required String ownerGateToken,
    required Duration leaseDuration,
    required DateTime nowUtc,
  });

  Future<ClaimedSyncOperation?> beginAttempt({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  });

  Future<bool> acknowledge({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required PushAcknowledged acknowledgement,
  });

  Future<bool> markRetry({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required DateTime nextAttemptAtUtc,
    required SyncFailure failure,
  });

  Future<bool> markTerminalFailure({
    required String operationId,
    required String leaseToken,
    required String ownerGateToken,
    required DateTime nowUtc,
    required SyncFailure failure,
  });

  Future<bool> releaseClaim({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required DateTime nowUtc,
  });

  Future<bool> resolvePushConflict({
    required ClaimedSyncOperation claim,
    required String ownerGateToken,
    required SyncEntity cloudEntity,
    required DateTime resolvedAtUtc,
  });

  Future<SyncCursor?> readCheckpoint(String ownerId, SyncCollection collection);

  Future<bool> applyPullPage({
    required String ownerId,
    required SyncCollection collection,
    required PullPage page,
    required String ownerGateToken,
    required DateTime nowUtc,
  });
}
