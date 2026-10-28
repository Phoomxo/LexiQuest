import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../adventure/domain/adventure_entry.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/data/learning_session_lifecycle_observer.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/research_event_identity.dart';
import 'drift_motivation_measurement_repository.dart';
import 'drift_motivation_measurement_timing_reader.dart';

final class DriftMeasurementOpportunityRepository
    implements LearningSessionLifecycleObserver {
  DriftMeasurementOpportunityRepository(
    this.database, {
    required this.measurements,
    required this.timing,
  }) {
    if (!identical(measurements.database, database) ||
        !identical(timing.database, database) ||
        !identical(measurements.timing, timing)) {
      throw ArgumentError(
        'Opportunity, measurement and timing databases must match',
      );
    }
  }
  @override
  final db.AppDatabase database;
  final DriftMotivationMeasurementRepository measurements;
  final DriftMotivationMeasurementTimingReader timing;

  Future<MeasurementOpportunity?> load(String ownerId, String opportunityId) =>
      timing.loadOpportunity(ownerId, opportunityId);

  Future<MeasurementOpportunity> open({
    required String ownerId,
    required String measurementRunId,
    required String entryAttemptId,
    required TodayExperiencePresentation effectivePresentation,
  }) {
    requireMeasurementEntryId(entryAttemptId);
    return measurements.writeForActiveRun(
      ownerId: ownerId,
      runId: measurementRunId,
      write: (run) async {
        final id = measurementOpportunityId(
          ownerId: ownerId,
          measurementRunId: run.id,
          permitId: run.permitId,
          entryAttemptId: entryAttemptId,
        );
        final previous = await load(ownerId, id);
        if (previous != null) {
          _binding(previous, run);
          if (previous.effectivePresentation != effectivePresentation) {
            _deny(ResearchCaptureReason.identityConflict);
          }
          return previous;
        }
        final now = await _now();
        if (now.isBefore(run.startedAtUtc)) {
          _deny(ResearchCaptureReason.outsideWindow);
        }
        await database.customStatement(
          'INSERT INTO measurement_opportunities (id,owner_id,local_revision,measurement_run_id,permit_id,'
          'entry_attempt_id,assigned_treatment,effective_presentation,opened_at_utc_ms,presented_event_id,'
          'presented_at_utc_ms,learning_session_id,learning_session_started_at_utc_ms,is_index_session,closed_at_utc_ms) '
          'VALUES (?,?,1,?,?,?,?,?,?,NULL,NULL,NULL,NULL,0,NULL)',
          [
            id,
            ownerId,
            run.id,
            run.permitId,
            entryAttemptId,
            run.treatment,
            effectivePresentation.wireName,
            now.millisecondsSinceEpoch,
          ],
        );
        return _required(ownerId, id);
      },
      validate: _times,
    );
  }

  Future<MeasurementOpportunity> recordPresented(
    String ownerId,
    String opportunityId,
  ) async {
    final initial = await _required(ownerId, opportunityId);
    late MotivationMeasurementRun checkedRun;
    var wrotePresentation = false;
    return measurements.writeForActiveRun(
      ownerId: ownerId,
      runId: initial.measurementRunId,
      write: (run) async {
        checkedRun = run;
        final o = await _required(ownerId, opportunityId);
        _binding(o, run);
        if (o.presentation != null) {
          await _facts(run);
          return o;
        }
        if (o.closedAtUtc != null) {
          _deny(ResearchCaptureReason.noActiveRun);
        }
        final now = await _now();
        _baselineAt(run, now);
        final at = _milliseconds(now);
        final identity = measurementPresentedIdentity(o.id);
        final eventId = researchEventId(identity, at);
        final payload = <String, Object?>{
          'assignedTreatment': o.assignedTreatment.wireName,
          'effectivePresentation': o.effectivePresentation.wireName,
          'entryAttemptId': o.entryAttemptId,
          'catalogVersion': run.study.catalogVersion,
        };
        validateMeasurementPresentedPayload(payload);
        final envelope = EventEnvelopeV2(
          eventId: eventId,
          eventType: measurementPresentedEventType,
          eventVersion: measurementPresentedEventVersion,
          occurredAtUtc: at,
          recordedAtUtc: at,
          actorIdentity: ownerId,
          ownerIdentity: ownerId,
          aggregateType: 'MeasurementOpportunity',
          aggregateId: o.id,
          correlationId: o.id,
          idempotencyKey: identity,
          consentContext: ConsentContext(
            researchConsentVersion: run.consentVersion,
            aiConsentGranted: false,
            voiceConsentGranted: false,
            socialConsentGranted: false,
          ),
          experimentContext: ExperimentContext(
            experimentId: run.study.experimentId,
            variantId: run.treatment,
            assignedAtUtc: await _assignedAt(run),
          ),
          contentRevision: run.study.contentRevision,
          policyVersion: run.study.evidencePolicyVersion,
          appVersion: run.study.appVersion,
          buildId: run.study.buildId,
          privacyClassification: PrivacyClassification.ownerOnly,
          payload: Map<String, dynamic>.from(payload),
        );
        await database
            .into(database.eventsV2)
            .insert(
              db.EventsV2Companion.insert(
                eventId: eventId,
                eventType: envelope.eventType,
                eventVersion: envelope.eventVersion,
                occurredAtUtc: at,
                recordedAtUtc: at,
                actorIdentity: ownerId,
                ownerId: ownerId,
                aggregateType: envelope.aggregateType,
                aggregateId: o.id,
                correlationId: Value(o.id),
                idempotencyKey: identity,
                consentContextJson: jsonEncode(
                  envelope.consentContext.toJson(),
                ),
                experimentContextJson: Value(
                  jsonEncode(envelope.experimentContext!.toJson()),
                ),
                contentRevision: Value(envelope.contentRevision),
                policyVersion: Value(envelope.policyVersion),
                appVersion: envelope.appVersion,
                buildId: envelope.buildId,
                privacyClassification: envelope.privacyClassification.name,
                payloadJson: jsonEncode(payload),
              ),
            );
        await _update(o, {
          'presented_event_id': eventId,
          'presented_at_utc_ms': at.millisecondsSinceEpoch,
        });
        wrotePresentation = true;
        await _facts(run);
        return _required(ownerId, o.id);
      },
      validate: (o, now) {
        _times(o, now);
        _binding(o, checkedRun);
        if (wrotePresentation) _baselineAt(checkedRun, now);
      },
    );
  }

  @override
  Future<void> accepted(LearningSessionLifecycleFact session) async {
    final study = measurements.participation.assignments.binding.study;
    final runs = await database
        .customSelect(
          "SELECT id FROM motivation_measurement_runs WHERE owner_id = ? AND state = 'started' AND protocol_id = ? AND protocol_version = ?",
          variables: [
            Variable<String>(session.ownerId),
            Variable<String>(study.protocolId),
            Variable<String>(study.protocolVersion),
          ],
        )
        .get();
    for (final row in runs) {
      await measurements.writeForActiveRun<MeasurementOpportunity?>(
        ownerId: session.ownerId,
        runId: row.read<String>('id'),
        write: (run) async {
          final facts = await timing.readForAcceptedSession(
            ownerId: run.ownerId,
            runId: run.id,
            permitId: run.permitId,
            assignmentId: run.assignmentId,
            session: session,
          );
          if (facts == null) {
            _deny(ResearchCaptureReason.timingUnavailable);
          }
          if (facts is! MotivationAfterExposure || facts.indexSession != null) {
            return null;
          }
          final first = await database
              .customSelect(
                'SELECT id FROM measurement_opportunities WHERE owner_id = ? AND presented_event_id = ?',
                variables: [
                  Variable<String>(run.ownerId),
                  Variable<String>(facts.firstExposureEventId),
                ],
              )
              .getSingleOrNull();
          if (first == null) {
            _deny(ResearchCaptureReason.timingUnavailable);
          }
          final o = await _required(run.ownerId, first.read<String>('id'));
          _binding(o, run);
          final now = await _now();
          if (session.startedAtUtcMs > now.millisecondsSinceEpoch) {
            _deny(ResearchCaptureReason.outsideWindow);
          }
          await _update(o, {
            'learning_session_id': session.id,
            'learning_session_started_at_utc_ms': session.startedAtUtcMs,
            'is_index_session': 1,
          });
          await _facts(run);
          return _required(run.ownerId, o.id);
        },
        validate: (o, now) {
          if (o != null) _times(o, now);
        },
      );
    }
  }

  @override
  Future<void> completed(LearningSessionLifecycleFact session) async {
    final linked = await database
        .customSelect(
          'SELECT id,measurement_run_id FROM measurement_opportunities WHERE owner_id = ? AND learning_session_id = ? AND is_index_session = 1',
          variables: [
            Variable<String>(session.ownerId),
            Variable<String>(session.id),
          ],
        )
        .getSingleOrNull();
    if (linked == null) {
      return;
    }
    await measurements.writeForActiveRun<MeasurementOpportunity>(
      ownerId: session.ownerId,
      runId: linked.read<String>('measurement_run_id'),
      write: (run) async {
        final o = await _required(run.ownerId, linked.read<String>('id'));
        _binding(o, run);
        final facts = await _facts(run);
        if (facts is! MotivationAfterExposure ||
            facts.indexSession?.id != session.id ||
            facts.indexSession?.state !=
                MotivationIndexSessionState.completed ||
            session.state != 'completed' ||
            facts.indexSession?.startedAtUtc.millisecondsSinceEpoch !=
                session.startedAtUtcMs ||
            facts.indexSession?.completedAtUtc?.millisecondsSinceEpoch !=
                session.endedAtUtcMs ||
            session.activityType == 'syncedEvidence' ||
            session.appVersion != run.study.appVersion ||
            session.buildId != run.study.buildId) {
          _deny(ResearchCaptureReason.sessionUnavailable);
        }
        final end = facts.indexSession!.completedAtUtc!;
        if (o.closedAtUtc != null) {
          if (o.closedAtUtc != end) {
            _deny(ResearchCaptureReason.identityConflict);
          }
          return o;
        }
        await _update(o, {'closed_at_utc_ms': end.millisecondsSinceEpoch});
        await _facts(run);
        return _required(run.ownerId, o.id);
      },
      validate: _times,
    );
  }

  Future<MotivationTimingFacts> _facts(MotivationMeasurementRun run) async {
    final facts = await timing.read(
      ownerId: run.ownerId,
      runId: run.id,
      permitId: run.permitId,
      assignmentId: run.assignmentId,
    );
    if (facts == null) {
      _deny(ResearchCaptureReason.timingUnavailable);
    }
    return facts;
  }

  Future<DateTime> _assignedAt(MotivationMeasurementRun run) async {
    final row = await database
        .customSelect(
          'SELECT assigned_at_utc_ms FROM experiment_assignments WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(run.assignmentId),
            Variable<String>(run.ownerId),
          ],
        )
        .getSingle();
    return DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('assigned_at_utc_ms'),
      isUtc: true,
    );
  }

  Future<MeasurementOpportunity> _required(String ownerId, String id) async {
    final result = await load(ownerId, id);
    if (result == null) {
      _deny(ResearchCaptureReason.noActiveRun);
    }
    return result;
  }

  Future<void> _update(
    MeasurementOpportunity o,
    Map<String, Object?> fields,
  ) async {
    final values = {...fields, 'local_revision': o.localRevision + 1};
    await database.customStatement(
      'UPDATE measurement_opportunities SET ${values.keys.map((key) => '$key = ?').join(', ')} WHERE id = ? AND owner_id = ? AND local_revision = ?',
      [...values.values, o.id, o.ownerId, o.localRevision],
    );
    final changed = await database
        .customSelect('SELECT changes() AS n')
        .getSingle();
    if (changed.read<int>('n') != 1) {
      _deny(ResearchCaptureReason.identityConflict);
    }
  }

  Future<DateTime> _now() async {
    final reading = await measurements.participation.assignments.trustedTime
        .read();
    if (reading == null ||
        !reading.isFresh ||
        !reading.effectiveNowUtc.isUtc ||
        reading.effectiveNowUtc.microsecondsSinceEpoch < 0) {
      _deny(ResearchCaptureReason.invalidPermit);
    }
    return reading.effectiveNowUtc;
  }

  static void _binding(MeasurementOpportunity o, MotivationMeasurementRun run) {
    if (o.ownerId != run.ownerId ||
        o.measurementRunId != run.id ||
        o.permitId != run.permitId ||
        o.assignedTreatment.wireName != run.treatment ||
        o.openedAtUtc.isBefore(run.startedAtUtc)) {
      _deny(ResearchCaptureReason.identityConflict);
    }
  }

  static void _times(MeasurementOpportunity o, DateTime now) {
    if (o.openedAtUtc.isAfter(now) ||
        o.presentation?.occurredAtUtc.isAfter(now) == true ||
        o.indexLink?.startedAtUtc.isAfter(now) == true ||
        o.closedAtUtc?.isAfter(now) == true) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
  }

  static void _baselineAt(MotivationMeasurementRun run, DateTime now) {
    if (run.score(MotivationTimepoint.baseline) == null) {
      _deny(ResearchCaptureReason.incomplete);
    }
    for (final response in run.responses.where(
      (r) =>
          run.instrument.item(r.itemId).timepoint ==
          MotivationTimepoint.baseline,
    )) {
      if (response.answeredAtUtc.isAfter(now) ||
          response.answeredAtUtc.isBefore(
            now.subtract(const Duration(hours: 24)),
          )) {
        _deny(ResearchCaptureReason.outsideWindow);
      }
    }
  }

  static DateTime _milliseconds(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value.millisecondsSinceEpoch,
        isUtc: true,
      );
  static Never _deny(ResearchCaptureReason reason) =>
      throw ResearchCaptureDenied(reason);
}
