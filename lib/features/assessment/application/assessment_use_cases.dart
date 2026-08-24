import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../../runtime/app_build_info.dart';
import '../../../runtime/registries/consent_registry.dart';
import '../../../runtime/registries/experiment_registry.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/evidence_policy_rollout.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../research/application/assigned_learning_event_context_provider.dart';
import '../../time_tracking/application/active_learning_time_controller.dart';
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
    this.contentManifests,
    this.createActiveLearningTimeController,
    required this.buildInfo,
    required this.databaseSchemaVersion,
    required this.nowUtc,
  }) : _eventContextProvider = AssignedLearningEventContextProvider(
         experimentRegistry: experimentRegistry,
         consentRegistry: consentRegistry,
         protocolModeCatalog: protocolModeCatalog,
       ),
       _comparison = AssessmentComparison(
         repository,
         instrumentCatalog,
         contentManifests,
       );

  final LocalOwnerRepository owners;
  final AssessmentRepository repository;
  final LearningUseCases learning;
  final ExperimentRegistry experimentRegistry;
  final ConsentRegistry consentRegistry;
  final EvidencePolicyRolloutModeProvider rolloutModeProvider;
  final ResearchProtocolModeCatalog protocolModeCatalog;
  final AssessmentInstrumentCatalog instrumentCatalog;
  final ContentManifestRepository? contentManifests;
  final ActiveLearningTimeControllerFactory? createActiveLearningTimeController;
  final AppBuildInfo buildInfo;
  final int databaseSchemaVersion;
  final DateTime Function() nowUtc;
  final AssignedLearningEventContextProvider _eventContextProvider;
  final AssessmentComparison _comparison;
  final Map<String, _ActiveAssessmentPresentation> _presentations = {};
  final Map<String, bool> _presentationForeground = {};
  Future<void> _presentationMutationTail = Future<void>.value();

  Future<AssessmentRun> start(AssessmentStartCommand command) async {
    _validateStartCommand(command);
    final definition = instrumentCatalog.lookup(
      instrumentId: command.instrumentId,
      instrumentVersion: command.instrumentVersion,
      formId: command.formId,
      formVersion: command.formVersion,
    );
    await requireVerifiedAssessmentForm(
      definition: definition,
      manifests: contentManifests,
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
        await requireVerifiedAssessmentForm(
          definition: definition,
          manifests: contentManifests,
        );
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
    return _completeAt(runId, null);
  }

  Future<AssessmentRun> _completeAt(
    String runId,
    DateTime? completedAtUtc,
  ) async {
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
    final transitionAtUtc = completedAtUtc ?? _now();
    final definition = instrumentCatalog.lookup(
      instrumentId: persisted.instrumentId,
      instrumentVersion: persisted.instrumentVersion,
      formId: persisted.formId,
      formVersion: persisted.formVersion,
    );
    _requireCatalogMatchesRun(definition, persisted);
    final authorityLease = await _resolveAuthority(
      ownerId: persisted.ownerId,
      definition: definition,
      atUtc: transitionAtUtc,
      pinnedRun: persisted,
    );
    try {
      return await repository.complete(
        runId: runId,
        completedAtUtc: transitionAtUtc,
        authorityGuard: (activeRun) => _validateAuthorityLease(
          lease: authorityLease,
          run: activeRun,
          definition: definition,
          atUtc: transitionAtUtc,
        ),
      );
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
    return _abandonAt(runId, null);
  }

  Future<AssessmentRun> _abandonAt(
    String runId,
    DateTime? abandonedAtUtc,
  ) async {
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
      return await repository.abandon(
        runId: runId,
        abandonedAtUtc: abandonedAtUtc ?? _now(),
      );
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
    try {
      AssessmentRun.validateCanonicalText(studyCycleId, 'studyCycleId');
      final owner = await owners.getOrCreateActiveOwner();
      AssessmentRun.validateCanonicalText(owner.id, 'ownerId');
      final comparedAtUtc = _now();
      final runs = await repository.listRunsForStudyCycle(
        ownerId: owner.id,
        studyCycleId: studyCycleId,
      );
      final completedPre = runs
          .where(
            (run) =>
                run.phase == AssessmentPhase.pre &&
                run.state == AssessmentRunState.completed,
          )
          .toList(growable: false);
      final completedPost = runs
          .where(
            (run) =>
                run.phase == AssessmentPhase.post &&
                run.state == AssessmentRunState.completed,
          )
          .toList(growable: false);
      if (completedPre.length == 1 && completedPost.length == 1) {
        for (final run in <AssessmentRun>[
          completedPre.single,
          completedPost.single,
        ]) {
          final definition = instrumentCatalog.lookup(
            instrumentId: run.instrumentId,
            instrumentVersion: run.instrumentVersion,
            formId: run.formId,
            formVersion: run.formVersion,
          );
          _requireCatalogMatchesRun(definition, run);
          await _resolveAuthority(
            ownerId: owner.id,
            definition: definition,
            atUtc: comparedAtUtc,
            pinnedRun: run,
          );
        }
      }
      return _comparison.compare(
        ownerId: owner.id,
        studyCycleId: studyCycleId,
        comparedAtUtc: comparedAtUtc,
      );
    } on Object {
      return const AssessmentComparisonIncompatibleMetadata();
    }
  }

  Future<AssessmentPresentation> beginPresentation(
    AssessmentStartCommand command,
  ) => _serializePresentation(() async {
    final existing = _presentations[command.runId];
    if (existing != null) {
      _requireSamePresentationCommand(existing.run, command);
      await requireVerifiedAssessmentForm(
        definition: existing.definition,
        manifests: contentManifests,
      );
      await _resolveAuthority(
        ownerId: existing.run.ownerId,
        definition: existing.definition,
        atUtc: _now(),
        pinnedRun: existing.run,
      );
      return existing.presentation;
    }
    final factory = createActiveLearningTimeController;
    if (factory == null) {
      throw StateError('Trustworthy assessment active time is unavailable.');
    }
    var timeAuthority = factory();
    try {
      final run = await start(command);
      if (run.state != AssessmentRunState.active) {
        throw StateError('A terminal assessment run cannot be presented.');
      }
      final definition = instrumentCatalog.lookup(
        instrumentId: run.instrumentId,
        instrumentVersion: run.instrumentVersion,
        formId: run.formId,
        formVersion: run.formVersion,
      );
      _requireCatalogMatchesRun(definition, run);
      final evidence = await repository.listOutcomeEvidence(
        ownerId: run.ownerId,
        learningSessionId: run.learningSessionId,
      );
      final captureAtUtc = _now();
      await _resolveAuthority(
        ownerId: run.ownerId,
        definition: definition,
        atUtc: captureAtUtc,
        pinnedRun: run,
      );
      final recovered = _recoverPresentationEvidence(
        run: run,
        definition: definition,
        evidence: evidence,
      );
      if (captureAtUtc.isBefore(recovered.latestEvidenceAtUtc)) {
        throw StateError('Assessment clock precedes persisted evidence.');
      }
      await timeAuthority.start(
        sessionId: run.learningSessionId,
        occurredAtUtc: captureAtUtc,
      );
      final wantsForeground = _presentationForeground[run.id] ?? true;
      if (!wantsForeground) {
        timeAuthority.dispose();
        timeAuthority = factory();
      }
      final active = _ActiveAssessmentPresentation(
        run: run,
        definition: definition,
        answeredItemIds: recovered.answeredItemIds,
        latestEvidenceAtUtc: recovered.latestEvidenceAtUtc,
        timeAuthority: timeAuthority,
        wantsForeground: wantsForeground,
      );
      _presentations[run.id] = active;
      return active.presentation;
    } catch (_) {
      timeAuthority.dispose();
      rethrow;
    }
  });

  Future<void> setPresentationForeground({
    required String runId,
    required bool isForeground,
  }) {
    AssessmentRun.validateRunId(runId);
    final occurredAtUtc = _now();
    _presentationForeground[runId] = isForeground;
    final observedPresentation = _presentations[runId];
    final observedAuthority = observedPresentation?.timeAuthority;
    final observation = observedAuthority?.observe(occurredAtUtc);
    if (observedPresentation != null) {
      observedPresentation.wantsForeground = isForeground;
    }
    return _serializePresentation(() async {
      final active = _presentations[runId];
      if (active == null) return;
      active.wantsForeground = _presentationForeground[runId] ?? false;
      final time = active.timeAuthority;
      if (!active.wantsForeground) {
        if (time.state == ActiveLearningTimeState.active) {
          if (identical(time, observedAuthority) && observation != null) {
            await time.pauseObserved(observation);
          } else {
            await time.pause(occurredAtUtc: occurredAtUtc);
          }
        } else if (time.state == ActiveLearningTimeState.idle) {
          await time.pause(occurredAtUtc: occurredAtUtc);
        }
        return;
      }
      _ResolvedAssessmentAuthority? authorityLease;
      if (time.state == ActiveLearningTimeState.inactive ||
          time.state == ActiveLearningTimeState.paused) {
        try {
          authorityLease = await _requireCurrentPresentationAuthority(
            active,
            occurredAtUtc,
          );
        } catch (_) {
          await _fencePresentationAfterAuthorityFailure(active, observation);
          rethrow;
        }
      }
      switch (time.state) {
        case ActiveLearningTimeState.inactive:
          await time.start(
            sessionId: active.run.learningSessionId,
            occurredAtUtc: occurredAtUtc,
          );
        case ActiveLearningTimeState.paused:
          if (identical(time, observedAuthority) && observation != null) {
            await time.resumeObserved(observation);
          } else {
            await time.resume(occurredAtUtc: occurredAtUtc);
          }
        case ActiveLearningTimeState.active ||
            ActiveLearningTimeState.idle ||
            ActiveLearningTimeState.finished:
          return;
      }
      try {
        await _validateAuthorityLease(
          lease: authorityLease!,
          run: active.run,
          definition: active.definition,
          atUtc: occurredAtUtc,
        );
      } catch (_) {
        await _fencePresentationAfterAuthorityFailure(active, observation);
        rethrow;
      }
    });
  }

  Future<AssessmentSubmissionReceipt> submitPresentedResponse({
    required String runId,
    required String itemId,
    required Object submittedResponse,
    required int responseTimeMs,
  }) => _serializePresentation(() async {
    final active = _requirePresentation(runId);
    if (active.answeredItemIds.contains(itemId)) {
      throw StateError('The assessment item already has a response.');
    }
    final item = active.definition.item(itemId);
    if (submittedResponse is! String ||
        item.responses[submittedResponse] == null) {
      throw ArgumentError.value(
        submittedResponse,
        'submittedResponse',
        'must be a controlled response for the pinned assessment item',
      );
    }
    if (responseTimeMs < 0 || responseTimeMs > 0x7fffffff) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must be a bounded nonnegative integer',
      );
    }
    final actionAtUtc = _now();
    final pending = active.pendingResponse;
    if (pending != null &&
        (pending.itemId != itemId ||
            pending.submittedResponse != submittedResponse)) {
      throw StateError('A different assessment response retry is pending.');
    }
    if (pending == null && actionAtUtc.isBefore(active.latestEvidenceAtUtc)) {
      throw StateError('Assessment response clock moved backwards.');
    }
    final authorityObservation = active.timeAuthority.observe(actionAtUtc);
    try {
      await _requireCurrentPresentationAuthority(active, actionAtUtc);
    } catch (_) {
      await _fencePresentationAfterAuthorityFailure(
        active,
        authorityObservation,
      );
      rethrow;
    }
    final frozen =
        pending ??
        _PendingAssessmentResponse(
          sourceEvidenceId: _presentationEvidenceId(runId, itemId),
          itemId: itemId,
          submittedResponse: submittedResponse,
          responseTimeMs: responseTimeMs,
          occurredAtUtc: actionAtUtc,
        );
    active.pendingResponse = frozen;
    await active.timeAuthority.recordInteraction(occurredAtUtc: actionAtUtc);
    try {
      final result = await recordResponse(
        runId: runId,
        sourceEvidenceId: frozen.sourceEvidenceId,
        itemId: frozen.itemId,
        submittedResponse: frozen.submittedResponse,
        responseTimeMs: frozen.responseTimeMs,
        occurredAtUtc: frozen.occurredAtUtc,
      );
      _acceptPendingResponse(active, frozen);
      return AssessmentSubmissionReceipt(
        itemId: frozen.itemId,
        inserted: result.inserted,
      );
    } catch (error, stackTrace) {
      try {
        await _requireCurrentPresentationAuthority(active, actionAtUtc);
      } catch (_) {
        await _fencePresentationAfterAuthorityFailure(
          active,
          authorityObservation,
        );
      }
      try {
        final reconciled = await _reconcilePendingResponse(active, frozen);
        if (reconciled != null) return reconciled;
      } on Object {
        // Preserve the write failure and the exact pending retry identity.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  });

  Future<void> pausePresentation(String runId) =>
      setPresentationForeground(runId: runId, isForeground: false);

  Future<void> resumePresentation(String runId) =>
      setPresentationForeground(runId: runId, isForeground: true);

  Future<AssessmentPresentationCompletion> completePresentation(String runId) =>
      _serializePresentation(() async {
        final active = _requirePresentation(runId);
        if (active.answeredItemIds.length != active.definition.items.length) {
          throw StateError('Every pinned assessment item requires a response.');
        }
        final terminalAtUtc = _now();
        if (terminalAtUtc.isBefore(active.latestEvidenceAtUtc)) {
          throw StateError('Assessment completion precedes response evidence.');
        }
        final authorityObservation = active.timeAuthority.observe(
          terminalAtUtc,
        );
        try {
          await _requireCurrentPresentationAuthority(active, terminalAtUtc);
        } catch (_) {
          await _fencePresentationAfterAuthorityFailure(
            active,
            authorityObservation,
          );
          rethrow;
        }
        final previousTimeState = active.timeAuthority.state;
        await active.timeAuthority.finish(occurredAtUtc: terminalAtUtc);
        late final AssessmentRun run;
        try {
          run = await _completeAt(runId, terminalAtUtc);
        } catch (_) {
          await _settleAfterFailedPresentationTerminal(
            active: active,
            previousTimeState: previousTimeState,
          );
          rethrow;
        }
        _presentations.remove(runId);
        _presentationForeground.remove(runId);
        active.timeAuthority.dispose();
        return AssessmentPresentationCompletion(
          run: run,
          comparison: await compare(run.studyCycleId),
        );
      });

  Future<AssessmentRun> abandonPresentation(String runId) =>
      _serializePresentation(() async {
        final active = _requirePresentation(runId);
        final terminalAtUtc = _now();
        if (terminalAtUtc.isBefore(active.latestEvidenceAtUtc)) {
          throw StateError(
            'Assessment abandonment precedes response evidence.',
          );
        }
        final previousTimeState = active.timeAuthority.state;
        await active.timeAuthority.finish(occurredAtUtc: terminalAtUtc);
        try {
          final run = await _abandonAt(runId, terminalAtUtc);
          _presentations.remove(runId);
          _presentationForeground.remove(runId);
          active.timeAuthority.dispose();
          return run;
        } catch (_) {
          await _settleAfterFailedPresentationTerminal(
            active: active,
            previousTimeState: previousTimeState,
          );
          rethrow;
        }
      });

  Future<void> detachPresentation(String runId) =>
      _serializePresentation(() async {
        final active = _presentations[runId];
        if (active == null) {
          _presentationForeground.remove(runId);
          return;
        }
        if (active.timeAuthority.state == ActiveLearningTimeState.active) {
          await active.timeAuthority.pause(occurredAtUtc: _now());
        }
        _presentations.remove(runId);
        _presentationForeground.remove(runId);
        active.timeAuthority.dispose();
      });

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

  Future<_ResolvedAssessmentAuthority> _requireCurrentPresentationAuthority(
    _ActiveAssessmentPresentation active,
    DateTime atUtc,
  ) => _resolveAuthority(
    ownerId: active.run.ownerId,
    definition: active.definition,
    atUtc: atUtc,
    pinnedRun: active.run,
  );

  Future<void> _validateAuthorityLease({
    required _ResolvedAssessmentAuthority lease,
    required AssessmentRun run,
    required AssessmentInstrumentDefinition definition,
    required DateTime atUtc,
  }) async {
    final current = await _resolveAuthority(
      ownerId: run.ownerId,
      definition: definition,
      atUtc: atUtc,
      pinnedRun: run,
    );
    if (!lease.sameIdentityAs(current)) {
      throw StateError('Assessment authority changed during mutation.');
    }
  }

  Future<void> _fencePresentationAfterAuthorityFailure(
    _ActiveAssessmentPresentation active,
    LearningTimeObservation? observation,
  ) async {
    active.wantsForeground = false;
    _presentationForeground[active.run.id] = false;
    final time = active.timeAuthority;
    if (time.state == ActiveLearningTimeState.active) {
      if (observation != null) {
        await time.pauseObserved(observation);
      } else {
        await time.pause(occurredAtUtc: _now());
      }
    } else if (time.state == ActiveLearningTimeState.idle) {
      if (observation != null) {
        await time.pauseObserved(observation);
      } else {
        await time.pause(occurredAtUtc: _now());
      }
    }
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

  _RecoveredPresentationEvidence _recoverPresentationEvidence({
    required AssessmentRun run,
    required AssessmentInstrumentDefinition definition,
    required List<AssessmentOutcomeEvidence> evidence,
  }) {
    final answered = <String>{};
    var latestEvidenceAtUtc = run.startedAtUtc;
    for (final outcome in evidence) {
      final context = outcome.evidenceContext;
      final itemId = context.assessmentItemId;
      if (outcome.ownerId != run.ownerId ||
          outcome.learningSessionId != run.learningSessionId ||
          outcome.persistedEvidenceClass != EvidenceClass.assessment.name ||
          context.evidenceClass != EvidenceClass.assessment ||
          context.classificationSource !=
              EvidenceClassificationSource.declared ||
          context.rolloutMode != EvidencePolicyRolloutMode.enforced ||
          context.engagementAllowed ||
          context.protocolId != run.protocolId ||
          context.protocolVersion != run.protocolVersion ||
          context.experimentId != run.experimentId ||
          context.experimentVersion != run.experimentVersion ||
          context.assignmentId != run.assignmentId ||
          context.cohort != run.cohort ||
          context.researchConsentVersion != run.consentVersion ||
          context.instrumentId != run.instrumentId ||
          context.instrumentVersion != run.instrumentVersion ||
          context.formId != run.formId ||
          context.formVersion != run.formVersion ||
          context.contentRevision != run.contentRevision ||
          context.policyVersion != run.evidencePolicyVersion ||
          context.featureContractRevision != run.featureContractRevision ||
          context.featureContractHash != run.featureContractHash ||
          itemId == null ||
          context.assessmentResponseCode == null ||
          context.scoringRuleVersion == null ||
          outcome.occurredAtUtc.isBefore(run.startedAtUtc)) {
        throw StateError('Persisted assessment response is incompatible.');
      }
      final item = definition.item(itemId);
      if (item.wordId != outcome.wordId ||
          item.promptMode != outcome.promptMode ||
          item.scoringRuleVersion != context.scoringRuleVersion ||
          !item.responses.values.any(
            (response) =>
                response.responseCode == context.assessmentResponseCode &&
                response.isCorrect == outcome.isCorrect,
          ) ||
          !answered.add(itemId)) {
        throw StateError('Persisted assessment response is incompatible.');
      }
      if (outcome.occurredAtUtc.isAfter(latestEvidenceAtUtc)) {
        latestEvidenceAtUtc = outcome.occurredAtUtc;
      }
    }
    return _RecoveredPresentationEvidence(
      answeredItemIds: answered,
      latestEvidenceAtUtc: latestEvidenceAtUtc,
    );
  }

  void _acceptPendingResponse(
    _ActiveAssessmentPresentation active,
    _PendingAssessmentResponse pending,
  ) {
    if (!identical(active.pendingResponse, pending)) {
      throw StateError('Assessment response retry identity changed.');
    }
    active.answeredItemIds.add(pending.itemId);
    if (pending.occurredAtUtc.isAfter(active.latestEvidenceAtUtc)) {
      active.latestEvidenceAtUtc = pending.occurredAtUtc;
    }
    active.pendingResponse = null;
  }

  Future<AssessmentSubmissionReceipt?> _reconcilePendingResponse(
    _ActiveAssessmentPresentation active,
    _PendingAssessmentResponse pending,
  ) async {
    if (!identical(active.pendingResponse, pending)) {
      throw StateError('Assessment response retry identity changed.');
    }
    final evidence = await repository.listOutcomeEvidence(
      ownerId: active.run.ownerId,
      learningSessionId: active.run.learningSessionId,
    );
    final recovered = _recoverPresentationEvidence(
      run: active.run,
      definition: active.definition,
      evidence: evidence,
    );
    final matching = evidence
        .where(
          (outcome) => outcome.sourceEvidenceId == pending.sourceEvidenceId,
        )
        .toList(growable: false);
    if (matching.isEmpty) {
      if (recovered.answeredItemIds.contains(pending.itemId)) {
        throw StateError('Assessment item has conflicting durable evidence.');
      }
      return null;
    }
    if (matching.length != 1) {
      throw StateError('Assessment response identity is ambiguous.');
    }
    final outcome = matching.single;
    final controlled = active.definition
        .item(pending.itemId)
        .responses[pending.submittedResponse]!;
    final context = outcome.evidenceContext;
    if (outcome.occurredAtUtc != pending.occurredAtUtc ||
        outcome.responseTimeMs != pending.responseTimeMs ||
        context.assessmentItemId != pending.itemId ||
        context.assessmentResponseCode != controlled.responseCode ||
        outcome.isCorrect != controlled.isCorrect) {
      throw StateError(
        'Assessment response identity has conflicting evidence.',
      );
    }
    active.answeredItemIds
      ..clear()
      ..addAll(recovered.answeredItemIds);
    active.latestEvidenceAtUtc = recovered.latestEvidenceAtUtc;
    active.pendingResponse = null;
    return AssessmentSubmissionReceipt(itemId: pending.itemId, inserted: false);
  }

  _ActiveAssessmentPresentation _requirePresentation(String runId) {
    AssessmentRun.validateRunId(runId);
    final active = _presentations[runId];
    if (active == null) {
      throw StateError('Assessment presentation is not active.');
    }
    return active;
  }

  void _requireSamePresentationCommand(
    AssessmentRun run,
    AssessmentStartCommand command,
  ) {
    if (run.id != command.runId ||
        run.learningSessionId != command.learningSessionId ||
        run.studyCycleId != command.studyCycleId ||
        run.phase != command.phase ||
        run.instrumentId != command.instrumentId ||
        run.instrumentVersion != command.instrumentVersion ||
        run.formId != command.formId ||
        run.formVersion != command.formVersion) {
      throw AssessmentRunConflict(
        runId: command.runId,
        reason: 'active presentation is bound to another start intent',
      );
    }
  }

  Future<T> _serializePresentation<T>(Future<T> Function() work) {
    final result = Completer<T>();
    _presentationMutationTail = _presentationMutationTail.then((_) async {
      try {
        result.complete(await work());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  ActiveLearningTimeState _failClosedRestoreState(
    _ActiveAssessmentPresentation active,
    ActiveLearningTimeState previousState,
  ) {
    if (!active.wantsForeground &&
        (previousState == ActiveLearningTimeState.active ||
            previousState == ActiveLearningTimeState.idle)) {
      return ActiveLearningTimeState.paused;
    }
    return previousState;
  }

  Future<void> _settleAfterFailedPresentationTerminal({
    required _ActiveAssessmentPresentation active,
    required ActiveLearningTimeState previousTimeState,
  }) async {
    late final AssessmentRun durable;
    try {
      durable = await repository.getRun(active.run.id);
    } catch (_) {
      _discardPresentation(active);
      rethrow;
    }
    if (durable.state != AssessmentRunState.active) {
      _discardPresentation(active);
      return;
    }
    try {
      await _requireCurrentPresentationAuthority(active, _now());
    } catch (_) {
      active.wantsForeground = false;
      _presentationForeground[active.run.id] = false;
      await active.timeAuthority.restoreAfterFailedTerminal(
        previousState: ActiveLearningTimeState.paused,
        occurredAtUtc: _now(),
      );
      return;
    }
    await active.timeAuthority.restoreAfterFailedTerminal(
      previousState: _failClosedRestoreState(active, previousTimeState),
      occurredAtUtc: _now(),
    );
  }

  void _discardPresentation(_ActiveAssessmentPresentation active) {
    if (identical(_presentations[active.run.id], active)) {
      _presentations.remove(active.run.id);
      _presentationForeground.remove(active.run.id);
    }
    active.timeAuthority.dispose();
  }

  DateTime _now() {
    final value = nowUtc();
    AssessmentRun.validateUtcTimestamp(value, 'nowUtc');
    return value;
  }
}

final class AssessmentPresentationCompletion {
  const AssessmentPresentationCompletion({
    required this.run,
    required this.comparison,
  });

  final AssessmentRun run;
  final AssessmentComparisonResult comparison;
}

final class _ActiveAssessmentPresentation {
  _ActiveAssessmentPresentation({
    required this.run,
    required this.definition,
    required Set<String> answeredItemIds,
    required this.latestEvidenceAtUtc,
    required this.timeAuthority,
    required this.wantsForeground,
  }) : answeredItemIds = Set<String>.of(answeredItemIds),
       items = List<AssessmentPresentationItem>.unmodifiable(
         definition.items.map(
           (item) => AssessmentPresentationItem(
             itemId: item.itemId,
             prompt: item.prompt,
             options: item.responses.keys.toList(growable: false)..sort(),
           ),
         ),
       );

  final AssessmentRun run;
  final AssessmentInstrumentDefinition definition;
  final Set<String> answeredItemIds;
  DateTime latestEvidenceAtUtc;
  final List<AssessmentPresentationItem> items;
  final ActiveLearningTimeController timeAuthority;
  bool wantsForeground;
  _PendingAssessmentResponse? pendingResponse;

  AssessmentPresentation get presentation => AssessmentPresentation(
    run: run,
    items: items,
    answeredItemIds: answeredItemIds,
  );
}

final class _PendingAssessmentResponse {
  const _PendingAssessmentResponse({
    required this.sourceEvidenceId,
    required this.itemId,
    required this.submittedResponse,
    required this.responseTimeMs,
    required this.occurredAtUtc,
  });

  final String sourceEvidenceId;
  final String itemId;
  final String submittedResponse;
  final int responseTimeMs;
  final DateTime occurredAtUtc;
}

final class _RecoveredPresentationEvidence {
  const _RecoveredPresentationEvidence({
    required this.answeredItemIds,
    required this.latestEvidenceAtUtc,
  });

  final Set<String> answeredItemIds;
  final DateTime latestEvidenceAtUtc;
}

String _presentationEvidenceId(String runId, String itemId) =>
    'assessment-response:'
    '${sha256.convert(utf8.encode('v1|$runId|$itemId'))}';

final class _ResolvedAssessmentAuthority {
  const _ResolvedAssessmentAuthority({
    required this.assignment,
    required this.mapping,
    required this.consentDecisionUtc,
  });

  final ExperimentAssignment assignment;
  final ResearchProtocolModeMapping mapping;
  final DateTime consentDecisionUtc;

  bool sameIdentityAs(_ResolvedAssessmentAuthority other) {
    return assignment == other.assignment &&
        mapping.protocolId == other.mapping.protocolId &&
        mapping.experimentId == other.mapping.experimentId &&
        mapping.experimentVersion == other.mapping.experimentVersion &&
        mapping.protocolVersion == other.mapping.protocolVersion &&
        mapping.consentVersion == other.mapping.consentVersion &&
        mapping.mode == other.mapping.mode &&
        consentDecisionUtc == other.consentDecisionUtc;
  }
}
