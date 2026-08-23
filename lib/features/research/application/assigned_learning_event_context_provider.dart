import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../../runtime/registries/consent_registry.dart';
import '../../../runtime/registries/experiment_registry.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/application/current_activity_evidence.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/evidence_policy_rollout.dart';
import '../../learning/domain/learning_event_context.dart';
import '../domain/experiment_assignment.dart' as research;
import '../domain/research_protocol_mode_catalog.dart';

export '../domain/research_protocol_mode_catalog.dart';

/// Resolves rollout only from immutable persisted assignment and consent.
///
/// Any unavailable, malformed, ambiguous, or withdrawn research state returns
/// Legacy. This provider is read-only and has no feature-flag or assignment
/// creation dependency.
final class PersistedEvidencePolicyRolloutModeProvider
    implements EvidencePolicyRolloutModeProvider {
  const PersistedEvidencePolicyRolloutModeProvider({
    required this.experimentRegistry,
    required this.consentRegistry,
    required this.protocolModeCatalog,
    this.currentActivityResearchStateProvider,
  });

  final ExperimentRegistry experimentRegistry;
  final ConsentRegistry consentRegistry;
  final ResearchProtocolModeCatalog protocolModeCatalog;
  final AssignedLearningEventContextProvider?
  currentActivityResearchStateProvider;

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) async {
    if (!_isCanonical(ownerId)) {
      return EvidencePolicyRolloutMode.legacy;
    }

    if (evidenceContext == null) {
      final provider =
          currentActivityResearchStateProvider ??
          AssignedLearningEventContextProvider(
            experimentRegistry: experimentRegistry,
            consentRegistry: consentRegistry,
            protocolModeCatalog: protocolModeCatalog,
          );
      final state = await provider._resolvePersistedActivityState(
        ownerId: ownerId,
      );
      return state?.mode ?? EvidencePolicyRolloutMode.legacy;
    }

    try {
      evidenceContext.validate();
      final experimentId = evidenceContext.experimentId;
      final experimentVersion = evidenceContext.experimentVersion;
      final protocolVersion = evidenceContext.protocolVersion;
      final consentVersion = evidenceContext.researchConsentVersion;
      final assignmentId = evidenceContext.assignmentId;
      final cohort = evidenceContext.cohort;
      if (experimentId == null ||
          experimentVersion == null ||
          protocolVersion == null ||
          consentVersion == null ||
          assignmentId == null ||
          cohort == null) {
        return EvidencePolicyRolloutMode.legacy;
      }

      final mapping = protocolModeCatalog.lookup(
        protocolId: evidenceContext.protocolId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
        protocolVersion: protocolVersion,
        consentVersion: consentVersion,
      );
      if (mapping == null) return EvidencePolicyRolloutMode.legacy;

      final assignment = await experimentRegistry.getAssignment(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
      );
      if (assignment == null) return EvidencePolicyRolloutMode.legacy;
      final assignmentIdentityMatches = await _matchesAssignmentIdentity(
        registry: experimentRegistry,
        assignment: assignment,
        candidateAssignmentId: assignmentId,
      );
      if (assignment.ownerId != ownerId ||
          assignment.experimentId != experimentId ||
          assignment.experimentVersion != experimentVersion ||
          assignment.protocolVersion != protocolVersion ||
          !assignmentIdentityMatches ||
          assignment.cohort != cohort ||
          !assignment.assignedAtUtc.isUtc ||
          assignment.assignedAtUtc.millisecondsSinceEpoch < 0) {
        return EvidencePolicyRolloutMode.legacy;
      }

      final consent = await consentRegistry.snapshot(
        purpose: ConsentPurpose.researchDataUpload,
        ownerId: ownerId,
        consentVersion: consentVersion,
      );
      final decisionUtc = consent.decisionUtc;
      if (consent.purpose != ConsentPurpose.researchDataUpload ||
          consent.ownerId != ownerId ||
          consent.consentVersion != consentVersion ||
          consent.state != ConsentState.granted ||
          decisionUtc == null ||
          !decisionUtc.isUtc ||
          decisionUtc.millisecondsSinceEpoch < 0 ||
          decisionUtc.isAfter(assignment.assignedAtUtc) ||
          consent.withdrawalUtc != null) {
        return EvidencePolicyRolloutMode.legacy;
      }
      return mapping.mode;
    } on Object {
      return EvidencePolicyRolloutMode.legacy;
    }
  }
}

final class AssignedLearningEventContextProvider
    implements CurrentActivityResearchStateProvider {
  const AssignedLearningEventContextProvider({
    required this.experimentRegistry,
    required this.consentRegistry,
    this.protocolModeCatalog,
  });

  final ExperimentRegistry experimentRegistry;
  final ConsentRegistry consentRegistry;
  final ResearchProtocolModeCatalog? protocolModeCatalog;

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    if (!_isCanonical(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId', 'invalid identifier');
    }
    if (!occurredAtUtc.isUtc || occurredAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        occurredAtUtc,
        'occurredAtUtc',
        'must be UTC and not before the Unix epoch',
      );
    }
    if (rolloutMode == EvidencePolicyRolloutMode.legacy) {
      return const CurrentActivityResearchSnapshot.legacyCompatibility();
    }
    final state = await _resolvePersistedActivityState(
      ownerId: ownerId,
      occurredAtUtc: occurredAtUtc,
    );
    if (state == null || state.mode != rolloutMode) {
      throw StateError(
        'Exact persisted current-activity research state is unavailable.',
      );
    }
    return state.snapshot;
  }

  Future<_ResolvedCurrentActivityResearchState?>
  _resolvePersistedActivityState({
    required String ownerId,
    DateTime? occurredAtUtc,
  }) async {
    if (!_isCanonical(ownerId)) return null;
    if (occurredAtUtc != null &&
        (!occurredAtUtc.isUtc || occurredAtUtc.millisecondsSinceEpoch < 0)) {
      return null;
    }
    final catalog = protocolModeCatalog;
    if (catalog == null || catalog.isEmpty) return null;

    try {
      final assignments = await experimentRegistry.listAssignments(
        ownerId: ownerId,
      );
      if (assignments.length != 1) return null;
      final assignment = assignments.single;
      final mapping = catalog.lookupForAssignment(
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
        protocolVersion: assignment.protocolVersion,
      );
      final protocolId = mapping?.protocolId;
      if (mapping == null ||
          mapping.mode == EvidencePolicyRolloutMode.legacy ||
          protocolId == null) {
        return null;
      }
      final consent = await consentRegistry.snapshot(
        purpose: ConsentPurpose.researchDataUpload,
        ownerId: ownerId,
        consentVersion: mapping.consentVersion,
      );
      final decisionUtc = consent.decisionUtc;
      if (assignment.ownerId != ownerId ||
          !assignment.assignedAtUtc.isUtc ||
          assignment.assignedAtUtc.millisecondsSinceEpoch < 0 ||
          (occurredAtUtc != null &&
              assignment.assignedAtUtc.isAfter(occurredAtUtc)) ||
          consent.purpose != ConsentPurpose.researchDataUpload ||
          consent.ownerId != ownerId ||
          consent.consentVersion != mapping.consentVersion ||
          consent.state != ConsentState.granted ||
          decisionUtc == null ||
          !decisionUtc.isUtc ||
          decisionUtc.millisecondsSinceEpoch < 0 ||
          decisionUtc.isAfter(assignment.assignedAtUtc) ||
          consent.withdrawalUtc != null) {
        return null;
      }
      return _ResolvedCurrentActivityResearchState(
        mode: mapping.mode,
        snapshot: CurrentActivityResearchSnapshot(
          engagementAllowed: true,
          consentContext: ConsentContext(
            aiConsentGranted: false,
            researchConsentVersion: mapping.consentVersion,
            voiceConsentGranted: false,
            socialConsentGranted: false,
          ),
          experimentContext: ExperimentContext(
            experimentId: assignment.experimentId,
            variantId: assignment.cohort,
            assignedAtUtc: assignment.assignedAtUtc,
          ),
          protocolId: protocolId,
          protocolVersion: assignment.protocolVersion,
          experimentVersion: assignment.experimentVersion,
          assignmentId: assignment.id,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    if (!_isCanonical(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId', 'invalid identifier');
    }
    if (!occurredAtUtc.isUtc || occurredAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        occurredAtUtc,
        'occurredAtUtc',
        'must be UTC and not before the Unix epoch',
      );
    }
    evidenceContext.validate();

    if (evidenceContext.rolloutMode == EvidencePolicyRolloutMode.legacy &&
        evidenceContext.evidenceClass != EvidenceClass.assessment) {
      final context = LearningEventContext.noResearch(evidenceContext);
      context.validateAgainst(
        evidenceContext: evidenceContext,
        occurredAtUtc: occurredAtUtc,
      );
      return context;
    }

    final experimentId = evidenceContext.experimentId!;
    final experimentVersion = evidenceContext.experimentVersion!;
    final consentVersion = evidenceContext.researchConsentVersion!;
    final catalog = protocolModeCatalog;
    if (catalog != null) {
      final mapping = catalog.lookup(
        protocolId: evidenceContext.protocolId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
        protocolVersion: evidenceContext.protocolVersion!,
        consentVersion: consentVersion,
      );
      if (mapping == null || mapping.mode == EvidencePolicyRolloutMode.legacy) {
        throw StateError('Mapped research evidence policy is unavailable.');
      }
    }
    final consent = await consentRegistry.snapshot(
      purpose: ConsentPurpose.researchDataUpload,
      ownerId: ownerId,
      consentVersion: consentVersion,
    );
    final decisionUtc = consent.decisionUtc;
    if (consent.state != ConsentState.granted ||
        decisionUtc == null ||
        !decisionUtc.isUtc ||
        decisionUtc.millisecondsSinceEpoch < 0 ||
        decisionUtc.isAfter(occurredAtUtc) ||
        consent.withdrawalUtc != null) {
      throw StateError('Granted persisted research consent is unavailable.');
    }

    final research.ExperimentAssignment? assignment;
    try {
      assignment = await experimentRegistry.getAssignment(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: experimentVersion,
      );
    } on research.ExperimentAssignmentConflict {
      throw StateError('Persisted experiment assignment conflicts.');
    } on FormatException {
      throw StateError('Persisted experiment assignment is malformed.');
    } on ArgumentError {
      throw StateError('Persisted experiment assignment is malformed.');
    } on StateError {
      throw StateError('Persisted experiment assignment is malformed.');
    }
    if (assignment == null) {
      throw StateError('Exact persisted experiment assignment is unavailable.');
    }
    final assignmentIdentityMatches = await _matchesAssignmentIdentity(
      registry: experimentRegistry,
      assignment: assignment,
      candidateAssignmentId: evidenceContext.assignmentId!,
    );
    if (assignment.ownerId != ownerId ||
        assignment.experimentId != experimentId ||
        assignment.experimentVersion != experimentVersion ||
        !assignmentIdentityMatches ||
        assignment.cohort != evidenceContext.cohort ||
        assignment.protocolVersion != evidenceContext.protocolVersion ||
        !assignment.assignedAtUtc.isUtc ||
        assignment.assignedAtUtc.millisecondsSinceEpoch < 0 ||
        decisionUtc.isAfter(assignment.assignedAtUtc) ||
        assignment.assignedAtUtc.isAfter(occurredAtUtc)) {
      throw StateError('Exact persisted experiment assignment is unavailable.');
    }

    final context = LearningEventContext(
      consentContext: ConsentContext(
        aiConsentGranted: false,
        researchConsentVersion: consentVersion,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: assignment.experimentId,
        variantId: assignment.cohort,
        assignedAtUtc: assignment.assignedAtUtc,
      ),
      protocolId: evidenceContext.protocolId,
      protocolVersion: assignment.protocolVersion,
      experimentVersion: assignment.experimentVersion,
      assignmentId: evidenceContext.assignmentId!,
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
    context.validateAgainst(
      evidenceContext: evidenceContext,
      occurredAtUtc: occurredAtUtc,
    );
    return context;
  }
}

final class _ResolvedCurrentActivityResearchState {
  const _ResolvedCurrentActivityResearchState({
    required this.mode,
    required this.snapshot,
  });

  final EvidencePolicyRolloutMode mode;
  final CurrentActivityResearchSnapshot snapshot;
}

Future<bool> _matchesAssignmentIdentity({
  required ExperimentRegistry registry,
  required research.ExperimentAssignment assignment,
  required String candidateAssignmentId,
}) async {
  if (assignment.id == candidateAssignmentId) return true;
  if (registry is! DriftExperimentRegistry) return false;
  return registry.matchesAssignmentIdentity(
    ownerId: assignment.ownerId,
    experimentId: assignment.experimentId,
    experimentVersion: assignment.experimentVersion,
    candidateAssignmentId: candidateAssignmentId,
  );
}

bool _isCanonical(String value) {
  return value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= EvidenceContext.maxIdentifierLength;
}
