enum TodayExperiencePresentation { standard, adventure }

enum AdventureEntryDestination { learn, standardToday, adventure }

enum AdventureAvailability {
  available,
  hidden,
  disabled,
  emergencyOff,
  missingDependency,
  invalidCatalog,
  contentUnavailable,
  assignmentConflict,
}

enum AdventureFallbackReason {
  none,
  learnerChoseStandard,
  featureUnavailable,
  dependencyUnavailable,
  catalogUnavailable,
  contentUnavailable,
  assignmentUnavailable,
  emergencyOff,
}

extension TodayExperiencePresentationWireName on TodayExperiencePresentation {
  String get wireName => name;
}

extension AdventureEntryDestinationWireName on AdventureEntryDestination {
  String get wireName => name;
}

extension AdventureAvailabilityWireName on AdventureAvailability {
  String get wireName => name;
}

extension AdventureFallbackReasonWireName on AdventureFallbackReason {
  String get wireName => name;
}

abstract final class TodayExperiencePresentationCodec {
  static TodayExperiencePresentation? tryDecode(Object? value) {
    if (value is! String) return null;
    for (final candidate in TodayExperiencePresentation.values) {
      if (candidate.wireName == value) return candidate;
    }
    return null;
  }

  static TodayExperiencePresentation decode(Object? value) {
    final decoded = tryDecode(value);
    if (decoded == null) {
      throw FormatException('Unknown Today experience presentation: $value');
    }
    return decoded;
  }
}

final class ActivePresentationPermit {
  const ActivePresentationPermit({
    required this.permitId,
    required this.ownerId,
    required this.assignedPresentation,
    required this.protocolId,
    required this.protocolVersion,
    required this.assignmentId,
    required this.expiresAtUtc,
  });

  final String permitId;
  final String ownerId;
  final TodayExperiencePresentation assignedPresentation;
  final String protocolId;
  final String protocolVersion;
  final String assignmentId;
  final DateTime expiresAtUtc;
}

final class AdventureEntryRequest {
  const AdventureEntryRequest({
    required this.ownerId,
    required this.entryAttemptId,
    required this.occurredAtUtc,
    this.sessionChoice,
    this.activePresentationPermit,
  });

  final String ownerId;
  final String entryAttemptId;
  final DateTime occurredAtUtc;
  final TodayExperiencePresentation? sessionChoice;
  final ActivePresentationPermit? activePresentationPermit;
}

final class AdventureProductEntryDecision {
  const AdventureProductEntryDecision({
    required this.entryAttemptId,
    required this.availability,
    required this.destination,
    required this.fallbackReason,
    required this.catalogId,
    required this.catalogVersion,
    required this.catalogSchemaVersion,
    this.permitId,
    this.assignmentId,
    this.treatment,
  });

  final String entryAttemptId;
  final AdventureAvailability availability;
  final AdventureEntryDestination destination;
  final AdventureFallbackReason fallbackReason;
  final String catalogId;
  final String catalogVersion;
  final int catalogSchemaVersion;
  final String? permitId;
  final String? assignmentId;
  final String? treatment;
}

abstract interface class AdventureProductEntryResolver {
  Future<AdventureProductEntryDecision> resolve(AdventureEntryRequest request);
}
