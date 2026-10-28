import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../sync/domain/research_sync.dart';
import '../../sync/domain/sync_entity.dart';
import '../domain/research_consent.dart';

final class DriftResearchConsentRepository
    implements ResearchConsentRepository {
  const DriftResearchConsentRepository(this.database);

  final db.AppDatabase database;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    final row =
        await (database.select(database.researchConsents)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.consentVersion.equals(version),
            ))
            .getSingleOrNull();
    return ResearchConsentStatus(
      version: version,
      accepted:
          row?.consentState == 'accepted' && row?.withdrawnAtUtcMs == null,
      decidedAtUtc: row == null ? null : _utc(row.decidedAtUtcMs),
      withdrawnAtUtc: row?.withdrawnAtUtcMs == null
          ? null
          : _utc(row!.withdrawnAtUtcMs!),
    );
  }

  @override
  Future<void> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) {
    final epoch = decidedAtUtc.millisecondsSinceEpoch;
    return database.transaction(() async {
      // Admit the intended learner while acquiring the SQLite write lock.
      // Owner transitions cannot commit between this check and the decision.
      final changed = await database.customUpdate(
        'UPDATE local_owners SET is_active = is_active '
        'WHERE id = ? AND is_active = 1',
        variables: [Variable<String>(ownerId)],
        updates: {database.localOwners},
      );
      final active = await (database.select(database.localOwners)
            ..where((row) => row.isActive.equals(true)))
          .get();
      if (changed != 1 || active.length != 1 || active.single.id != ownerId) {
        throw StateError('consent decision owner must be the active owner');
      }
      final previous =
          await (database.select(database.researchConsents)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.consentVersion.equals(version),
              ))
              .getSingleOrNull();
      if (previous != null &&
          (epoch < previous.decidedAtUtcMs ||
              (accepted &&
                  previous.withdrawnAtUtcMs != null &&
                  epoch <= previous.withdrawnAtUtcMs!))) {
        throw const FormatException(
          'Consent decision cannot precede withdrawal',
        );
      }
      if (previous == null) {
        await database
            .into(database.researchConsents)
            .insert(
              db.ResearchConsentsCompanion.insert(
                id: 'consent:$ownerId:$version',
                ownerId: ownerId,
                consentVersion: version,
                consentState: accepted ? 'accepted' : 'withdrawn',
                decidedAtUtcMs: epoch,
                withdrawnAtUtcMs: Value(accepted ? null : epoch),
              ),
            );
      } else {
        await (database.update(
          database.researchConsents,
        )..where((row) => row.id.equals(previous.id))).write(
          db.ResearchConsentsCompanion(
            consentState: Value(accepted ? 'accepted' : 'withdrawn'),
            decidedAtUtcMs: Value(epoch),
            withdrawnAtUtcMs: Value(accepted ? null : epoch),
          ),
        );
      }
      if (accepted) return;

      // Capture denial in this same transaction before a later acceptance can
      // replace the mutable consent projection. Existing permit identities are
      // the scope; neither rollout nor a measurement run is needed to withdraw.
      final permits = await (database.select(
        database.researchParticipationPermits,
      )..where((permit) => permit.ownerId.equals(ownerId))).get();
      for (final permit in permits) {
        await database
            .into(database.outboxOperations)
            .insert(
              db.OutboxOperationsCompanion.insert(
                operationId: ResearchSyncContract.operationIdFor(
                  collection: SyncCollection.researchWithdrawals,
                  entityId: permit.id,
                  payload: {'permitId': permit.id, 'ownerId': ownerId},
                  revision: 1,
                ),
                ownerId: ownerId,
                entityType: 'researchWithdrawal',
                entityId: permit.id,
                operationKind: 'upsert',
                payloadVersion: const Value(1),
                createdAtUtcMs: epoch,
              ),
              // Never reset an acknowledgement, retry delay or an in-flight lease.
              mode: InsertMode.insertOrIgnore,
            );
      }

      // Preserve the original completion time and all response evidence.
      await database.customUpdate(
        '''
        UPDATE motivation_measurement_runs
        SET state = 'withdrawn',
            closed_at_utc_ms = COALESCE(closed_at_utc_ms, MAX(started_at_utc_ms, ?)),
            local_revision = local_revision + 1
        WHERE owner_id = ? AND consent_version = ? AND is_deleted = 0
          AND state IN ('started', 'completed')
      ''',
        variables: [
          Variable<int>(epoch),
          Variable<String>(ownerId),
          Variable<int>(version),
        ],
        updates: {database.motivationMeasurementRuns},
      );
      await database.customUpdate(
        '''
        UPDATE measurement_opportunities
        SET closed_at_utc_ms = MAX(opened_at_utc_ms, ?),
            local_revision = local_revision + 1
        WHERE owner_id = ? AND closed_at_utc_ms IS NULL AND is_deleted = 0
          AND measurement_run_id IN (
            SELECT id FROM motivation_measurement_runs
            WHERE owner_id = ? AND consent_version = ?
          )
      ''',
        variables: [
          Variable<int>(epoch),
          Variable<String>(ownerId),
          Variable<String>(ownerId),
          Variable<int>(version),
        ],
        updates: {database.measurementOpportunities},
      );
      await _suppressResearchUploads(ownerId, version);
    });
  }

  Future<void> _suppressResearchUploads(String ownerId, int version) async {
    // The future transport must use these exact entity types and repeat the
    // participation check at upload claim. Never suppress generic learning events.
    await database.customUpdate(
      '''
      WITH scope(owner_id, consent_version) AS (VALUES (?, ?)),
      scoped_runs AS (
        SELECT r.* FROM motivation_measurement_runs r, scope s
        WHERE r.owner_id = s.owner_id AND r.consent_version = s.consent_version
      ),
      scoped_opportunities AS (
        SELECT o.* FROM measurement_opportunities o, scope s
        WHERE o.owner_id = s.owner_id
          AND o.measurement_run_id IN (SELECT id FROM scoped_runs)
      ),
      scoped_permits AS (
        SELECT p.id FROM research_participation_permits p, scope s
        WHERE p.owner_id = s.owner_id AND (
          EXISTS (SELECT 1 FROM scoped_runs r
            WHERE r.assignment_id = p.assignment_id AND r.protocol_id = p.protocol_id
              AND r.protocol_version = p.protocol_version)
          OR NOT EXISTS (SELECT 1 FROM motivation_measurement_runs r
            WHERE r.owner_id = p.owner_id AND r.assignment_id = p.assignment_id
              AND r.protocol_id = p.protocol_id AND r.protocol_version = p.protocol_version)
        )
      ),
      scoped_assessments AS (
        SELECT r.* FROM assessment_runs r, scope s
        WHERE r.owner_id = s.owner_id AND r.consent_version = s.consent_version
      )
      UPDATE outbox_operations
      SET state = 'superseded', failure_code = 'researchConsentWithdrawn',
          lease_token = NULL, lease_expires_at_utc_ms = NULL,
          next_attempt_at_utc_ms = NULL
      WHERE owner_id = ? AND operation_kind = 'upsert'
        AND state IN ('pending', 'retryWaiting', 'inFlight', 'permanentFailure')
        AND (
          (entity_type = 'motivationMeasurementRun' AND entity_id IN (SELECT id FROM scoped_runs))
          OR (entity_type = 'motivationResponse' AND entity_id IN (
            SELECT id FROM motivation_responses WHERE owner_id = outbox_operations.owner_id
              AND run_id IN (SELECT id FROM scoped_runs)))
          OR (entity_type = 'measurementOpportunity' AND entity_id IN (SELECT id FROM scoped_opportunities))
          OR (entity_type = 'researchSessionProof' AND entity_id IN (
            SELECT id FROM research_session_proofs
            WHERE owner_id = outbox_operations.owner_id
              AND measurement_run_id IN (SELECT id FROM scoped_runs)))
          OR (entity_type = 'researchParticipationPermit' AND entity_id IN (SELECT id FROM scoped_permits))
          OR (entity_type = 'assessmentRun' AND entity_id IN (SELECT id FROM scoped_assessments))
          OR (entity_type = 'experimentAssignment' AND entity_id IN (
            SELECT assignment_id FROM scoped_runs UNION SELECT assignment_id FROM scoped_assessments))
          OR (entity_type IN ('eventsV2', 'TodayExperiencePresented',
              'TodayExperiencePresentationChanged', 'TodayExperienceMissionStarted',
              'TodayExperienceMissionCompleted') AND entity_id IN (
            SELECT e.event_id FROM events_v2 e
            JOIN scoped_opportunities o ON e.owner_id = o.owner_id
              AND (e.correlation_id = o.id OR
                (e.aggregate_type = 'MeasurementOpportunity' AND e.aggregate_id = o.id))
            WHERE e.event_type IN ('TodayExperiencePresented',
              'TodayExperiencePresentationChanged', 'TodayExperienceMissionStarted',
              'TodayExperienceMissionCompleted')
              AND (outbox_operations.entity_type = 'eventsV2'
                OR outbox_operations.entity_type = e.event_type)
          ))
        )
    ''',
      variables: [
        Variable<String>(ownerId),
        Variable<int>(version),
        Variable<String>(ownerId),
      ],
      updates: {database.outboxOperations},
    );
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
