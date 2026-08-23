/// Stable, versioned experiment assignment lookup.
///
/// Assignment remains independent from product delivery, feature visibility,
/// consent decisions, and runtime kill switches.
library;

import '../../features/research/data/drift_experiment_assignment_repository.dart';
import '../../features/research/domain/experiment_assignment.dart';

export '../../features/research/domain/experiment_assignment.dart'
    show ExperimentAssignment;

abstract interface class ExperimentRegistry {
  Future<ExperimentAssignment?> getAssignment({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
  });

  Future<List<ExperimentAssignment>> listAssignments({required String ownerId});
}

final class NoOpExperimentRegistry implements ExperimentRegistry {
  const NoOpExperimentRegistry();

  @override
  Future<ExperimentAssignment?> getAssignment({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
  }) async => null;

  @override
  Future<List<ExperimentAssignment>> listAssignments({
    required String ownerId,
  }) async => const <ExperimentAssignment>[];
}

final class DriftExperimentRegistry implements ExperimentRegistry {
  const DriftExperimentRegistry(this._repository);

  final DriftExperimentAssignmentRepository _repository;

  @override
  Future<ExperimentAssignment?> getAssignment({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
  }) async {
    ExperimentAssignment assignment;
    try {
      assignment = await _repository.getAssignment(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
      );
    } on StateError {
      return null;
    }

    _requireValidAssignment(assignment, expectedOwnerId: ownerId);
    if (assignment.experimentId != experimentId ||
        assignment.experimentVersion != experimentVersion) {
      throw StateError('Malformed persisted experiment assignment.');
    }
    return assignment;
  }

  @override
  Future<List<ExperimentAssignment>> listAssignments({
    required String ownerId,
  }) async {
    final assignments = await _repository.listAssignmentsForOwner(
      ownerId: ownerId,
    );
    for (final assignment in assignments) {
      _requireValidAssignment(assignment, expectedOwnerId: ownerId);
    }
    return assignments;
  }

  Future<bool> matchesAssignmentIdentity({
    required String ownerId,
    required String experimentId,
    required int experimentVersion,
    required String candidateAssignmentId,
  }) {
    return _repository.matchesAssignmentIdentity(
      ownerId: ownerId,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      candidateAssignmentId: candidateAssignmentId,
    );
  }
}

void _requireValidAssignment(
  ExperimentAssignment assignment, {
  required String expectedOwnerId,
}) {
  if (assignment.ownerId != expectedOwnerId ||
      !_isCanonical(assignment.id) ||
      !_isCanonical(assignment.ownerId) ||
      !_isCanonical(assignment.experimentId) ||
      assignment.experimentVersion <= 0 ||
      !_isCanonical(assignment.cohort) ||
      !_isCanonical(assignment.protocolVersion) ||
      !assignment.assignedAtUtc.isUtc ||
      assignment.assignedAtUtc.millisecondsSinceEpoch < 0) {
    throw StateError('Malformed persisted experiment assignment.');
  }
}

bool _isCanonical(String value) {
  return value.isNotEmpty && value == value.trim() && value.runes.length <= 256;
}
