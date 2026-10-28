final class ResearchConsentStatus {
  const ResearchConsentStatus({
    required this.version,
    required this.accepted,
    this.decidedAtUtc,
    this.withdrawnAtUtc,
  });

  final int version;
  final bool accepted;
  final DateTime? decidedAtUtc;
  final DateTime? withdrawnAtUtc;
}

abstract interface class ResearchConsentRepository {
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  });

  Future<void> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  });
}
