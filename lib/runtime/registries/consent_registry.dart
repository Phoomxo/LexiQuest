/// V2 Consent Registry — per-purpose, per-owner consent state.
///
/// Consent is orthogonal to feature availability ([FeatureRegistry]) and
/// experiment cohort ([ExperimentRegistry]).  A feature may be enabled while
/// consent for a specific data-sharing purpose is denied, and the two
/// registries must never be conflated.
library;

/// Purposes for which explicit learner consent may be required.
enum ConsentPurpose {
  /// Sending learning summaries to an AI provider (e.g. Gemini).
  aiProviderDataSharing,

  /// Uploading anonymised interaction data for research.
  researchDataUpload,

  /// Exporting personal data to an external format.
  personalDataExport,
}

/// Whether the learner has granted or denied consent for a purpose.
enum ConsentState {
  /// The learner has explicitly granted consent.
  granted,

  /// The learner has explicitly denied consent.
  denied,

  /// Consent has not yet been collected for this purpose.
  unknown,
}

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

/// Read-only contract for querying learner consent.
abstract interface class ConsentRegistry {
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  });
}

/// No-op [ConsentRegistry] that reports [ConsentState.unknown] for every query.
///
/// Use in Phase -1 before real consent infrastructure is wired up, or in
/// tests that do not exercise consent-gated behaviour.
final class NoOpConsentRegistry implements ConsentRegistry {
  const NoOpConsentRegistry();

  @override
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  }) async => ConsentSnapshot(
    purpose: purpose,
    ownerId: ownerId,
    consentVersion: consentVersion,
    state: ConsentState.unknown,
    decisionUtc: null,
    withdrawalUtc: null,
  );
}
