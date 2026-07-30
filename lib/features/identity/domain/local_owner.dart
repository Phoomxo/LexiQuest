final class LocalOwner {
  const LocalOwner({
    required this.id,
    required this.createdAtUtc,
    this.firebaseUid,
    this.upgradedAtUtc,
  });

  final String id;
  final String? firebaseUid;
  final DateTime createdAtUtc;
  final DateTime? upgradedAtUtc;
}
