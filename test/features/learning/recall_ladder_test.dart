import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/recall_ladder.dart';

void main() {
  test(
    'an empty recent sample suggests exposure without asserting mastery',
    () {
      final snapshot = RecallLadderSnapshot(
        ownerId: 'synthetic',
        word: null,
        observations: const [],
      );
      expect(snapshot.suggestedStage, RecallLadderStage.exposure);
      expect(snapshot.latest, isNull);
    },
  );
  for (final entry in <String, (EvidenceClass, String, RecallLadderStage)>{
    'meaningChoice': (
      EvidenceClass.recognition,
      'meaning-recall',
      RecallLadderStage.matching,
    ),
    'matchingPair': (
      EvidenceClass.recognition,
      'meaning-recognition',
      RecallLadderStage.cloze,
    ),
    'clozeChoice': (
      EvidenceClass.recognition,
      'cloze-context',
      RecallLadderStage.typedRecall,
    ),
    'definitionTyped': (
      EvidenceClass.independentRecall,
      'definition-recall',
      RecallLadderStage.dictation,
    ),
    'dictation': (
      EvidenceClass.independentRecall,
      'dictation-spelling',
      RecallLadderStage.speaking,
    ),
    'pronunciationTranscript': (
      EvidenceClass.pronunciation,
      'pronunciation-transcript',
      RecallLadderStage.speaking,
    ),
  }.entries) {
    test(
      '${entry.key} suggests the next practice while retaining its actual evidence class',
      () {
        final observation = _observation(
          entry.key,
          entry.value.$1,
          entry.value.$2,
        )!;
        expect(suggestRecallLadderStage(observation), entry.value.$3);
        expect(observation.evidenceClass, entry.value.$1);
      },
    );
  }
  test(
    'wrong independent recall repeats and assisted recall suggests earlier support',
    () {
      final wrong = _observation(
        'definitionTyped',
        EvidenceClass.independentRecall,
        'definition-recall',
        correct: false,
      )!;
      final assisted = _observation(
        'definitionTyped',
        EvidenceClass.guidedPractice,
        'definition-recall',
        hints: 1,
      )!;
      expect(suggestRecallLadderStage(wrong), RecallLadderStage.typedRecall);
      expect(assisted.assisted, isTrue);
      expect(suggestRecallLadderStage(assisted), RecallLadderStage.cloze);
    },
  );
  test('guided contextual typing is not independent recall readiness', () {
    final observation = _observation(
      'clozeTyped',
      EvidenceClass.guidedPractice,
      'cloze-context',
      hints: 1,
    )!;
    expect(observation.assisted, isTrue);
    expect(suggestRecallLadderStage(observation), RecallLadderStage.matching);
  });
  test(
    'legacy inferred unsupported and forged classes never create an observation',
    () {
      expect(
        _from(
          'meaningChoice',
          LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        ),
        isNull,
      );
      expect(
        _observation(
          'meaningChoice',
          EvidenceClass.independentRecall,
          'meaning-recall',
        ),
        isNull,
      );
      expect(
        _observation(
          'meaningChoice',
          EvidenceClass.recognition,
          'invented-skill',
        ),
        isNull,
      );
      expect(
        _observation(
          'wordScramble',
          EvidenceClass.recreational,
          'word-scramble',
        ),
        isNull,
      );
    },
  );
  test(
    'protocol-controlled context is excluded even if the response was correct',
    () {
      final context = EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning-recall',
        hintLevel: 0,
        contentRevision: 'local-vocabulary-v1:1',
        rolloutMode: EvidencePolicyRolloutMode.shadow,
        protocolId: 'synthetic-protocol',
        protocolVersion: 'synthetic-v1',
        experimentId: 'synthetic-experiment',
        experimentVersion: 1,
        assignmentId: 'synthetic-assignment',
        cohort: 'synthetic-cohort',
        researchConsentVersion: 1,
      );
      expect(_from('meaningChoice', context), isNull);
    },
  );
  test(
    'latest actual timestamp selects the suggestion rather than the highest stage',
    () {
      final old = _observation(
        'dictation',
        EvidenceClass.independentRecall,
        'dictation-spelling',
      )!;
      final recent = _observation(
        'meaningChoice',
        EvidenceClass.recognition,
        'meaning-recall',
        at: DateTime.utc(2026, 11, 2),
      )!;
      final snapshot = RecallLadderSnapshot(
        ownerId: 'synthetic',
        word: null,
        observations: [old, recent],
      );
      expect(snapshot.suggestedStage, RecallLadderStage.matching);
      expect(snapshot.observedCount(RecallLadderStage.dictation), 1);
      expect(snapshot.observedCount(RecallLadderStage.speaking), 0);
    },
  );
}

RecallLadderObservation? _observation(
  String prompt,
  EvidenceClass evidenceClass,
  String skill, {
  bool correct = true,
  int hints = 0,
  DateTime? at,
}) => RecallLadderObservation.fromEvidence(
  attemptId: 'synthetic:$prompt',
  promptMode: prompt,
  isCorrect: correct,
  occurredAtUtc: at ?? DateTime.utc(2026, 11, 1),
  context: EvidenceContext.forNewEvidence(
    evidenceClass: evidenceClass,
    skillId: skill,
    hintLevel: hints,
    contentRevision: 'local-vocabulary-v1:1',
    rolloutMode: EvidencePolicyRolloutMode.legacy,
  ),
);

RecallLadderObservation? _from(String prompt, EvidenceContext context) =>
    RecallLadderObservation.fromEvidence(
      attemptId: 'synthetic:control',
      promptMode: prompt,
      isCorrect: true,
      occurredAtUtc: DateTime.utc(2026, 11, 1),
      context: context,
    );
