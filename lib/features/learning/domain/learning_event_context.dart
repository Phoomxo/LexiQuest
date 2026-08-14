import '../../events/domain/event_envelope_v2.dart';
import '../../../product/feature_contract/feature_contract_digest.dart';
import 'evidence_context.dart';

/// Immutable provider-owned metadata that accompanies one learning event.
///
/// [EvidenceContext] remains the canonical evidence declaration. This value
/// carries the consent and assignment snapshot that widgets must never build.
final class LearningEventContext {
  const LearningEventContext({
    this.schemaVersion = currentSchemaVersion,
    required this.consentContext,
    required this.experimentContext,
    required this.protocolId,
    required this.protocolVersion,
    required this.experimentVersion,
    required this.assignmentId,
    required this.featureContractIdentity,
  });

  factory LearningEventContext.noResearch(EvidenceContext evidenceContext) {
    return LearningEventContext(
      consentContext: const ConsentContext.none(),
      experimentContext: null,
      protocolId: null,
      protocolVersion: null,
      experimentVersion: null,
      assignmentId: null,
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }

  /// Reconstructs the provider-owned snapshot available in a persisted event.
  /// Provider-only identifiers are retained in the complete evidence payload
  /// because the frozen envelope has no dedicated fields for them.
  factory LearningEventContext.fromEvidenceEnvelope({
    required EventEnvelopeV2 envelope,
    required EvidenceContext evidenceContext,
  }) {
    return LearningEventContext(
      consentContext: envelope.consentContext,
      experimentContext: envelope.experimentContext,
      protocolId: evidenceContext.protocolId,
      protocolVersion: evidenceContext.protocolVersion,
      experimentVersion: evidenceContext.experimentVersion,
      assignmentId: evidenceContext.assignmentId,
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final ConsentContext consentContext;
  final ExperimentContext? experimentContext;
  final String? protocolId;
  final String? protocolVersion;
  final int? experimentVersion;
  final String? assignmentId;
  final FeatureContractIdentity featureContractIdentity;

  void validateAgainst({
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) {
    evidenceContext.validate();
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'occurredAtUtc', 'must be UTC');
    }
    if (schemaVersion != currentSchemaVersion) {
      throw StateError('unsupported learning-event context version');
    }
    if (featureContractIdentity.revision !=
            evidenceContext.featureContractRevision ||
        featureContractIdentity.semanticHash !=
            evidenceContext.featureContractHash) {
      throw StateError('learning-event feature contract does not match');
    }

    final researchRequired =
        evidenceContext.rolloutMode != EvidencePolicyRolloutMode.legacy ||
        evidenceContext.evidenceClass == EvidenceClass.assessment;
    if (!researchRequired) {
      if (consentContext.researchConsentVersion != 0 ||
          experimentContext != null ||
          protocolId != null ||
          protocolVersion != null ||
          experimentVersion != null ||
          assignmentId != null ||
          evidenceContext.protocolId != null ||
          evidenceContext.protocolVersion != null ||
          evidenceContext.experimentId != null ||
          evidenceContext.experimentVersion != null ||
          evidenceContext.assignmentId != null ||
          evidenceContext.cohort != null ||
          evidenceContext.researchConsentVersion != null) {
        throw StateError('legacy evidence must use no-research context');
      }
      return;
    }

    final experiment = experimentContext;
    if (consentContext.researchConsentVersion <= 0 ||
        consentContext.researchConsentVersion !=
            evidenceContext.researchConsentVersion) {
      throw StateError('research consent snapshot does not match evidence');
    }
    if (experiment == null ||
        experiment.experimentId != evidenceContext.experimentId ||
        experiment.variantId != evidenceContext.cohort) {
      throw StateError('experiment assignment does not match evidence');
    }
    if (!experiment.assignedAtUtc.isUtc ||
        experiment.assignedAtUtc.isAfter(occurredAtUtc)) {
      throw StateError('experiment assignment time is invalid');
    }
    if (protocolId == null || protocolId != evidenceContext.protocolId) {
      throw StateError('protocol id does not match evidence');
    }
    if (protocolVersion == null ||
        protocolVersion != evidenceContext.protocolVersion) {
      throw StateError('protocol version does not match evidence');
    }
    if (experimentVersion == null ||
        experimentVersion != evidenceContext.experimentVersion) {
      throw StateError('experiment version does not match evidence');
    }
    if (assignmentId == null || assignmentId != evidenceContext.assignmentId) {
      throw StateError('assignment id does not match evidence');
    }
  }
}

/// Resolves the provider-owned context for an immutable evidence occurrence.
abstract interface class LearningEventContextProvider {
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  });
}

/// Safe pre-assignment provider used until persisted research state exists.
///
/// It permits only non-assessment Legacy evidence and always emits an
/// explicit no-research snapshot. Research-capable modes fail closed.
final class BaselineLearningEventContextProvider
    implements LearningEventContextProvider {
  const BaselineLearningEventContextProvider();

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    if (ownerId.trim() != ownerId || ownerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'invalid identifier');
    }
    evidenceContext.validate();
    if (evidenceContext.rolloutMode != EvidencePolicyRolloutMode.legacy ||
        evidenceContext.evidenceClass == EvidenceClass.assessment) {
      throw StateError('persisted research context is unavailable');
    }
    final result = LearningEventContext.noResearch(evidenceContext);
    result.validateAgainst(
      evidenceContext: evidenceContext,
      occurredAtUtc: occurredAtUtc,
    );
    return result;
  }
}
