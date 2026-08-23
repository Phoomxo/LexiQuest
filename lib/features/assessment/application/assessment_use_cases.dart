import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../../runtime/app_build_info.dart';
import '../../../runtime/registries/consent_registry.dart';
import '../../../runtime/registries/experiment_registry.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/evidence_policy_rollout.dart';
import '../../research/application/assigned_learning_event_context_provider.dart';
import '../domain/assessment_instrument_catalog.dart';
import '../domain/assessment_models.dart';
import '../domain/assessment_repository.dart';
import 'assessment_comparison.dart';

export 'assessment_comparison.dart';

final class AssessmentUseCases {
  AssessmentUseCases({
    required this.owners,
    required this.repository,
    required this.learning,
    required this.experimentRegistry,
    required this.consentRegistry,
    required this.rolloutModeProvider,
    required this.protocolModeCatalog,
    required this.instrumentCatalog,
    required this.buildInfo,
    required this.databaseSchemaVersion,
    required this.nowUtc,
  }) : _eventContextProvider = AssignedLearningEventContextProvider(
         experimentRegistry: experimentRegistry,
         consentRegistry: consentRegistry,
         protocolModeCatalog: protocolModeCatalog,
       ),
       _comparison = AssessmentComparison(repository, instrumentCatalog);

  final LocalOwnerRepository owners;
  final AssessmentRepository repository;
  final LearningUseCases learning;
  final ExperimentRegistry experimentRegistry;
  final ConsentRegistry consentRegistry;
  final EvidencePolicyRolloutModeProvider rolloutModeProvider;
  final ResearchProtocolModeCatalog protocolModeCatalog;
  final AssessmentInstrumentCatalog instrumentCatalog;
  final AppBuildInfo buildInfo;
  final int databaseSchemaVersion;
  final DateTime Function() nowUtc;
  final AssignedLearningEventContextProvider _eventContextProvider;
  final AssessmentComparison _comparison;

  Future<AssessmentRun> start(AssessmentStartCommand command) async {
    _validateStartCommand(command);
    final definition = instrumentCatalog.lookup(
      instrumentId: command.instrumentId,
      instrumentVersion: command.instrumentVersion,
      formId: command.formId,
      formVersion: command.formVersion,
    );
    final owner = await owners.getOrCreateActiveOwner();
    AssessmentRun.validateCanonicalText(owner.id, 'ownerId');
    final persisted = await _persistedRunOrNull(command.runId);
    if (persisted != null) {
      _requireSameStartIntent(
        command: command,
        ownerId: owner.id,
        definition: definition,
        persisted: persisted,
      );
      return _returnOrRepairPersistedStart(persisted);
    }
    final startedAtUtc = _now();
    final authority = await _resolveAuthority(
      ownerId: owner.id,
      definition: definition,
      atUtc: startedAtUtc,
    );

    final run = AssessmentRun(
      id: command.runId,
      ownerId: owner.id,
      learningSessionId: command.learningSessionId,
      studyCycleId: command.studyCycleId,
      phase: command.phase,
      state: AssessmentRunState.active,
      protocolId: definition.protocolId,
      protocolVersion: authority.assignment.protocolVersion,
      experimentId: definition.experimentId,
      experimentVersion: definition.experimentVersion,
      assignmentId: authority.assignment.id,
      cohort: authority.assignment.cohort,
      consentVersion: authority.mapping.consentVersion,
      consentDecidedAtUtc: authority.consentDecisionUtc,
      instrumentId: definition.instrumentId,
      instrumentVersion: definition.instrumentVersion,
      formId: definition.formId,
      formVersion: definition.formVersion,
      instrumentChecksumSha256: definition.instrumentChecksumSha256,
      formChecksumSha256: definition.formChecksumSha256,
      appVersion: buildInfo.version,
      buildId: buildInfo.buildId,
      databaseSchemaVersion: databaseSchemaVersion,
      contentRevision: definition.contentRevision,
      evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
      featureContractRevision: currentFeatureContractIdentity.revision,
      featureContractHash: currentFeatureContractIdentity.semanticHash,
      startedAtUtc: startedAtUtc,
      completedAtUtc: null,
      abandonedAtUtc: null,
    );
    try {
      return await repository.start(run);
    } on AssessmentRunConflict {
      final durable = await _persistedRunOrNull(command.runId);
      if (durable == null) rethrow;
      _requireSameStartIntent(
        command: command,
        ownerId: owner.id,
        definition: definition,
        persisted: durable,
      );
      return _returnOrRepairPersistedStart(durable);
    } on ArgumentError catch (error) {
      throw StateError('Assessment start references are invalid: $error');
    }
  }

  Future<AssessmentResponseResult> recordResponse({
    required String runId,
    required String sourceEvidenceId,
    required String itemId,
    required Object submittedResponse,
    required int responseTimeMs,
    required DateTime occurredAtUtc,
  }) async {
    if (responseTimeMs < 0 || responseTimeMs > 0x7fffffff) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must be a bounded nonnegative integer',
      );
    }
    if (submittedResponse is! String) {
      throw ArgumentError.value(
        submittedResponse,
        'submittedResponse',
        'must be a controlled catalog response',
      );
    }
    if (submittedResponse.isEmpty ||
        submittedResponse != submittedResponse.trim() ||
        submittedResponse.runes.length > AssessmentRun.maxCanonicalRunes) {
      throw ArgumentError.value(
        submittedResponse,
        'submittedResponse',
        'must be one bounded canonical catalog response',
      );
    }

    return repository.serializeActiveResponse(
      runId: runId,
      occurredAtUtc: occurredAtUtc,
      work: (run) async {
        final definition = instrumentCatalog.lookup(
          instrumentId: run.instrumentId,
          instrumentVersion: run.instrumentVersion,
          formId: run.formId,
          formVersion: run.formVersion,
        );
        _requireCatalogMatchesRun(definition, run);
        await _resolveAuthority(
          ownerId: run.ownerId,
          definition: definition,
          atUtc: occurredAtUtc,
          pinnedRun: run,
        );
        final item = definition.item(itemId);
        final controlled = item.responses[submittedResponse];
        if (controlled == null) {
          throw ArgumentError.value(
            submittedResponse,
            'submittedResponse',
            'is not a controlled response for the pinned assessment item',
          );
        }

        final evidenceContext = EvidenceContext.forNewEvidence(
          evidenceClass: EvidenceClass.assessment,
          skillId: item.wordId,
          hintLevel: 0,
          contentRevision: run.contentRevision,
          rolloutMode: EvidencePolicyRolloutMode.enforced,
          protocolId: run.protocolId,
          protocolVersion: run.protocolVersion,
          experimentId: run.experimentId,
          experimentVersion: run.experimentVersion,
          assignmentId: run.assignmentId,
          cohort: run.cohort,
          researchConsentVersion: run.consentVersion,
          instrumentId: run.instrumentId,
          instrumentVersion: run.instrumentVersion,
          formId: run.formId,
          formVersion: run.formVersion,
          assessmentItemId: item.itemId,
          assessmentResponseCode: controlled.responseCode,
          scoringRuleVersion: item.scoringRuleVersion,
          engagementAllowed: false,
        );
        if (evidenceContext.policyVersion != run.evidencePolicyVersion ||
            evidenceContext.featureContractRevision !=
                run.featureContractRevision ||
            evidenceContext.featureContractHash != run.featureContractHash) {
          throw StateError(
            'Pinned assessment evidence policy is no longer supported.',
          );
        }

        final resolved = await learning.resolveEvidenceForRecording(
          command: FrozenLearningEvidenceCommand(
            sourceEvidenceId: sourceEvidenceId,
            occurredAtUtc: occurredAtUtc,
            sessionId: run.learningSessionId,
            wordId: item.wordId,
            promptMode: item.promptMode,
            isCorrect: controlled.isCorrect,
            responseTimeMs: responseTimeMs,
            attemptNumber: 1,
            providerProvenance: 'assessmentCatalog',
          ),
          resolveContexts:
              ({
                required String ownerId,
                required FrozenLearningEvidenceCommand command,
              }) async {
                if (ownerId != run.ownerId) {
                  throw StateError(
                    'Active owner changed during assessment write.',
                  );
                }
                return ResolvedLearningEvidenceContexts(
                  evidenceContext: evidenceContext,
                  eventContext: await _eventContextProvider.resolve(
                    ownerId: ownerId,
                    evidenceContext: evidenceContext,
                    occurredAtUtc: command.occurredAtUtc,
                  ),
                );
              },
        );
        final result = await learning.recordResolvedEvidence(resolved);
        return AssessmentResponseResult(
          sourceEvidenceId: sourceEvidenceId,
          responseCode: controlled.responseCode,
          isCorrect: controlled.isCorrect,
          inserted: result.inserted,
        );
      },
    );
  }

  Future<AssessmentRun> complete(String runId) async {
    final persisted = await repository.getRun(runId);
    if (persisted.state == AssessmentRunState.completed) {
      return repository.complete(
        runId: runId,
        completedAtUtc: persisted.completedAtUtc!,
      );
    }
    if (persisted.state != AssessmentRunState.active) {
      throw AssessmentRunConflict(
        runId: runId,
        reason: 'terminal assessment state cannot change',
      );
    }
    try {
      return await repository.complete(runId: runId, completedAtUtc: _now());
    } on AssessmentRunConflict {
      final durable = await repository.getRun(runId);
      if (durable.state != AssessmentRunState.completed) rethrow;
      return repository.complete(
        runId: runId,
        completedAtUtc: durable.completedAtUtc!,
      );
    }
  }

  Future<AssessmentRun> abandon(String runId) async {
    final persisted = await repository.getRun(runId);
    if (persisted.state == AssessmentRunState.abandoned) {
      return repository.abandon(
        runId: runId,
        abandonedAtUtc: persisted.abandonedAtUtc!,
      );
    }
    if (persisted.state != AssessmentRunState.active) {
      throw AssessmentRunConflict(
        runId: runId,
        reason: 'terminal assessment state cannot change',
      );
    }
    try {
      return await repository.abandon(runId: runId, abandonedAtUtc: _now());
    } on AssessmentRunConflict {
      final durable = await repository.getRun(runId);
      if (durable.state != AssessmentRunState.abandoned) rethrow;
      return repository.abandon(
        runId: runId,
        abandonedAtUtc: durable.abandonedAtUtc!,
      );
    }
  }

  Future<AssessmentComparisonResult> compare(String studyCycleId) async {
    AssessmentRun.validateCanonicalText(studyCycleId, 'studyCycleId');
    final owner = await owners.getOrCreateActiveOwner();
    AssessmentRun.validateCanonicalText(owner.id, 'ownerId');
    return _comparison.compare(ownerId: owner.id, studyCycleId: studyCycleId);
  }

  Future<_ResolvedAssessmentAuthority> _resolveAuthority({
    required String ownerId,
    required AssessmentInstrumentDefinition definition,
    required DateTime atUtc,
    AssessmentRun? pinnedRun,
  }) async {
    final ExperimentAssignment? assignment;
    try {
      assignment = await experimentRegistry.getAssignment(
        ownerId: ownerId,
        experimentId: definition.experimentId,
        experimentVersion: definition.experimentVersion,
      );
    } on Object {
      throw StateError('Persisted assessment assignment conflicts.');
    }
    final registry = experimentRegistry;
    final bool identityMatches;
    try {
      identityMatches =
          assignment != null &&
          registry is DriftExperimentRegistry &&
          await registry.matchesAssignmentIdentity(
            ownerId: ownerId,
            experimentId: definition.experimentId,
            experimentVersion: definition.experimentVersion,
            candidateAssignmentId: assignment.id,
          );
    } on Object {
      throw StateError('Persisted assessment assignment identity conflicts.');
    }
    if (assignment == null || !identityMatches) {
      throw StateError('Exact persisted assessment assignment is unavailable.');
    }
    final mapping = protocolModeCatalog.lookupForAssignment(
      experimentId: assignment.experimentId,
      experimentVersion: assignment.experimentVersion,
      protocolVersion: assignment.protocolVersion,
    );
    if (mapping == null ||
        mapping.protocolId != definition.protocolId ||
        mapping.mode != EvidencePolicyRolloutMode.enforced) {
      throw StateError('Assessment protocol is not Enforced and exact.');
    }
    final consent = await consentRegistry.snapshot(
      purpose: ConsentPurpose.researchDataUpload,
      ownerId: ownerId,
      consentVersion: mapping.consentVersion,
    );
    final decisionUtc = consent.decisionUtc;
    if (consent.purpose != ConsentPurpose.researchDataUpload ||
        consent.ownerId != ownerId ||
        consent.consentVersion != mapping.consentVersion ||
        consent.state != ConsentState.granted ||
        decisionUtc == null ||
        !decisionUtc.isUtc ||
        decisionUtc.millisecondsSinceEpoch < 0 ||
        consent.withdrawalUtc != null ||
        !assignment.assignedAtUtc.isUtc ||
        assignment.assignedAtUtc.millisecondsSinceEpoch < 0 ||
        decisionUtc.isAfter(assignment.assignedAtUtc) ||
        assignment.assignedAtUtc.isAfter(atUtc)) {
      throw StateError('Exact assessment consent is unavailable.');
    }
    final rollout = await rolloutModeProvider.resolve(
      ownerId: ownerId,
      evidenceContext: null,
    );
    if (rollout != EvidencePolicyRolloutMode.enforced) {
      throw StateError('Assessment requires Enforced evidence rollout.');
    }

    final run = pinnedRun;
    if (run != null &&
        (run.ownerId != ownerId ||
            run.protocolId != definition.protocolId ||
            run.protocolVersion != assignment.protocolVersion ||
            run.experimentId != assignment.experimentId ||
            run.experimentVersion != assignment.experimentVersion ||
            run.assignmentId != assignment.id ||
            run.cohort != assignment.cohort ||
            run.consentVersion != mapping.consentVersion ||
            run.consentDecidedAtUtc != decisionUtc)) {
      throw StateError('Persisted assessment authority differs from run pins.');
    }
    return _ResolvedAssessmentAuthority(
      assignment: assignment,
      mapping: mapping,
      consentDecisionUtc: decisionUtc,
    );
  }

  void _validateStartCommand(AssessmentStartCommand command) {
    AssessmentRun.validateRunId(command.runId);
    for (final entry in <String, String>{
      'learningSessionId': command.learningSessionId,
      'studyCycleId': command.studyCycleId,
      'instrumentId': command.instrumentId,
      'instrumentVersion': command.instrumentVersion,
      'formId': command.formId,
      'formVersion': command.formVersion,
      'appVersion': buildInfo.version,
      'buildId': buildInfo.buildId,
    }.entries) {
      AssessmentRun.validateCanonicalText(entry.value, entry.key);
    }
    if (databaseSchemaVersion <= 0) {
      throw ArgumentError.value(
        databaseSchemaVersion,
        'databaseSchemaVersion',
        'must be positive',
      );
    }
  }

  void _requireCatalogMatchesRun(
    AssessmentInstrumentDefinition definition,
    AssessmentRun run,
  ) {
    if (definition.instrumentId != run.instrumentId ||
        definition.instrumentVersion != run.instrumentVersion ||
        definition.formId != run.formId ||
        definition.formVersion != run.formVersion ||
        definition.protocolId != run.protocolId ||
        definition.experimentId != run.experimentId ||
        definition.experimentVersion != run.experimentVersion ||
        definition.contentRevision != run.contentRevision ||
        definition.instrumentChecksumSha256 != run.instrumentChecksumSha256 ||
        definition.formChecksumSha256 != run.formChecksumSha256) {
      throw const AssessmentCatalogException(
        'Assessment catalog no longer matches immutable run pins.',
      );
    }
  }

  Future<AssessmentRun?> _persistedRunOrNull(String runId) async {
    try {
      return await repository.getRun(runId);
    } on AssessmentRunConflict catch (error) {
      if (error.runId == runId &&
          error.reason == 'assessment run does not exist') {
        return null;
      }
      rethrow;
    }
  }

  void _requireSameStartIntent({
    required AssessmentStartCommand command,
    required String ownerId,
    required AssessmentInstrumentDefinition definition,
    required AssessmentRun persisted,
  }) {
    try {
      _requireCatalogMatchesRun(definition, persisted);
    } on AssessmentCatalogException {
      throw AssessmentRunConflict(
        runId: command.runId,
        reason: 'run id is bound to a different assessment start intent',
      );
    }
    final sameIntent =
        persisted.id == command.runId &&
        persisted.ownerId == ownerId &&
        persisted.learningSessionId == command.learningSessionId &&
        persisted.studyCycleId == command.studyCycleId &&
        persisted.phase == command.phase &&
        persisted.appVersion == buildInfo.version &&
        persisted.buildId == buildInfo.buildId &&
        persisted.databaseSchemaVersion == databaseSchemaVersion &&
        persisted.evidencePolicyVersion ==
            EvidenceContext.currentPolicyVersion &&
        persisted.featureContractRevision ==
            currentFeatureContractIdentity.revision &&
        persisted.featureContractHash ==
            currentFeatureContractIdentity.semanticHash;
    if (!sameIntent) {
      throw AssessmentRunConflict(
        runId: command.runId,
        reason: 'run id is bound to a different assessment start intent',
      );
    }
  }

  Future<AssessmentRun> _returnOrRepairPersistedStart(
    AssessmentRun persisted,
  ) async {
    if (persisted.state != AssessmentRunState.active) return persisted;
    try {
      return await repository.start(persisted);
    } on ArgumentError catch (error) {
      throw StateError('Assessment start references are invalid: $error');
    }
  }

  DateTime _now() {
    final value = nowUtc();
    AssessmentRun.validateUtcTimestamp(value, 'nowUtc');
    return value;
  }
}

final class _ResolvedAssessmentAuthority {
  const _ResolvedAssessmentAuthority({
    required this.assignment,
    required this.mapping,
    required this.consentDecisionUtc,
  });

  final ExperimentAssignment assignment;
  final ResearchProtocolModeMapping mapping;
  final DateTime consentDecisionUtc;
}
