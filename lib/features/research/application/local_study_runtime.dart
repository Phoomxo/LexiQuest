import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../adventure/domain/adventure_entry.dart';
import '../../consent/application/research_consent_use_cases.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/data/learning_session_lifecycle_observer.dart';
import '../../learning/domain/learning_models.dart';
import '../data/drift_experiment_assignment_repository.dart';
import '../data/drift_measurement_opportunity_repository.dart';
import '../data/drift_motivation_measurement_repository.dart';
import '../data/drift_motivation_measurement_timing_reader.dart';
import '../data/drift_research_participation_repository.dart';
import '../data/research_p256_signature_verifier.dart';
import '../domain/ed25519_research_permit_signature_verifier.dart';
import '../domain/experiment_assignment.dart';
import '../domain/experiment_assignment_admission.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_measurement_repository.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_participant_snapshot.dart';
import '../domain/research_runtime_availability.dart';
import '../domain/research_trusted_time.dart';
import 'research_participation_permit_validator.dart';
import 'study_runtime.dart';

/// All asynchronous sources must be bounded local reads. This factory neither
/// enrolls a participant nor imports, fetches or manufactures signed documents.
final class StudyLocalAuthorities {
  StudyLocalAuthorities({
    required this.binding,
    required this.permits,
    required this.states,
    required this.operationSignatures,
    required this.participationDocuments,
    required this.participationSignatures,
    required this.receipts,
    required this.trustedTime,
    required this.supportedFormatVersion,
    required this.trustedIssuerId,
    required this.trustedIssuerKeyId,
    required this.availability,
    required Set<TodayExperiencePresentation> supportedPresentations,
  }) : supportedPresentations = Set.unmodifiable(supportedPresentations);

  final ExperimentAssignmentAdmissionBinding binding;
  final ResearchPermitSource permits;
  final ResearchPermitStateSource states;
  final Ed25519ResearchPermitSignatureVerifier operationSignatures;
  final ResearchParticipationDocumentSource participationDocuments;
  final ResearchP256SignatureVerifier participationSignatures;
  final ResearchReceiptAuthority receipts;
  final ResearchTrustedTimeSource trustedTime;
  final int supportedFormatVersion;
  final String trustedIssuerId;
  final String trustedIssuerKeyId;
  final ResearchRuntimeAvailability availability;
  final Set<TodayExperiencePresentation> supportedPresentations;
}

final class LocalStudyRuntime implements StudyRuntime {
  LocalStudyRuntime({
    required this.context,
    required this.authorities,
    required this.catalog,
  }) {
    final study = authorities.binding.study;
    if (!identical(context.database, context.ownerWrites.database) ||
        !identical(context.database, context.consentRepository.database) ||
        catalog.version != study.catalogVersion ||
        context.buildInfo.version != study.appVersion ||
        context.buildInfo.buildId != study.buildId ||
        authorities.supportedFormatVersion < 1) {
      throw ArgumentError('Inconsistent local study composition');
    }
    consent = ResearchConsentUseCases(
      owners: context.owners,
      repository: context.consentRepository,
      nowUtc: context.nowUtc,
      version: study.consentVersion,
    );
    _timing = DriftMotivationMeasurementTimingReader(context.database);
    lifecycleObserver = _StudyObserver(this);
  }

  final StudyRuntimeContext context;
  final StudyLocalAuthorities authorities;
  @override
  final StudyPresentationCatalog catalog;
  @override
  late final ResearchConsentUseCases consent;
  @override
  late final LearningSessionLifecycleObserver lifecycleObserver;
  late final DriftMotivationMeasurementTimingReader _timing;
  final _owners = <String, _OwnerStudy>{};
  final _launches = <String, Future<ConfiguredQuizLaunch>>{};
  final _openings = <(String, String), _StudyOpening>{};

  @override
  LearningUseCases get learning {
    final value = context.getLearning();
    final repository = value.repository;
    if (repository is! DriftLearningRepository ||
        !identical(repository.database, context.database) ||
        !identical(repository.lifecycleObserver, lifecycleObserver) ||
        !identical(value.owners, context.owners) ||
        value.buildInfo.version != context.buildInfo.version ||
        value.buildInfo.buildId != context.buildInfo.buildId) {
      throw StateError(
        'Study and ordinary learning must use one canonical writer',
      );
    }
    return value;
  }

  _OwnerStudy _forOwner(String ownerId) => _owners.putIfAbsent(ownerId, () {
    final binding = authorities.binding;
    final study = binding.study;
    final assignments = DriftExperimentAssignmentRepository(
      context.database,
      binding: binding,
      authorizer: SignedPermitResearchOperationAuthorizer(
        permits: authorities.permits,
        states: authorities.states,
        verifier: authorities.operationSignatures,
        requirements: ResearchPermitRequirements(
          supportedFormatVersion: authorities.supportedFormatVersion,
          trustedIssuerId: authorities.trustedIssuerId,
          trustedIssuerKeyId: authorities.trustedIssuerKeyId,
          signatureAlgorithm: Ed25519ResearchPermitSignatureVerifier.algorithm,
          assignmentId: experimentAssignmentId(
            ownerId: ownerId,
            experimentId: study.experimentId,
            experimentVersion: study.experimentVersion,
          ),
          assignmentRevision: binding.assignmentRevision,
          protocolId: study.protocolId,
          protocolRevision: binding.protocolRevision,
          instrumentId: study.instrument.instrumentId,
          instrumentRevision: binding.instrumentRevision,
        ),
        trustedTime: authorities.trustedTime,
      ),
      trustedTime: authorities.trustedTime,
      participationDocuments: authorities.participationDocuments,
      participationValidator: ResearchParticipationPermitValidator(
        protocolId: study.protocolId,
        protocolVersion: study.protocolVersion,
        signatures: authorities.participationSignatures,
        receipts: authorities.receipts,
      ),
      consent: context.consentRepository,
      ownerWrites: context.ownerWrites,
    );
    final participation = DriftResearchParticipationRepository(
      context.database,
      assignments: assignments,
    );
    final measurements = DriftMotivationMeasurementRepository(
      context.database,
      participation: participation,
      timing: _timing,
      consentNowUtc: context.nowUtc,
    );
    return _OwnerStudy(
      participation,
      measurements,
      DriftMeasurementOpportunityRepository(
        context.database,
        measurements: measurements,
        timing: _timing,
      ),
    );
  });

  @override
  MotivationMeasurementRepository measurementsFor(String ownerId) =>
      _forOwner(ownerId).measurements;

  @override
  Future<StudyView> load(String ownerId) async {
    try {
      return await _inspect(ownerId);
    } on ResearchCaptureDenied catch (error) {
      return _view(ownerId, StudyPhase.unavailable, reason: error.reason);
    } on Object {
      return _view(
        ownerId,
        StudyPhase.unavailable,
        reason: ResearchCaptureReason.sessionUnavailable,
      );
    }
  }

  Future<StudyView> _inspect(String ownerId, {_StudyOpening? opening}) async {
    await _requireOwner(ownerId);
    if (!authorities.availability.isEnabled) {
      _deny(ResearchCaptureReason.noPermit);
    }
    final scope = _forOwner(ownerId);
    final participant = await scope.participation.inspectParticipant(
      ownerId: ownerId,
    );
    if (participant == null) {
      _deny(ResearchCaptureReason.invalidPermit);
    }
    if (!authorities.supportedPresentations.contains(
      participant.permit.assignedTreatment,
    )) {
      _deny(ResearchCaptureReason.invalidInput);
    }
    final study = authorities.binding.study;
    final runId = motivationMeasurementRunId(
      ownerId: ownerId,
      permitId: participant.permit.id,
      protocolId: study.protocolId,
      protocolVersion: study.protocolVersion,
      instrumentChecksumSha256: study.instrument.checksumSha256,
    );
    final cycles = await context.database
        .customSelect(
          'SELECT id FROM motivation_measurement_runs WHERE owner_id = ? '
          'AND assignment_id = ? AND protocol_id = ? AND protocol_version = ?',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(participant.assignment.id),
            Variable<String>(study.protocolId),
            Variable<String>(study.protocolVersion),
          ],
        )
        .get();
    if (cycles.length > 1 ||
        (cycles.isNotEmpty && cycles.single.read<String>('id') != runId)) {
      _deny(ResearchCaptureReason.versionConflict);
    }
    final run = await scope.measurements.inspect(ownerId, runId);
    if (cycles.isNotEmpty && run == null) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    MeasurementOpportunity? opportunity;
    ConfiguredQuizState? index;
    if (run != null) {
      _runBinding(run, participant);
      final rows = await context.database
          .customSelect(
            'SELECT id FROM measurement_opportunities WHERE owner_id = ? AND measurement_run_id = ?',
            variables: [Variable<String>(ownerId), Variable<String>(run.id)],
          )
          .get();
      // This protocol has one fixed presentation. Multiple openings provide no
      // proof that a particular unpresented view was actually seen.
      if (rows.length > 1) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      if (rows.isNotEmpty) {
        opportunity = await scope.opportunities.load(
          ownerId,
          rows.single.read<String>('id'),
        );
        if (opportunity == null ||
            opportunity.id !=
                measurementOpportunityId(
                  ownerId: ownerId,
                  measurementRunId: run.id,
                  permitId: run.permitId,
                  entryAttemptId: opportunity.entryAttemptId,
                ) ||
            opportunity.permitId != run.permitId ||
            opportunity.assignedTreatment !=
                participant.permit.assignedTreatment ||
            opportunity.effectivePresentation !=
                opportunity.assignedTreatment) {
          _deny(ResearchCaptureReason.identityConflict);
        }
      }
      final facts = run.timing;
      if (facts == null) {
        _deny(ResearchCaptureReason.timingUnavailable);
      }
      if (facts is MotivationAfterExposure) {
        if (opportunity?.presentation?.eventId != facts.firstExposureEventId) {
          _deny(ResearchCaptureReason.identityConflict);
        }
        if (facts.indexSession != null) {
          index = await (learning.repository as DriftLearningRepository)
              .inspectConfiguredQuiz(
                sessionId: facts.indexSession!.id,
                expectedOwnerId: ownerId,
              );
          if (index.startedAtUtc != facts.indexSession!.startedAtUtc ||
              index.state != facts.indexSession!.state.name ||
              (index.endedAtUtc != facts.indexSession!.completedAtUtc &&
                  index.state == 'completed') ||
              index.plan.configuration.stableSerialization !=
                  catalog.configuration.stableSerialization) {
            _deny(ResearchCaptureReason.sessionUnavailable);
          }
        }
      } else if (opportunity?.presentation != null ||
          opportunity?.indexLink != null) {
        _deny(ResearchCaptureReason.timingUnavailable);
      }
    }
    var now = await _now();
    var completionRecorded = false;
    if (index != null) {
      completionRecorded = await scope.opportunities.inspectIndexFacts(
        run: run!,
        opportunity: opportunity!,
        index: index,
        nowUtc: now,
      );
    }
    final freshAuthority = await scope.participation
        .inspectParticipantWithReceipt(ownerId: ownerId);
    final finalTime = await _checkedTime();
    now = DateTime.fromMillisecondsSinceEpoch(
      finalTime.effectiveNowUtc.millisecondsSinceEpoch,
      isUtc: true,
    );
    if (freshAuthority == null ||
        !_sameParticipant(participant, freshAuthority.snapshot) ||
        now.isBefore(freshAuthority.operation.permit.issuedAtUtc) ||
        !now.isBefore(freshAuthority.operation.permit.expiresAtUtc) ||
        now.isBefore(freshAuthority.snapshot.permit.issuedAtUtc) ||
        !now.isBefore(freshAuthority.snapshot.permit.expiresAtUtc) ||
        (freshAuthority.snapshot.permit.revokedAtUtc != null &&
            !now.isBefore(freshAuthority.snapshot.permit.revokedAtUtc!))) {
      _deny(ResearchCaptureReason.invalidPermit);
    }
    if (run != null) {
      _runBinding(run, freshAuthority.snapshot);
    }
    if (opportunity != null &&
        (opportunity.openedAtUtc.isAfter(now) ||
            opportunity.presentation?.occurredAtUtc.isAfter(now) == true ||
            opportunity.indexLink?.startedAtUtc.isAfter(now) == true ||
            opportunity.closedAtUtc?.isAfter(now) == true)) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
    await _requireOwner(ownerId);
    final deadlines = <DateTime>[
      freshAuthority.operation.permit.expiresAtUtc,
      freshAuthority.snapshot.permit.expiresAtUtc,
      if (freshAuthority.snapshot.permit.revokedAtUtc != null)
        freshAuthority.snapshot.permit.revokedAtUtc!,
      finalTime.validUntilUtc,
      finalTime.effectiveNowUtc
          .add(finalTime.maximumAge - finalTime.age)
          .add(const Duration(milliseconds: 1)),
      if (run != null &&
          run.timing is MotivationBeforeExposure &&
          run.score(MotivationTimepoint.baseline) != null)
        for (final response in run.responses)
          if (run.instrument.item(response.itemId).timepoint ==
              MotivationTimepoint.baseline)
            response.answeredAtUtc.add(
              const Duration(hours: 24, milliseconds: 1),
            ),
      if (index?.state == 'completed' && index?.endedAtUtc != null)
        index!.endedAtUtc!.add(const Duration(minutes: 30, milliseconds: 1)),
    ]..sort();
    StudyView timedView(
      String owner,
      StudyPhase phase, {
      ResearchCaptureReason? reason,
      MotivationMeasurementRun? run,
      MeasurementOpportunity? opportunity,
      ConfiguredQuizState? index,
    }) => _view(
      owner,
      phase,
      reason: reason,
      run: run,
      opportunity: opportunity,
      index: index,
      evaluatedAtUtc: now,
      promptExpiresAtUtc: deadlines.first,
    );
    if (run == null) {
      return timedView(ownerId, StudyPhase.baseline);
    }
    if (opportunity != null &&
        opportunity.presentation == null &&
        !_knownUnpresentedOpening(opening, opportunity)) {
      return timedView(
        ownerId,
        StudyPhase.unavailable,
        reason: ResearchCaptureReason.timingUnavailable,
        run: run,
        opportunity: opportunity,
      );
    }
    if (run.state != MotivationMeasurementRunState.started &&
        run.state != MotivationMeasurementRunState.completed) {
      return timedView(
        ownerId,
        StudyPhase.stopped,
        run: run,
        opportunity: opportunity,
        index: index,
      );
    }
    if (run.score(MotivationTimepoint.baseline) == null) {
      if (run.timing is! MotivationBeforeExposure) {
        _deny(ResearchCaptureReason.incomplete);
      }
      return timedView(
        ownerId,
        StudyPhase.baseline,
        run: run,
        opportunity: opportunity,
      );
    }
    if (run.timing is MotivationBeforeExposure) {
      final baseline = run.responses.where(
        (r) =>
            run.instrument.item(r.itemId).timepoint ==
            MotivationTimepoint.baseline,
      );
      if (baseline.any(
        (r) =>
            r.answeredAtUtc.isAfter(now) ||
            r.answeredAtUtc.isBefore(now.subtract(const Duration(hours: 24))),
      )) {
        return timedView(
          ownerId,
          StudyPhase.stopped,
          reason: ResearchCaptureReason.outsideWindow,
          run: run,
          opportunity: opportunity,
        );
      }
      return timedView(
        ownerId,
        StudyPhase.ready,
        run: run,
        opportunity: opportunity,
      );
    }
    if (index == null) {
      return timedView(
        ownerId,
        StudyPhase.ready,
        run: run,
        opportunity: opportunity,
      );
    }
    if (index.state == 'active') {
      return timedView(
        ownerId,
        StudyPhase.activeIndex,
        run: run,
        opportunity: opportunity,
        index: index,
      );
    }
    if (index.state != 'completed') {
      return timedView(
        ownerId,
        StudyPhase.stopped,
        reason: ResearchCaptureReason.sessionUnavailable,
        run: run,
        opportunity: opportunity,
        index: index,
      );
    }
    if (!completionRecorded) {
      return timedView(
        ownerId,
        StudyPhase.unavailable,
        reason: ResearchCaptureReason.incomplete,
        run: run,
        opportunity: opportunity,
        index: index,
      );
    }
    if (run.state == MotivationMeasurementRunState.completed) {
      return timedView(
        ownerId,
        StudyPhase.completed,
        run: run,
        opportunity: opportunity,
        index: index,
      );
    }
    if (index.endedAtUtc == null ||
        now.isBefore(index.endedAtUtc!) ||
        now.isAfter(index.endedAtUtc!.add(const Duration(minutes: 30)))) {
      return timedView(
        ownerId,
        StudyPhase.stopped,
        reason: ResearchCaptureReason.outsideWindow,
        run: run,
        opportunity: opportunity,
        index: index,
      );
    }
    return timedView(
      ownerId,
      StudyPhase.post,
      run: run,
      opportunity: opportunity,
      index: index,
    );
  }

  @override
  Future<StudyView> begin(String ownerId) => _write(ownerId, () async {
    final before = await _inspect(ownerId);
    if (before.run != null) {
      return before;
    }
    if (before.phase != StudyPhase.baseline) {
      _deny(ResearchCaptureReason.noActiveRun);
    }
    final scope = _forOwner(ownerId);
    final participant = await scope.participation.inspectParticipant(
      ownerId: ownerId,
    );
    if (participant == null) {
      _deny(ResearchCaptureReason.invalidPermit);
    }
    await scope.measurements.start(
      MotivationMeasurementStart(
        ownerId: ownerId,
        permitId: participant.permit.id,
      ),
    );
    return _inspect(ownerId);
  });

  @override
  Future<StudyView> openPresentation(
    String ownerId, {
    required String entryAttemptId,
    required bool Function() stillCurrent,
  }) async {
    requireMeasurementEntryId(entryAttemptId);
    _StudyOpening? preparedOpening;
    final result = await _write(ownerId, () async {
      final opening = _openings.putIfAbsent((
        ownerId,
        entryAttemptId,
      ), () => _StudyOpening(ownerId, entryAttemptId));
      preparedOpening = opening;
      if (!_preframe(opening)) {
        _deny(ResearchCaptureReason.timingUnavailable);
      }
      final before = await _inspect(ownerId, opening: opening);
      if (before.opportunity != null &&
          before.opportunity!.entryAttemptId != entryAttemptId) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      if (before.phase != StudyPhase.ready ||
          before.run == null ||
          !_preframe(opening)) {
        _deny(
          before.phase == StudyPhase.baseline
              ? ResearchCaptureReason.incomplete
              : ResearchCaptureReason.timingUnavailable,
        );
      }
      var opportunity = before.opportunity;
      if (opportunity == null) {
        opportunity = await _forOwner(ownerId).opportunities.open(
          ownerId: ownerId,
          measurementRunId: before.run!.id,
          entryAttemptId: entryAttemptId,
          effectivePresentation: TodayExperiencePresentationCodec.decode(
            before.run!.treatment,
          ),
        );
        opening.prepared = opportunity;
      } else if (!_knownUnpresentedOpening(opening, opportunity)) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      final after = await _inspect(ownerId, opening: opening);
      if (after.phase != StudyPhase.ready ||
          after.opportunity?.id != opportunity.id ||
          !_preframe(opening) ||
          !stillCurrent()) {
        _deny(ResearchCaptureReason.sessionUnavailable);
      }
      return after;
    });
    final opening = preparedOpening!;
    if (!_preframe(opening)) {
      _deny(ResearchCaptureReason.timingUnavailable);
    }
    opening.phase = _OpeningPhase.prepared;
    return result;
  }

  @override
  void markPresentationMayRender(
    String ownerId,
    String opportunityId, {
    required String entryAttemptId,
  }) {
    final opening = _requireOpening(ownerId, opportunityId, entryAttemptId);
    if (opening.phase != _OpeningPhase.prepared) {
      _deny(ResearchCaptureReason.timingUnavailable);
    }
    opening.phase = _OpeningPhase.potentialRender;
  }

  @override
  void invalidatePresentationOpening(
    String ownerId, {
    required String entryAttemptId,
  }) {
    final opening = _openings[(ownerId, entryAttemptId)];
    if (opening != null && opening.phase != _OpeningPhase.committed) {
      opening.phase = _OpeningPhase.uncertain;
    }
  }

  @override
  Future<StudyView> recordPresented(
    String ownerId,
    String opportunityId, {
    required String entryAttemptId,
    required bool Function() stillVisible,
  }) async {
    _StudyOpening? attemptedOpening;
    try {
      final result = await _write(ownerId, () async {
        final opening = _requireOpening(ownerId, opportunityId, entryAttemptId);
        attemptedOpening = opening;
        final newCapture = opening.phase == _OpeningPhase.potentialRender;
        if (!newCapture) {
          final stored = await _forOwner(
            ownerId,
          ).opportunities.load(ownerId, opportunityId);
          if (stored?.presentation == null) {
            _deny(ResearchCaptureReason.timingUnavailable);
          }
        }
        opening.phase = _OpeningPhase.capturing;
        bool currentFrame() =>
            opening.phase == _OpeningPhase.capturing && stillVisible();
        final before = await _inspect(
          ownerId,
          opening: newCapture ? opening : null,
        );
        if (before.phase == StudyPhase.unavailable) {
          _deny(before.reason ?? ResearchCaptureReason.sessionUnavailable);
        }
        if (before.opportunity?.id != opportunityId ||
            before.run?.state != MotivationMeasurementRunState.started) {
          _deny(ResearchCaptureReason.sessionUnavailable);
        }
        await _forOwner(ownerId).opportunities.recordPresented(
          ownerId,
          opportunityId,
          stillVisible: currentFrame,
        );
        final after = await _inspect(ownerId);
        if (after.phase == StudyPhase.unavailable) {
          _deny(after.reason ?? ResearchCaptureReason.sessionUnavailable);
        }
        if (!currentFrame()) {
          _deny(ResearchCaptureReason.sessionUnavailable);
        }
        return after;
      });
      attemptedOpening!.phase = _OpeningPhase.committed;
      return result;
    } on Object {
      attemptedOpening?.phase = _OpeningPhase.uncertain;
      rethrow;
    }
  }

  _StudyOpening _requireOpening(
    String ownerId,
    String opportunityId,
    String entryAttemptId,
  ) {
    final opening = _openings[(ownerId, entryAttemptId)];
    if (opening == null || opening.prepared?.id != opportunityId) {
      _deny(ResearchCaptureReason.timingUnavailable);
    }
    return opening;
  }

  static bool _preframe(_StudyOpening opening) =>
      opening.phase == _OpeningPhase.preparing ||
      opening.phase == _OpeningPhase.prepared;

  static bool _knownUnpresentedOpening(
    _StudyOpening? opening,
    MeasurementOpportunity current,
  ) {
    final prepared = opening?.prepared;
    return opening != null &&
        prepared != null &&
        (_preframe(opening) || opening.phase == _OpeningPhase.capturing) &&
        current.presentation == null &&
        current.indexLink == null &&
        current.closedAtUtc == null &&
        current.id == prepared.id &&
        current.ownerId == opening.ownerId &&
        current.entryAttemptId == opening.entryAttemptId &&
        current.measurementRunId == prepared.measurementRunId &&
        current.permitId == prepared.permitId &&
        current.assignedTreatment == prepared.assignedTreatment &&
        current.effectivePresentation == prepared.effectivePresentation &&
        current.openedAtUtc == prepared.openedAtUtc &&
        current.localRevision == prepared.localRevision;
  }

  @override
  Future<ConfiguredQuizState> startIndex(
    String ownerId,
    String opportunityId, {
    required bool Function() stillVisible,
  }) async {
    final canonicalLearning = learning;
    var inserted = false;
    final result = await _write(ownerId, () async {
      final before = await _inspect(ownerId);
      if (before.opportunity?.id != opportunityId) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      if (before.phase == StudyPhase.activeIndex && before.index != null) {
        final resumed = await canonicalLearning.resumeQuiz(
          sessionId: before.index!.sessionId,
          expectedOwnerId: ownerId,
        );
        final after = await _inspect(ownerId);
        if (after.phase != StudyPhase.activeIndex ||
            after.index?.sessionId != resumed.sessionId ||
            after.opportunity?.id != opportunityId ||
            !stillVisible()) {
          _deny(ResearchCaptureReason.sessionUnavailable);
        }
        return resumed;
      }
      if (!before.canStart || !stillVisible()) {
        _deny(ResearchCaptureReason.sessionUnavailable);
      }
      final launch = await _launchFor(ownerId, opportunityId);
      final accepted = await canonicalLearning.startConfiguredQuiz(
        launch,
        notifyLocalMutation: false,
      );
      inserted = !accepted.restored;
      final after = await _inspect(ownerId);
      if (after.phase != StudyPhase.activeIndex ||
          after.index?.sessionId != accepted.sessionId ||
          after.opportunity?.id != opportunityId ||
          !stillVisible()) {
        _deny(ResearchCaptureReason.sessionUnavailable);
      }
      return accepted;
    });
    if (inserted) {
      canonicalLearning.onLocalMutation?.call();
    }
    return result;
  }

  @override
  Future<ConfiguredQuizState> resumeIndex(String ownerId) =>
      _write(ownerId, () async {
        final before = await _inspect(ownerId);
        final index = before.index;
        if (index == null ||
            index.state == 'abandoned' ||
            (before.phase == StudyPhase.unavailable &&
                before.reason != ResearchCaptureReason.incomplete)) {
          _deny(ResearchCaptureReason.sessionUnavailable);
        }
        var resumed = await learning.resumeQuiz(
          sessionId: index.sessionId,
          expectedOwnerId: ownerId,
        );
        if (resumed.state == 'completed' &&
            before.reason == ResearchCaptureReason.incomplete) {
          resumed = (await learning.finishConfiguredQuiz(
            sessionId: resumed.sessionId,
            expectedOwnerId: ownerId,
            expectedRevision: resumed.checkpointRevision,
            notifyLocalMutation: false,
          )).state;
        }
        final after = await _inspect(ownerId);
        if (after.index?.sessionId != resumed.sessionId ||
            after.phase == StudyPhase.unavailable) {
          _deny(ResearchCaptureReason.sessionUnavailable);
        }
        return resumed;
      });

  Future<T> _write<T>(String ownerId, Future<T> Function() action) async {
    if (await context.ownerWrites.hasAmbientTransaction()) {
      _deny(ResearchCaptureReason.sessionUnavailable);
    }
    return context.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: action,
    );
  }

  Future<ConfiguredQuizLaunch> _launchFor(
    String ownerId,
    String opportunityId,
  ) async {
    final previous = _launches[opportunityId];
    if (previous != null) {
      return previous;
    }
    final pending = learning.prepareConfiguredQuiz(
      configuration: catalog.configuration,
      expectedOwnerId: ownerId,
    );
    _launches[opportunityId] = pending;
    try {
      return await pending;
    } on Object {
      if (identical(_launches[opportunityId], pending)) {
        _launches.remove(opportunityId);
      }
      rethrow;
    }
  }

  Future<void> _requireOwner(String ownerId) async {
    final intent = await context.ownerWrites.inspect();
    final rows = await context.database
        .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
        .get();
    if (rows.length != 1 ||
        rows.single.read<String>('id') != ownerId ||
        intent != null) {
      _deny(ResearchCaptureReason.ownerConflict);
    }
  }

  Future<ResearchTrustedTime> _checkedTime() async {
    final reading = await authorities.trustedTime.read();
    if (reading == null ||
        !reading.isFresh ||
        !reading.effectiveNowUtc.isUtc ||
        reading.effectiveNowUtc.millisecondsSinceEpoch < 0) {
      _deny(ResearchCaptureReason.timingUnavailable);
    }
    return reading;
  }

  Future<DateTime> _now() async {
    final reading = await _checkedTime();
    return DateTime.fromMillisecondsSinceEpoch(
      reading.effectiveNowUtc.millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  static bool _sameParticipant(
    ResearchParticipantSnapshot a,
    ResearchParticipantSnapshot b,
  ) =>
      a.permit.canonicalPayload() == b.permit.canonicalPayload() &&
      a.permit.payloadSha256 == b.permit.payloadSha256 &&
      a.permit.signature == b.permit.signature &&
      a.assignment == b.assignment &&
      a.consent.version == b.consent.version &&
      a.consent.decidedAtUtc == b.consent.decidedAtUtc &&
      a.consent.accepted == b.consent.accepted;

  static void _runBinding(
    MotivationMeasurementRun run,
    ResearchParticipantSnapshot p,
  ) {
    if (run.ownerId != p.permit.ownerId ||
        run.permitId != p.permit.id ||
        run.permitPayloadSha256 != p.permit.payloadSha256 ||
        run.assignmentId != p.assignment.id ||
        run.treatment != p.assignment.cohort ||
        run.consentVersion != p.consent.version ||
        run.consentDecidedAtUtc != p.consent.decidedAtUtc) {
      _deny(ResearchCaptureReason.versionConflict);
    }
  }

  StudyView _view(
    String ownerId,
    StudyPhase phase, {
    ResearchCaptureReason? reason,
    MotivationMeasurementRun? run,
    MeasurementOpportunity? opportunity,
    ConfiguredQuizState? index,
    DateTime? evaluatedAtUtc,
    DateTime? promptExpiresAtUtc,
  }) => StudyView(
    ownerId: ownerId,
    catalog: catalog,
    phase: phase,
    reason: reason,
    run: run,
    opportunity: opportunity,
    index: index,
    evaluatedAtUtc: evaluatedAtUtc,
    promptExpiresAtUtc: promptExpiresAtUtc,
  );

  static Never _deny(ResearchCaptureReason reason) =>
      throw ResearchCaptureDenied(reason);
}

enum _OpeningPhase {
  preparing,
  prepared,
  potentialRender,
  capturing,
  committed,
  uncertain,
}

final class _StudyOpening {
  _StudyOpening(this.ownerId, this.entryAttemptId);
  final String ownerId;
  final String entryAttemptId;
  MeasurementOpportunity? prepared;
  _OpeningPhase phase = _OpeningPhase.preparing;
}

final class _OwnerStudy {
  const _OwnerStudy(this.participation, this.measurements, this.opportunities);
  final DriftResearchParticipationRepository participation;
  final DriftMotivationMeasurementRepository measurements;
  final DriftMeasurementOpportunityRepository opportunities;
}

final class _StudyObserver implements LearningSessionLifecycleObserver {
  const _StudyObserver(this.runtime);
  final LocalStudyRuntime runtime;
  @override
  AppDatabase get database => runtime.context.database;
  @override
  Future<void> accepted(LearningSessionLifecycleFact session) async {
    if (!runtime.authorities.availability.isEnabled) {
      return;
    }
    await runtime._forOwner(session.ownerId).opportunities.accepted(session);
  }

  @override
  Future<void> completed(LearningSessionLifecycleFact session) async {
    if (!runtime.authorities.availability.isEnabled) {
      return;
    }
    await runtime._forOwner(session.ownerId).opportunities.completed(session);
  }
}
