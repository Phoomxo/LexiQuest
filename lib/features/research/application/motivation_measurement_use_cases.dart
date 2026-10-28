import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../adventure/domain/adventure_entry.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import '../data/drift_measurement_opportunity_repository.dart';
import '../data/drift_motivation_measurement_repository.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/motivation_measurement.dart';
import '../domain/research_event_identity.dart';

/// Shared Standard/Adventure participant workflow; canonical learning is read-only.
final class MotivationMeasurementUseCases {
  MotivationMeasurementUseCases({
    required this.database,
    required this.measurements,
    required this.opportunities,
    this.onLocalMutation,
  });
  final AppDatabase database;
  final DriftMotivationMeasurementRepository measurements;
  final DriftMeasurementOpportunityRepository opportunities;
  final Future<void> Function(String ownerId)? onLocalMutation;

  /// Queue recovery is secondary to a committed local capture. Claim-time
  /// scanning recovers a failed/busy/offline enqueue without repeating answers.
  Future<void> notifyCommitted(String ownerId) async {
    try {
      await onLocalMutation?.call(ownerId);
    } on Object {
      /* Recover on sync. */
    }
  }

  Future<T> _capture<T>(String ownerId, Future<T> Function() action) async {
    final result = await action();
    await notifyCommitted(ownerId);
    return result;
  }

  Future<MotivationMeasurementRun> record(MotivationResponse response) =>
      _capture(response.ownerId, () => measurements.record(response));
  Future<MotivationMeasurementRun> close(MotivationMeasurementClose command) =>
      _capture(command.ownerId, () => measurements.close(command));
  Future<MeasurementOpportunity> recordPresented(
    String ownerId,
    String opportunityId,
  ) => _capture(
    ownerId,
    () => opportunities.recordPresented(ownerId, opportunityId),
  );
  Future<MeasurementOpportunity> changePresentation({
    required String ownerId,
    required String opportunityId,
    required TodayExperiencePresentation presentation,
    required int expectedRevision,
  }) => _capture(
    ownerId,
    () => opportunities.changePresentation(
      ownerId: ownerId,
      opportunityId: opportunityId,
      presentation: presentation,
      expectedRevision: expectedRevision,
    ),
  );
  Future<MotivationMeasurementRun?> prepare({
    required String ownerId,
    required String permitId,
  }) async {
    try {
      final run = await measurements.start(
        MotivationMeasurementStart(ownerId: ownerId, permitId: permitId),
      );
      if (run.state != MotivationMeasurementRunState.started) return null;
      await notifyCommitted(ownerId);
      return run;
    } on ResearchCaptureDenied {
      return null;
    }
  }

  Future<MeasurementOpportunity?> open({
    required String ownerId,
    required String runId,
    required String entryAttemptId,
    required TodayExperiencePresentation presentation,
  }) async {
    try {
      return await _capture(
        ownerId,
        () => opportunities.open(
          ownerId: ownerId,
          measurementRunId: runId,
          entryAttemptId: entryAttemptId,
          effectivePresentation: presentation,
        ),
      );
    } on ResearchCaptureDenied {
      return null;
    }
  }

  /// Observes the SAME accepted learning rows in both presentations. This is
  /// recovery/projection, not a parallel start/completion authority. An invalid
  /// first session cannot be silently replaced with a later convenient one.
  Future<void> reconcile(String ownerId) => _capture(
    ownerId,
    () => database.transaction(() async {
      final runs =
          await (database.select(database.motivationMeasurementRuns)..where(
                (r) =>
                    r.ownerId.equals(ownerId) &
                    r.state.equals('started') &
                    r.isDeleted.equals(false),
              ))
              .get();
      for (final row in runs) {
        try {
          final run = await measurements.load(ownerId, row.id);
          if (run == null || run.firstExposureAtUtc == null) continue;
          await measurements.requireActiveRun(run);
          final ops =
              await (database.select(database.measurementOpportunities)
                    ..where(
                      (o) =>
                          o.ownerId.equals(ownerId) &
                          o.measurementRunId.equals(row.id) &
                          o.isDeleted.equals(false),
                    )
                    ..orderBy([
                      (o) => OrderingTerm.asc(o.openedAtUtcMs),
                      (o) => OrderingTerm.asc(o.id),
                    ]))
                  .get();
          final exposures = <String, DateTime>{};
          for (final o in ops) {
            if (o.presentedEventId == null) continue;
            final event =
                await (database.select(database.eventsV2)..where(
                      (e) =>
                          e.eventId.equals(o.presentedEventId!) &
                          e.ownerId.equals(ownerId) &
                          e.eventType.equals('TodayExperiencePresented'),
                    ))
                    .getSingleOrNull();
            if (event != null) {
              exposures[o.id] = researchEventOccurrence(
                event.eventId,
                event.occurredAtUtc,
              );
            }
          }
          final sessions =
              await (database.select(database.learningSessions)
                    ..where(
                      (s) =>
                          s.ownerId.equals(ownerId) &
                          s.startedAtUtcMs.isBiggerOrEqualValue(
                            run.firstExposureAtUtc!.millisecondsSinceEpoch,
                          ),
                    )
                    ..orderBy([
                      (s) => OrderingTerm.asc(s.startedAtUtcMs),
                      (s) => OrderingTerm.asc(s.id),
                    ]))
                  .get();
          final assigned = {
            for (final o in ops)
              if (o.learningSessionId != null) o.learningSessionId!: o.id,
          };
          final consumed = assigned.values.toSet();
          for (final session in sessions) {
            try {
              if (!(await DriftPairMatchingSessionPurposeReader(database).read(
                ownerId: ownerId,
                sessionId: session.id,
              )).allowsLearningAuthority) {
                continue;
              }
            } catch (_) {
              // Ambiguous Pair authority cannot be promoted to research learning.
              continue;
            }
            var opportunityId = assigned[session.id];
            if (opportunityId == null) {
              final candidates = ops
                  .where(
                    (o) =>
                        !consumed.contains(o.id) &&
                        o.closedAtUtcMs == null &&
                        exposures[o.id] != null &&
                        exposures[o.id]!.millisecondsSinceEpoch <=
                            session.startedAtUtcMs,
                  )
                  .toList();
              if (candidates.isEmpty) continue;
              if (session.sessionConfigurationJson == null ||
                  !{'active', 'completed'}.contains(session.state)) {
                break;
              }
              SessionConfiguration config;
              try {
                config = SessionConfiguration.fromStableSerialization(
                  session.sessionConfigurationJson!,
                );
              } on Object {
                break;
              }
              // A transport alias for the canonical accepted configuration. No
              // content/answers are copied and no inferred learning plan is saved.
              opportunityId = candidates.last.id;
              await opportunities.attachAcceptedSession(
                ownerId: ownerId,
                opportunityId: opportunityId,
                learningSessionId: session.id,
                planId: 'session-plan:${config.contentIdentity}',
                mode: config.mode,
              );
              consumed.add(opportunityId);
              assigned[session.id] = opportunityId;
            }
            final current = await opportunities.load(ownerId, opportunityId);
            if (session.state == 'completed' &&
                current?.completedEventId == null) {
              await opportunities.completeAcceptedSession(
                ownerId,
                opportunityId,
              );
            }
          }
        } on ResearchCaptureDenied {
          // Denied research must not interfere with ordinary learning. Retry is
          // safe after a legitimate authority refresh; no later index substitution.
          continue;
        }
      }
    }),
  );

  /// UI can reconcile on canonical changes, including completion while away.
  Stream<void> watch(String ownerId) => database
      .customSelect(
        '''SELECT 'learning' AS kind,id,state AS status,0 AS revision,0 AS cloud_revision,
      started_at_utc_ms AS occurred_at,ended_at_utc_ms AS ended_at,session_configuration_identity AS tag
      FROM learning_sessions WHERE owner_id=?
      UNION ALL SELECT 'checkpoint',event_id,event_type,event_version,0,0,NULL,payload_json
      FROM events_v2 WHERE owner_id=? AND event_type='LearningActivityCheckpoint'
      UNION ALL SELECT 'owner',id,CAST(is_active AS TEXT),0,0,0,NULL,firebase_uid FROM local_owners
      UNION ALL SELECT 'permit',id,CAST(is_deleted AS TEXT),local_revision,cloud_revision,
      expires_at_utc_ms,revoked_at_utc_ms,payload_sha256 || ':' || signature
      FROM research_participation_permits WHERE owner_id=?
      UNION ALL SELECT 'consent',id,consent_state,consent_version,0,
      decided_at_utc_ms,withdrawn_at_utc_ms,'' FROM research_consents WHERE owner_id=?
      ORDER BY kind,id''',
        variables: [
          Variable<String>(ownerId),
          Variable<String>(ownerId),
          Variable<String>(ownerId),
          Variable<String>(ownerId),
        ],
        readsFrom: {
          database.learningSessions,
          database.eventsV2,
          database.researchConsents,
          database.researchParticipationPermits,
          database.localOwners,
        },
        // A write fence can notify Drift without changing owner data. Compare the
        // actual projection before notifying UI, otherwise reconciliation loops.
      )
      .watch()
      .map((rows) => jsonEncode(rows.map((r) => r.data).toList()))
      .distinct()
      .map((_) {});
}
