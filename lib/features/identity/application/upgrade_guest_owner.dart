import '../domain/owner_upgrade.dart';

typedef OwnerUpgradeCoordinator =
    Future<OwnerUpgradeResult> Function(
      String sourceOwnerId,
      Future<OwnerUpgradeResult> Function() operation,
    );

final class UpgradeGuestOwner {
  const UpgradeGuestOwner(this._repository, {this.coordinate});

  final OwnerUpgradeRepository _repository;
  final OwnerUpgradeCoordinator? coordinate;

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

  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    return _repository.createLocalGuestAfterLogout();
  }

  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    return _repository.rollbackLocalGuestLogout(
      previousOwnerId: previousOwnerId,
      guestOwnerId: guestOwnerId,
    );
  }
}
