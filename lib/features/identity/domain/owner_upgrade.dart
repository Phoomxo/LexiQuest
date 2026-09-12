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

final Set<String> ownerUpgradeInventory = ownerLifecycleDirectOwnerTableNames;
