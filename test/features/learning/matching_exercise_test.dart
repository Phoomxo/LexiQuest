import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/matching_exercise.dart';

void main() {
  MatchingPlan plan() => MatchingPlan(
    session: LearningSessionDraft(
      id: '${MatchingPlan.sessionPrefix}synthetic-codec',
      ownerId: 'synthetic-matching-owner',
      activityType: MatchingPlan.activityType,
      startedAtUtc: DateTime.utc(2026, 11),
      appVersion: 'synthetic',
      buildId: 'synthetic',
    ),
    words: [
      for (var index = 0; index < 4; index++)
        QuizWord(
          id: 'synthetic-word-$index',
          categoryId: 'synthetic-category',
          spelling: 'word$index',
          meaning: 'ความหมาย$index',
          partOfSpeech: 'noun',
          contentRevision: 'local-vocabulary-v1:1',
        ),
    ],
  );

  test(
    'matching plan roundtrips exact pins and an initially unsolved board',
    () {
      final original = plan();
      final restored = MatchingPlan.parse(
        id: original.id,
        json: original.stableSerialization,
      );
      expect(restored.stableSerialization, original.stableSerialization);
      expect(restored.meaningOrder, [1, 2, 3, 0]);
      final changed =
          jsonDecode(original.stableSerialization) as Map<String, dynamic>;
      (changed['words'] as List).first['meaning'] = 'changed';
      expect(
        () => MatchingPlan.parse(id: original.id, json: jsonEncode(changed)),
        throwsFormatException,
      );
      changed['extra'] = true;
      expect(
        () => MatchingPlan.parse(id: original.id, json: jsonEncode(changed)),
        throwsFormatException,
      );
    },
  );

  test('ambiguous labels and unpinned targets cannot form a board', () {
    final original = plan();
    expect(
      () => MatchingPlan(
        session: original.session,
        words: [
          original.words.first,
          QuizWord(
            id: 'different',
            categoryId: 'synthetic-category',
            spelling: 'WORD0 ',
            meaning: 'other',
            partOfSpeech: 'noun',
            contentRevision: 'local-vocabulary-v1:1',
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => MatchingPlan(
        session: original.session,
        words: [original.words.first],
      ),
      throwsFormatException,
    );
  });

  test(
    'matching records recognition without recall mastery or engagement grants',
    () {
      final original = plan();
      final command = original.command(
        MatchingPairIntent(
          id: 'attempt:matching:${original.session.id}:1',
          ordinal: 1,
          wordIndex: 0,
          meaningIndex: 1,
          occurredAtUtcMs:
              original.session.startedAtUtc!.millisecondsSinceEpoch,
          responseTimeMs: 900,
        ),
      );
      expect(command.isCorrect, isFalse);
      expect(command.evidenceContext.evidenceClass, EvidenceClass.recognition);
      expect(command.evidenceContext.engagementAllowed, isFalse);
      for (final projection in [
        LearningProjection.masterySrs,
        LearningProjection.quest,
        LearningProjection.streak,
        LearningProjection.achievement,
        LearningProjection.xp,
        LearningProjection.coins,
      ]) {
        expect(
          EvidenceProjectionDecision.resolve(
            context: command.evidenceContext,
            projection: projection,
          ).isEligible,
          isFalse,
          reason: projection.name,
        );
      }
      expect(
        EvidenceProjectionDecision.resolve(
          context: command.evidenceContext,
          projection: LearningProjection.activeLearningEffort,
        ).isEligible,
        isTrue,
      );
    },
  );

  test(
    'checkpoint rejects claimed completion and contradictory answered pairs',
    () {
      final original = plan();
      final selected = MatchingCheckpoint(
        phase: MatchingPhase.selecting,
        attemptCount: 0,
        matched: [],
        selectedWord: 0,
        selectedMeaning: 1,
      );
      expect(
        MatchingCheckpoint.parse(
          selected.stableSerialization,
          original,
        ).stableSerialization,
        selected.stableSerialization,
      );
      expect(
        () => MatchingCheckpoint(
          phase: MatchingPhase.completed,
          attemptCount: 0,
          matched: [],
          endedAtUtcMs: original.session.startedAtUtc!.millisecondsSinceEpoch,
        ).validate(original),
        throwsFormatException,
      );
      expect(
        () => MatchingCheckpoint(
          phase: MatchingPhase.selecting,
          attemptCount: 1,
          matched: [0],
          selectedWord: 0,
        ).validate(original),
        throwsFormatException,
      );
      expect(
        () => MatchingCheckpoint(
          phase: MatchingPhase.answered,
          attemptCount: 1,
          matched: [],
          answer: MatchingPairIntent(
            id: 'attempt:matching:${original.session.id}:1',
            ordinal: 1,
            wordIndex: 0,
            meaningIndex: 0,
            occurredAtUtcMs:
                original.session.startedAtUtc!.millisecondsSinceEpoch,
            responseTimeMs: 20,
          ),
        ).validate(original),
        throwsFormatException,
      );
    },
  );

  test(
    'matching legacy or forged recall metadata cannot widen projection eligibility',
    () {
      final original = plan();
      final valid = original.evidence;
      final invalid = <EvidenceContext>[
        LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        EvidenceContext.legacyCompatibility(
          evidenceClass: EvidenceClass.recognition,
          skillId: 'meaning-recognition',
          hintLevel: 0,
          contentRevision: original.id,
          engagementAllowed: false,
        ),
        EvidenceContext.forNewEvidence(
          evidenceClass: EvidenceClass.independentRecall,
          skillId: 'meaning-recognition',
          hintLevel: 0,
          contentRevision: original.id,
          rolloutMode: EvidencePolicyRolloutMode.legacy,
        ),
        EvidenceContext.forNewEvidence(
          evidenceClass: EvidenceClass.recognition,
          skillId: 'meaning-recognition',
          hintLevel: 0,
          contentRevision: original.id,
          rolloutMode: EvidencePolicyRolloutMode.legacy,
          engagementAllowed: true,
        ),
        EvidenceContext.forNewEvidence(
          evidenceClass: EvidenceClass.recognition,
          skillId: 'meaning-recognition',
          hintLevel: 1,
          contentRevision: original.id,
          rolloutMode: EvidencePolicyRolloutMode.legacy,
        ),
      ];
      for (final context in invalid) {
        for (final projection in LearningProjection.values) {
          expect(
            LearningEvidenceContract.allowsOrdinaryProjection(
              promptMode: MatchingPlan.promptMode,
              evidenceClass: context.evidenceClass.name,
              evidenceContextJson: jsonEncode(context.toJson()),
              projection: projection,
            ),
            isFalse,
            reason:
                '${context.evidenceClass}/${context.classificationSource}/${context.engagementAllowed}/$projection',
          );
        }
      }
      expect(
        LearningEvidenceContract.allowsOrdinaryProjection(
          promptMode: MatchingPlan.promptMode,
          evidenceClass: valid.evidenceClass.name,
          evidenceContextJson: jsonEncode(valid.toJson()),
          projection: LearningProjection.history,
        ),
        isTrue,
      );
      expect(
        LearningEvidenceContract.allowsOrdinaryProjection(
          promptMode: MatchingPlan.promptMode,
          evidenceClass: valid.evidenceClass.name,
          evidenceContextJson: jsonEncode(valid.toJson()),
          projection: LearningProjection.masterySrs,
        ),
        isFalse,
      );
    },
  );
}
