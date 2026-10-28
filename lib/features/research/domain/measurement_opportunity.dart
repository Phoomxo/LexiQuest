import '../../adventure/domain/adventure_entry.dart';

/// Durable participant-only denominator and links to canonical learning facts.
final class MeasurementOpportunity {
  const MeasurementOpportunity({
    required this.id,
    required this.ownerId,
    required this.measurementRunId,
    required this.permitId,
    required this.entryAttemptId,
    required this.assignedTreatment,
    required this.effectivePresentation,
    required this.openedAtUtc,
    required this.localRevision,
    required this.lastSwitchOrdinal,
    required this.suppressedSwitchCount,
    this.presentedEventId,
    this.learningSessionId,
    this.startedEventId,
    this.completedEventId,
    this.closedAtUtc,
  });
  final String id, ownerId, measurementRunId, permitId, entryAttemptId;
  final TodayExperiencePresentation assignedTreatment, effectivePresentation;
  final DateTime openedAtUtc;
  final DateTime? closedAtUtc;
  final int localRevision, lastSwitchOrdinal, suppressedSwitchCount;
  final String? presentedEventId,
      learningSessionId,
      startedEventId,
      completedEventId;
}
