import '../domain/evidence_context.dart';
import '../domain/learning_evidence_contract.dart';

EvidenceContext captureCurrentActivityEvidence({
  required String promptMode,
  String? contentRevision,
  int hintLevel = 0,
}) {
  final declaration = switch (promptMode) {
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
    hintLevel: hintLevel,
    contentRevision: contentRevision,
    rolloutMode: EvidencePolicyRolloutMode.legacy,
  );
}
