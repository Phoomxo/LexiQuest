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

abstract interface class EvidenceEligibilityPolicy {
  String get version;

  ProjectionDisposition disposition(
    EvidenceContext context,
    LearningProjection projection,
  );
}

final class EvidenceEligibilityPolicySet implements EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicySet();

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
        _legacyDisposition(projection),
      _ => throw StateError(
        'Unsupported evidence policy ${context.policyVersion}.',
      ),
    };
  }
}

final class EvidenceEligibilityPolicyV1 implements EvidenceEligibilityPolicy {
  const EvidenceEligibilityPolicyV1();

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
    EvidenceEligibilityPolicy policy = const EvidenceEligibilityPolicySet(),
  }) {
    final policyDisposition = policy.disposition(context, projection);
    context.validate();

    return switch (context.rolloutMode) {
      EvidencePolicyRolloutMode.legacy => EvidenceProjectionDecision._(
        context: context,
        projection: projection,
        dispositionToApply: _legacyDisposition(projection),
        candidateDispositionToRecord: null,
        contributesToEfficacyOutcomes: false,
        retainedForProjectionComparison: false,
      ),
      EvidencePolicyRolloutMode.shadow => EvidenceProjectionDecision._(
        context: context,
        projection: projection,
        dispositionToApply: _legacyDisposition(projection),
        candidateDispositionToRecord: policyDisposition,
        contributesToEfficacyOutcomes: false,
        retainedForProjectionComparison: true,
      ),
      EvidencePolicyRolloutMode.enforced => EvidenceProjectionDecision._(
        context: context,
        projection: projection,
        dispositionToApply: policyDisposition,
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
