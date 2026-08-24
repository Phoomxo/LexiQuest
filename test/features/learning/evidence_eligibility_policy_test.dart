import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';

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

    test('v1 rejects a valid context owned by the legacy policy', () {
      const policy = EvidenceEligibilityPolicyV1();
      final context = _legacyContext();

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
      final legacy = _legacyContext();

      for (final projection in LearningProjection.values) {
        expect(
          policy.disposition(legacy, projection),
          _expectedLegacy[projection],
          reason: '$projection',
        );
      }

      final declaredLegacy = Map<String, Object?>.of(
        _declaredContext().toJson(),
      )..['policyVersion'] = 'legacy-v1';
      expect(
        () => EvidenceContext.fromJson(declaredLegacy),
        throwsFormatException,
      );
    });

    test('unknown serialized policy is rejected before policy lookup', () {
      final unknown = Map<String, Object?>.of(_declaredContext().toJson())
        ..['policyVersion'] = 'future-policy';

      expect(() => EvidenceContext.fromJson(unknown), throwsFormatException);
    });
  });

  group('EvidenceProjectionDecision resolver', () {
    test('resolves every Enforced and Shadow cell from frozen policies', () {
      for (final evidenceClass in EvidenceClass.values) {
        for (final projection in LearningProjection.values) {
          final enforced = EvidenceProjectionDecision.resolve(
            context: _declaredContext(
              evidenceClass: evidenceClass,
              rolloutMode: EvidencePolicyRolloutMode.enforced,
            ),
            projection: projection,
          );
          expect(
            enforced.dispositionToApply,
            _expectedV1[evidenceClass]![projection],
            reason: 'Enforced $evidenceClass x $projection',
          );
          expect(enforced.candidateDispositionToRecord, isNull);

          final shadow = EvidenceProjectionDecision.resolve(
            context: _declaredContext(
              evidenceClass: evidenceClass,
              rolloutMode: EvidencePolicyRolloutMode.shadow,
            ),
            projection: projection,
          );
          final hasSrsSafetyFloor =
              projection == LearningProjection.masterySrs &&
              (evidenceClass == EvidenceClass.exposure ||
                  evidenceClass == EvidenceClass.recognition ||
                  evidenceClass == EvidenceClass.guidedPractice);
          final expectedShadow = evidenceClass == EvidenceClass.recreational
              ? _expectedV1[evidenceClass]![projection]
              : hasSrsSafetyFloor
              ? ProjectionDisposition.deny
              : _expectedLegacy[projection];
          expect(
            shadow.dispositionToApply,
            expectedShadow,
            reason: 'Shadow applied $evidenceClass x $projection',
          );
          expect(
            shadow.candidateDispositionToRecord,
            _expectedV1[evidenceClass]![projection],
            reason: 'Shadow candidate $evidenceClass x $projection',
          );
          expect(
            shadow.isDivergent,
            expectedShadow != _expectedV1[evidenceClass]![projection],
            reason: 'Shadow divergence $evidenceClass x $projection',
          );
        }
      }
    });

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
          context: _legacyContext(),
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

    test(
      'recreational evidence keeps its game-history safety floor in Legacy and Shadow',
      () {
        final contexts = <EvidenceContext>[
          _legacyContext(evidenceClass: EvidenceClass.recreational),
          _declaredContext(
            evidenceClass: EvidenceClass.recreational,
            rolloutMode: EvidencePolicyRolloutMode.shadow,
          ),
        ];

        for (final context in contexts) {
          for (final projection in LearningProjection.values) {
            final decision = EvidenceProjectionDecision.resolve(
              context: context,
              projection: projection,
            );
            final expected =
                _expectedV1[EvidenceClass.recreational]![projection]!;
            expect(
              const EvidenceEligibilityPolicySet().disposition(
                context,
                projection,
              ),
              expected,
              reason: '${context.rolloutMode.name} policy $projection',
            );
            expect(
              decision.dispositionToApply,
              expected,
              reason: '${context.rolloutMode.name} $projection',
            );
            expect(
              decision.isEligible,
              expected == ProjectionDisposition.allow,
              reason: '${context.rolloutMode.name} $projection',
            );
          }
        }
      },
    );

    test(
      'non-mastery evidence keeps its SRS safety floor in Legacy and Shadow',
      () {
        for (final evidenceClass in const <EvidenceClass>[
          EvidenceClass.recognition,
          EvidenceClass.exposure,
          EvidenceClass.guidedPractice,
        ]) {
          final contexts = <EvidenceContext>[
            _legacyContext(evidenceClass: evidenceClass),
            _declaredContext(
              evidenceClass: evidenceClass,
              rolloutMode: EvidencePolicyRolloutMode.shadow,
            ),
          ];
          for (final context in contexts) {
            expect(
              EvidenceProjectionDecision.resolve(
                context: context,
                projection: LearningProjection.masterySrs,
              ).dispositionToApply,
              ProjectionDisposition.deny,
            );
          }
        }
      },
    );

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

    test('invalid legacy combinations fail before resolver lookup', () {
      final legacyInShadow = Map<String, Object?>.of(_legacyContext().toJson())
        ..['rolloutMode'] = 'shadow';

      expect(
        () => EvidenceContext.fromJson(legacyInShadow),
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
  bool engagementAllowed = true,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: evidenceClass,
  skillId: 'vocabulary.meaning',
  hintLevel: 0,
  contentRevision: 'content-r1',
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

EvidenceContext _legacyContext({
  EvidenceClass evidenceClass = EvidenceClass.independentRecall,
}) => EvidenceContext.legacyCompatibility(
  evidenceClass: evidenceClass,
  skillId: 'legacy.practice',
  hintLevel: 0,
  contentRevision: 'legacy-content',
  engagementAllowed: false,
);
