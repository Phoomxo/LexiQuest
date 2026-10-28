import 'recommendation_models.dart';

abstract interface class LearningRecommendationPolicy {
  RecommendationDecision recommend(RecommendationEvidence evidence);
}

/// f14's frozen recommendation policy.
///
/// This policy is deterministic and read-only. New behavior requires a new
/// policy version; unknown versions return a neutral decision rather than
/// guessing from untrusted evidence.
final class FlashcardFirstRecommendationPolicy
    implements LearningRecommendationPolicy {
  const FlashcardFirstRecommendationPolicy();

  static const String policyVersion = 'f14-v1';
  static const double flashcardConfidenceThreshold = 0.7;
  static const Duration maximumEvidenceAge = Duration(days: 30);

  @override
  RecommendationDecision recommend(RecommendationEvidence evidence) {
    if (evidence.policyVersion != policyVersion) {
      return _failClosed(
        evidence,
        RecommendationReasonCode.unsupportedPolicyVersion,
      );
    }
    if (evidence.ownerId.isEmpty ||
        evidence.contentOwnerId.isEmpty ||
        evidence.contentId.isEmpty ||
        evidence.ownerId != evidence.contentOwnerId) {
      return _failClosed(evidence, RecommendationReasonCode.crossOwnerEvidence);
    }
    if (_hasCrossOwnerReference(evidence)) {
      return _failClosed(evidence, RecommendationReasonCode.crossOwnerEvidence);
    }
    if (!_hasValidReferences(evidence.evidenceReferences)) {
      return _failClosed(
        evidence,
        RecommendationReasonCode.invalidEvidenceReference,
      );
    }
    if (!evidence.observedAtUtc.isUtc ||
        !evidence.evaluatedAtUtc.isUtc ||
        evidence.observedAtUtc.isAfter(evidence.evaluatedAtUtc)) {
      return _failClosed(
        evidence,
        RecommendationReasonCode.invalidEvidenceTime,
      );
    }
    if (_hasFutureReference(evidence)) {
      return _failClosed(
        evidence,
        RecommendationReasonCode.invalidEvidenceTime,
      );
    }
    if (_hasStaleReference(evidence)) {
      return _failClosed(evidence, RecommendationReasonCode.staleEvidence);
    }
    if (evidence.isMastered && !_hasValidMasteryReference(evidence)) {
      return _failClosed(
        evidence,
        RecommendationReasonCode.invalidMasteryEvidence,
      );
    }

    final confidence = evidence.confidence;
    if (confidence == null) {
      return _failClosed(evidence, RecommendationReasonCode.missingConfidence);
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      return _failClosed(evidence, RecommendationReasonCode.invalidConfidence);
    }
    if (evidence.isMastered) {
      return _decision(
        evidence,
        action: RecommendationAction.noRecommendation,
        reasonCode: RecommendationReasonCode.masteredItem,
      );
    }
    if (evidence.isUnseen) {
      return _decision(
        evidence,
        action: RecommendationAction.flashcardPreparation,
        reasonCode: RecommendationReasonCode.unseenItem,
      );
    }
    if (confidence < flashcardConfidenceThreshold) {
      return _decision(
        evidence,
        action: RecommendationAction.flashcardPreparation,
        reasonCode: RecommendationReasonCode.lowConfidence,
      );
    }
    return _decision(
      evidence,
      action: RecommendationAction.noRecommendation,
      reasonCode: RecommendationReasonCode.confidenceSufficient,
    );
  }

  RecommendationDecision _failClosed(
    RecommendationEvidence evidence,
    RecommendationReasonCode reasonCode,
  ) => _decision(
    evidence,
    action: RecommendationAction.noRecommendation,
    reasonCode: reasonCode,
  );

  RecommendationDecision _decision(
    RecommendationEvidence evidence, {
    required RecommendationAction action,
    required RecommendationReasonCode reasonCode,
  }) => RecommendationDecision(
    policyVersion: policyVersion,
    ownerId: evidence.ownerId,
    contentId: evidence.contentId,
    action: action,
    reasonCode: reasonCode,
    evidenceReferences: evidence.evidenceReferences,
  );

  bool _hasValidReferences(List<RecommendationEvidenceReference> references) {
    if (references.isEmpty) return false;
    return references.every(
      (reference) =>
          reference.referenceId.isNotEmpty &&
          reference.version.isNotEmpty &&
          reference.capturedAtUtc.isUtc,
    );
  }

  bool _hasCrossOwnerReference(RecommendationEvidence evidence) =>
      evidence.evidenceReferences.any(
        (reference) =>
            reference.ownerId != evidence.ownerId ||
            reference.contentId != evidence.contentId,
      );

  bool _hasStaleReference(RecommendationEvidence evidence) {
    final observedAt = <DateTime>[
      evidence.observedAtUtc,
      ...evidence.evidenceReferences.map(
        (reference) => reference.capturedAtUtc,
      ),
    ];
    return observedAt.any(
      (timestamp) =>
          evidence.evaluatedAtUtc.difference(timestamp) > maximumEvidenceAge,
    );
  }

  bool _hasFutureReference(RecommendationEvidence evidence) =>
      evidence.evidenceReferences.any(
        (reference) => reference.capturedAtUtc.isAfter(evidence.evaluatedAtUtc),
      );

  bool _hasValidMasteryReference(RecommendationEvidence evidence) {
    final srsReferences = evidence.evidenceReferences
        .where(
          (reference) =>
              reference.source == RecommendationEvidenceSource.srsReadModel,
        )
        .toList(growable: false);
    return srsReferences.length == 1 &&
        RegExp(r'^srs:\S+$').hasMatch(srsReferences.single.referenceId) &&
        RegExp(r'^srs-v[1-9][0-9]*$').hasMatch(srsReferences.single.version);
  }
}
