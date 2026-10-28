import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

void main() {
  test('validates identifiers before delegating one upgrade', () async {
    final repository = _FakeOwnerUpgradeRepository();
    final upgrade = UpgradeGuestOwner(repository);

    expect(
      () => upgrade(activeOwnerId: ' ', firebaseUid: 'firebase-user'),
      throwsArgumentError,
    );
    expect(
      () => upgrade(activeOwnerId: 'guest-owner', firebaseUid: ' '),
      throwsArgumentError,
    );
    final result = await upgrade(
      activeOwnerId: ' guest-owner ',
      firebaseUid: ' firebase-user ',
    );

    expect(result.targetOwnerId, 'guest-owner');
    expect(repository.calls, 1);
    expect(repository.lastOwnerId, 'guest-owner');
    expect(repository.lastFirebaseUid, 'firebase-user');
  });
}

final class _FakeOwnerUpgradeRepository implements OwnerUpgradeRepository {
  int calls = 0;
  String? lastOwnerId;
  String? lastFirebaseUid;

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    throw UnimplementedError();
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async {
    calls += 1;
    lastOwnerId = activeOwnerId;
    lastFirebaseUid = firebaseUid;
    return OwnerUpgradeResult(
      targetOwnerId: activeOwnerId,
      mode: OwnerUpgradeMode.anonymousBound,
      conflictCount: 0,
    );
  }
}
