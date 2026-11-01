import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../assessment/application/assessment_comparison.dart';
import '../../assessment/data/drift_assessment_repository.dart';
import '../../assessment/domain/assessment_instrument_catalog.dart';
import '../../assessment/domain/assessment_models.dart';
import '../../export/domain/export_contracts.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../application/local_study_runtime.dart';
import '../application/research_participation_permit_validator.dart';
import '../domain/experiment_assignment.dart';
import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/research_authority_snapshot.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_participation_permit.dart';
import '../domain/study_archive.dart';
import 'drift_motivation_measurement_repository.dart';
import 'drift_measurement_opportunity_repository.dart';
import 'drift_motivation_measurement_timing_reader.dart';
import 'local_research_authority_cache.dart';

final class DriftStudyArchiveRepository
    implements StudyUploadArchiveRepository {
  DriftStudyArchiveRepository({
    required this.study,
    required this.motivationAuthority,
  }) {
    final context = study.context;
    final authorities = study.authorities;
    if (!identical(
          context.database,
          motivationAuthority.ownerWrites.database,
        ) ||
        !identical(context.ownerWrites, motivationAuthority.ownerWrites) ||
        !identical(authorities.permits, motivationAuthority) ||
        !identical(authorities.states, motivationAuthority) ||
        !identical(authorities.participationDocuments, motivationAuthority) ||
        !identical(authorities.receipts, motivationAuthority) ||
        !identical(authorities.trustedTime, motivationAuthority)) {
      throw ArgumentError(
        'Study archive must share the actual Study authority.',
      );
    }
  }

  final LocalStudyRuntime study;
  final LocalResearchAuthorityCache motivationAuthority;

  @override
  Future<List<StudyArchivePreview>> listCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _listCycles(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
    operation: ResearchOperation.export,
  );

  @override
  Future<List<StudyArchivePreview>> listUploadCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _listCycles(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
    operation: ResearchOperation.upload,
  );

  Future<List<StudyArchivePreview>> _listCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
    required ResearchOperation operation,
  }) => _boundary(() async {
    requireResearchCode(expectedOwnerId);
    await _outside(stillCurrent);
    final lease = await _authorize(expectedOwnerId, stillCurrent, operation);
    final rows = await study.context.ownerWrites.writeForActiveOwner(
      expectedOwnerId: expectedOwnerId,
      write: () => study.context.database
          .customSelect(
            'SELECT id FROM motivation_measurement_runs WHERE owner_id = ? AND assignment_id = ? AND assignment_revision = ? AND protocol_id = ? AND protocol_version = ? AND protocol_revision = ? AND instrument_id = ? AND instrument_revision = ? ORDER BY started_at_utc_ms DESC, id',
            variables: [
              Variable<String>(expectedOwnerId),
              Variable<String>(
                lease.motivation.scope.requirements.assignmentId,
              ),
              Variable<int>(
                lease.motivation.scope.requirements.assignmentRevision,
              ),
              Variable<String>(lease.motivation.scope.requirements.protocolId),
              Variable<String>(lease.motivation.scope.protocolVersion),
              Variable<int>(
                lease.motivation.scope.requirements.protocolRevision,
              ),
              Variable<String>(
                lease.motivation.scope.requirements.instrumentId,
              ),
              Variable<int>(
                lease.motivation.scope.requirements.instrumentRevision,
              ),
            ],
          )
          .get(),
    );
    _captured(lease, stillCurrent);
    final result = <StudyArchivePreview>[];
    for (final row in rows) {
      result.add(
        (await _prepareFor(
          StudyArchiveTarget(
            expectedOwnerId: expectedOwnerId,
            studyCycleId: row.read<String>('id'),
          ),
          stillCurrent: stillCurrent,
          operation: operation,
        )).preview,
      );
      _captured(lease, stillCurrent);
    }
    return List.unmodifiable(result);
  });

  @override
  Future<PreparedStudyArchive> prepare(
    StudyArchiveTarget target, {
    required bool Function() stillCurrent,
  }) => _prepareFor(
    target,
    stillCurrent: stillCurrent,
    operation: ResearchOperation.export,
  );

  @override
  Future<PreparedStudyUploadArchive> prepareUpload(
    StudyArchiveTarget target, {
    required bool Function() stillCurrent,
  }) => _prepareFor(
    target,
    stillCurrent: stillCurrent,
    operation: ResearchOperation.upload,
  );

  Future<_PreparedArchive> _prepareFor(
    StudyArchiveTarget target, {
    required bool Function() stillCurrent,
    required ResearchOperation operation,
  }) => _boundary(() async {
    requireResearchCode(target.expectedOwnerId);
    requireResearchCode(target.studyCycleId);
    await _outside(stillCurrent);
    final lease = await _authorize(
      target.expectedOwnerId,
      stillCurrent,
      operation,
    );
    final snapshot = await study.context.ownerWrites.writeForActiveOwner(
      expectedOwnerId: target.expectedOwnerId,
      write: () async {
        final result = await _snapshot(target, lease, stillCurrent);
        final finalLease = await _authorize(
          target.expectedOwnerId,
          stillCurrent,
          operation,
        );
        _captured(lease, stillCurrent);
        if (lease.fingerprint != finalLease.fingerprint) _deny();
        return result;
      },
    );
    _captured(lease, stillCurrent);
    return _PreparedArchive(this, target, lease, snapshot);
  });

  @override
  Future<void> requireCurrent(
    PreparedStudyArchive prepared, {
    required bool Function() stillCurrent,
  }) => _requireCurrent(prepared, stillCurrent, ResearchOperation.export);

  @override
  Future<void> requireCurrentUpload(
    PreparedStudyUploadArchive prepared, {
    required bool Function() stillCurrent,
  }) => _requireCurrent(prepared, stillCurrent, ResearchOperation.upload);

  Future<void> _requireCurrent(
    PreparedStudyArchive prepared,
    bool Function() stillCurrent,
    ResearchOperation operation,
  ) => _boundary(() async {
    if (prepared is! _PreparedArchive ||
        !identical(prepared.issuer, this) ||
        prepared.lease.motivation.receipt.permit.operation != operation) {
      _deny();
    }
    _captured(prepared.lease, stillCurrent);
    final current = await _prepareFor(
      prepared.target,
      stillCurrent: stillCurrent,
      operation: operation,
    );
    _captured(prepared.lease, stillCurrent);
    if (current.lease.fingerprint != prepared.lease.fingerprint ||
        current.snapshot.fingerprint != prepared.snapshot.fingerprint) {
      _deny();
    }
  });

  Future<void> _outside(bool Function() current) async {
    _visible(current);
    if (await study.context.ownerWrites.hasAmbientTransaction()) _deny();
    _visible(current);
  }

  LocalResearchAuthorityCache? get _assessmentCache {
    final repository = study.assessment?.repository;
    return repository is DriftAssessmentRepository
        ? repository.authority.cache
        : null;
  }

  Future<_ArchiveLease> _authorize(
    String ownerId,
    bool Function() current,
    ResearchOperation operation,
  ) async {
    _visible(current);
    if (!study.authorities.availability.isEnabled) _deny();
    final motivation = await _grant(
      motivationAuthority,
      ownerId,
      current,
      operation,
    );
    final pins = motivation.scope.requirements;
    final binding = study.authorities.binding;
    final protocol = binding.study;
    if (pins.assignmentId !=
            experimentAssignmentId(
              ownerId: ownerId,
              experimentId: protocol.experimentId,
              experimentVersion: protocol.experimentVersion,
            ) ||
        pins.assignmentRevision != binding.assignmentRevision ||
        pins.protocolId != protocol.protocolId ||
        pins.protocolRevision != binding.protocolRevision ||
        pins.instrumentId != protocol.instrument.instrumentId ||
        pins.instrumentRevision != binding.instrumentRevision ||
        pins.trustedIssuerId != study.authorities.trustedIssuerId ||
        pins.trustedIssuerKeyId != study.authorities.trustedIssuerKeyId ||
        motivation.scope.protocolVersion != protocol.protocolVersion ||
        motivation.scope.consentVersion != protocol.consentVersion) {
      _deny();
    }
    _ArchiveGrant? assessment;
    final configured = study.assessment;
    if (study.hasConfiguredAssessment && configured == null) _deny();
    if (configured != null) {
      final cache = _assessmentCache;
      if (cache == null ||
          !identical(cache.ownerWrites, study.context.ownerWrites)) {
        _deny();
      }
      assessment = await _grant(cache, ownerId, current, operation);
      final other = assessment.scope;
      if (other.binding != motivation.scope.binding ||
          other.requirements.assignmentId != pins.assignmentId ||
          other.requirements.assignmentRevision != pins.assignmentRevision ||
          other.requirements.protocolId != pins.protocolId ||
          other.requirements.protocolRevision != pins.protocolRevision ||
          other.protocolVersion != motivation.scope.protocolVersion ||
          other.consentVersion != motivation.scope.consentVersion) {
        _deny();
      }
      configured.mapping.requireMatches(
        scope: other,
        definition: configured.definition,
      );
    }
    if (operation == ResearchOperation.upload && assessment == null) _deny();
    final lease = _ArchiveLease(motivation, assessment);
    _captured(lease, current);
    return lease;
  }

  Future<_ArchiveGrant> _grant(
    LocalResearchAuthorityCache cache,
    String ownerId,
    bool Function() current,
    ResearchOperation operation,
  ) async {
    final scope = cache.currentScope();
    final generation = cache.readGeneration;
    if (scope == null || scope.binding.ownerId != ownerId) _deny();
    final receipt = await SignedPermitResearchOperationAuthorizer(
      permits: cache,
      states: cache,
      verifier: cache.operationSignatures,
      requirements: scope.requirements,
      trustedTime: cache,
    ).authorizeWithReceipt(ownerId: ownerId, operation: operation);
    final grant = receipt == null
        ? null
        : _ArchiveGrant(cache, scope, generation, receipt);
    if (grant == null) _deny();
    _grantCaptured(grant, current);
    return grant;
  }

  void _captured(_ArchiveLease lease, bool Function() current) {
    _grantCaptured(lease.motivation, current);
    final assessment = lease.assessment;
    if (assessment != null) _grantCaptured(assessment, current);
  }

  void _grantCaptured(_ArchiveGrant grant, bool Function() current) {
    _visible(current);
    if (grant.cache.currentScope() != grant.scope ||
        grant.cache.readGeneration != grant.generation) {
      _deny();
    }
  }

  Future<_ArchiveSnapshot> _snapshot(
    StudyArchiveTarget target,
    _ArchiveLease lease,
    bool Function() current,
  ) async {
    final database = study.context.database;
    final ownerId = target.expectedOwnerId;
    final rows = await database
        .customSelect(
          'SELECT * FROM motivation_measurement_runs WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(target.studyCycleId),
            Variable<String>(ownerId),
          ],
        )
        .get();
    if (rows.length != 1) _deny();
    final original = rows.single.data;
    if (original['assignment_id'] !=
        lease.motivation.scope.requirements.assignmentId) {
      _deny();
    }
    final children = await database
        .customSelect(
          'SELECT owner_id FROM motivation_responses WHERE run_id = ? UNION ALL SELECT owner_id FROM measurement_opportunities WHERE measurement_run_id = ? UNION ALL SELECT owner_id FROM assessment_runs WHERE study_cycle_id = ?',
          variables: [
            for (var i = 0; i < 3; i++) Variable<String>(target.studyCycleId),
          ],
        )
        .get();
    if (children.any((row) => row.read<String>('owner_id') != ownerId)) _deny();
    final measurements = study.measurementsFor(ownerId);
    if (measurements is! DriftMotivationMeasurementRepository) _deny();
    final timingReader = measurements.timing;
    if (timingReader is! DriftMotivationMeasurementTimingReader) _deny();
    final run = await measurements.inspectForArchive(
      ownerId,
      target.studyCycleId,
    );
    if (run == null ||
        run.timing == null ||
        run.state == MotivationMeasurementRunState.withdrawn) {
      _deny();
    }
    var now = await _trustedNow(lease.motivation, current);
    if (run.startedAtUtc.isAfter(now) ||
        (run.closedAtUtc?.isAfter(now) ?? false) ||
        run.responses.any((row) => row.answeredAtUtc.isAfter(now))) {
      _deny();
    }
    final participation = await motivationAuthority.loadCurrent(
      ownerId: ownerId,
      permitId: run.permitId,
    );
    if (participation == null ||
        participation.payloadSha256 != run.permitPayloadSha256 ||
        participation.assignedTreatment.name != run.treatment) {
      _deny();
    }
    final validation =
        await ResearchParticipationPermitValidator(
          protocolId: run.study.protocolId,
          protocolVersion: run.study.protocolVersion,
          signatures: motivationAuthority.participationSignatures,
          receipts: motivationAuthority,
        ).validate(
          participation,
          expectedOwnerId: ownerId,
          expectedAssignmentId: run.assignmentId,
          evaluatedAtUtc: now,
        );
    if (!validation.isActive) _deny();
    final assessmentGrant = lease.assessment;
    if (assessmentGrant != null) {
      final other = await assessmentGrant.cache.loadCurrent(
        ownerId: ownerId,
        permitId: run.permitId,
      );
      final otherNow = await _trustedNow(assessmentGrant, current);
      if (other == null ||
          other.canonicalPayload() != participation.canonicalPayload() ||
          other.payloadSha256 != participation.payloadSha256 ||
          other.signature != participation.signature) {
        _deny();
      }
      final otherValidation =
          await ResearchParticipationPermitValidator(
            protocolId: run.study.protocolId,
            protocolVersion: run.study.protocolVersion,
            signatures: assessmentGrant.cache.participationSignatures,
            receipts: assessmentGrant.cache,
          ).validate(
            other,
            expectedOwnerId: ownerId,
            expectedAssignmentId: run.assignmentId,
            evaluatedAtUtc: otherNow,
          );
      if (!otherValidation.isActive) _deny();
      if (otherNow.isBefore(now)) now = otherNow;
    }
    if (run.startedAtUtc.isAfter(now) ||
        (run.closedAtUtc?.isAfter(now) ?? false) ||
        run.responses.any((row) => row.answeredAtUtc.isAfter(now))) {
      _deny();
    }
    final consent = await study.context.consentRepository.load(
      ownerId: ownerId,
      version: run.consentVersion,
    );
    if (!consent.accepted ||
        consent.withdrawnAtUtc != null ||
        consent.decidedAtUtc != run.consentDecidedAtUtc) {
      _deny();
    }
    final local = await database
        .customSelect(
          'SELECT * FROM research_participation_permits WHERE id = ?',
          variables: [Variable<String>(run.permitId)],
        )
        .getSingleOrNull();
    final expectedPermit = _participationFields(participation);
    if (local == null ||
        expectedPermit.entries.any(
          (entry) => local.data[entry.key] != entry.value,
        )) {
      _deny();
    }
    final assignment = await database
        .customSelect(
          'SELECT * FROM experiment_assignments WHERE id = ?',
          variables: [Variable<String>(run.assignmentId)],
        )
        .getSingleOrNull();
    if (assignment == null ||
        assignment.data['owner_id'] != ownerId ||
        assignment.data['experiment_id'] != run.study.experimentId ||
        assignment.data['experiment_version'] != run.study.experimentVersion ||
        assignment.data['cohort'] != run.treatment ||
        assignment.data['protocol_version'] != run.study.protocolVersion ||
        (assignment.data['assigned_at_utc_ms']! as int) >
            run.startedAtUtc.millisecondsSinceEpoch) {
      _deny();
    }
    final aliases = <String, String>{};
    String alias(String id) =>
        aliases.putIfAbsent(id, () => 'r${aliases.length + 1}');
    final graph = <Object?>[original, expectedPermit, assignment.data];
    final opportunities = await database
        .customSelect(
          'SELECT * FROM measurement_opportunities WHERE measurement_run_id = ? ORDER BY opened_at_utc_ms, id',
          variables: [Variable<String>(run.id)],
        )
        .get();
    if (opportunities.length > 1) _deny();
    final typedOpportunities = <MeasurementOpportunity>[];
    final exposures = <Map<String, Object?>>[];
    for (final opportunity in opportunities) {
      final row = opportunity.data;
      if (row['permit_id'] != run.permitId ||
          row['assigned_treatment'] != run.treatment ||
          row['pending_presentation_change_json'] != null) {
        _deny();
      }
      final typedOpportunity = await timingReader.loadOpportunity(
        ownerId,
        row['id']! as String,
      );
      if (typedOpportunity == null) _deny();
      typedOpportunities.add(typedOpportunity);
      if (row['presented_event_id'] != null &&
          !await timingReader.validatePresentationHistory(
            typedOpportunity,
            notAfter: now,
          )) {
        _deny();
      }
      graph.add(row);
      final eventRows = await database
          .customSelect(
            'SELECT * FROM events_v2 WHERE aggregate_id = ? OR correlation_id = ? ORDER BY occurred_at_utc, event_id',
            variables: [
              Variable<String>(row['id']! as String),
              Variable<String>(row['id']! as String),
            ],
          )
          .get();
      if (eventRows.any((event) => event.data['owner_id'] != ownerId)) _deny();
      graph.addAll(eventRows.map((event) => event.data));
      exposures.add({
        'opportunity': alias(row['id']! as String),
        'openedAtUtc': _date(row['opened_at_utc_ms']),
        'presentedEvent': row['presented_event_id'] == null
            ? null
            : alias(row['presented_event_id']! as String),
        'presentedAtUtc': row['presented_at_utc_ms'] == null
            ? null
            : _date(row['presented_at_utc_ms']),
        'effectivePresentation': row['effective_presentation'],
        'switchCount':
            (row['last_switch_ordinal']! as int) +
            (row['suppressed_switch_count']! as int),
        'isIndex': row['is_index_session'] == 1,
        'session': row['learning_session_id'] == null
            ? null
            : alias(row['learning_session_id']! as String),
      });
    }
    final timing = run.timing;
    final after = timing is MotivationAfterExposure ? timing : null;
    final index = after?.indexSession;
    final indexAnswers = <Map<String, Object?>>[];
    var completionRecorded = false;
    DateTime? indexEndedAtUtc;
    if (index != null) {
      final canonical = study.learning.repository;
      if (canonical is! DriftLearningRepository ||
          typedOpportunities.length != 1) {
        _deny();
      }
      final configured = await canonical.inspectConfiguredQuiz(
        sessionId: index.id,
        expectedOwnerId: ownerId,
      );
      if (configured.startedAtUtc != index.startedAtUtc ||
          configured.state != index.state.name ||
          (index.state == MotivationIndexSessionState.completed &&
              configured.endedAtUtc != index.completedAtUtc) ||
          configured.plan.configuration.stableSerialization !=
              study.catalog.configuration.stableSerialization) {
        _deny();
      }
      indexEndedAtUtc = configured.endedAtUtc;
      completionRecorded =
          await DriftMeasurementOpportunityRepository(
            database,
            measurements: measurements,
            timing: timingReader,
          ).inspectIndexFacts(
            run: run,
            opportunity: typedOpportunities.single,
            index: configured,
            nowUtc: now,
          );
      if (run.state == MotivationMeasurementRunState.completed &&
          !completionRecorded) {
        _deny();
      }
      final session = await database
          .customSelect(
            'SELECT * FROM learning_sessions WHERE id = ?',
            variables: [Variable<String>(index.id)],
          )
          .getSingleOrNull();
      if (session == null || session.data['owner_id'] != ownerId) _deny();
      graph.add(session.data);
      final answers = await database
          .customSelect(
            'SELECT * FROM answer_attempts WHERE session_id = ? ORDER BY occurred_at_utc_ms, id',
            variables: [Variable<String>(index.id)],
          )
          .get();
      for (final answer in answers) {
        final row = answer.data;
        if (row['owner_id'] != ownerId ||
            !LearningEvidenceContract.validAttempt(
              id: row['id']! as String,
              ownerId: row['owner_id']! as String,
              sessionId: row['session_id']! as String,
              wordId: row['word_id']! as String,
              promptMode: row['prompt_mode']! as String,
              responseTimeMs: row['response_time_ms'] as int?,
              attemptNumber: row['attempt_number']! as int,
              occurredAtUtcMs: row['occurred_at_utc_ms']! as int,
              providerProvenance: row['provider_provenance'] as String?,
              evidenceClass: row['evidence_class']! as String,
              evidenceContextJson: row['evidence_context_json']! as String,
            ) ||
            (row['occurred_at_utc_ms']! as int) > now.millisecondsSinceEpoch) {
          _deny();
        }
        graph.add(row);
        indexAnswers.add({
          'evidence': alias(row['id']! as String),
          'correct': row['is_correct'] == 1,
          'occurredAtUtc': _date(row['occurred_at_utc_ms']),
          'responseTimeMs': row['response_time_ms'],
          'evidenceClass': row['evidence_class'],
        });
      }
    }
    final assessmentRows = await database
        .customSelect(
          'SELECT * FROM assessment_runs WHERE study_cycle_id = ? ORDER BY phase, id',
          variables: [Variable<String>(run.id)],
        )
        .get();
    final assessment = study.assessment;
    final sections = <Map<String, Object?>>[];
    final phases = <String>{};
    if (study.hasConfiguredAssessment &&
        (assessment == null || lease.assessment == null)) {
      _deny();
    }
    if (assessmentRows.isNotEmpty &&
        (assessment == null || lease.assessment == null)) {
      _deny();
    }
    if (assessment != null) {
      final scope = lease.assessment!.scope;
      final runs = await assessment.repository.listRunsForStudyCycle(
        ownerId: ownerId,
        studyCycleId: run.id,
      );
      if (runs.length != assessmentRows.length) _deny();
      final catalog = AssessmentInstrumentCatalog(
        entries: [assessment.definition],
      );
      for (final item in runs) {
        if (!phases.add(item.phase.name)) _deny();
        assessment.mapping.requireMatches(
          scope: scope,
          definition: assessment.definition,
          pinnedRun: item,
        );
        final expected = assessment.command(
          ownerId: ownerId,
          studyCycleId: run.id,
          phase: item.phase,
        );
        if (item.id != expected.runId ||
            item.learningSessionId != expected.learningSessionId ||
            item.participationPermitId != run.permitId ||
            item.participationPermitPayloadSha256 != run.permitPayloadSha256 ||
            item.participationPermitRevision != participation.localRevision ||
            item.consentDecidedAtUtc != run.consentDecidedAtUtc ||
            item.cohort != run.treatment ||
            item.startedAtUtc.isBefore(run.startedAtUtc) ||
            item.startedAtUtc.isAfter(now)) {
          _deny();
        }
        final definition = assessmentDefinitionForRun(item, catalog);
        final outcomes = await assessment.repository.listOutcomeEvidence(
          ownerId: ownerId,
          learningSessionId: item.learningSessionId,
        );
        if (item.state != AssessmentRunState.abandoned) {
          verifiedAssessmentItemIds(item, definition, outcomes);
        }
        if (outcomes.any((fact) => fact.occurredAtUtc.isAfter(now))) _deny();
        final rawAnswers = await database
            .customSelect(
              'SELECT * FROM answer_attempts WHERE session_id = ? ORDER BY occurred_at_utc_ms, id',
              variables: [Variable<String>(item.learningSessionId)],
            )
            .get();
        if (rawAnswers.length != outcomes.length ||
            rawAnswers.any((row) => row.data['owner_id'] != ownerId)) {
          _deny();
        }
        graph.addAll(rawAnswers.map((row) => row.data));
        sections.add({
          'run': alias(item.id),
          'session': alias(item.learningSessionId),
          'phase': item.phase.name,
          'state': item.state.name,
          'startedAtUtc': item.startedAtUtc.toIso8601String(),
          'completedAtUtc': item.completedAtUtc?.toIso8601String(),
          'abandonedAtUtc': item.abandonedAtUtc?.toIso8601String(),
          'instrumentId': item.instrumentId,
          'instrumentVersion': item.instrumentVersion,
          'instrumentRevision': item.instrumentRevision,
          'instrumentChecksumSha256': item.instrumentChecksumSha256,
          'formId': item.formId,
          'formVersion': item.formVersion,
          'formContentRevision': item.formContentRevision,
          'formChecksumSha256': item.formChecksumSha256,
          'featureContractRevision': item.featureContractRevision,
          'featureContractHash': item.featureContractHash,
          'outcomes': [
            for (final fact in outcomes)
              {
                'evidence': alias(fact.sourceEvidenceId),
                'itemId': fact.evidenceContext.assessmentItemId,
                'responseCode': fact.evidenceContext.assessmentResponseCode,
                'correct': fact.isCorrect,
                'responseTimeMs': fact.responseTimeMs,
                'occurredAtUtc': fact.occurredAtUtc.toIso8601String(),
              },
          ],
        });
      }
      final pre = runs
          .where((item) => item.phase == AssessmentPhase.pre)
          .firstOrNull;
      final post = runs
          .where((item) => item.phase == AssessmentPhase.post)
          .firstOrNull;
      if (after != null &&
          (pre == null ||
              pre.state != AssessmentRunState.completed ||
              pre.completedAtUtc!.isAfter(after.firstExposureAtUtc))) {
        _deny();
      }
      if (post != null &&
          (pre?.state != AssessmentRunState.completed ||
              !completionRecorded ||
              index?.state != MotivationIndexSessionState.completed ||
              post.startedAtUtc.isBefore(index!.completedAtUtc!))) {
        _deny();
      }
    }
    graph.addAll(assessmentRows.map((row) => row.data));
    final missing = <String>[
      for (final point in MotivationTimepoint.values)
        if (run.score(point) == null) 'motivation-${point.name}',
      if (after == null) 'first-exposure',
      if (index == null) 'index-session',
      if (!completionRecorded) 'index-completion',
      if (assessment != null)
        for (final phase in AssessmentPhase.values)
          if (!sections.any(
            (section) =>
                section['phase'] == phase.name &&
                section['state'] == 'completed',
          ))
            'assessment-${phase.name}',
    ];
    final instrument = run.instrument;
    final payload = <String, Object?>{
      'schema': 'lexiquest.controlled-study-archive.v1',
      'cycle': alias(run.id),
      'assignment': alias(run.assignmentId),
      'participationPermit': alias(run.permitId),
      'assignmentRevision': run.assignmentRevision,
      'protocolId': run.study.protocolId,
      'protocolVersion': run.study.protocolVersion,
      'protocolRevision': run.protocolRevision,
      'consentVersion': run.consentVersion,
      'treatment': run.treatment,
      'state': run.state.name,
      'startedAtUtc': run.startedAtUtc.toIso8601String(),
      'closedAtUtc': run.closedAtUtc?.toIso8601String(),
      'appVersion': run.study.appVersion,
      'buildId': run.study.buildId,
      'databaseSchemaVersion': run.databaseSchemaVersion,
      'contentRevision': run.study.contentRevision,
      'evidencePolicyVersion': run.study.evidencePolicyVersion,
      'catalogVersion': run.study.catalogVersion,
      'motivation': {
        'instrumentId': instrument.instrumentId,
        'instrumentVersion': instrument.instrumentVersion,
        'instrumentRevision': run.instrumentRevision,
        'instrumentChecksumSha256': instrument.checksumSha256,
        'formId': instrument.formId,
        'formVersion': instrument.formVersion,
        'itemCatalogVersion': instrument.itemCatalogVersion,
        'scoringRuleVersion': motivationScoringRuleVersion,
        'primaryAnalysisEligible':
            run.primaryAnalysisEligible && completionRecorded,
        'responses': [
          for (final response in run.responses)
            {
              'response': alias(response.id),
              'itemId': response.itemId,
              'timepoint': instrument.item(response.itemId).timepoint.name,
              'responseCode': response.responseCode,
              'ordinalValue': response.ordinalValue,
              'answeredAtUtc': response.answeredAtUtc.toIso8601String(),
            },
        ],
      },
      'exposures': exposures,
      'firstExposureEvent': after == null
          ? null
          : alias(after.firstExposureEventId),
      'index': index == null
          ? null
          : {
              'session': alias(index.id),
              'state': index.state.name,
              'completionRecorded': completionRecorded,
              'startedAtUtc': index.startedAtUtc.toIso8601String(),
              'completedAtUtc': index.completedAtUtc?.toIso8601String(),
              'endedAtUtc': indexEndedAtUtc?.toIso8601String(),
              'answers': indexAnswers,
            },
      'assessments': sections,
      'missingPhases': missing,
    };
    _captured(lease, current);
    final encoded = jsonEncode(payload);
    return _ArchiveSnapshot(
      StudyArchivePreview(
        target: target,
        state: run.state.name,
        startedAtUtc: run.startedAtUtc,
        motivationResponseCount: run.responses.length,
        assessmentPhases: phases.toList()..sort(),
        missingPhases: missing,
      ),
      encoded,
      sha256.convert(utf8.encode(jsonEncode([graph, encoded]))).toString(),
      now,
      run.databaseSchemaVersion,
      run.responses.length +
          indexAnswers.length +
          sections.fold<int>(
            0,
            (total, section) => total + (section['outcomes']! as List).length,
          ),
    );
  }

  Future<DateTime> _trustedNow(
    _ArchiveGrant grant,
    bool Function() current,
  ) async {
    final reading = await grant.cache.read();
    _grantCaptured(grant, current);
    if (reading == null || !reading.isFresh) _deny();
    return reading.effectiveNowUtc;
  }

  static Map<String, Object?> _participationFields(
    ResearchParticipationPermit permit,
  ) => {
    'id': permit.id,
    'owner_id': permit.ownerId,
    'local_revision': permit.localRevision,
    'cloud_revision': permit.cloudRevision,
    'is_deleted': permit.isDeleted ? 1 : 0,
    'participant_class': permit.participantClass.name,
    'age_band_code': permit.ageBandCode,
    'assignment_id': permit.assignmentId,
    'assigned_treatment': permit.assignedTreatment.name,
    'consent_receipt_id': permit.consentReceiptId,
    'guardian_permission_receipt_ref': permit.guardianPermissionReceiptRef,
    'learner_assent_receipt_ref': permit.learnerAssentReceiptRef,
    'protocol_id': permit.protocolId,
    'protocol_version': permit.protocolVersion,
    'issued_at_utc_ms': permit.issuedAtUtc.millisecondsSinceEpoch,
    'expires_at_utc_ms': permit.expiresAtUtc.millisecondsSinceEpoch,
    'revoked_at_utc_ms': permit.revokedAtUtc?.millisecondsSinceEpoch,
    'issuer_key_id': permit.issuerKeyId,
    'payload_sha256': permit.payloadSha256,
    'signature': permit.signature,
  };

  static String _date(Object? value) {
    if (value is! int || value < 0) _deny();
    return DateTime.fromMillisecondsSinceEpoch(
      value,
      isUtc: true,
    ).toIso8601String();
  }

  static void _visible(bool Function() current) {
    if (!current()) throw const ExportException(ExportFailureCode.cancelled);
  }

  static Future<T> _boundary<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ExportException {
      rethrow;
    } on Object {
      throw const ExportException(ExportFailureCode.unavailable);
    }
  }

  static Never _deny() =>
      throw const ExportException(ExportFailureCode.unavailable);
}

final class _ArchiveGrant {
  const _ArchiveGrant(this.cache, this.scope, this.generation, this.receipt);
  final LocalResearchAuthorityCache cache;
  final ResearchAuthorityScope scope;
  final int generation;
  final AuthorizedResearchOperation receipt;
  String get fingerprint =>
      sha256.convert(receipt.permit.signedPayload()).toString();
}

final class _ArchiveLease {
  const _ArchiveLease(this.motivation, this.assessment);
  final _ArchiveGrant motivation;
  final _ArchiveGrant? assessment;
  String get fingerprint =>
      '${motivation.fingerprint}:${assessment?.fingerprint}';
}

final class _ArchiveSnapshot {
  const _ArchiveSnapshot(
    this.preview,
    this.json,
    this.fingerprint,
    this.generatedAtUtc,
    this.schemaVersion,
    this.recordCount,
  );
  final StudyArchivePreview preview;
  final String json;
  final String fingerprint;
  final DateTime generatedAtUtc;
  final int schemaVersion;
  final int recordCount;
}

final class _PreparedArchive implements PreparedStudyUploadArchive {
  const _PreparedArchive(this.issuer, this.target, this.lease, this.snapshot);
  final DriftStudyArchiveRepository issuer;
  final StudyArchiveTarget target;
  final _ArchiveLease lease;
  final _ArchiveSnapshot snapshot;

  @override
  StudyArchivePreview get preview => snapshot.preview;

  @override
  ResearchAuthorityScope get motivationScope => lease.motivation.scope;

  @override
  ResearchAuthorityScope get assessmentScope => lease.assessment!.scope;

  @override
  ExportArtifact get artifact => ExportArtifact(
    format: ExportFormat.researchJson,
    suggestedFileName: 'lexiquest-study-archive.json',
    mimeType: 'application/json',
    bytes: Uint8List.fromList(utf8.encode(snapshot.json)),
    recordCount: snapshot.recordCount,
    schemaVersion: snapshot.schemaVersion,
    algorithmVersion: 1,
    generatedAtUtc: snapshot.generatedAtUtc,
    timeZone: 'UTC',
    exclusions: const [
      'owner-and-auth-identifiers',
      'signed-documents-and-receipts',
      'raw-content-and-audio',
      'ordinary-rewards',
      'learning-time',
    ],
  );
}
