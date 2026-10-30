import 'dart:convert';

import 'evidence_context.dart';
import 'evidence_eligibility_policy.dart';

abstract final class LearningEvidenceContract {
  static const int maxIdentifierLength = 256;
  static const int maxPromptModeLength = 60;
  static const int maxProviderProvenanceLength = 120;
  static const int maxResponseTimeMs = 2147483647;
  static const int maxAttemptNumber = 1000000;

  // Frozen archived v13 sentinel is reused by the current-lineage v11 migration.
  static const String frozenV13LegacyEvidenceContextJson =
      '{"schemaVersion":1,"evidenceClass":"independentRecall",'
      '"skillId":"legacy-unspecified","hintLevel":0,'
      '"policyVersion":"legacy-v1","contentRevision":"legacy-unknown",'
      '"featureContractRevision":"legacy-unversioned",'
      '"featureContractHash":"0000000000000000000000000000000000000000000000000000000000000000",'
      '"classificationSource":"legacyInferred","rolloutMode":"legacy",'
      '"protocolId":null,"protocolVersion":null,'
      '"experimentId":null,"experimentVersion":null,'
      '"assignmentId":null,"cohort":null,"researchConsentVersion":null,'
      '"instrumentId":null,"instrumentVersion":null,'
      '"formId":null,"formVersion":null,'
      '"assessmentItemId":null,"assessmentResponseCode":null,'
      '"scoringRuleVersion":null,"engagementAllowed":true}';

  static final EvidenceContext _legacyEvidence = EvidenceContext.fromJson(
    jsonDecode(frozenV13LegacyEvidenceContextJson) as Map<String, dynamic>,
  );

  static EvidenceContext frozenV13LegacyEvidenceContext() => _legacyEvidence;

  static bool isOrdinaryEvidence(EvidenceContext context) {
    context.validate();
    return context.rolloutMode == EvidencePolicyRolloutMode.legacy &&
        (context.classificationSource ==
                EvidenceClassificationSource.declared ||
            jsonEncode(context.toJson()) ==
                frozenV13LegacyEvidenceContextJson) &&
        context.evidenceClass != EvidenceClass.assessment &&
        <Object?>[
          context.protocolId,
          context.protocolVersion,
          context.experimentId,
          context.experimentVersion,
          context.assignmentId,
          context.cohort,
          context.researchConsentVersion,
          context.instrumentId,
          context.instrumentVersion,
          context.formId,
          context.formVersion,
          context.assessmentItemId,
          context.assessmentResponseCode,
          context.scoringRuleVersion,
        ].every((value) => value == null);
  }

  static bool validEvidenceMetadata({
    required String evidenceClass,
    required String evidenceContextJson,
  }) {
    if (evidenceContextJson.length > 16384) return false;
    try {
      final decoded = jsonDecode(evidenceContextJson);
      if (decoded is! Map<String, dynamic>) return false;
      final context = EvidenceContext.fromJson(decoded);
      return context.evidenceClass.name == evidenceClass &&
          isOrdinaryEvidence(context);
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Applies the approved projection decision only to the introduced native
  /// declaration. Other admitted ordinary evidence keeps compatibility behavior.
  static bool allowsOrdinaryProjection({
    required String promptMode,
    required String evidenceClass,
    required String evidenceContextJson,
    required LearningProjection projection,
  }) {
    if (!validEvidenceMetadata(
      evidenceClass: evidenceClass,
      evidenceContextJson: evidenceContextJson,
    )) {
      return false;
    }
    if (promptMode != 'dictation') {
      return true;
    }
    final context = EvidenceContext.fromJson(
      jsonDecode(evidenceContextJson) as Map<String, dynamic>,
    );
    if (context.classificationSource != EvidenceClassificationSource.declared ||
        context.policyVersion != EvidenceContext.currentPolicyVersion) {
      return true;
    }
    return EvidenceProjectionDecision.resolve(
      context: context,
      projection: projection,
    ).isEligible;
  }

  /// Checks stored Assessment shape, not run linkage or current authority.
  static bool strictAssessmentShape({
    required String persistedEvidenceClass,
    required EvidenceContext context,
  }) {
    try {
      context.validate();
      return persistedEvidenceClass == EvidenceClass.assessment.name &&
          context.evidenceClass == EvidenceClass.assessment &&
          context.classificationSource ==
              EvidenceClassificationSource.declared &&
          context.rolloutMode == EvidencePolicyRolloutMode.enforced &&
          context.hintLevel == 0 &&
          !context.engagementAllowed;
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  static bool validText(String value, {required int maxLength}) {
    final length = value.runes.length;
    return value.trim().isNotEmpty && length <= maxLength;
  }

  static bool validIdentifier(String value) =>
      validText(value, maxLength: maxIdentifierLength);

  static bool validAttempt({
    required String id,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required int? responseTimeMs,
    required int attemptNumber,
    required int occurredAtUtcMs,
    required String? providerProvenance,
    String evidenceClass = 'independentRecall',
    String evidenceContextJson = frozenV13LegacyEvidenceContextJson,
  }) {
    return validIdentifier(id) &&
        validIdentifier(ownerId) &&
        validIdentifier(sessionId) &&
        validIdentifier(wordId) &&
        validText(promptMode, maxLength: maxPromptModeLength) &&
        (responseTimeMs == null ||
            (responseTimeMs >= 0 && responseTimeMs <= maxResponseTimeMs)) &&
        attemptNumber > 0 &&
        attemptNumber <= maxAttemptNumber &&
        occurredAtUtcMs >= 0 &&
        (providerProvenance == null ||
            (providerProvenance.runes.length <= maxProviderProvenanceLength)) &&
        validEvidenceMetadata(
          evidenceClass: evidenceClass,
          evidenceContextJson: evidenceContextJson,
        );
  }

  static bool validReading({
    required String eventId,
    required String ownerId,
    required String documentId,
    required int documentRevision,
    required String eventType,
    required int? position,
    required int occurredAtUtcMs,
  }) {
    return validIdentifier(eventId) &&
        validIdentifier(ownerId) &&
        validIdentifier(documentId) &&
        documentRevision > 0 &&
        (eventType == 'checkpoint' || eventType == 'completed') &&
        (position == null || position >= 0) &&
        occurredAtUtcMs >= 0;
  }
}
