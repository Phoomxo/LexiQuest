import 'local_owner.dart';

abstract interface class LocalOwnerRepository {
  Future<LocalOwner> getOrCreateActiveOwner();

  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid);
}
