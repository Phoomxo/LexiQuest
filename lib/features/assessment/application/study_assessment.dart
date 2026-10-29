import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning/domain/learning_models.dart';
import '../../research/domain/measurement_opportunity.dart';
import '../../research/domain/motivation_measurement.dart';
import '../../research/domain/research_trusted_time.dart';
import '../domain/assessment_authority.dart';
import '../domain/assessment_instrument_catalog.dart';
import '../domain/assessment_models.dart';
import '../domain/assessment_repository.dart';
import 'assessment_comparison.dart';
import 'assessment_use_cases.dart';

/// Explicit Assessment composition. Its writer and authority remain distinct
/// from the Motivation instrument and canonical ordinary learning writer.
final class StudyAssessment {
  StudyAssessment({
    required this.repository,
    required AssessmentInstrumentDefinition definition,
    required this.mapping,
    required this.contentAuthority,
    required this.cycleReader,
    required this.trustedTime,
  }) : _catalog = AssessmentInstrumentCatalog(entries: [definition]),
       definition = definition {
    _catalog.lookup(
      instrumentId: definition.instrumentId,
      instrumentVersion: definition.instrumentVersion,
      formId: definition.formId,
      formVersion: definition.formVersion,
    );
    if (mapping.instrumentId != definition.instrumentId ||
        mapping.instrumentVersion != definition.instrumentVersion ||
        mapping.formId != definition.formId ||
        mapping.formVersion != definition.formVersion ||
        mapping.formContentRevision != definition.formContentRevision ||
        mapping.instrumentChecksumSha256 !=
            definition.instrumentChecksumSha256 ||
        mapping.formChecksumSha256 != definition.formChecksumSha256 ||
        mapping.protocolId != definition.protocolId ||
        mapping.experimentId != definition.experimentId ||
        mapping.experimentVersion != definition.experimentVersion ||
        mapping.contentRevision != definition.contentRevision) {
      throw ArgumentError(
        'Study Assessment mapping does not match its supplied form.',
      );
    }
    useCases = AssessmentUseCases(
      repository: repository,
      instrumentCatalog: _catalog,
      contentAuthority: contentAuthority,
    );
    comparison = AssessmentComparison(
      repository: repository,
      instrumentCatalog: _catalog,
      contentAuthority: contentAuthority,
      cycleReader: cycleReader,
      trustedTime: trustedTime,
    );
  }

  final AssessmentRepository repository;
  final AssessmentFormContentAuthority contentAuthority;
  final AssessmentCycleReader cycleReader;
  final ResearchTrustedTimeSource trustedTime;
  final AssessmentInstrumentCatalog _catalog;
  final AssessmentInstrumentDefinition definition;
  final AssessmentAuthorityMapping mapping;
  late final AssessmentUseCases useCases;
  late final AssessmentComparison comparison;

  AssessmentStartCommand command({
    required String ownerId,
    required String studyCycleId,
    required AssessmentPhase phase,
  }) {
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateCanonicalText(studyCycleId, 'studyCycleId');
    final digest = sha256.convert(
      utf8.encode(jsonEncode([ownerId, studyCycleId, phase.name])),
    );
    return AssessmentStartCommand(
      runId: 'assessment-run:$digest',
      learningSessionId: 'assessment-session:$digest',
      studyCycleId: studyCycleId,
      phase: phase,
      instrumentId: definition.instrumentId,
      instrumentVersion: definition.instrumentVersion,
      formId: definition.formId,
      formVersion: definition.formVersion,
    );
  }

  /// Local historical integrity only. No form-content retrieval, phase authority,
  /// current grant, creation, or capture occurs here, including inside a caller TX.
  Future<StudyAssessmentStatus> inspect({
    required MotivationMeasurementRun cycle,
    required MeasurementOpportunity? opportunity,
    required ConfiguredQuizState? index,
    required bool completionRecorded,
    required int participationPermitRevision,
  }) async {
    final runs = List<AssessmentRun>.unmodifiable(
      await repository.listRunsForStudyCycle(
        ownerId: cycle.ownerId,
        studyCycleId: cycle.id,
      ),
    );
    final byPhase = <AssessmentPhase, AssessmentRun>{};
    DateTime? latest;
    void observe(DateTime value) {
      if (latest == null || value.isAfter(latest!)) latest = value;
    }

    var stopped = false;
    for (final run in runs) {
      if (byPhase.containsKey(run.phase)) {
        throw StateError('Ambiguous Study Assessment phase.');
      }
      final expected = command(
        ownerId: cycle.ownerId,
        studyCycleId: cycle.id,
        phase: run.phase,
      );
      _original(run, expected, cycle, participationPermitRevision);
      final current = await repository.getRun(
        ownerId: cycle.ownerId,
        runId: run.id,
      );
      if (current != run) {
        throw StateError('Study Assessment changed during inspection.');
      }
      observe(run.startedAtUtc);
      if (run.completedAtUtc != null) observe(run.completedAtUtc!);
      if (run.abandonedAtUtc != null) observe(run.abandonedAtUtc!);
      byPhase[run.phase] = run;
      if (run.state == AssessmentRunState.abandoned) {
        stopped = true;
        continue;
      }
      final evidence = List<AssessmentOutcomeEvidence>.unmodifiable(
        await repository.listOutcomeEvidence(
          ownerId: cycle.ownerId,
          learningSessionId: run.learningSessionId,
        ),
      );
      verifiedAssessmentItemIds(
        run,
        assessmentDefinitionForRun(run, _catalog),
        evidence,
      );
      for (final fact in evidence) {
        observe(fact.occurredAtUtc);
      }
      if (run.phase == AssessmentPhase.pre &&
          opportunity != null &&
          (run.state != AssessmentRunState.completed ||
              run.completedAtUtc!.isAfter(opportunity.openedAtUtc))) {
        throw StateError('Assessment pre did not precede the first opening.');
      }
      if (run.phase == AssessmentPhase.post &&
          (index?.state != 'completed' ||
              index?.endedAtUtc == null ||
              !completionRecorded ||
              run.startedAtUtc.isBefore(index!.endedAtUtc!))) {
        throw StateError('Assessment post lacks the original completed index.');
      }
    }
    final pre = byPhase[AssessmentPhase.pre];
    final post = byPhase[AssessmentPhase.post];
    final preCompleted = pre?.state == AssessmentRunState.completed;
    final postCompleted = post?.state == AssessmentRunState.completed;
    if (opportunity != null && !preCompleted) {
      throw StateError('The first opening has no completed Assessment pre.');
    }
    if (post != null && !preCompleted) {
      throw StateError('Assessment post has no completed pre.');
    }
    final pending = stopped
        ? null
        : !preCompleted
        ? command(
            ownerId: cycle.ownerId,
            studyCycleId: cycle.id,
            phase: AssessmentPhase.pre,
          )
        : index?.state == 'completed' && completionRecorded && !postCompleted
        ? command(
            ownerId: cycle.ownerId,
            studyCycleId: cycle.id,
            phase: AssessmentPhase.post,
          )
        : null;
    return StudyAssessmentStatus._(
      pending,
      stopped,
      preCompleted && postCompleted,
      latest,
    );
  }

  void _original(
    AssessmentRun run,
    AssessmentStartCommand expected,
    MotivationMeasurementRun cycle,
    int participationPermitRevision,
  ) {
    if (run.id != expected.runId ||
        run.learningSessionId != expected.learningSessionId ||
        run.ownerId != cycle.ownerId ||
        run.studyCycleId != cycle.id ||
        run.instrumentId != expected.instrumentId ||
        run.instrumentVersion != expected.instrumentVersion ||
        run.formId != expected.formId ||
        run.formVersion != expected.formVersion ||
        run.protocolId != cycle.study.protocolId ||
        run.protocolVersion != cycle.study.protocolVersion ||
        run.protocolRevision != cycle.protocolRevision ||
        run.protocolVersion != mapping.protocolVersion ||
        run.protocolRevision != mapping.protocolRevision ||
        run.instrumentRevision != mapping.instrumentRevision ||
        run.experimentId != cycle.study.experimentId ||
        run.experimentVersion != cycle.study.experimentVersion ||
        run.assignmentId != cycle.assignmentId ||
        run.assignmentRevision != cycle.assignmentRevision ||
        run.cohort != cycle.treatment ||
        run.consentVersion != cycle.consentVersion ||
        run.consentDecidedAtUtc != cycle.consentDecidedAtUtc ||
        run.participationPermitId != cycle.permitId ||
        run.participationPermitRevision != participationPermitRevision ||
        run.participationPermitPayloadSha256 != cycle.permitPayloadSha256 ||
        run.startedAtUtc.isBefore(cycle.startedAtUtc)) {
      throw StateError('Study Assessment original cycle pins do not match.');
    }
    assessmentDefinitionForRun(run, _catalog);
  }
}

/// Pending/completed display markers. Every actual command reauthorizes itself.
final class StudyAssessmentStatus {
  const StudyAssessmentStatus._(
    this.pendingCommand,
    this.stopped,
    this.hasCompletedPair,
    this.latestFactAtUtc,
  );
  final AssessmentStartCommand? pendingCommand;
  final bool stopped;
  final bool hasCompletedPair;
  final DateTime? latestFactAtUtc;
}
