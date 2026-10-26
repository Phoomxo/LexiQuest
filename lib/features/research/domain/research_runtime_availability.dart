/// Runtime visibility gate for optional research enrollment and export UI.
///
/// Every authority prerequisite must be explicitly present before research UI
/// is exposed. This is separate from operation authorization: collection and
/// export still require their signed permit checks at the execution boundary.
final class ResearchRuntimeAvailability {
  const ResearchRuntimeAvailability({
    this.ethicsApproved = false,
    this.protocolApproved = false,
    this.instrumentApproved = false,
    this.trustedIssuerConfigured = false,
    this.trustedTimeConfigured = false,
    this.rolloutApproved = false,
  });

  static const disabled = ResearchRuntimeAvailability();

  /// Complete synthetic fixture for tests only; it is never a production
  /// default and does not grant operation authority by itself.
  static const syntheticComplete = ResearchRuntimeAvailability(
    ethicsApproved: true,
    protocolApproved: true,
    instrumentApproved: true,
    trustedIssuerConfigured: true,
    trustedTimeConfigured: true,
    rolloutApproved: true,
  );

  final bool ethicsApproved;
  final bool protocolApproved;
  final bool instrumentApproved;
  final bool trustedIssuerConfigured;
  final bool trustedTimeConfigured;
  final bool rolloutApproved;

  bool get isEnabled =>
      ethicsApproved &&
      protocolApproved &&
      instrumentApproved &&
      trustedIssuerConfigured &&
      trustedTimeConfigured &&
      rolloutApproved;
}
