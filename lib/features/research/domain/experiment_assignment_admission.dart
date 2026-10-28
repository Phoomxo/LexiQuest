import 'motivation_study_protocol.dart';
import 'research_participation_permit.dart';

final class ExperimentAssignmentAdmissionBinding {
  ExperimentAssignmentAdmissionBinding({
    required this.study,
    required this.assignmentRevision,
    required this.protocolRevision,
    required this.instrumentRevision,
  }) {
    if (assignmentRevision <= 0 ||
        protocolRevision <= 0 ||
        instrumentRevision <= 0) {
      throw const FormatException(
        'Research authority revisions must be positive',
      );
    }
  }

  final MotivationStudyProtocol study;
  final int assignmentRevision;
  final int protocolRevision;
  final int instrumentRevision;
}

/// A bounded local read of authoritative current signed state. An unavailable or
/// unproven revision must return null; callers must not echo the submitted permit.
abstract interface class ResearchParticipationDocumentSource {
  Future<ResearchParticipationPermit?> loadCurrent({
    required String ownerId,
    required String permitId,
  });
}
