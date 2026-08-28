import '../domain/owner_upgrade.dart';

typedef OwnerUpgradeCoordinator =
    Future<OwnerUpgradeResult> Function(
      String sourceOwnerId,
      Future<OwnerUpgradeResult> Function() operation,
    );
typedef OwnerLogoutRollbackCoordinator =
    Future<void> Function(
      String previousOwnerId,
      String guestOwnerId,
      Future<void> Function() operation,
    );

final class UpgradeGuestOwner {
  const UpgradeGuestOwner(
    this._repository, {
    this.coordinate,
    this.coordinateRollback,
  });

  final OwnerUpgradeRepository _repository;
  final OwnerUpgradeCoordinator? coordinate;
  final OwnerLogoutRollbackCoordinator? coordinateRollback;

  Future<OwnerUpgradeResult> call({
    required String activeOwnerId,
    required String firebaseUid,
  }) {
    final canonicalOwnerId = activeOwnerId.trim();
    final canonicalUid = firebaseUid.trim();
    if (canonicalOwnerId.isEmpty) {
      throw ArgumentError.value(
        activeOwnerId,
        'activeOwnerId',
        'must not be blank',
      );
    }
    if (canonicalUid.isEmpty) {
      throw ArgumentError.value(
        firebaseUid,
        'firebaseUid',
        'must not be blank',
      );
    }
    Future<OwnerUpgradeResult> operation() => _repository.upgrade(
      activeOwnerId: canonicalOwnerId,
      firebaseUid: canonicalUid,
    );
    return coordinate?.call(canonicalOwnerId, operation) ?? operation();
  }

  Future<OwnerUpgradeResult> createLocalGuestAfterLogout({
    required String sourceOwnerId,
  }) {
    final canonicalOwnerId = sourceOwnerId.trim();
    if (canonicalOwnerId.isEmpty) {
      throw ArgumentError.value(
        sourceOwnerId,
        'sourceOwnerId',
        'must not be blank',
      );
    }
    Future<OwnerUpgradeResult> operation() =>
        _repository.createLocalGuestAfterLogout();
    return coordinate?.call(canonicalOwnerId, operation) ?? operation();
  }

  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    final previous = previousOwnerId.trim();
    final guest = guestOwnerId.trim();
    if (previous.isEmpty || guest.isEmpty) {
      throw ArgumentError('logout rollback owners must not be blank');
    }
    Future<void> operation() => _repository.rollbackLocalGuestLogout(
      previousOwnerId: previous,
      guestOwnerId: guest,
    );
    return coordinateRollback?.call(previous, guest, operation) ?? operation();
  }
}
