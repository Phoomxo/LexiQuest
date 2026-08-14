import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  group('EvidenceEligibilityPolicyV1', () {
    test('defines and resolves the exact exhaustive 7 by 11 matrix', () {
      expect(evidenceEligibilityV1, _expectedV1);
      expect(evidenceEligibilityV1.keys.toSet(), EvidenceClass.values.toSet());
      for (final evidenceClass in EvidenceClass.values) {
        final row = evidenceEligibilityV1[evidenceClass];
        expect(row, isNotNull, reason: '$evidenceClass row');
        expect(
          row!.keys.toSet(),
          LearningProjection.values.toSet(),
          reason: '$evidenceClass columns',
        );
        for (final projection in LearningProjection.values) {
          expect(
            const EvidenceEligibilityPolicyV1().disposition(
              _declaredContext(evidenceClass: evidenceClass),
              projection,
            ),
            _expectedV1[evidenceClass]![projection],
            reason: '$evidenceClass x $projection',
          );
        }
      }
    });

    test('keeps the matrix immutable', () {
      expect(
        () =>
            evidenceEligibilityV1[EvidenceClass.assessment]![LearningProjection
                    .masterySrs] =
                ProjectionDisposition.allow,
        throwsUnsupportedError,
      );
    });

    test('recreational evidence keeps history but denies active effort', () {
      const policy = EvidenceEligibilityPolicyV1();
      final context = _declaredContext(
        evidenceClass: EvidenceClass.recreational,
      );

      expect(
        policy.disposition(context, LearningProjection.history),
        ProjectionDisposition.allow,
      );
      expect(
        policy.disposition(context, LearningProjection.activeLearningEffort),
        ProjectionDisposition.deny,
      );
    });

    test('fails closed when called with an unsupported policy version', () {
      const policy = EvidenceEligibilityPolicyV1();
      final context = _declaredContext(policyVersion: 'unknown-policy');

      expect(
        () => policy.disposition(context, LearningProjection.sessionOutcome),
        throwsStateError,
      );
    });
  });

  group('legacy compatibility policy', () {
    test('is the exact exhaustive compatibility row', () {
      expect(legacyEvidenceEligibilityV1, _expectedLegacy);
      expect(
        legacyEvidenceEligibilityV1.keys.toSet(),
        LearningProjection.values.toSet(),
      );
    });

    test('is available only to legacy-inferred evidence', () {
      const policy = EvidenceEligibilityPolicySet();
      const legacy = _legacyContext;

      for (final projection in LearningProjection.values) {
        expect(
          policy.disposition(legacy, projection),
          _expectedLegacy[projection],
          reason: '$projection',
        );
      }

      final declaredLegacy = _declaredContext(policyVersion: 'legacy-v1');
      expect(
        () => policy.disposition(
          declaredLegacy,
          LearningProjection.sessionOutcome,
        ),
        throwsStateError,
      );
    });

    test('unknown policy versions fail closed without an allow fallback', () {
      const policy = EvidenceEligibilityPolicySet();
      final unknown = _declaredContext(policyVersion: 'future-policy');

      for (final projection in LearningProjection.values) {
        expect(
          () => policy.disposition(unknown, projection),
          throwsStateError,
          reason: '$projection',
        );
      }
    });
  });

  group('EvidenceProjectionDecision resolver', () {
    test('Legacy applies compatibility and has no research candidate', () {
      final context = _declaredContext(
        evidenceClass: EvidenceClass.assessment,
        rolloutMode: EvidencePolicyRolloutMode.legacy,
      );

      final decision = EvidenceProjectionDecision.resolve(
        context: context,
        projection: LearningProjection.masterySrs,
      );

      expect(decision.dispositionToApply, ProjectionDisposition.allow);
      expect(decision.candidateDispositionToRecord, isNull);
      expect(decision.contributesToEfficacyOutcomes, isFalse);
      expect(decision.retainedForProjectionComparison, isFalse);
      expect(decision.isDivergent, isFalse);
      expect(decision.isEligible, isTrue);
    });

    test(
      'legacy-inferred replay applies compatibility and is never research',
      () {
        final decision = EvidenceProjectionDecision.resolve(
          context: _legacyContext,
          projection: LearningProjection.xp,
        );

        expect(decision.dispositionToApply, ProjectionDisposition.allow);
        expect(decision.candidateDispositionToRecord, isNull);
        expect(decision.contributesToEfficacyOutcomes, isFalse);
        expect(decision.retainedForProjectionComparison, isFalse);
      },
    );

    test('Shadow applies compatibility and records the v1 candidate only', () {
      final context = _declaredContext(
        evidenceClass: EvidenceClass.assessment,
        rolloutMode: EvidencePolicyRolloutMode.shadow,
      );

      final decision = EvidenceProjectionDecision.resolve(
        context: context,
        projection: LearningProjection.masterySrs,
      );

      expect(decision.dispositionToApply, ProjectionDisposition.allow);
      expect(decision.candidateDispositionToRecord, ProjectionDisposition.deny);
      expect(decision.contributesToEfficacyOutcomes, isFalse);
      expect(decision.retainedForProjectionComparison, isTrue);
      expect(decision.isDivergent, isTrue);
      expect(decision.isEligible, isTrue);
    });

    test('Enforced applies v1 and permits efficacy outcomes', () {
      final context = _declaredContext(
        evidenceClass: EvidenceClass.assessment,
        rolloutMode: EvidencePolicyRolloutMode.enforced,
      );

      final decision = EvidenceProjectionDecision.resolve(
        context: context,
        projection: LearningProjection.assessmentOutcome,
      );

      expect(decision.dispositionToApply, ProjectionDisposition.allow);
      expect(decision.candidateDispositionToRecord, isNull);
      expect(decision.contributesToEfficacyOutcomes, isTrue);
      expect(decision.retainedForProjectionComparison, isFalse);
      expect(decision.isDivergent, isFalse);
      expect(decision.isEligible, isTrue);
    });

    test('protocol-controlled requires explicit engagement eligibility', () {
      final denied = EvidenceProjectionDecision.resolve(
        context: _declaredContext(engagementAllowed: false),
        projection: LearningProjection.quest,
      );
      final allowed = EvidenceProjectionDecision.resolve(
        context: _declaredContext(engagementAllowed: true),
        projection: LearningProjection.quest,
      );

      expect(
        denied.dispositionToApply,
        ProjectionDisposition.protocolControlled,
      );
      expect(denied.isEligible, isFalse);
      expect(allowed.isEligible, isTrue);
    });

    test('unknown policy and invalid legacy combinations fail closed', () {
      final unknown = _declaredContext(policyVersion: 'future-policy');
      final legacyInShadow = EvidenceContext(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'legacy.practice',
        hintLevel: 0,
        policyVersion: 'legacy-v1',
        contentRevision: 'legacy-content',
        featureContractRevision: EvidenceContext.legacyFeatureContractRevision,
        featureContractHash: EvidenceContext.legacyFeatureContractHash,
        classificationSource: EvidenceClassificationSource.legacyInferred,
        rolloutMode: EvidencePolicyRolloutMode.shadow,
      );

      expect(
        () => EvidenceProjectionDecision.resolve(
          context: unknown,
          projection: LearningProjection.sessionOutcome,
        ),
        throwsStateError,
      );
      expect(
        () => EvidenceProjectionDecision.resolve(
          context: legacyInShadow,
          projection: LearningProjection.sessionOutcome,
        ),
        throwsFormatException,
      );
    });
  });
}

const _expectedLegacy = <LearningProjection, ProjectionDisposition>{
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

const _expectedV1 =
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

EvidenceContext _declaredContext({
  EvidenceClass evidenceClass = EvidenceClass.independentRecall,
  EvidencePolicyRolloutMode rolloutMode = EvidencePolicyRolloutMode.enforced,
  String policyVersion = 'learning-evidence-v1',
  bool engagementAllowed = true,
}) => EvidenceContext(
  evidenceClass: evidenceClass,
  skillId: 'vocabulary.meaning',
  hintLevel: 0,
  policyVersion: policyVersion,
  contentRevision: 'content-r1',
  featureContractRevision: currentFeatureContractIdentity.revision,
  featureContractHash: currentFeatureContractIdentity.semanticHash,
  classificationSource: EvidenceClassificationSource.declared,
  rolloutMode: rolloutMode,
  protocolId: 'protocol-1',
  protocolVersion: 'protocol-v1',
  experimentId: 'experiment-1',
  experimentVersion: 1,
  assignmentId: 'assignment-1',
  cohort: 'cohort-a',
  researchConsentVersion: 1,
  instrumentId: evidenceClass == EvidenceClass.assessment
      ? 'instrument-1'
      : null,
  instrumentVersion: evidenceClass == EvidenceClass.assessment
      ? 'instrument-v1'
      : null,
  formId: evidenceClass == EvidenceClass.assessment ? 'form-1' : null,
  formVersion: evidenceClass == EvidenceClass.assessment ? 'form-v1' : null,
  assessmentItemId: evidenceClass == EvidenceClass.assessment ? 'item-1' : null,
  assessmentResponseCode: evidenceClass == EvidenceClass.assessment
      ? 'option-a'
      : null,
  scoringRuleVersion: evidenceClass == EvidenceClass.assessment
      ? 'scoring-v1'
      : null,
  engagementAllowed: engagementAllowed,
);

const EvidenceContext _legacyContext = EvidenceContext(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'legacy.practice',
  hintLevel: 0,
  policyVersion: 'legacy-v1',
  contentRevision: 'legacy-content',
  featureContractRevision: EvidenceContext.legacyFeatureContractRevision,
  featureContractHash: EvidenceContext.legacyFeatureContractHash,
  classificationSource: EvidenceClassificationSource.legacyInferred,
  rolloutMode: EvidencePolicyRolloutMode.legacy,
  engagementAllowed: false,
);
