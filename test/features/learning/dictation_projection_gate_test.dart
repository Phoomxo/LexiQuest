import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

void main() {
  bool eligible(
    EvidenceContext context,
    LearningProjection projection, {
    String prompt = 'dictation',
  }) => LearningEvidenceContract.allowsOrdinaryProjection(
    promptMode: prompt,
    evidenceClass: context.evidenceClass.name,
    evidenceContextJson: jsonEncode(context.toJson()),
    projection: projection,
  );

  EvidenceContext declared(EvidenceClass evidenceClass) =>
      EvidenceContext.forNewEvidence(
        evidenceClass: evidenceClass,
        skillId: 'dictation-spelling',
        hintLevel: evidenceClass == EvidenceClass.guidedPractice ? 1 : 0,
        contentRevision: 'local-vocabulary-v1:1',
        rolloutMode: EvidencePolicyRolloutMode.legacy,
      );

  test(
    'declared Dictation applies each approved projection with false engagement',
    () {
      final guided = declared(EvidenceClass.guidedPractice);
      final normal = declared(EvidenceClass.independentRecall);
      expect(guided.engagementAllowed, isFalse);
      expect(normal.engagementAllowed, isFalse);
      for (final projection in LearningProjection.values) {
        expect(
          eligible(guided, projection),
          {
            LearningProjection.sessionOutcome,
            LearningProjection.history,
            LearningProjection.activeLearningEffort,
          }.contains(projection),
          reason: 'guided ${projection.name}',
        );
        expect(
          eligible(normal, projection),
          {
            LearningProjection.sessionOutcome,
            LearningProjection.history,
            LearningProjection.activeLearningEffort,
            LearningProjection.masterySrs,
          }.contains(projection),
          reason: 'normal ${projection.name}',
        );
      }
    },
  );

  test(
    'frozen inferred Dictation and other declared prompts retain consumed ordinary behavior',
    () {
      final legacy = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
      final guided = declared(EvidenceClass.guidedPractice);
      for (final projection in [
        LearningProjection.sessionOutcome,
        LearningProjection.history,
        LearningProjection.masterySrs,
        LearningProjection.xp,
        LearningProjection.coins,
        LearningProjection.quest,
        LearningProjection.streak,
        LearningProjection.achievement,
      ]) {
        expect(eligible(legacy, projection), isTrue);
        expect(
          eligible(guided, projection, prompt: 'old-other-prompt'),
          isTrue,
        );
      }
    },
  );

  test(
    'malformed ordinary metadata and mismatched class never gain projection admission',
    () {
      final context = declared(EvidenceClass.independentRecall);
      for (final projection in LearningProjection.values) {
        for (final body in ['{}', '[]', '{', 'x' * 16385]) {
          expect(
            LearningEvidenceContract.allowsOrdinaryProjection(
              promptMode: 'dictation',
              evidenceClass: 'independentRecall',
              evidenceContextJson: body,
              projection: projection,
            ),
            isFalse,
          );
        }
        expect(
          LearningEvidenceContract.allowsOrdinaryProjection(
            promptMode: 'dictation',
            evidenceClass: 'guidedPractice',
            evidenceContextJson: jsonEncode(context.toJson()),
            projection: projection,
          ),
          isFalse,
        );
      }
    },
  );
}
