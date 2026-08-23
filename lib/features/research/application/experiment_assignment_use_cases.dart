import '../../../runtime/registries/consent_registry.dart';
import '../data/drift_experiment_assignment_repository.dart';
import '../domain/experiment_assignment.dart';

final class ExperimentAssignmentUseCases {
  const ExperimentAssignmentUseCases({
    required this.repository,
    required this.consentRegistry,
  });

  final DriftExperimentAssignmentRepository repository;
  final ConsentRegistry consentRegistry;

  Future<ExperimentAssignment?> assignIfConsented({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
    required String cohort,
    required String protocolVersion,
    required int consentVersion,
    required DateTime assignedAtUtc,
  }) async {
    final consent = await consentRegistry.snapshot(
      purpose: ConsentPurpose.researchDataUpload,
      ownerId: ownerId,
      consentVersion: consentVersion,
    );
    final decisionUtc = consent.decisionUtc;
    if (consent.state != ConsentState.granted ||
        decisionUtc == null ||
        !decisionUtc.isUtc ||
        decisionUtc.millisecondsSinceEpoch < 0 ||
        decisionUtc.isAfter(assignedAtUtc) ||
        consent.withdrawalUtc != null) {
      return null;
    }

    return repository.assignIfAbsent(
      ownerId: ownerId,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      cohort: cohort,
      protocolVersion: protocolVersion,
      assignedAtUtc: assignedAtUtc,
    );
  }
}
