final class ResearchConsentStatus {
  const ResearchConsentStatus({
    required this.ownerId,
    required this.version,
    required this.accepted,
    this.decidedAtUtc,
    this.withdrawnAtUtc,
  });

  final String ownerId;
  final int version;
  final bool accepted;
  final DateTime? decidedAtUtc;
  final DateTime? withdrawnAtUtc;

  bool sameFacts(ResearchConsentStatus other) =>
      ownerId == other.ownerId &&
      version == other.version &&
      accepted == other.accepted &&
      decidedAtUtc == other.decidedAtUtc &&
      withdrawnAtUtc == other.withdrawnAtUtc;
}

abstract interface class AuthoritativeResearchConsentRepository
    implements ResearchConsentRepository {
  Future<bool> mirrorAcknowledgement({
    required ResearchConsentStatus expected,
    required ResearchConsentStatus acknowledged,
    required String authSubjectId,
    required bool Function() stillCurrent,
  });

  Future<bool> withdrawLocally({
    required ResearchConsentStatus expected,
    required DateTime withdrawnAtUtc,
    required String authSubjectId,
    required bool Function() stillCurrent,
  });
}

abstract interface class ResearchConsentRemoteDecisions {
  ResearchConsentRepository get repository;
  Future<bool> accept(ResearchConsentStatus expected);
  Future<bool> withdraw(
    ResearchConsentStatus expected,
    DateTime withdrawnAtUtc,
  );
}

abstract interface class ResearchConsentRepository {
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  });

  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  });
}
