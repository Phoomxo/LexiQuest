import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'account_deletion_contracts.dart';

enum DeletionIntentPhase {
  preparing,
  pendingCloud,
  cloudConfirmed,
  localCompleted,
  recoveryUncertain,
}

/// A local concurrency handle. It does not establish deletion authority.
final class DeletionIntentToken {
  const DeletionIntentToken.fromBindings({
    required this.ownerBinding,
    required this.firebaseUidBinding,
    required this.operationBinding,
    required this.nonceBinding,
  });

  factory DeletionIntentToken.bind({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required String nonce,
  }) => DeletionIntentToken.fromBindings(
    ownerBinding: _hash(ownerId),
    firebaseUidBinding: _hash(firebaseUid),
    operationBinding: durableAccountDeletionBinding(idempotencyKey),
    nonceBinding: _hash(nonce),
  );

  final String ownerBinding;
  final String firebaseUidBinding;
  final String operationBinding;
  final String nonceBinding;

  bool matchesOperation({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
  }) =>
      ownerBinding == _hash(ownerId) &&
      firebaseUidBinding == _hash(firebaseUid) &&
      operationBinding == durableAccountDeletionBinding(idempotencyKey);

  bool matchesOwner(String ownerId) => ownerBinding == _hash(ownerId);

  bool sameAttempt(DeletionIntentToken other) =>
      ownerBinding == other.ownerBinding &&
      firebaseUidBinding == other.firebaseUidBinding &&
      operationBinding == other.operationBinding &&
      nonceBinding == other.nonceBinding;
}

final class DeletionIntentSnapshot {
  const DeletionIntentSnapshot({
    required this.phase,
    required this.casToken,
    this.cloudReceipt,
    this.localReceipt,
  });

  const DeletionIntentSnapshot.uncertain()
    : phase = DeletionIntentPhase.recoveryUncertain,
      casToken = null,
      cloudReceipt = null,
      localReceipt = null;

  final DeletionIntentPhase phase;
  final DeletionIntentToken? casToken;
  final CloudDeletionReceipt? cloudReceipt;
  final LocalDeletionReceipt? localReceipt;

  String? get ownerBinding => casToken?.ownerBinding;
  String? get firebaseUidBinding => casToken?.firebaseUidBinding;
  String? get operationBinding => casToken?.operationBinding;
  String? get nonceBinding => casToken?.nonceBinding;
}

abstract interface class OwnerWriteCoordinator {
  /// Runs database work in the same transaction as the owner and intent checks.
  Future<T> writeForActiveOwner<T>({
    required String expectedOwnerId,
    required Future<T> Function() write,
  });

  Future<void> requireOwnerUnfenced(String ownerId);
  Future<DeletionIntentSnapshot?> inspect();
  Future<DeletionIntentSnapshot> adoptRecovery(
    AccountDeletionJournalEntry entry,
  );
  Future<DeletionIntentToken> beginDeletion({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
  });
  Future<void> markPending(DeletionIntentToken token);
  Future<void> markCloud(DeletionIntentToken token, CloudDeletionReceipt cloud);
  Future<void> markLocal(
    DeletionIntentToken token,
    CloudDeletionReceipt cloud,
    LocalDeletionReceipt local,
  );
  Future<bool> abortPreparing(DeletionIntentToken token);
  Future<void> clearCompleted(DeletionIntentToken token);
  Future<void> preserveRecoveryUncertainty();
}

String _hash(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';
