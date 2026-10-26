final class ResearchTrustedTime {
  ResearchTrustedTime({
    required DateTime anchorUtc,
    required DateTime validUntilUtc,
    required this.age,
    required this.maximumAge,
  }) : anchorUtc = anchorUtc.toUtc(),
       validUntilUtc = validUntilUtc.toUtc();

  final DateTime anchorUtc;
  final DateTime validUntilUtc;
  // Age must come from a monotonic or equally trusted authority.
  final Duration age;
  final Duration maximumAge;
  DateTime get effectiveNowUtc => anchorUtc.add(age);

  bool get isFresh =>
      !age.isNegative &&
      maximumAge > Duration.zero &&
      age <= maximumAge &&
      effectiveNowUtc.isBefore(validUntilUtc);
}

abstract interface class ResearchTrustedTimeSource {
  /// Returns null unless freshness can be proven from a monotonic or trusted
  /// anchor. Wall-clock-only cache ages are not sufficient.
  Future<ResearchTrustedTime?> read();
}
