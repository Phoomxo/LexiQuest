import '../../consent/domain/research_consent.dart';
import 'experiment_assignment.dart';
import 'research_participation_permit.dart';

/// A freshly checked local context, not continuing authority for another write.
final class ResearchParticipantSnapshot {
  const ResearchParticipantSnapshot(this.permit, this.assignment, this.consent);

  final ResearchParticipationPermit permit;
  final ExperimentAssignment assignment;
  final ResearchConsentStatus consent;
}

final class ResearchParticipationConflict implements Exception {
  const ResearchParticipationConflict({
    required this.ownerId,
    required this.permitId,
  });

  final String ownerId;
  final String permitId;
}
