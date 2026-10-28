import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_measurement_repository.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_event_identity.dart';
import 'drift_research_participation_repository.dart';

final class DriftMotivationMeasurementRepository
    implements MotivationMeasurementRepository {
  DriftMotivationMeasurementRepository(
    this.database, {
    required this.study,
    required this.participation,
    required this.nowUtc,
  });
  final db.AppDatabase database;
  final MotivationStudyProtocol study;
  final DriftResearchParticipationRepository participation;
  final DateTime Function() nowUtc;

  String runIdFor(String ownerId, String permitId) =>
      'motivation:${sha256.convert(utf8.encode(jsonEncode([ownerId, permitId, study.protocolId, study.protocolVersion, study.instrument.checksumSha256])))}';

  @override
  Future<MotivationMeasurementRun> start(MotivationMeasurementStart command) =>
      database.transaction(() async {
        final context = await participation.requireParticipant(
          command.ownerId,
          command.permitId,
        );
        final id = runIdFor(command.ownerId, command.permitId);
        final existing = await load(command.ownerId, id);
        if (existing != null) return existing;
        final conflicts =
            await (database.select(database.motivationMeasurementRuns)..where(
                  (row) =>
                      row.ownerId.equals(command.ownerId) &
                      row.assignmentId.equals(context.assignment.id) &
                      row.protocolId.equals(study.protocolId) &
                      row.protocolVersion.equals(study.protocolVersion),
                ))
                .get();
        if (conflicts.isNotEmpty) {
          throw const ResearchCaptureDenied(
            ResearchCaptureReason.versionConflict,
          );
        }
        final now = nowUtc();
        requireResearchUtc(now);
        final instrument = study.instrument;
        await database
            .into(database.motivationMeasurementRuns)
            .insert(
              db.MotivationMeasurementRunsCompanion.insert(
                id: id,
                ownerId: command.ownerId,
                assignmentId: context.assignment.id,
                consentVersion: study.consentVersion,
                consentDecidedAtUtcMs: context.consent.decidedAtUtcMs,
                protocolId: study.protocolId,
                protocolVersion: study.protocolVersion,
                treatment: context.assignment.cohort,
                instrumentId: instrument.instrumentId,
                instrumentVersion: instrument.instrumentVersion,
                formId: instrument.formId,
                formVersion: instrument.formVersion,
                appVersion: study.appVersion,
                buildId: study.buildId,
                databaseSchemaVersion: db.AppDatabase.currentSchemaVersion,
                contentRevision: study.contentRevision,
                evidencePolicyVersion: study.evidencePolicyVersion,
                state: 'started',
                startedAtUtcMs: now.millisecondsSinceEpoch,
              ),
            );
        return (await load(command.ownerId, id))!;
      });

  Future<ResearchParticipantSnapshot> requireActiveRun(
    MotivationMeasurementRun run,
  ) async {
    final context = await participation.requireParticipant(
      run.ownerId,
      run.permitId,
    );
    final row = await (database.select(
      database.motivationMeasurementRuns,
    )..where((row) => row.id.equals(run.id))).getSingleOrNull();
    if (row == null || row.isDeleted || row.state != 'started') {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    _checkPins(row);
    if (row.consentVersion != study.consentVersion ||
        row.consentDecidedAtUtcMs != context.consent.decidedAtUtcMs ||
        row.assignmentId != context.assignment.id ||
        row.treatment != context.assignment.cohort ||
        row.startedAtUtcMs <
            context.permit.issuedAtUtc.millisecondsSinceEpoch) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.versionConflict);
    }
    return context;
  }

  @override
  Future<MotivationMeasurementRun> record(
    MotivationResponse response,
  ) => database.transaction(() async {
    var run = await load(response.ownerId, response.runId);
    if (run == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    await requireActiveRun(run);
    run = (await load(response.ownerId, response.runId))!;
    final item = study.instrument.item(response.itemId);
    final option = study.instrument.response(
      response.itemId,
      response.responseCode,
    );
    final previous = run.responses
        .where((entry) => entry.itemId == response.itemId)
        .firstOrNull;
    if (previous != null) {
      if (previous.responseCode != response.responseCode) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.identityConflict,
        );
      }
      return run;
    }
    final now = nowUtc();
    requireResearchUtc(now);
    if (now.isBefore(run.startedAtUtc)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.outsideWindow);
    }
    if (item.timepoint == MotivationTimepoint.baseline) {
      if (run.firstExposureAtUtc != null) {
        throw const ResearchCaptureDenied(ResearchCaptureReason.outsideWindow);
      }
    } else {
      final completion = run.indexCompletionAtUtc;
      if (completion == null ||
          now.isBefore(completion) ||
          now.isAfter(completion.add(const Duration(minutes: 30)))) {
        throw const ResearchCaptureDenied(ResearchCaptureReason.outsideWindow);
      }
    }
    final id =
        'response:${sha256.convert(utf8.encode(jsonEncode([run.id, response.itemId])))}';
    await database
        .into(database.motivationResponses)
        .insert(
          db.MotivationResponsesCompanion.insert(
            id: id,
            ownerId: run.ownerId,
            runId: run.id,
            itemId: item.id,
            itemCatalogVersion: study.instrument.itemCatalogVersion,
            responseCode: option.code,
            ordinalValue: Value(option.ordinalValue),
            answeredAtUtcMs: now.millisecondsSinceEpoch,
          ),
        );
    return (await load(run.ownerId, run.id))!;
  });

  @override
  Future<MotivationMeasurementRun> close(
    MotivationMeasurementClose command,
  ) => database.transaction(() async {
    final run = await load(command.ownerId, command.runId);
    if (run == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    // Repeated close is a read, never a new research write.
    if (run.state == command.state &&
        command.state != MotivationMeasurementRunState.started) {
      return run;
    }
    if (command.state == MotivationMeasurementRunState.started) {
      throw const FormatException('Cannot reopen a run');
    }
    if (command.state == MotivationMeasurementRunState.withdrawn) {
      await participation.lockOwner(command.ownerId);
    } else {
      await requireActiveRun(run);
    }
    if (command.state == MotivationMeasurementRunState.completed &&
        (run.score(MotivationTimepoint.baseline) == null ||
            run.score(MotivationTimepoint.post) == null)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.incomplete);
    }
    final now = nowUtc();
    requireResearchUtc(now);
    await database.customUpdate(
      'UPDATE motivation_measurement_runs SET state=?,closed_at_utc_ms=?,local_revision=local_revision+1 WHERE id=? AND owner_id=?',
      variables: [
        Variable<String>(command.state.name),
        Variable<int>(now.millisecondsSinceEpoch),
        Variable<String>(run.id),
        Variable<String>(run.ownerId),
      ],
      updates: {database.motivationMeasurementRuns},
    );
    return (await load(run.ownerId, run.id))!;
  });

  @override
  Future<MotivationMeasurementRun?> load(String ownerId, String runId) async {
    final row =
        await (database.select(database.motivationMeasurementRuns)..where(
              (row) => row.id.equals(runId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    _checkPins(row);
    final permits =
        await (database.select(database.researchParticipationPermits)..where(
              (p) =>
                  p.ownerId.equals(ownerId) &
                  p.assignmentId.equals(row.assignmentId),
            ))
            .get();
    final matching = permits
        .where((p) => runIdFor(ownerId, p.id) == runId)
        .toList();
    if (matching.length != 1) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.versionConflict);
    }
    final answers =
        await (database.select(database.motivationResponses)..where(
              (r) =>
                  r.runId.equals(runId) &
                  r.ownerId.equals(ownerId) &
                  r.isDeleted.equals(false),
            ))
            .get();
    for (final answer in answers) {
      final option = study.instrument.response(
        answer.itemId,
        answer.responseCode,
      );
      if (answer.itemCatalogVersion != study.instrument.itemCatalogVersion ||
          answer.ordinalValue != option.ordinalValue) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.versionConflict,
        );
      }
    }
    final exposure = await database
        .customSelect(
          "SELECT e.event_id,e.occurred_at_utc FROM measurement_opportunities o JOIN events_v2 e ON e.event_id=o.presented_event_id AND e.owner_id=o.owner_id AND e.aggregate_id=o.id AND e.correlation_id=o.id WHERE o.owner_id=? AND o.measurement_run_id=? AND o.is_deleted=0 AND e.event_type='TodayExperiencePresented' AND e.event_version=1 AND e.aggregate_type='MeasurementOpportunity' ORDER BY e.event_id LIMIT 1",
          variables: [Variable<String>(ownerId), Variable<String>(runId)],
        )
        .getSingleOrNull();
    final first = exposure == null
        ? null
        : researchEventOccurrence(
            exposure.read<String>('event_id'),
            exposure.read<DateTime>('occurred_at_utc'),
          );
    // MDS §5.1: the FIRST ACCEPTED session is the index, not whichever session
    // completes first. An incomplete/abandoned index cannot be replaced later.
    final completion = first == null
        ? null
        : await database
              .customSelect(
                "SELECT s.state,s.ended_at_utc_ms,s.started_at_utc_ms FROM measurement_opportunities o JOIN learning_sessions s ON s.id=o.learning_session_id AND s.owner_id=o.owner_id JOIN events_v2 e ON e.event_id=o.started_event_id AND e.owner_id=o.owner_id AND e.aggregate_id=s.id AND e.correlation_id=o.id WHERE o.owner_id=? AND o.measurement_run_id=? AND o.is_deleted=0 AND e.event_type='TodayExperienceMissionStarted' AND e.event_version=1 AND e.aggregate_type='LearningSession' AND s.started_at_utc_ms>=? ORDER BY s.started_at_utc_ms,e.event_id LIMIT 1",
                variables: [
                  Variable<String>(ownerId),
                  Variable<String>(runId),
                  Variable<int>(first.millisecondsSinceEpoch),
                ],
              )
              .getSingleOrNull();
    final end = completion?.readNullable<int>('ended_at_utc_ms');
    final index =
        completion != null &&
            completion.read<String>('state') == 'completed' &&
            end != null &&
            end >= completion.read<int>('started_at_utc_ms')
        ? end
        : null;
    return MotivationMeasurementRun(
      id: row.id,
      ownerId: row.ownerId,
      permitId: matching.single.id,
      assignmentId: row.assignmentId,
      instrument: study.instrument,
      state: MotivationMeasurementRunState.values.byName(row.state),
      startedAtUtc: researchUtc(row.startedAtUtcMs),
      closedAtUtc: row.closedAtUtcMs == null
          ? null
          : researchUtc(row.closedAtUtcMs!),
      firstExposureAtUtc: first,
      indexCompletionAtUtc: index == null ? null : researchUtc(index),
      responses: [
        for (final answer in answers)
          RecordedMotivationResponse(
            itemId: answer.itemId,
            responseCode: answer.responseCode,
            ordinalValue: answer.ordinalValue,
            answeredAtUtc: researchUtc(answer.answeredAtUtcMs),
          ),
      ],
    );
  }

  void _checkPins(db.MotivationMeasurementRunRow row) {
    final i = study.instrument;
    if (row.protocolId != study.protocolId ||
        row.protocolVersion != study.protocolVersion ||
        row.instrumentId != i.instrumentId ||
        row.instrumentVersion != i.instrumentVersion ||
        row.formId != i.formId ||
        row.formVersion != i.formVersion ||
        row.appVersion != study.appVersion ||
        row.buildId != study.buildId ||
        row.databaseSchemaVersion != db.AppDatabase.currentSchemaVersion ||
        row.contentRevision != study.contentRevision ||
        row.evidencePolicyVersion != study.evidencePolicyVersion) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.versionConflict);
    }
  }
}
