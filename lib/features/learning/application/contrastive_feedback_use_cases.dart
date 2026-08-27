import '../../learning_packs/domain/content_manifest.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';

enum ContrastiveFeedbackRolloutStage { implementedOff, internal }

/// Child-capability rollout. The broad live kill switch remains Feature.quiz;
/// this stage prevents a new capability from being enabled by composition
/// merely because the established quiz route is enabled.
final class ContrastiveFeedbackRollout {
  const ContrastiveFeedbackRollout.implementedOff()
    : stage = ContrastiveFeedbackRolloutStage.implementedOff;

  const ContrastiveFeedbackRollout.internal()
    : stage = ContrastiveFeedbackRolloutStage.internal;

  final ContrastiveFeedbackRolloutStage stage;

  bool get allowsPresentation =>
      stage == ContrastiveFeedbackRolloutStage.internal;
}

/// Read-only resolver for reviewed contrastive feedback.
///
/// The input is the f17 feedback value emitted after the canonical answer
/// commit. There is deliberately no second caller-controlled lookup request.
final class ContrastiveFeedbackUseCases {
  factory ContrastiveFeedbackUseCases({
    required ContentManifestRepository manifests,
  }) => ContrastiveFeedbackUseCases._(manifests);

  ContrastiveFeedbackUseCases._(this._manifests);

  final ContentManifestRepository _manifests;
  final Map<String, _ResolutionReceipt> _receipts =
      <String, _ResolutionReceipt>{};

  Future<ContrastiveExplanation?> resolveAfterCommit({
    required AnswerFeedback committedFeedback,
  }) {
    final attempt = committedFeedback.committedContrastiveAttempt;
    if (committedFeedback.isCorrect ||
        attempt == null ||
        !attempt.isSelfConsistent) {
      return Future<ContrastiveExplanation?>.value();
    }
    final fingerprint = attempt.stableFingerprint;
    final existing = _receipts[attempt.attemptIdentity];
    if (existing != null) {
      return existing.fingerprint == fingerprint
          ? existing.resolution
          : Future<ContrastiveExplanation?>.value();
    }
    final resolution = _resolve(attempt);
    _receipts[attempt.attemptIdentity] = _ResolutionReceipt(
      fingerprint: fingerprint,
      resolution: resolution,
    );
    return resolution;
  }

  Future<ContrastiveExplanation?> _resolve(
    CommittedContrastiveAttempt attempt,
  ) async {
    try {
      final verified = await _manifests.requireVerified(
        attempt.manifestIdentity,
      );
      final manifest = verified.manifest;
      if (manifest.identity != attempt.manifestIdentity ||
          manifest.checksumSha256 != attempt.manifestChecksumSha256 ||
          manifest.provenance != ContentProvenance.packaged ||
          manifest.reviewState != ContentReviewState.approved ||
          manifest.publicationState != ContentPublicationState.published ||
          manifest.reviewedAtUtc == null ||
          manifest.publishedAtUtc == null) {
        return null;
      }
      final metadata = RichLexicalMetadata.fromVerifiedArtifact(
        bytes: verified.bytes,
        wordId: attempt.wordId,
        contentRevision: attempt.manifestIdentity.revision,
        verifiedArtifactChecksumSha256: manifest.checksumSha256,
      );
      final rationale = metadata.contrastiveFeedback[attempt.promptMode];
      if (rationale == null ||
          rationale.correctOptionId != attempt.correctOptionId) {
        return null;
      }
      final selected =
          rationale.distractorRationales[attempt.selectedDistractorId];
      if (selected == null) return null;
      return ContrastiveExplanation.reviewed(
        manifestIdentity: attempt.manifestIdentity,
        correctOptionId: attempt.correctOptionId,
        selectedDistractorId: attempt.selectedDistractorId,
        correctRationale: rationale.correctRationale,
        distractorRationale: selected,
      );
    } on Object {
      // Missing, unreviewed, stale, malformed, or checksum-invalid optional
      // content hides the explanation. No generation or alternate route exists.
      return null;
    }
  }
}

final class _ResolutionReceipt {
  const _ResolutionReceipt({
    required this.fingerprint,
    required this.resolution,
  });

  final String fingerprint;
  final Future<ContrastiveExplanation?> resolution;
}
