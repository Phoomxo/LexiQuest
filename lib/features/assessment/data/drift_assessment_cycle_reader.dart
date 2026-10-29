import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../learning/data/drift_learning_repository.dart';
import '../../research/data/drift_measurement_opportunity_repository.dart';
import '../../research/data/drift_motivation_measurement_repository.dart';
import '../../research/domain/measurement_opportunity.dart';
import '../../research/domain/motivation_measurement.dart';
import '../domain/assessment_authority.dart';
import '../domain/assessment_models.dart';

/// Reads the actual configured R3 cycle. It never collects Motivation answers,
/// substitutes instruments, creates opportunities, or repairs completion facts.
final class DriftAssessmentCycleReader implements AssessmentCycleReader {
  DriftAssessmentCycleReader(
    this.database, {
    required this.measurements,
    required this.opportunities,
    required this.learning,
  }) {
    if (!identical(measurements.database, database) ||
        !identical(opportunities.database, database) ||
        !identical(opportunities.measurements, measurements) ||
        !identical(learning.database, database)) {
      throw ArgumentError(
        'Assessment cycle readers must share the actual database.',
      );
    }
  }

  final AppDatabase database;
  final DriftMotivationMeasurementRepository measurements;
  final DriftMeasurementOpportunityRepository opportunities;
  final DriftLearningRepository learning;

  @override
  Future<AssessmentCycleReceipt> requirePhase({
    required AssessmentRun run,
  }) => measurements.participation.assignments.ownerWrites.writeForActiveOwner(
    expectedOwnerId: run.ownerId,
    write: () async {
      final reading = await measurements.participation.assignments.trustedTime
          .read();
      if (reading == null ||
          !reading.isFresh ||
          run.startedAtUtc.isAfter(reading.effectiveNowUtc)) {
        _deny();
      }
      final cycle = await measurements.inspect(run.ownerId, run.studyCycleId);
      if (cycle == null ||
          cycle.ownerId != run.ownerId ||
          cycle.id != run.studyCycleId ||
          cycle.permitId != run.participationPermitId ||
          cycle.permitPayloadSha256 != run.participationPermitPayloadSha256 ||
          cycle.assignmentId != run.assignmentId ||
          cycle.assignmentRevision != run.assignmentRevision ||
          cycle.protocolRevision != run.protocolRevision ||
          cycle.study.protocolId != run.protocolId ||
          cycle.study.protocolVersion != run.protocolVersion ||
          cycle.study.experimentId != run.experimentId ||
          cycle.study.experimentVersion != run.experimentVersion ||
          cycle.consentVersion != run.consentVersion ||
          cycle.consentDecidedAtUtc != run.consentDecidedAtUtc ||
          cycle.treatment != run.cohort ||
          cycle.startedAtUtc.isAfter(run.startedAtUtc) ||
          (cycle.state != MotivationMeasurementRunState.started &&
              cycle.state != MotivationMeasurementRunState.completed)) {
        _deny();
      }
      final permit = await database
          .customSelect(
            'SELECT local_revision, payload_sha256 FROM research_participation_permits WHERE id = ? AND owner_id = ?',
            variables: [
              Variable<String>(run.participationPermitId),
              Variable<String>(run.ownerId),
            ],
          )
          .getSingleOrNull();
      if (permit == null ||
          permit.data['local_revision'] != run.participationPermitRevision ||
          permit.data['payload_sha256'] !=
              run.participationPermitPayloadSha256) {
        _deny();
      }
      final rows = await database
          .customSelect(
            'SELECT id FROM measurement_opportunities WHERE owner_id = ? AND measurement_run_id = ?',
            variables: [
              Variable<String>(run.ownerId),
              Variable<String>(run.studyCycleId),
            ],
          )
          .get();
      final facts = cycle.timing;
      if (run.phase == AssessmentPhase.pre) {
        // Even an unpresented opening makes the phase unavailable.
        if (rows.isNotEmpty ||
            facts is! MotivationBeforeExposure ||
            cycle.state != MotivationMeasurementRunState.started) {
          _deny();
        }
        return _AssessmentCycleReceipt(
          run.ownerId,
          run.studyCycleId,
          run.phase,
        );
      }
      if (facts is! MotivationAfterExposure ||
          facts.indexSession == null ||
          facts.indexSession!.state != MotivationIndexSessionState.completed ||
          facts.indexSession!.completedAtUtc == null ||
          run.startedAtUtc.isBefore(facts.indexSession!.completedAtUtc!)) {
        _deny();
      }
      final matching = <MeasurementOpportunity>[];
      for (final row in rows) {
        final opportunity = await opportunities.load(
          run.ownerId,
          row.read<String>('id'),
        );
        if (opportunity == null) _deny();
        if (opportunity.presentation?.eventId == facts.firstExposureEventId) {
          matching.add(opportunity);
        }
      }
      if (matching.length != 1) _deny();
      final opportunity = matching.single;
      if (opportunity.pendingPresentationChange != null ||
          opportunity.indexLink?.sessionId != facts.indexSession!.id ||
          opportunity.indexLink?.startedAtUtc !=
              facts.indexSession!.startedAtUtc ||
          opportunity.presentation?.occurredAtUtc != facts.firstExposureAtUtc) {
        _deny();
      }
      final index = await learning.inspectConfiguredQuiz(
        sessionId: facts.indexSession!.id,
        expectedOwnerId: run.ownerId,
      );
      if (!await opportunities.inspectIndexFacts(
        run: cycle,
        opportunity: opportunity,
        index: index,
        nowUtc: reading.effectiveNowUtc,
      )) {
        _deny();
      }
      return _AssessmentCycleReceipt(
        run.ownerId,
        run.studyCycleId,
        run.phase,
        opportunityId: opportunity.id,
        firstExposureAtUtc: facts.firstExposureAtUtc,
        interventionSessionId: index.sessionId,
        interventionStartedAtUtc: index.startedAtUtc,
        interventionCompletedAtUtc: index.endedAtUtc,
      );
    },
  );

  static Never _deny() =>
      throw StateError('Assessment phase lacks canonical cycle proof.');
}

final class _AssessmentCycleReceipt implements AssessmentCycleReceipt {
  const _AssessmentCycleReceipt(
    this.ownerId,
    this.studyCycleId,
    this.phase, {
    this.opportunityId,
    this.firstExposureAtUtc,
    this.interventionSessionId,
    this.interventionStartedAtUtc,
    this.interventionCompletedAtUtc,
  });
  @override
  final String ownerId;
  @override
  final String studyCycleId;
  @override
  final AssessmentPhase phase;
  @override
  final String? opportunityId;
  @override
  final DateTime? firstExposureAtUtc;
  @override
  final String? interventionSessionId;
  @override
  final DateTime? interventionStartedAtUtc;
  @override
  final DateTime? interventionCompletedAtUtc;
}
