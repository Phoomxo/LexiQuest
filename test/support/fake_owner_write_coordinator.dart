import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';

/// Stateful test double; database purge/identity proofs belong to Drift tests.
final class FakeOwnerWriteCoordinator implements OwnerWriteCoordinator {
  DeletionIntentSnapshot? state;
  void Function(String operation)? onCall;
  final Map<String, Object> failures = {};
  var _nonce = 0;

  void _call(String operation) {
    onCall?.call(operation);
    if (failures[operation] case final error?) throw error;
  }

  @override
  Future<T> writeForActiveOwner<T>({
    required String expectedOwnerId,
    required Future<T> Function() write,
  }) async {
    await requireOwnerUnfenced(expectedOwnerId);
    return write();
  }

  @override
  Future<void> requireOwnerUnfenced(String ownerId) async {
    _call('requireOwnerUnfenced');
    if (state != null &&
        (state!.casToken == null ||
            state!.casToken!.matchesOwner(ownerId) ||
            state!.localReceipt?.newGuestOwnerId == ownerId)) {
      _unavailable();
    }
  }

  @override
  Future<DeletionIntentSnapshot?> inspect() async {
    _call('inspect');
    return state;
  }

  @override
  Future<DeletionIntentToken> beginDeletion({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
  }) async {
    _call('beginDeletion');
    if (state case final existing?) {
      if (existing.casToken?.matchesOperation(
            ownerId: ownerId,
            firebaseUid: firebaseUid,
            idempotencyKey: idempotencyKey,
          ) !=
          true) {
        _unavailable();
      }
      return existing.casToken!;
    }
    final token = DeletionIntentToken.bind(
      ownerId: ownerId,
      firebaseUid: firebaseUid,
      idempotencyKey: idempotencyKey,
      nonce: 'synthetic-attempt-${_nonce++}',
    );
    state = DeletionIntentSnapshot(
      phase: DeletionIntentPhase.preparing,
      casToken: token,
    );
    return token;
  }

  @override
  Future<DeletionIntentSnapshot> adoptRecovery(
    AccountDeletionJournalEntry entry,
  ) async {
    _call('adoptRecovery');
    if (state != null &&
        state!.casToken?.matchesOperation(
              ownerId: entry.ownerId,
              firebaseUid: entry.firebaseUid,
              idempotencyKey: entry.idempotencyKey,
            ) !=
            true) {
      _unavailable();
    }
    final token =
        state?.casToken ??
        DeletionIntentToken.bind(
          ownerId: entry.ownerId,
          firebaseUid: entry.firebaseUid,
          idempotencyKey: entry.idempotencyKey,
          nonce: 'synthetic-adopt-${_nonce++}',
        );
    final cloud = entry.cloudReceipt?.durableMarker() ?? state?.cloudReceipt;
    if (state?.cloudReceipt case final saved?) {
      if (cloud == null || !_sameCloud(saved, cloud)) _unavailable();
    }
    final local = state?.localReceipt ?? entry.localReceipt;
    state = DeletionIntentSnapshot(
      phase: local != null
          ? DeletionIntentPhase.localCompleted
          : cloud != null
          ? DeletionIntentPhase.cloudConfirmed
          : DeletionIntentPhase.pendingCloud,
      casToken: token,
      cloudReceipt: cloud,
      localReceipt: local,
    );
    return state!;
  }

  @override
  Future<void> markPending(DeletionIntentToken token) async {
    _call('markPending');
    final current = _require(token);
    if (current.phase != DeletionIntentPhase.preparing &&
        current.phase != DeletionIntentPhase.pendingCloud) {
      _unavailable();
    }
    state = DeletionIntentSnapshot(
      phase: DeletionIntentPhase.pendingCloud,
      casToken: token,
    );
  }

  @override
  Future<void> markCloud(
    DeletionIntentToken token,
    CloudDeletionReceipt cloud,
  ) async {
    _call('markCloud');
    final current = _require(token);
    if (!token.matchesOperation(
      ownerId: cloud.ownerId,
      firebaseUid: cloud.firebaseUid,
      idempotencyKey: cloud.idempotencyKey,
    )) {
      _unavailable();
    }
    if (current.cloudReceipt case final saved?) {
      if (!_sameCloud(saved, cloud.durableMarker())) _unavailable();
      return;
    }
    if (current.phase != DeletionIntentPhase.pendingCloud) _unavailable();
    state = DeletionIntentSnapshot(
      phase: DeletionIntentPhase.cloudConfirmed,
      casToken: token,
      cloudReceipt: cloud.durableMarker(),
    );
  }

  @override
  Future<void> markLocal(
    DeletionIntentToken token,
    CloudDeletionReceipt cloud,
    LocalDeletionReceipt local,
  ) async {
    _call('markLocal');
    final current = _require(token);
    if (current.cloudReceipt == null ||
        !_sameCloud(current.cloudReceipt!, cloud) ||
        (current.phase != DeletionIntentPhase.cloudConfirmed &&
            current.phase != DeletionIntentPhase.localCompleted)) {
      _unavailable();
    }
    state = DeletionIntentSnapshot(
      phase: DeletionIntentPhase.localCompleted,
      casToken: token,
      cloudReceipt: cloud,
      localReceipt: local,
    );
  }

  @override
  Future<bool> abortPreparing(DeletionIntentToken token) async {
    _call('abortPreparing');
    if (state?.phase != DeletionIntentPhase.preparing ||
        state?.casToken?.sameAttempt(token) != true) {
      return false;
    }
    state = null;
    return true;
  }

  @override
  Future<void> clearCompleted(DeletionIntentToken token) async {
    _call('clearCompleted');
    if (_require(token).phase != DeletionIntentPhase.localCompleted) {
      _unavailable();
    }
    state = null;
  }

  @override
  Future<void> preserveRecoveryUncertainty() async {
    _call('preserveRecoveryUncertainty');
    if (state == null) {
      state = const DeletionIntentSnapshot.uncertain();
    } else if (state!.phase == DeletionIntentPhase.preparing) {
      state = DeletionIntentSnapshot(
        phase: DeletionIntentPhase.pendingCloud,
        casToken: state!.casToken,
      );
    }
  }

  DeletionIntentSnapshot _require(DeletionIntentToken token) {
    if (state?.casToken?.sameAttempt(token) != true) _unavailable();
    return state!;
  }

  bool _sameCloud(CloudDeletionReceipt a, CloudDeletionReceipt b) =>
      a.receiptId == b.receiptId &&
      a.ownerId == b.ownerId &&
      a.firebaseUid == b.firebaseUid &&
      durableAccountDeletionBinding(a.idempotencyKey) ==
          durableAccountDeletionBinding(b.idempotencyKey) &&
      a.completedAtUtc == b.completedAtUtc;

  Never _unavailable() => throw const AccountDeletionException(
    AccountDeletionFailureCode.unavailable,
  );
}
