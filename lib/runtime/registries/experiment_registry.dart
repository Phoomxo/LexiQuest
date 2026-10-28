/// V2 Experiment Registry — A/B experiment cohort assignment.
///
/// Intentionally separate from [FeatureRegistry]: enabling a feature flag
/// for a user must never implicitly assign them to an experiment cohort, and
/// vice versa.  Callers that need both must query each registry independently.
library;

/// The result of looking up a user's assignment for one experiment.
final class ExperimentAssignment {
  const ExperimentAssignment._({
    required this.experimentId,
    required this.ownerId,
    required this.cohort,
  });

  /// The experiment that was queried.
  final String experimentId;

  /// The owner (learner) that was queried.
  final String ownerId;

  /// `null` when the owner has not been assigned to any cohort.
  final String? cohort;

  /// `true` when the owner has no assignment for this experiment.
  bool get isUnassigned => cohort == null;

  /// `true` when [cohort] matches [name] (case-sensitive).
  bool isCohort(String name) => cohort == name;

  @override
  String toString() =>
      'ExperimentAssignment(experiment=$experimentId, owner=$ownerId, '
      'cohort=${cohort ?? "<unassigned>"})';
}

/// Read-only contract for querying experiment cohort assignments.
abstract interface class ExperimentRegistry {
  /// Returns the [ExperimentAssignment] for [experimentId] and [ownerId].
  ///
  /// Always returns a non-null value; use [ExperimentAssignment.isUnassigned]
  /// to detect the absence of an assignment.
  ExperimentAssignment getAssignment(String experimentId, String ownerId);
}

/// No-op [ExperimentRegistry] that reports every owner as unassigned.
///
/// Suitable for production Phase -1 before real experiment infrastructure
/// is wired up, and for tests that do not exercise experiment behaviour.
final class NoOpExperimentRegistry implements ExperimentRegistry {
  const NoOpExperimentRegistry();

  @override
  ExperimentAssignment getAssignment(String experimentId, String ownerId) =>
      ExperimentAssignment._(
        experimentId: experimentId,
        ownerId: ownerId,
        cohort: null,
      );
}
