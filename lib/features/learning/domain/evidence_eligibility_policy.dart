import 'evidence_context.dart';

enum LearningProjection {
  sessionOutcome,
  masterySrs,
  assessmentOutcome,
  activeLearningEffort,
  history,
  pronunciation,
  quest,
  streak,
  achievement,
  xp,
  coins,
}

enum ProjectionDisposition { allow, deny, protocolControlled }

sealed class EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicy._();

  String get version;

  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  );
}

final class EvidenceEligibilityPolicySet extends EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicySet() : super._();

  @override
  String get version => 'policy-set-v1';

  @override
  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  ) {
    return switch (context.policyVersion) {
      EvidenceEligibilityPolicyV1.policyVersion =>
        const EvidenceEligibilityPolicyV1().disposition(context, projection),
      EvidenceContext.legacyPolicyVersion
          when context.classificationSource ==
              EvidenceClassificationSource.legacyInferred =>
        context.evidenceClass == EvidenceClass.recreational
            ? evidenceEligibilityV1[EvidenceClass.recreational]![projection]!
            : _legacyDisposition(projection),
      _ => throw StateError(
        'Unsupported evidence policy ${context.policyVersion}.',
      ),
    };
  }
}

final class EvidenceEligibilityPolicyV1 extends EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicyV1() : super._();

  static const String policyVersion = EvidenceContext.currentPolicyVersion;

  @override
  String get version => policyVersion;

  @override
  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  ) {
    if (context.policyVersion != policyVersion) {
      throw StateError('Unsupported evidence policy ${context.policyVersion}.');
    }
    final row = evidenceEligibilityV1[context.evidenceClass];
    if (row == null) {
      throw StateError('Missing evidence policy row ${context.evidenceClass}.');
    }
    final result = row[projection];
    if (result == null) {
      throw StateError('Missing evidence policy projection $projection.');
    }
    return result;
  }
}

final class EvidenceProjectionDecision {
  const EvidenceProjectionDecision._({
    required this.context,
    required this.projection,
    required this.dispositionToApply,
    required this.candidateDispositionToRecord,
    required this.contributesToEfficacyOutcomes,
    required this.retainedForProjectionComparison,
  });

  factory EvidenceProjectionDecision.resolve({
    required EvidenceContext context,
    required LearningProjection projection,
  }) {
    context.validate();
    final policyDisposition = const EvidenceEligibilityPolicySet().disposition(
      context,
      projection,
    );
    final effectiveDisposition = effectiveProjectionDisposition(
      context: context,
      projection: projection,
      policyDisposition: policyDisposition,
    );

    return switch (context.rolloutMode) {
      EvidencePolicyRolloutMode.legacy => EvidenceProjectionDecision._(
        context: context,
        projection: projection,
        dispositionToApply: effectiveDisposition,
        candidateDispositionToRecord: null,
        contributesToEfficacyOutcomes: false,
        retainedForProjectionComparison: false,
      ),
      EvidencePolicyRolloutMode.shadow => EvidenceProjectionDecision._(
        context: context,
        projection: projection,
        dispositionToApply: effectiveDisposition,
        candidateDispositionToRecord: policyDisposition,
        contributesToEfficacyOutcomes: false,
        retainedForProjectionComparison: true,
      ),
      EvidencePolicyRolloutMode.enforced => EvidenceProjectionDecision._(
        context: context,
        projection: projection,
        dispositionToApply: effectiveDisposition,
        candidateDispositionToRecord: null,
        contributesToEfficacyOutcomes:
            context.classificationSource ==
            EvidenceClassificationSource.declared,
        retainedForProjectionComparison: false,
      ),
    };
  }

  final EvidenceContext context;
  final LearningProjection projection;
  final ProjectionDisposition dispositionToApply;
  final ProjectionDisposition? candidateDispositionToRecord;
  final bool contributesToEfficacyOutcomes;
  final bool retainedForProjectionComparison;

  EvidencePolicyRolloutMode get rolloutMode => context.rolloutMode;
  String get policyVersion => context.policyVersion;
  ProjectionDisposition get effectiveDisposition => dispositionToApply;
  ProjectionDisposition? get v1CandidateDisposition =>
      candidateDispositionToRecord;

  bool get isDivergent =>
      candidateDispositionToRecord != null &&
      candidateDispositionToRecord != dispositionToApply;

  bool get isEligible => switch (dispositionToApply) {
    ProjectionDisposition.allow => true,
    ProjectionDisposition.deny => false,
    ProjectionDisposition.protocolControlled => context.engagementAllowed,
  };
}

/// Resolves the production disposition while preserving the recreational
/// safety floor across rollout modes. Recreational events are game history,
/// never learning-effort or reward evidence, so Legacy and Shadow cannot widen
/// their eligibility through the class-agnostic compatibility row.
ProjectionDisposition effectiveProjectionDisposition({
  required EvidenceContext context,
  required LearningProjection projection,
  required ProjectionDisposition policyDisposition,
}) {
  if (context.evidenceClass == EvidenceClass.recreational) {
    return evidenceEligibilityV1[EvidenceClass.recreational]![projection]!;
  }
  // A presentation-only occurrence is never a memory update, including while
  // the rest of the application is still on the class-agnostic Legacy rollout.
  // This is the same kind of safety floor as recreational active effort, but
  // deliberately scoped to the canonical SRS projection so Legacy fallback
  // behavior for unrelated projections remains byte-for-byte unchanged.
  if (context.evidenceClass == EvidenceClass.exposure &&
      projection == LearningProjection.masterySrs) {
    return ProjectionDisposition.deny;
  }
  return switch (context.rolloutMode) {
    EvidencePolicyRolloutMode.legacy => _legacyDisposition(projection),
    EvidencePolicyRolloutMode.shadow => _legacyDisposition(projection),
    EvidencePolicyRolloutMode.enforced => policyDisposition,
  };
}

ProjectionDisposition _legacyDisposition(LearningProjection projection) {
  final result = legacyEvidenceEligibilityV1[projection];
  if (result == null) {
    throw StateError('Missing legacy evidence projection $projection.');
  }
  return result;
}

const legacyEvidenceEligibilityV1 = <LearningProjection, ProjectionDisposition>{
  LearningProjection.sessionOutcome: ProjectionDisposition.allow,
  LearningProjection.masterySrs: ProjectionDisposition.allow,
  LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
  LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
  LearningProjection.history: ProjectionDisposition.allow,
  LearningProjection.pronunciation: ProjectionDisposition.deny,
  LearningProjection.quest: ProjectionDisposition.allow,
  LearningProjection.streak: ProjectionDisposition.allow,
  LearningProjection.achievement: ProjectionDisposition.allow,
  LearningProjection.xp: ProjectionDisposition.allow,
  LearningProjection.coins: ProjectionDisposition.allow,
};

const evidenceEligibilityV1 =
    <EvidenceClass, Map<LearningProjection, ProjectionDisposition>>{
      EvidenceClass.assessment: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.deny,
        LearningProjection.assessmentOutcome: ProjectionDisposition.allow,
        LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.deny,
        LearningProjection.quest: ProjectionDisposition.deny,
        LearningProjection.streak: ProjectionDisposition.deny,
        LearningProjection.achievement: ProjectionDisposition.deny,
        LearningProjection.xp: ProjectionDisposition.deny,
        LearningProjection.coins: ProjectionDisposition.deny,
      },
      EvidenceClass
          .independentRecall: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.allow,
        LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
        LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.deny,
        LearningProjection.quest: ProjectionDisposition.protocolControlled,
        LearningProjection.streak: ProjectionDisposition.protocolControlled,
        LearningProjection.achievement:
            ProjectionDisposition.protocolControlled,
        LearningProjection.xp: ProjectionDisposition.protocolControlled,
        LearningProjection.coins: ProjectionDisposition.protocolControlled,
      },
      EvidenceClass.recognition: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.deny,
        LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
        LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.deny,
        LearningProjection.quest: ProjectionDisposition.protocolControlled,
        LearningProjection.streak: ProjectionDisposition.protocolControlled,
        LearningProjection.achievement:
            ProjectionDisposition.protocolControlled,
        LearningProjection.xp: ProjectionDisposition.protocolControlled,
        LearningProjection.coins: ProjectionDisposition.protocolControlled,
      },
      EvidenceClass.guidedPractice: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.deny,
        LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
        LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.deny,
        LearningProjection.quest: ProjectionDisposition.deny,
        LearningProjection.streak: ProjectionDisposition.deny,
        LearningProjection.achievement: ProjectionDisposition.deny,
        LearningProjection.xp: ProjectionDisposition.deny,
        LearningProjection.coins: ProjectionDisposition.deny,
      },
      EvidenceClass.pronunciation: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.deny,
        LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
        LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.allow,
        LearningProjection.quest: ProjectionDisposition.deny,
        LearningProjection.streak: ProjectionDisposition.deny,
        LearningProjection.achievement: ProjectionDisposition.deny,
        LearningProjection.xp: ProjectionDisposition.deny,
        LearningProjection.coins: ProjectionDisposition.deny,
      },
      EvidenceClass.exposure: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.deny,
        LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
        LearningProjection.activeLearningEffort: ProjectionDisposition.allow,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.deny,
        LearningProjection.quest: ProjectionDisposition.deny,
        LearningProjection.streak: ProjectionDisposition.deny,
        LearningProjection.achievement: ProjectionDisposition.deny,
        LearningProjection.xp: ProjectionDisposition.deny,
        LearningProjection.coins: ProjectionDisposition.deny,
      },
      EvidenceClass.recreational: <LearningProjection, ProjectionDisposition>{
        LearningProjection.sessionOutcome: ProjectionDisposition.allow,
        LearningProjection.masterySrs: ProjectionDisposition.deny,
        LearningProjection.assessmentOutcome: ProjectionDisposition.deny,
        LearningProjection.activeLearningEffort: ProjectionDisposition.deny,
        LearningProjection.history: ProjectionDisposition.allow,
        LearningProjection.pronunciation: ProjectionDisposition.deny,
        LearningProjection.quest: ProjectionDisposition.deny,
        LearningProjection.streak: ProjectionDisposition.deny,
        LearningProjection.achievement: ProjectionDisposition.deny,
        LearningProjection.xp: ProjectionDisposition.deny,
        LearningProjection.coins: ProjectionDisposition.deny,
      },
    };
