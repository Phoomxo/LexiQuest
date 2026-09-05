import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart' as db;
import '../../adventure/domain/adventure_entry.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../events/domain/today_experience_event_payload_policy.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_event_identity.dart';
import 'drift_motivation_measurement_repository.dart';
import 'drift_research_participation_repository.dart';

final class DriftMeasurementOpportunityRepository {
  DriftMeasurementOpportunityRepository(
    this.database, {
    required this.measurements,
    required this.nowUtc,
  });
  final db.AppDatabase database;
  final DriftMotivationMeasurementRepository measurements;
  final DateTime Function() nowUtc;
  Future<void> _requireLearningPurpose(String owner, String session) async {
    try {
      if (!(await DriftPairMatchingSessionPurposeReader(
        database,
      ).read(ownerId: owner, sessionId: session)).allowsLearningAuthority) {
        throw StateError('Replay or unknown matching');
      }
    } catch (_) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
  }

  Future<MeasurementOpportunity> open({
    required String ownerId,
    required String measurementRunId,
    required String entryAttemptId,
    required TodayExperiencePresentation effectivePresentation,
  }) => database.transaction(() async {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(entryAttemptId)) {
      throw const FormatException('Expected entry UUID v4');
    }
    final initial = await measurements.load(ownerId, measurementRunId);
    if (initial == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    final context = await measurements.requireActiveRun(initial);
    final run = (await measurements.load(ownerId, measurementRunId))!;
    final id =
        'opportunity:${sha256.convert(utf8.encode(jsonEncode([ownerId, run.id, run.permitId, entryAttemptId])))}';
    final existing = await load(ownerId, id);
    if (existing != null) return existing;
    final now = nowUtc();
    requireResearchUtc(now);
    if (now.isBefore(run.startedAtUtc) ||
        run.responses.any((r) => r.answeredAtUtc.isAfter(now))) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.outsideWindow);
    }
    await database
        .into(database.measurementOpportunities)
        .insert(
          db.MeasurementOpportunitiesCompanion.insert(
            id: id,
            ownerId: ownerId,
            measurementRunId: run.id,
            permitId: run.permitId,
            entryAttemptId: entryAttemptId,
            assignedTreatment: context.permit.assignedTreatment.name,
            effectivePresentation: effectivePresentation.name,
            openedAtUtcMs: now.millisecondsSinceEpoch,
          ),
        );
    return (await load(ownerId, id))!;
  });

  Future<MeasurementOpportunity?> load(
    String ownerId,
    String opportunityId,
  ) async {
    final row =
        await (database.select(database.measurementOpportunities)..where(
              (r) =>
                  r.ownerId.equals(ownerId) &
                  r.id.equals(opportunityId) &
                  r.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return MeasurementOpportunity(
      id: row.id,
      ownerId: row.ownerId,
      measurementRunId: row.measurementRunId,
      permitId: row.permitId,
      entryAttemptId: row.entryAttemptId,
      assignedTreatment: TodayExperiencePresentationCodec.decode(
        row.assignedTreatment,
      ),
      effectivePresentation: TodayExperiencePresentationCodec.decode(
        row.effectivePresentation,
      ),
      openedAtUtc: researchUtc(row.openedAtUtcMs),
      closedAtUtc: row.closedAtUtcMs == null
          ? null
          : researchUtc(row.closedAtUtcMs!),
      localRevision: row.localRevision,
      lastSwitchOrdinal: row.lastSwitchOrdinal,
      suppressedSwitchCount: row.suppressedSwitchCount,
      presentedEventId: row.presentedEventId,
      learningSessionId: row.learningSessionId,
      startedEventId: row.startedEventId,
      completedEventId: row.completedEventId,
    );
  }

  Future<(MeasurementOpportunity, ResearchParticipantSnapshot)> _active(
    String ownerId,
    String id,
  ) async {
    final initial = await load(ownerId, id);
    if (initial == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    final run = await measurements.load(ownerId, initial.measurementRunId);
    if (run == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    final context = await measurements.requireActiveRun(run);
    // Discard pre-lookup snapshots after asynchronous authority validation.
    final o = await load(ownerId, id);
    if (o == null ||
        o.permitId != context.permit.id ||
        o.measurementRunId != run.id ||
        o.assignedTreatment != context.permit.assignedTreatment) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
    final now = nowUtc();
    requireResearchUtc(now);
    if (now.isBefore(o.openedAtUtc)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.outsideWindow);
    }
    return (o, context);
  }

  Future<MeasurementOpportunity> recordPresented(
    String ownerId,
    String opportunityId,
  ) => database.transaction(() async {
    final (o, context) = await _active(ownerId, opportunityId);
    if (o.presentedEventId != null) return o;
    final run = (await measurements.load(ownerId, o.measurementRunId))!;
    if (run.score(MotivationTimepoint.baseline) == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.incomplete);
    }
    if (o.closedAtUtc != null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    final event =
        await _event(o, context, 'TodayExperiencePresented', nowUtc(), {
          ..._presentation(o),
          'entryAttemptId': o.entryAttemptId,
          'catalogVersion': measurements.study.catalogVersion,
        });
    await _update(
      o,
      db.MeasurementOpportunitiesCompanion(presentedEventId: Value(event)),
    );
    return (await load(ownerId, opportunityId))!;
  });

  Future<MeasurementOpportunity> changePresentation({
    required String ownerId,
    required String opportunityId,
    required TodayExperiencePresentation presentation,
    required int expectedRevision,
  }) => database.transaction(() async {
    final (o, context) = await _active(ownerId, opportunityId);
    if (expectedRevision < 1) {
      throw const FormatException('Expected positive revision');
    }
    if (o.localRevision != expectedRevision ||
        presentation == o.effectivePresentation) {
      return o;
    }
    if (o.presentedEventId == null || o.closedAtUtc != null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    final ordinal = o.lastSwitchOrdinal + 1;
    if (ordinal <= 10) {
      await _event(o, context, 'TodayExperiencePresentationChanged', nowUtc(), {
        'assignedTreatment': o.assignedTreatment.name,
        'effectivePresentation': presentation.name,
        'fromPresentation': o.effectivePresentation.name,
        'switchOrdinal': ordinal,
      }, ordinal: ordinal);
    }
    await _update(
      o,
      db.MeasurementOpportunitiesCompanion(
        effectivePresentation: Value(presentation.name),
        lastSwitchOrdinal: Value(ordinal <= 10 ? ordinal : 10),
        suppressedSwitchCount: Value(
          o.suppressedSwitchCount + (ordinal > 10 ? 1 : 0),
        ),
      ),
    );
    return (await load(ownerId, opportunityId))!;
  });

  Future<MeasurementOpportunity> attachAcceptedSession({
    required String ownerId,
    required String opportunityId,
    required String learningSessionId,
    required String planId,
    required LessonMode mode,
  }) => database.transaction(() async {
    requireResearchCode(learningSessionId);
    requireResearchCode(planId);
    final (o, context) = await _active(ownerId, opportunityId);
    await _requireLearningPurpose(ownerId, learningSessionId);
    if (o.learningSessionId != null) {
      if (o.learningSessionId != learningSessionId) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.identityConflict,
        );
      }
      final event = await _linkedEvent(
        o,
        o.startedEventId,
        'TodayExperienceMissionStarted',
      );
      final payload = jsonDecode(event.payloadJson) as Map;
      if (payload['planId'] != planId || payload['mode'] != mode.id) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.identityConflict,
        );
      }
      return o;
    }
    if (o.closedAtUtc != null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noActiveRun);
    }
    final presented = await _linkedEvent(
      o,
      o.presentedEventId,
      'TodayExperiencePresented',
    );
    final exposure = researchEventOccurrence(
      presented.eventId,
      presented.occurredAtUtc,
    );
    final session =
        await (database.select(database.learningSessions)..where(
              (s) => s.id.equals(learningSessionId) & s.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (session == null ||
        !{'active', 'completed'}.contains(session.state) ||
        session.startedAtUtcMs < exposure.millisecondsSinceEpoch ||
        session.startedAtUtcMs > nowUtc().millisecondsSinceEpoch ||
        session.sessionConfigurationJson == null) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    SessionConfiguration configuration;
    try {
      configuration = SessionConfiguration.fromStableSerialization(
        session.sessionConfigurationJson!,
      );
    } on Object {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    if (configuration.ownerId != ownerId ||
        configuration.mode != mode ||
        configuration.contentIdentity != session.sessionConfigurationIdentity) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    final duplicates =
        await (database.select(database.measurementOpportunities)..where(
              (r) =>
                  r.ownerId.equals(ownerId) &
                  r.learningSessionId.equals(learningSessionId),
            ))
            .get();
    if (duplicates.isNotEmpty) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
    final event = await _event(
      o,
      context,
      'TodayExperienceMissionStarted',
      researchUtc(session.startedAtUtcMs),
      {
        ..._presentation(o),
        'opportunityId': o.id,
        'planId': planId,
        'mode': mode.id,
      },
      sessionId: learningSessionId,
    );
    await _update(
      o,
      db.MeasurementOpportunitiesCompanion(
        learningSessionId: Value(learningSessionId),
        startedEventId: Value(event),
      ),
    );
    return (await load(ownerId, opportunityId))!;
  });

  Future<MeasurementOpportunity> completeAcceptedSession(
    String ownerId,
    String opportunityId,
  ) => database.transaction(() async {
    final (o, context) = await _active(ownerId, opportunityId);
    if (o.learningSessionId != null) {
      await _requireLearningPurpose(ownerId, o.learningSessionId!);
    }
    if (o.completedEventId != null) return o;
    if (o.closedAtUtc != null || o.learningSessionId == null) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    final started = await _linkedEvent(
      o,
      o.startedEventId,
      'TodayExperienceMissionStarted',
    );
    final session =
        await (database.select(database.learningSessions)..where(
              (s) =>
                  s.id.equals(o.learningSessionId!) & s.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (session == null ||
        session.state != 'completed' ||
        session.endedAtUtcMs == null ||
        session.endedAtUtcMs! < session.startedAtUtcMs ||
        session.endedAtUtcMs! > nowUtc().millisecondsSinceEpoch) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    final event = await _event(
      o,
      context,
      'TodayExperienceMissionCompleted',
      researchUtc(session.endedAtUtcMs!),
      {
        ..._presentation(o),
        'opportunityId': o.id,
        'planId': (jsonDecode(started.payloadJson) as Map)['planId'],
        'terminalState': 'completed',
      },
      sessionId: session.id,
    );
    await _update(
      o,
      db.MeasurementOpportunitiesCompanion(
        completedEventId: Value(event),
        closedAtUtcMs: Value(session.endedAtUtcMs),
      ),
    );
    return (await load(ownerId, opportunityId))!;
  });

  Map<String, dynamic> _presentation(MeasurementOpportunity o) => {
    'assignedTreatment': o.assignedTreatment.name,
    'effectivePresentation': o.effectivePresentation.name,
  };

  Future<void> _update(
    MeasurementOpportunity o,
    db.MeasurementOpportunitiesCompanion change,
  ) async {
    final count =
        await (database.update(database.measurementOpportunities)..where(
              (r) =>
                  r.id.equals(o.id) &
                  r.ownerId.equals(o.ownerId) &
                  r.localRevision.equals(o.localRevision) &
                  r.isDeleted.equals(false),
            ))
            .write(change.copyWith(localRevision: Value(o.localRevision + 1)));
    if (count != 1) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
  }

  Future<db.EventsV2Data> _linkedEvent(
    MeasurementOpportunity o,
    String? id,
    String type,
  ) async {
    if (id == null) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    final e =
        await (database.select(database.eventsV2)..where(
              (e) =>
                  e.eventId.equals(id) &
                  e.ownerId.equals(o.ownerId) &
                  e.eventType.equals(type),
            ))
            .getSingleOrNull();
    if (e == null || e.eventVersion != 1 || e.correlationId != o.id) {
      throw const ResearchCaptureDenied(
        ResearchCaptureReason.sessionUnavailable,
      );
    }
    TodayExperienceEventPayloadPolicy.validate(
      type,
      Map<String, dynamic>.from(jsonDecode(e.payloadJson) as Map),
    );
    return e;
  }

  Future<String> _event(
    MeasurementOpportunity o,
    ResearchParticipantSnapshot context,
    String type,
    DateTime occurred,
    Map<String, dynamic> payload, {
    String? sessionId,
    int ordinal = 0,
  }) async {
    TodayExperienceEventPayloadPolicy.validate(type, payload);
    final now = nowUtc();
    requireResearchUtc(now);
    requireResearchUtc(occurred);
    if (occurred.isAfter(now)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.outsideWindow);
    }
    final identity =
        'research:${sha256.convert(utf8.encode(jsonEncode([o.id, type, ordinal])))}';
    final study = measurements.study;
    final envelope = EventEnvelopeV2(
      eventId: researchEventId(identity, occurred),
      eventType: type,
      eventVersion: 1,
      occurredAtUtc: occurred,
      recordedAtUtc: now,
      actorIdentity: o.ownerId,
      ownerIdentity: o.ownerId,
      aggregateType: sessionId == null
          ? 'MeasurementOpportunity'
          : 'LearningSession',
      aggregateId: sessionId ?? o.id,
      correlationId: o.id,
      idempotencyKey: identity,
      consentContext: ConsentContext(
        researchConsentVersion: study.consentVersion,
        aiConsentGranted: false,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: study.experimentId,
        variantId: context.assignment.cohort,
        assignedAtUtc: context.assignment.assignedAtUtc,
      ),
      contentRevision: study.contentRevision,
      policyVersion: study.evidencePolicyVersion,
      appVersion: study.appVersion,
      buildId: study.buildId,
      privacyClassification: PrivacyClassification.ownerOnly,
      payload: Map.unmodifiable(payload),
    );
    // Learning event store late-source handling rewinds learning cursors;
    // neutral presentation facts must not mutate those projections.
    await database
        .into(database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: envelope.eventId,
            eventType: type,
            eventVersion: 1,
            occurredAtUtc: occurred,
            recordedAtUtc: now,
            actorIdentity: o.ownerId,
            ownerId: o.ownerId,
            aggregateType: envelope.aggregateType,
            aggregateId: envelope.aggregateId,
            correlationId: Value(o.id),
            idempotencyKey: identity,
            consentContextJson: jsonEncode(envelope.consentContext.toJson()),
            experimentContextJson: Value(
              jsonEncode(envelope.experimentContext!.toJson()),
            ),
            contentRevision: Value(study.contentRevision),
            policyVersion: Value(study.evidencePolicyVersion),
            appVersion: study.appVersion,
            buildId: study.buildId,
            privacyClassification: envelope.privacyClassification.name,
            payloadJson: jsonEncode(payload),
          ),
        );
    return envelope.eventId;
  }
}
