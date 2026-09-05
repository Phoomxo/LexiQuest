import '../../domain/evidence_context.dart';
import '../../domain/hint_policy.dart';

enum PairAudioDelivery { localPronunciation, textAndIpa }

/// Visible speech is a modality. Only persisted answer-revealing support
/// acquired before an attempt changes its evidence classification.
abstract final class PairSupportPolicy {
  static HintEvidenceClassification classify({
    required int? supportRevision,
    required int attemptRevision,
  }) => HintEvidenceClassification(
    evidenceClass: supportRevision != null && supportRevision < attemptRevision
        ? EvidenceClass.guidedPractice
        : EvidenceClass.recognition,
    hintLevel: supportRevision != null && supportRevision < attemptRevision
        ? 1
        : 0,
  );

  /// There is deliberately no remote-text delivery option.
  static PairAudioDelivery audio({required bool localAvailable}) =>
      localAvailable
      ? PairAudioDelivery.localPronunciation
      : PairAudioDelivery.textAndIpa;
}
