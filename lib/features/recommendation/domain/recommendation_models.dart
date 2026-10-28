import '../../learning/domain/lesson_mode.dart';

/// Read-only recommendation inputs, references, and decisions.
///
/// These types deliberately contain identifiers and timestamps only. They do
/// not carry raw learner content, repositories, or research-assignment state.
enum RecommendationAction {
  flashcardPreparation,
  lessonMode,
  learnerChoice,
  noRecommendation,
}

enum RecommendationReasonCode {
  unseenItem,
  lowConfidence,
  masteredItem,
  confidenceSufficient,
  unsupportedPolicyVersion,
  missingConfidence,
  invalidConfidence,
  crossOwnerEvidence,
  staleEvidence,
  invalidEvidenceTime,
  invalidEvidenceReference,
  invalidMasteryEvidence,
  recallLadderNextStep,
  recallLadderComplete,
  unsupportedLadderVersion,
  unsupportedAuthorityVersion,
  unsupportedProtocolVersion,
  canonicalAuthorityUnavailable,
  modeUnavailable,
  protocolLockedStep,
  accessibilityAlternativeRequired,
  invalidLadderEvidence,
  circularRecommendationPrevented,
}

extension RecommendationReasonCodeWireValue on RecommendationReasonCode {
  String get value => switch (this) {
    RecommendationReasonCode.unseenItem => 'unseen_item',
    RecommendationReasonCode.lowConfidence => 'low_confidence',
    RecommendationReasonCode.masteredItem => 'mastered_item',
    RecommendationReasonCode.confidenceSufficient => 'confidence_sufficient',
    RecommendationReasonCode.unsupportedPolicyVersion =>
      'unsupported_policy_version',
    RecommendationReasonCode.missingConfidence => 'missing_confidence',
    RecommendationReasonCode.invalidConfidence => 'invalid_confidence',
    RecommendationReasonCode.crossOwnerEvidence => 'cross_owner_evidence',
    RecommendationReasonCode.staleEvidence => 'stale_evidence',
    RecommendationReasonCode.invalidEvidenceTime => 'invalid_evidence_time',
    RecommendationReasonCode.invalidEvidenceReference =>
      'invalid_evidence_reference',
    RecommendationReasonCode.invalidMasteryEvidence =>
      'invalid_mastery_evidence',
    RecommendationReasonCode.recallLadderNextStep => 'recall_ladder_next_step',
    RecommendationReasonCode.recallLadderComplete => 'recall_ladder_complete',
    RecommendationReasonCode.unsupportedLadderVersion =>
      'unsupported_ladder_version',
    RecommendationReasonCode.unsupportedAuthorityVersion =>
      'unsupported_authority_version',
    RecommendationReasonCode.unsupportedProtocolVersion =>
      'unsupported_protocol_version',
    RecommendationReasonCode.canonicalAuthorityUnavailable =>
      'canonical_authority_unavailable',
    RecommendationReasonCode.modeUnavailable => 'mode_unavailable',
    RecommendationReasonCode.protocolLockedStep => 'protocol_locked_step',
    RecommendationReasonCode.accessibilityAlternativeRequired =>
      'accessibility_alternative_required',
    RecommendationReasonCode.invalidLadderEvidence => 'invalid_ladder_evidence',
    RecommendationReasonCode.circularRecommendationPrevented =>
      'circular_recommendation_prevented',
  };
}

enum RecommendationLearnerChoice { dismiss, override }

enum RecommendationEvidenceSource {
  progressReadModel,
  srsReadModel,
  responseEvidenceReadModel,
}

/// An immutable, non-content-bearing pointer to canonical read evidence.
final class RecommendationEvidenceReference {
  const RecommendationEvidenceReference({
    required this.source,
    required this.ownerId,
    required this.contentId,
    required this.referenceId,
    required this.version,
    required this.capturedAtUtc,
  });

  final RecommendationEvidenceSource source;
  final String ownerId;
  final String contentId;
  final String referenceId;
  final String version;
  final DateTime capturedAtUtc;
}

/// The complete bounded policy input for one owner and one content identity.
///
/// A null or non-finite confidence value is not inferred and is rejected by
/// the policy. [isUnseen] is explicit so an entirely incorrect seen item is
/// not misrepresented as unseen evidence.
final class RecommendationEvidence {
  RecommendationEvidence({
    required this.policyVersion,
    required this.ownerId,
    required this.contentOwnerId,
    required this.contentId,
    required this.confidence,
    required this.isUnseen,
    required this.isMastered,
    required this.observedAtUtc,
    required this.evaluatedAtUtc,
    required List<RecommendationEvidenceReference> evidenceReferences,
  }) : evidenceReferences = List.unmodifiable(evidenceReferences);

  final String policyVersion;
  final String ownerId;
  final String contentOwnerId;
  final String contentId;
  final double? confidence;
  final bool isUnseen;
  final bool isMastered;
  final DateTime observedAtUtc;
  final DateTime evaluatedAtUtc;
  final List<RecommendationEvidenceReference> evidenceReferences;
}

/// A pure advisory result. Applying [learnerChoice] only produces another
/// value; it cannot write progress, SRS, assignments, or research state.
final class RecommendationDecision {
  RecommendationDecision({
    required this.policyVersion,
    required this.ownerId,
    required this.contentId,
    required this.action,
    required this.reasonCode,
    required List<RecommendationEvidenceReference> evidenceReferences,
    this.recommendedMode,
    List<LessonMode> learnerChoiceModes = const <LessonMode>[],
    this.learnerChoice,
  }) : evidenceReferences = List.unmodifiable(evidenceReferences),
       learnerChoiceModes = List.unmodifiable(learnerChoiceModes);

  final String policyVersion;
  final String ownerId;
  final String contentId;
  final RecommendationAction action;
  final RecommendationReasonCode reasonCode;
  final List<RecommendationEvidenceReference> evidenceReferences;
  final LessonMode? recommendedMode;
  final List<LessonMode> learnerChoiceModes;
  final RecommendationLearnerChoice? learnerChoice;

  bool get isAdvisory => true;

  Set<RecommendationLearnerChoice> get allowedLearnerChoices =>
      const <RecommendationLearnerChoice>{
        RecommendationLearnerChoice.dismiss,
        RecommendationLearnerChoice.override,
      };

  RecommendationDecision withLearnerChoice(RecommendationLearnerChoice choice) {
    return RecommendationDecision(
      policyVersion: policyVersion,
      ownerId: ownerId,
      contentId: contentId,
      action: action,
      reasonCode: reasonCode,
      evidenceReferences: evidenceReferences,
      recommendedMode: recommendedMode,
      learnerChoiceModes: learnerChoiceModes,
      learnerChoice: choice,
    );
  }
}
