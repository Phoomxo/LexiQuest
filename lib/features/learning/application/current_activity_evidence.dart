import '../domain/evidence_context.dart';
import '../domain/learning_evidence_contract.dart';

EvidenceContext captureCurrentActivityEvidence({
  required String promptMode,
  String? contentRevision,
  int hintLevel = 0,
}) {
  if (LearningEvidenceContract.nativeProjectionPromptModes.contains(
        promptMode,
      ) &&
      (contentRevision == null || contentRevision.trim().isEmpty)) {
    throw ArgumentError(switch (promptMode) {
      'dictation' => 'Dictation requires its actual content revision',
      'wordScramble' => 'Word Scramble requires its actual content revision',
      'sentenceScramble' =>
        'Sentence Scramble requires its actual content revision',
      _ => 'Cloze requires its actual content revision',
    });
  }
  final declaration = switch (promptMode) {
    'dictation' => (
      hintLevel == 0
          ? EvidenceClass.independentRecall
          : EvidenceClass.guidedPractice,
      'dictation-spelling',
    ),
    'clozeTyped' => (EvidenceClass.guidedPractice, 'cloze-context'),
    'clozeChoice' => (EvidenceClass.recognition, 'cloze-context'),
    'wordScramble' => (EvidenceClass.recreational, 'word-scramble'),
    'sentenceScramble' => (EvidenceClass.recreational, 'sentence-scramble'),
    'meaningChoice' => (
      hintLevel == 0 ? EvidenceClass.recognition : EvidenceClass.guidedPractice,
      'meaning-recall',
    ),
    'srsRecall' => (EvidenceClass.independentRecall, 'srs-recall'),
    'associativeRecall' => (
      EvidenceClass.independentRecall,
      'associative-recall',
    ),
    'ghostSpelling' => (EvidenceClass.recreational, 'ghost-duel'),
    'shadowing' => (EvidenceClass.pronunciation, 'shadowing-pronunciation'),
    'pronunciationTranscript' => (
      EvidenceClass.pronunciation,
      'pronunciation-transcript',
    ),
    _ => null,
  };
  if (contentRevision == null || declaration == null) {
    return LearningEvidenceContract.frozenV13LegacyEvidenceContext();
  }
  return EvidenceContext.forNewEvidence(
    evidenceClass: declaration.$1,
    skillId: declaration.$2,
    hintLevel: switch (promptMode) {
      'clozeTyped' => 1,
      'clozeChoice' || 'wordScramble' || 'sentenceScramble' => 0,
      _ => hintLevel,
    },
    contentRevision: contentRevision,
    rolloutMode: EvidencePolicyRolloutMode.legacy,
  );
}
