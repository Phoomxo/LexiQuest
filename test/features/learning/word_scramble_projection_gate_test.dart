import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

EvidenceContext _recreational() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.recreational,
  skillId: 'word-scramble',
  hintLevel: 0,
  contentRevision: 'word-scramble-v1:synthetic-content-digest',
  rolloutMode: EvidencePolicyRolloutMode.legacy,
);

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

void main() {
  test(
    'Word Scramble captures exact current recreational metadata and actual pin',
    () {
      for (final suppliedHint in [0, 1, 2]) {
        final context = captureCurrentActivityEvidence(
          promptMode: 'wordScramble',
          contentRevision: 'word-scramble-v1:synthetic-content-digest',
          hintLevel: suppliedHint,
        );
        expect(context.toJson(), _recreational().toJson());
        expect(
          context.classificationSource,
          EvidenceClassificationSource.declared,
        );
        expect(context.policyVersion, EvidenceContext.currentPolicyVersion);
        expect(context.evidenceClass, EvidenceClass.recreational);
        expect(context.skillId, 'word-scramble');
        expect(context.hintLevel, 0);
        expect(context.engagementAllowed, isFalse);
        expect(context.protocolId, isNull);
        expect(context.assignmentId, isNull);
        expect(context.instrumentId, isNull);
        expect(LearningEvidenceContract.isOrdinaryEvidence(context), isTrue);
      }
    },
  );

  test(
    'Word Scramble never falls back to inferred evidence without actual content',
    () {
      for (final pin in <String?>[null, '', ' ']) {
        expect(
          () => captureCurrentActivityEvidence(
            promptMode: 'wordScramble',
            contentRevision: pin,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('declared Word Scramble permits only session outcome and history', () {
    final context = _recreational();
    for (final projection in LearningProjection.values) {
      expect(
        _eligible('wordScramble', context, projection),
        {
          LearningProjection.sessionOutcome,
          LearningProjection.history,
        }.contains(projection),
        reason: projection.name,
      );
      final decision = EvidenceProjectionDecision.resolve(
        context: context,
        projection: projection,
      );
      expect(decision.contributesToEfficacyOutcomes, isFalse);
      expect(decision.retainedForProjectionComparison, isFalse);
    }
  });

  test(
    'inferred Word Scramble and other ordinary prompts retain compatibility',
    () {
      for (final projection in LearningProjection.values) {
        expect(
          _eligible(
            'wordScramble',
            LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
            projection,
          ),
          isTrue,
        );
        expect(
          _eligible('wordScrambleLegacy', _recreational(), projection),
          isTrue,
        );
        expect(
          _eligible('other-unmigrated-mode', _recreational(), projection),
          isTrue,
        );
      }
    },
  );

  test('invalid or mismatched Word Scramble metadata gains no projection', () {
    for (final projection in LearningProjection.values) {
      for (final json in ['{}', '[]', '{', 'x' * 16385]) {
        expect(
          LearningEvidenceContract.allowsOrdinaryProjection(
            promptMode: 'wordScramble',
            evidenceClass: 'recreational',
            evidenceContextJson: json,
            projection: projection,
          ),
          isFalse,
        );
      }
      expect(
        LearningEvidenceContract.allowsOrdinaryProjection(
          promptMode: 'wordScramble',
          evidenceClass: 'independentRecall',
          evidenceContextJson: jsonEncode(_recreational().toJson()),
          projection: projection,
        ),
        isFalse,
      );
    }
  });

  test(
    'existing native declarations keep their distinct projection decisions',
    () {
      for (final (prompt, hint, evidenceClass, mastery, effort) in [
        ('dictation', 0, EvidenceClass.independentRecall, true, true),
        ('dictation', 1, EvidenceClass.guidedPractice, false, true),
        ('clozeTyped', 0, EvidenceClass.guidedPractice, false, true),
        ('clozeChoice', 0, EvidenceClass.recognition, false, true),
      ]) {
        final context = captureCurrentActivityEvidence(
          promptMode: prompt,
          hintLevel: hint,
          contentRevision: 'synthetic-current-native-content',
        );
        expect(context.evidenceClass, evidenceClass);
        expect(
          _eligible(prompt, context, LearningProjection.masterySrs),
          mastery,
        );
        expect(
          _eligible(prompt, context, LearningProjection.activeLearningEffort),
          effort,
        );
        for (final projection in [
          LearningProjection.xp,
          LearningProjection.coins,
          LearningProjection.quest,
          LearningProjection.streak,
          LearningProjection.achievement,
        ]) {
          expect(_eligible(prompt, context, projection), isFalse);
        }
      }
    },
  );
}
