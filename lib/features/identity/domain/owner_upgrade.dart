import 'owner_lifecycle_manifest.dart';

enum OwnerUpgradeMode {
  anonymousBound,
  mergedExisting,
  alreadyBound,
  localGuestCreated,
}

final class OwnerUpgradeResult {
  const OwnerUpgradeResult({
    required this.targetOwnerId,
    required this.mode,
    required this.conflictCount,
  });

  final String targetOwnerId;
  final OwnerUpgradeMode mode;
  final int conflictCount;
}

/// Runs external transition effects inside an already acquired owner lease,
/// outside the transaction that commits the canonical owner change.
abstract interface class OwnerTransitionLifecycle {
  Future<T> run<T>({
    required String sourceOwnerId,
    required String operationToken,
    required Future<T> Function() operation,
    required String Function(T result) targetOwnerId,
  });
}

abstract interface class OwnerUpgradeRepository {
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  });

  Future<OwnerUpgradeResult> createLocalGuestAfterLogout();

  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  });
}

/// Optional in-memory admission for an explicit logout queued behind another
/// owner operation. It does not change persisted owner or session identities.
abstract interface class AdmittedOwnerLogoutRepository {
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout({
    String? expectedOwnerId,
    bool Function()? isCurrent,
  });
}

final Set<String> ownerUpgradeInventory = ownerLifecycleDirectOwnerTableNames;
