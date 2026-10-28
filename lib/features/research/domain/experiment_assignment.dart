final class ExperimentAssignment {
  const ExperimentAssignment({
    required this.id,
    required this.ownerId,
    required this.experimentId,
    required this.experimentVersion,
    required this.cohort,
    required this.protocolVersion,
    required this.assignedAtUtc,
  });

  final String id;
  final String ownerId;
  final String experimentId;
  final int experimentVersion;
  final String cohort;
  final String protocolVersion;
  final DateTime assignedAtUtc;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ExperimentAssignment &&
            other.id == id &&
            other.ownerId == ownerId &&
            other.experimentId == experimentId &&
            other.experimentVersion == experimentVersion &&
            other.cohort == cohort &&
            other.protocolVersion == protocolVersion &&
            other.assignedAtUtc == assignedAtUtc;
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    experimentId,
    experimentVersion,
    cohort,
    protocolVersion,
    assignedAtUtc,
  );
}

final class ExperimentAssignmentConflict implements Exception {
  const ExperimentAssignmentConflict({
    required this.ownerId,
    required this.experimentId,
    required this.experimentVersion,
  });

  final String ownerId;
  final String experimentId;
  final int experimentVersion;

  @override
  String toString() {
    return 'ExperimentAssignmentConflict('
        'ownerId: $ownerId, '
        'experimentId: $experimentId, '
        'experimentVersion: $experimentVersion)';
  }
}
