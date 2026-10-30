import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

void main() {
  for (final (prompt, evidenceClass, hint) in const [
    ('clozeTyped', EvidenceClass.guidedPractice, 1),
    ('clozeChoice', EvidenceClass.recognition, 0),
  ]) {
    test('$prompt declares its calibrated generated-content evidence', () {
      final context = captureCurrentActivityEvidence(
        promptMode: prompt,
        contentRevision: 'cloze-v1:synthetic-content-digest',
      );
      expect(context.evidenceClass, evidenceClass);
      expect(context.skillId, 'cloze-context');
      expect(context.hintLevel, hint);
      expect(context.contentRevision, 'cloze-v1:synthetic-content-digest');
      expect(context.engagementAllowed, isFalse);
      expect(
        context.classificationSource,
        EvidenceClassificationSource.declared,
      );
      expect(context.policyVersion, EvidenceContext.currentPolicyVersion);
      expect(context.rolloutMode, EvidencePolicyRolloutMode.legacy);
      expect(LearningEvidenceContract.isOrdinaryEvidence(context), isTrue);
    });

    test(
      '$prompt cannot fall back to inferred evidence without a content pin',
      () {
        for (final pin in <String?>[null, '', ' ']) {
          expect(
            () => captureCurrentActivityEvidence(
              promptMode: prompt,
              contentRevision: pin,
            ),
            throwsArgumentError,
          );
        }
      },
    );

    test(
      '$prompt keeps session history and effort without mastery or motivation',
      () {
        final context = EvidenceContext.forNewEvidence(
          evidenceClass: evidenceClass,
          skillId: 'cloze-context',
          hintLevel: hint,
          contentRevision: 'cloze-v1:synthetic-content-digest',
          rolloutMode: EvidencePolicyRolloutMode.legacy,
        );
        for (final projection in LearningProjection.values) {
          expect(
            _eligible(prompt, context, projection),
            {
              LearningProjection.sessionOutcome,
              LearningProjection.history,
              LearningProjection.activeLearningEffort,
            }.contains(projection),
            reason: projection.name,
          );
        }
      },
    );

    test(
      '$prompt keeps frozen inferred compatibility and denies invalid metadata',
      () {
        for (final projection in LearningProjection.values) {
          expect(
            _eligible(
              prompt,
              LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
              projection,
            ),
            isTrue,
          );
          for (final body in ['{}', '[]', '{', 'x' * 16385]) {
            expect(
              LearningEvidenceContract.allowsOrdinaryProjection(
                promptMode: prompt,
                evidenceClass: evidenceClass.name,
                evidenceContextJson: body,
                projection: projection,
              ),
              isFalse,
            );
          }
        }
      },
    );
  }

  test('other declared ordinary prompts keep their consumed compatibility', () {
    final context = EvidenceContext.forNewEvidence(
      evidenceClass: EvidenceClass.guidedPractice,
      skillId: 'existing-guided',
      hintLevel: 1,
      contentRevision: 'synthetic-existing-revision',
      rolloutMode: EvidencePolicyRolloutMode.legacy,
    );
    for (final prompt in [
      'meaningChoice',
      'pronunciationTranscript',
      'associativeRecall',
      'srsRecall',
      'cloze',
      'clozeTypedLegacy',
    ]) {
      for (final projection in LearningProjection.values) {
        expect(_eligible(prompt, context, projection), isTrue, reason: prompt);
      }
    }
  });

  test('Dictation keeps its exact independent and assisted declarations', () {
    for (final hint in [0, 1, 2]) {
      final context = captureCurrentActivityEvidence(
        promptMode: 'dictation',
        contentRevision: 'local-vocabulary-v1:7',
        hintLevel: hint,
      );
      expect(
        context.evidenceClass,
        hint == 0
            ? EvidenceClass.independentRecall
            : EvidenceClass.guidedPractice,
      );
      expect(context.skillId, 'dictation-spelling');
      expect(context.hintLevel, hint);
      expect(context.contentRevision, 'local-vocabulary-v1:7');
      expect(context.engagementAllowed, isFalse);
      expect(
        _eligible('dictation', context, LearningProjection.masterySrs),
        hint == 0,
      );
      expect(_eligible('dictation', context, LearningProjection.xp), isFalse);
    }
    expect(
      () => captureCurrentActivityEvidence(promptMode: 'dictation'),
      throwsArgumentError,
    );
  });
}

bool _eligible(
  String prompt,
  EvidenceContext context,
  LearningProjection projection,
) => LearningEvidenceContract.allowsOrdinaryProjection(
  promptMode: prompt,
  evidenceClass: context.evidenceClass.name,
  evidenceContextJson: jsonEncode(context.toJson()),
  projection: projection,
);
