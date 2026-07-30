import '../domain/owner_upgrade.dart';

final class UpgradeGuestOwner {
  const UpgradeGuestOwner(this._repository);

  final OwnerUpgradeRepository _repository;

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
    return _repository.upgrade(
      activeOwnerId: canonicalOwnerId,
      firebaseUid: canonicalUid,
    );
  }
}
