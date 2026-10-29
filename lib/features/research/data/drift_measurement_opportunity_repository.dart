import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../adventure/domain/adventure_entry.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/data/learning_session_lifecycle_observer.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/accepted_quiz_plan.dart';
import '../../learning/domain/learning_models.dart';
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
    String opportunityId, {
    required bool Function() stillVisible,
  }) async {
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
        if (!stillVisible()) _deny(ResearchCaptureReason.sessionUnavailable);
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
      DateTime? missionRecordedAt;
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
          final proof = await _configuredSession(session, completed: false);
          await _requireNoMissionFacts(o, proof.sessionId);
          final now = await _now();
          if (session.startedAtUtcMs > now.millisecondsSinceEpoch) {
            _deny(ResearchCaptureReason.outsideWindow);
          }
          final event = await _missionEnvelope(
            o,
            run,
            proof,
            measurementMissionStartedEventType,
            _milliseconds(now),
          );
          await _insertMission(event);
          missionRecordedAt = event.recordedAtUtc;
          await _update(o, {
            'learning_session_id': session.id,
            'learning_session_started_at_utc_ms': session.startedAtUtcMs,
            'is_index_session': 1,
          });
          await _facts(run);
          await _requireMissionFact(
            o,
            run,
            proof,
            measurementMissionStartedEventType,
            now,
          );
          return _required(run.ownerId, o.id);
        },
        validate: (o, now) {
          if (o != null) _times(o, now);
          if (missionRecordedAt?.isAfter(now) == true) {
            _deny(ResearchCaptureReason.outsideWindow);
          }
        },
      );
    }
  }

  @override
  Future<void> completed(LearningSessionLifecycleFact session) async {
    final linked = await database
        .customSelect(
          'SELECT id,measurement_run_id FROM measurement_opportunities '
          'WHERE owner_id = ? AND learning_session_id = ? AND is_index_session = 1',
          variables: [
            Variable<String>(session.ownerId),
            Variable<String>(session.id),
          ],
        )
        .getSingleOrNull();
    if (linked == null) return;
    DateTime? missionRecordedAt;
    await measurements.writeForActiveRun<MeasurementOpportunity>(
      ownerId: session.ownerId,
      runId: linked.read<String>('measurement_run_id'),
      write: (run) async {
        final opportunity = await _required(
          run.ownerId,
          linked.read<String>('id'),
        );
        _binding(opportunity, run);
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
        final proof = await _configuredSession(session, completed: true);
        final end = facts.indexSession!.completedAtUtc!;
        final now = await _now();
        await _requireMissionFact(
          opportunity,
          run,
          proof,
          measurementMissionStartedEventType,
          now,
        );
        final existing = await _missionRow(
          opportunity,
          proof.sessionId,
          measurementMissionCompletedEventType,
        );
        if (opportunity.closedAtUtc != null) {
          if (opportunity.closedAtUtc != end || existing == null) {
            _deny(ResearchCaptureReason.identityConflict);
          }
          missionRecordedAt = await _requireMissionFact(
            opportunity,
            run,
            proof,
            measurementMissionCompletedEventType,
            now,
            row: existing,
          );
          return opportunity;
        }
        if (existing != null) _deny(ResearchCaptureReason.identityConflict);
        final event = await _missionEnvelope(
          opportunity,
          run,
          proof,
          measurementMissionCompletedEventType,
          _milliseconds(now),
        );
        await _insertMission(event);
        missionRecordedAt = event.recordedAtUtc;
        await _update(opportunity, {
          'closed_at_utc_ms': end.millisecondsSinceEpoch,
        });
        await _facts(run);
        await _requireMissionFact(
          opportunity,
          run,
          proof,
          measurementMissionCompletedEventType,
          now,
        );
        return _required(run.ownerId, opportunity.id);
      },
      validate: (opportunity, now) {
        _times(opportunity, now);
        if (missionRecordedAt?.isAfter(now) == true) {
          _deny(ResearchCaptureReason.outsideWindow);
        }
      },
    );
  }

  /// Verifies committed index facts without collecting or repairing them.
  /// False means both completion projections are absent, not permission to
  /// fabricate a start. Explicit canonical completion retry owns repair.
  Future<bool> inspectIndexFacts({
    required MotivationMeasurementRun run,
    required MeasurementOpportunity opportunity,
    required ConfiguredQuizState index,
    required DateTime nowUtc,
  }) async {
    _binding(opportunity, run);
    final facts = await _facts(run);
    if (facts is! MotivationAfterExposure ||
        facts.firstExposureEventId != opportunity.presentation?.eventId ||
        facts.indexSession?.id != index.sessionId ||
        facts.indexSession?.startedAtUtc != index.startedAtUtc ||
        index.ownerId != run.ownerId ||
        index.plan.mode != 'meaning-quiz' ||
        index.appVersion != run.study.appVersion ||
        index.buildId != run.study.buildId ||
        index.startedAtUtc.isAfter(nowUtc)) {
      _deny(ResearchCaptureReason.sessionUnavailable);
    }
    await _requireMissionFact(
      opportunity,
      run,
      index,
      measurementMissionStartedEventType,
      nowUtc,
    );
    final completed = await _missionRow(
      opportunity,
      index.sessionId,
      measurementMissionCompletedEventType,
    );
    if (index.state != 'completed') {
      if (opportunity.closedAtUtc != null || completed != null) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      return false;
    }
    if (index.checkpoint is! CompletedQuizSession ||
        index.endedAtUtc == null ||
        index.endedAtUtc!.isAfter(nowUtc) ||
        facts.indexSession?.completedAtUtc != index.endedAtUtc) {
      _deny(ResearchCaptureReason.sessionUnavailable);
    }
    if (opportunity.closedAtUtc == null && completed == null) {
      return false;
    }
    if (opportunity.closedAtUtc != index.endedAtUtc || completed == null) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    await _requireMissionFact(
      opportunity,
      run,
      index,
      measurementMissionCompletedEventType,
      nowUtc,
      row: completed,
    );
    return true;
  }

  Future<ConfiguredQuizState> _configuredSession(
    LearningSessionLifecycleFact fact, {
    required bool completed,
  }) async {
    try {
      final proof = await DriftLearningRepository(
        database,
        ownerWrites: measurements.participation.assignments.ownerWrites,
      ).resumeQuiz(sessionId: fact.id, expectedOwnerId: fact.ownerId);
      if (proof.sessionId != fact.id ||
          proof.ownerId != fact.ownerId ||
          proof.activityType != fact.activityType ||
          proof.startedAtUtc.millisecondsSinceEpoch != fact.startedAtUtcMs ||
          proof.appVersion != fact.appVersion ||
          proof.buildId != fact.buildId ||
          proof.state != fact.state ||
          proof.endedAtUtc?.millisecondsSinceEpoch != fact.endedAtUtcMs ||
          proof.plan.mode != 'meaning-quiz' ||
          (completed
              ? proof.state != 'completed' ||
                    proof.checkpoint is! CompletedQuizSession ||
                    proof.endedAtUtc == null
              : proof.state != 'active' ||
                    proof.checkpointRevision != 1 ||
                    proof.checkpoint.stableSerialization !=
                        QuizCheckpoint.initial(
                          proof.plan,
                        ).stableSerialization)) {
        _deny(ResearchCaptureReason.sessionUnavailable);
      }
      return proof;
    } on Object {
      _deny(ResearchCaptureReason.sessionUnavailable);
    }
  }

  Map<String, Object?> _missionPayload(
    MeasurementOpportunity opportunity,
    ConfiguredQuizState proof,
    String type,
  ) {
    final payload = <String, Object?>{
      'assignedTreatment': opportunity.assignedTreatment.wireName,
      'effectivePresentation': opportunity.effectivePresentation.wireName,
      'opportunityId': opportunity.id,
      'planId': proof.plan.id,
      if (type == measurementMissionStartedEventType)
        'mode': proof.plan.mode
      else
        'terminalState': 'completed',
    };
    if (type == measurementMissionStartedEventType) {
      validateMeasurementMissionStartedPayload(payload);
    } else if (type == measurementMissionCompletedEventType) {
      validateMeasurementMissionCompletedPayload(payload);
    } else {
      _deny(ResearchCaptureReason.invalidInput);
    }
    return payload;
  }

  Future<EventEnvelopeV2> _missionEnvelope(
    MeasurementOpportunity opportunity,
    MotivationMeasurementRun run,
    ConfiguredQuizState proof,
    String type,
    DateTime recordedAt,
  ) async {
    final occurred = type == measurementMissionStartedEventType
        ? proof.startedAtUtc
        : proof.endedAtUtc;
    if (occurred == null || recordedAt.isBefore(occurred)) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
    final identity = measurementMissionIdentity(opportunity.id, type);
    return EventEnvelopeV2(
      eventId: researchEventId(identity, occurred),
      eventType: type,
      eventVersion: measurementMissionEventVersion,
      occurredAtUtc: occurred,
      recordedAtUtc: recordedAt,
      actorIdentity: run.ownerId,
      ownerIdentity: run.ownerId,
      aggregateType: 'LearningSession',
      aggregateId: proof.sessionId,
      correlationId: opportunity.id,
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
      payload: Map<String, dynamic>.from(
        _missionPayload(opportunity, proof, type),
      ),
    );
  }

  Future<void> _insertMission(EventEnvelopeV2 envelope) async {
    await database
        .into(database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: envelope.eventId,
            eventType: envelope.eventType,
            eventVersion: envelope.eventVersion,
            occurredAtUtc: envelope.occurredAtUtc,
            recordedAtUtc: envelope.recordedAtUtc,
            actorIdentity: envelope.actorIdentity,
            ownerId: envelope.ownerIdentity,
            aggregateType: envelope.aggregateType,
            aggregateId: envelope.aggregateId,
            correlationId: Value(envelope.correlationId),
            idempotencyKey: envelope.idempotencyKey,
            consentContextJson: jsonEncode(envelope.consentContext.toJson()),
            experimentContextJson: Value(
              jsonEncode(envelope.experimentContext!.toJson()),
            ),
            contentRevision: Value(envelope.contentRevision),
            policyVersion: Value(envelope.policyVersion),
            appVersion: envelope.appVersion,
            buildId: envelope.buildId,
            privacyClassification: envelope.privacyClassification.name,
            payloadJson: jsonEncode(envelope.payload),
          ),
        );
  }

  Future<Map<String, Object?>?> _missionRow(
    MeasurementOpportunity opportunity,
    String sessionId,
    String type,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM events_v2 WHERE idempotency_key = ? OR '
          '(event_type = ? AND (correlation_id = ? OR aggregate_id = ?))',
          variables: [
            Variable<String>(measurementMissionIdentity(opportunity.id, type)),
            Variable<String>(type),
            Variable<String>(opportunity.id),
            Variable<String>(sessionId),
          ],
          readsFrom: {database.eventsV2},
        )
        .get();
    if (rows.length > 1) _deny(ResearchCaptureReason.identityConflict);
    return rows.isEmpty ? null : rows.single.data;
  }

  Future<void> _requireNoMissionFacts(
    MeasurementOpportunity opportunity,
    String sessionId,
  ) async {
    for (final type in [
      measurementMissionStartedEventType,
      measurementMissionCompletedEventType,
    ]) {
      if (await _missionRow(opportunity, sessionId, type) != null) {
        _deny(ResearchCaptureReason.identityConflict);
      }
    }
  }

  Future<DateTime> _requireMissionFact(
    MeasurementOpportunity opportunity,
    MotivationMeasurementRun run,
    ConfiguredQuizState proof,
    String type,
    DateTime now, {
    Map<String, Object?>? row,
  }) async {
    final stored = row ?? await _missionRow(opportunity, proof.sessionId, type);
    if (stored == null) _deny(ResearchCaptureReason.identityConflict);
    final recordedSeconds = stored['recorded_at_utc'];
    if (recordedSeconds is! int ||
        recordedSeconds < 0 ||
        recordedSeconds > now.millisecondsSinceEpoch ~/ 1000) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    final recorded = DateTime.fromMillisecondsSinceEpoch(
      recordedSeconds * 1000,
      isUtc: true,
    );
    final occurred = type == measurementMissionStartedEventType
        ? proof.startedAtUtc
        : proof.endedAtUtc!;
    if (recordedSeconds < occurred.millisecondsSinceEpoch ~/ 1000) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    final expected = await _missionEnvelope(
      opportunity,
      run,
      proof,
      type,
      recorded.isBefore(occurred) ? occurred : recorded,
    );
    final expectedRow = <String, Object?>{
      'event_id': expected.eventId,
      'event_type': expected.eventType,
      'event_version': expected.eventVersion,
      'occurred_at_utc': occurred.millisecondsSinceEpoch ~/ 1000,
      'recorded_at_utc': recordedSeconds,
      'actor_identity': expected.actorIdentity,
      'owner_id': expected.ownerIdentity,
      'tenant_context_json': null,
      'aggregate_type': expected.aggregateType,
      'aggregate_id': expected.aggregateId,
      'correlation_id': expected.correlationId,
      'causation_id': null,
      'idempotency_key': expected.idempotencyKey,
      'consent_context_json': jsonEncode(expected.consentContext.toJson()),
      'experiment_context_json': jsonEncode(
        expected.experimentContext!.toJson(),
      ),
      'content_revision': expected.contentRevision,
      'policy_version': expected.policyVersion,
      'app_version': expected.appVersion,
      'build_id': expected.buildId,
      'provider_provenance_json': null,
      'privacy_classification': expected.privacyClassification.name,
      'payload_json': jsonEncode(expected.payload),
    };
    if (stored.length != expectedRow.length ||
        expectedRow.entries.any((entry) => stored[entry.key] != entry.value)) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    try {
      final decodedOccurrence = researchEventOccurrence(
        stored['event_id']! as String,
        DateTime.fromMillisecondsSinceEpoch(
          (stored['occurred_at_utc']! as int) * 1000,
          isUtc: true,
        ),
      );
      if (decodedOccurrence != occurred) {
        _deny(ResearchCaptureReason.identityConflict);
      }
    } on Object {
      _deny(ResearchCaptureReason.identityConflict);
    }
    return recorded;
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
