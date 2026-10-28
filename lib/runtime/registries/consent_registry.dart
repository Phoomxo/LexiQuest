/// Typed, versioned consent snapshots independent from feature and experiment
/// state.
library;

enum ConsentPurpose {
  aiProviderDataSharing,
  researchDataUpload,
  personalDataExport,
}

enum ConsentState { granted, denied, unknown }

final class ConsentSnapshot {
  const ConsentSnapshot({
    required this.purpose,
    required this.ownerId,
    required this.consentVersion,
    required this.state,
    required this.decisionUtc,
    required this.withdrawalUtc,
  });

  final ConsentPurpose purpose;
  final String ownerId;
  final int consentVersion;
  final ConsentState state;
  final DateTime? decisionUtc;
  final DateTime? withdrawalUtc;
}

abstract interface class ConsentRegistry {
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  });
}

final class NoOpConsentRegistry implements ConsentRegistry {
  const NoOpConsentRegistry();

  @override
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  }) async {
    return ConsentSnapshot(
      purpose: purpose,
      ownerId: ownerId,
      consentVersion: consentVersion,
      state: ConsentState.unknown,
      decisionUtc: null,
      withdrawalUtc: null,
    );
  }
}
