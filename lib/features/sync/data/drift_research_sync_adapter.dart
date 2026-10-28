import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';
import '../../research/domain/research_participation_permit.dart';
import '../../research/domain/research_event_identity.dart';
import '../../research/domain/research_session_proof.dart';
import '../../research/data/drift_research_session_proof_repository.dart';
import '../domain/research_sync.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_result.dart';
import 'drift_owner_operation_gate.dart';

/// Transport only: no learning/reward projection, capture or issuer authority.
/// Called inside the existing store transaction and owner-operation fence.
final class DriftResearchSyncAdapter {
  DriftResearchSyncAdapter(
    this.database, {
    required this.rollout,
    required this.authorizer,
    DateTime Function()? researchNowUtc,
  }) : _researchNowUtc = researchNowUtc ?? (() => DateTime.now().toUtc());
  final db.AppDatabase database;
  final ResearchMeasurementSyncRollout rollout;
  final ResearchSyncAuthorizer? authorizer;
  final DateTime Function() _researchNowUtc;
  late final _proofs = DriftResearchSessionProofRepository(
    database,
    rollout: rollout,
    authorizeCandidate: authorizer == null ? null : _authorizeProofCandidate,
    nowUtc: _researchNowUtc,
  );

  Future<bool> _authorizeProofCandidate(ResearchSyncRequest request) async {
    final proof = ResearchSessionProof.decode(request.payload);
    return allowed(
      ResearchSyncSnapshot(
        SyncCollection.researchSessionProofs,
        request.ownerId,
        proof.id,
        1,
        0,
        _utc(proof.endedAtUtcMs ?? proof.startedAtUtcMs),
        proof.toJson(),
        phase: ResearchSyncPhase.enqueue,
      ),
      request.firebaseUid,
      request.ownerGateToken!,
      request.evaluatedAtUtc,
      ResearchSyncPhase.enqueue,
    );
  }

  Future<bool> ownerAllowed(
    String ownerId,
    String uid,
    String token,
    DateTime now, {
    bool requireAuthorizer = true,
  }) async {
    if (!rollout.allowsSync ||
        (requireAuthorizer && authorizer == null) ||
        !now.isUtc ||
        uid.isEmpty ||
        uid != uid.trim() ||
        token.isEmpty) {
      return false;
    }
    final owners = await (database.select(
      database.localOwners,
    )..where((r) => r.isActive.equals(true))).get();
    if (owners.length != 1 ||
        owners.single.id != ownerId ||
        owners.single.firebaseUid != uid) {
      return false;
    }
    final gate =
        await (database.select(database.runtimeFlags)
              ..where((r) => r.key.equals(DriftOwnerOperationGate.gateKey)))
            .getSingleOrNull();
    return gate != null &&
        gate.boolValue &&
        gate.source == token &&
        gate.expiresAtUtcMs != null &&
        gate.expiresAtUtcMs! > now.millisecondsSinceEpoch &&
        !await DriftOwnerOperationGate(
          database,
        ).isOwnerFenced(ownerId: ownerId, nowUtc: now);
  }

  Future<int> enqueue({
    required String ownerId,
    required String firebaseUid,
    required String ownerGateToken,
    required DateTime nowUtc,
    required int limit,
  }) async {
    if (limit < 1 || limit > 50) throw RangeError.range(limit, 1, 50);
    if (!await ownerAllowed(
      ownerId,
      firebaseUid,
      ownerGateToken,
      nowUtc,
      requireAuthorizer: false,
    )) {
      return 0;
    }
    var inserted = 0;
    // Recover denial first, even after receipts/permits expire or are revoked.
    // Existing operations (including acknowledgements) preserve one identity.
    final withdrawals = await database
        .customSelect(
          '''
      SELECT p.id FROM research_participation_permits p
      WHERE p.owner_id = ? AND ${_withdrawalScope('p')}
        AND NOT EXISTS (SELECT 1 FROM outbox_operations o
          WHERE o.owner_id = p.owner_id AND o.entity_id = p.id
            AND o.entity_type = 'researchWithdrawal')
      ORDER BY p.id LIMIT ?
    ''',
          variables: [Variable(ownerId), Variable(limit)],
        )
        .get();
    for (final row in withdrawals) {
      final s = await snapshot(
        SyncCollection.researchWithdrawals,
        ownerId,
        row.read<String>('id'),
      );
      if (!await allowed(
        s,
        firebaseUid,
        ownerGateToken,
        nowUtc,
        ResearchSyncPhase.enqueue,
      )) {
        continue;
      }
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: s.operationId,
              ownerId: ownerId,
              entityType: s.entityType,
              entityId: s.id,
              operationKind: 'upsert',
              createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      inserted++;
    }
    if (inserted >= limit || authorizer == null) return inserted;
    // At most 6 * limit candidate rows inspected; no new persistence inventory.
    for (final c in ResearchSyncContract.collections) {
      if (inserted >= limit) return inserted;
      if (c == SyncCollection.researchSessionProofs) {
        inserted += await _proofs.prepareForOwner(
          ownerId: ownerId,
          firebaseUid: firebaseUid,
          ownerGateToken: ownerGateToken,
          limit: limit - inserted,
        );
        continue;
      }
      final events = c == SyncCollection.neutralEventsV2;
      final table = _table(c);
      final idColumn = events ? 'event_id' : 'id';
      final filter = events
          ? "event_type IN ('TodayExperiencePresented','TodayExperiencePresentationChanged','TodayExperienceMissionStarted','TodayExperienceMissionCompleted') AND NOT EXISTS (SELECT 1 FROM outbox_operations o WHERE o.owner_id = t.owner_id AND o.entity_id = t.event_id AND o.entity_type = t.event_type AND o.state = 'acknowledged')"
          : c == SyncCollection.researchParticipationPermits
          ? 'is_deleted = 0 AND last_acknowledged_at_utc_ms IS NULL'
          : 'is_deleted = 0 AND local_revision > cloud_revision';
      final rows = await database
          .customSelect(
            'SELECT $idColumn FROM $table t WHERE owner_id = ? AND $filter ORDER BY $idColumn LIMIT ?',
            variables: [Variable(ownerId), Variable(limit)],
          )
          .get();
      for (final row in rows) {
        if (inserted >= limit) return inserted;
        try {
          final s = await snapshot(c, ownerId, row.read<String>(idColumn));
          if (!await allowed(
            s,
            firebaseUid,
            ownerGateToken,
            nowUtc,
            ResearchSyncPhase.enqueue,
          )) {
            continue;
          }
          final operationId = s.operationId;
          final existing = await (database.select(
            database.outboxOperations,
          )..where((r) => r.operationId.equals(operationId))).getSingleOrNull();
          if (existing != null) continue;
          // Never rewrite an attempted identity/payload. A new source revision
          // gets a new identity; pulls reconcile uncertain previous delivery.
          await (database.update(database.outboxOperations)..where(
                (r) =>
                    r.ownerId.equals(ownerId) &
                    r.entityType.equals(s.entityType) &
                    r.entityId.equals(s.id) &
                    r.attemptCount.equals(0) &
                    (r.state.equals('pending') |
                        r.state.equals('retryWaiting')),
              ))
              .write(
                const db.OutboxOperationsCompanion(
                  state: Value('superseded'),
                  failureCode: Value('researchSourceAdvanced'),
                ),
              );
          await database
              .into(database.outboxOperations)
              .insert(
                db.OutboxOperationsCompanion.insert(
                  operationId: operationId,
                  ownerId: ownerId,
                  entityType: s.entityType,
                  entityId: s.id,
                  operationKind: 'upsert',
                  baseRevision: Value(s.baseRevision),
                  createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
                ),
                mode: InsertMode.insertOrIgnore,
              );
          inserted++;
        } on InvalidSyncPayloadFailure {
          continue;
        }
      }
    }
    return inserted;
  }

  Future<bool> claimAllowed(
    db.OutboxOperation op, {
    required String firebaseUid,
    required String token,
    required DateTime now,
    PushMutation? claimed,
  }) async {
    try {
      final c = ResearchSyncContract.collectionForEntityType(op.entityType);
      if (c == null || op.operationKind != 'upsert' || op.payloadVersion != 1) {
        return false;
      }
      final s = await snapshot(c, op.ownerId, op.entityId);
      if (s.entityType != op.entityType ||
          s.operationId != op.operationId ||
          (claimed != null &&
              !ResearchSyncContract.same(s.payload, claimed.payload))) {
        return false;
      }
      return await allowed(s, firebaseUid, token, now, ResearchSyncPhase.claim);
    } on Object {
      return false;
    }
  }

  Future<PushMutation> mutation(
    db.OutboxOperation op, {
    required String uid,
    required int baseRevision,
    String? token,
  }) async {
    final c = ResearchSyncContract.collectionForEntityType(op.entityType);
    if (c == null) throw const InvalidSyncPayloadFailure();
    final s = await snapshot(c, op.ownerId, op.entityId);
    if (s.operationId != op.operationId || s.entityType != op.entityType) {
      throw const InvalidSyncPayloadFailure();
    }
    return PushMutation(
      operationId: op.operationId,
      firebaseUid: uid,
      collection: c,
      entityId: s.id,
      operationKind: SyncOperationKind.upsert,
      payloadVersion: 1,
      baseRevision: baseRevision,
      localRevision: s.revision,
      clientUpdatedAtUtc: s.updatedAt,
      payload: s.payload,
      ownerGateToken: token,
    );
  }

  Future<bool> allowed(
    ResearchSyncSnapshot s,
    String uid,
    String token,
    DateTime now,
    ResearchSyncPhase phase, {
    SyncServerReadProvenance? serverReadProvenance,
  }) async {
    if (serverReadProvenance != null &&
        (phase != ResearchSyncPhase.pull ||
            !serverReadProvenance.matchesPayload(
              firebaseUid: uid,
              collection: s.collection,
              entityId: s.id,
              payload: s.payload,
            ))) {
      return false;
    }
    if (s.collection == SyncCollection.researchWithdrawals) {
      if (s.revision != 1 ||
          s.entityType != 'researchWithdrawal' ||
          !ResearchSyncContract.same(s.payload, {
            'permitId': s.id,
            'ownerId': s.ownerId,
          }))
        return false;
      return phase != ResearchSyncPhase.pull &&
          await ownerAllowed(
            s.ownerId,
            uid,
            token,
            now,
            requireAuthorizer: false,
          ) &&
          (await _durableWithdrawalExists(s) ||
              await _withdrawalPending(s.ownerId, s.id));
    }
    if (!await ownerAllowed(s.ownerId, uid, token, now)) return false;
    if (!await localContextAllowed(
      s,
      now,
      phase: phase,
      firebaseUid: uid,
      serverReadProvenance: serverReadProvenance,
    )) {
      return false;
    }
    if (!await authorizeResearchSync(
      authorizer,
      ResearchSyncRequest(
        phase: phase,
        ownerId: s.ownerId,
        firebaseUid: uid,
        collection: s.collection,
        entityId: s.id,
        payload: s.payload,
        evaluatedAtUtc: now,
        ownerGateToken: token,
        serverReadProvenance: serverReadProvenance,
      ),
    )) {
      return false;
    }
    // The callback may await receipt authority. Recheck mutable local state
    // after it returns; never equate a stale authorization result with consent.
    return await ownerAllowed(s.ownerId, uid, token, now) &&
        await localContextAllowed(
          s,
          now,
          phase: phase,
          firebaseUid: uid,
          serverReadProvenance: serverReadProvenance,
        );
  }

  Future<bool> localContextAllowed(
    ResearchSyncSnapshot s,
    DateTime now, {
    ResearchSyncPhase phase = ResearchSyncPhase.push,
    String? firebaseUid,
    SyncServerReadProvenance? serverReadProvenance,
  }) async {
    try {
      final permitId =
          s.collection == SyncCollection.researchParticipationPermits
          ? s.id
          : s.payload['permitId']! as String;
      final p = s.collection == SyncCollection.researchParticipationPermits
          ? ResearchSyncContract.permitFromPayload(s.payload)
          : await _permit(s.ownerId, permitId);
      if (phase == ResearchSyncPhase.pull &&
          s.collection == SyncCollection.researchParticipationPermits) {
        final existing = await _row(s.collection, s.id);
        if (existing != null) {
          return existing['owner_id'] == s.ownerId &&
              _samePermitPins(_permitFromRow(existing), p);
        }
      }
      if (p.ownerId != s.ownerId ||
          p.isDeleted ||
          p.revokedAtUtc != null ||
          now.isBefore(p.issuedAtUtc) ||
          !now.isBefore(p.expiresAtUtc)) {
        return false;
      }
      if (s.collection != SyncCollection.researchParticipationPermits &&
          !await _referencesAllowed(
            s,
            p,
            phase,
            firebaseUid,
            serverReadProvenance,
          )) {
        return false;
      }
      final currentPermit = await _row(
        SyncCollection.researchParticipationPermits,
        p.id,
      );
      if (currentPermit != null &&
          (currentPermit['owner_id'] != s.ownerId ||
              currentPermit['is_deleted'] == true ||
              currentPermit['is_deleted'] == 1 ||
              currentPermit['revoked_at_utc_ms'] != null ||
              currentPermit['payload_sha256'] != p.payloadSha256 ||
              currentPermit['local_revision'] != p.localRevision ||
              currentPermit['cloud_revision'] != p.cloudRevision ||
              currentPermit['signature'] != p.signature)) {
        return false;
      }
      final assignment =
          await (database.select(database.experimentAssignments)..where(
                (r) =>
                    r.id.equals(p.assignmentId) & r.ownerId.equals(s.ownerId),
              ))
              .getSingleOrNull();
      if (assignment == null ||
          assignment.protocolVersion != p.protocolVersion ||
          assignment.cohort != p.assignedTreatment.name ||
          assignment.assignedAtUtcMs > p.issuedAtUtc.millisecondsSinceEpoch) {
        return false;
      }
      final consents =
          await (database.select(database.researchConsents)
                ..where((r) => r.ownerId.equals(s.ownerId))
                ..orderBy([(r) => OrderingTerm.desc(r.decidedAtUtcMs)]))
              .get();
      if (consents.isEmpty) return false;
      final consent = consents.first;
      if (consent.consentState != 'accepted' ||
          consent.withdrawnAtUtcMs != null ||
          consent.decidedAtUtcMs > assignment.assignedAtUtcMs) {
        return false;
      }
      if (s.collection == SyncCollection.researchParticipationPermits) {
        return true;
      }
      Map<String, Object?>? run;
      if (s.collection == SyncCollection.motivationMeasurementRuns) {
        run = s.payload;
      } else if (s.collection == SyncCollection.researchSessionProofs) {
        final proof = ResearchSessionProof.decode(s.payload);
        run = (await snapshot(
          SyncCollection.motivationMeasurementRuns,
          s.ownerId,
          proof.measurementRunId,
        )).payload;
      } else if (s.collection == SyncCollection.motivationResponses) {
        run = (await snapshot(
          SyncCollection.motivationMeasurementRuns,
          s.ownerId,
          s.payload['runId']! as String,
        )).payload;
      } else {
        Map<String, Object?> opportunity;
        if (s.collection == SyncCollection.neutralEventsV2) {
          final e = s.payload['envelope']! as Map;
          opportunity = (await snapshot(
            SyncCollection.measurementOpportunities,
            s.ownerId,
            e['correlationId'] as String,
          )).payload;
          if (e['consentContext'] is! Map ||
              (e['consentContext'] as Map)['researchConsentVersion'] !=
                  consent.consentVersion) {
            return false;
          }
        } else {
          opportunity = s.payload;
        }
        if (opportunity['permitId'] != p.id ||
            opportunity['assignedTreatment'] != p.assignedTreatment.name) {
          return false;
        }
        run = (await snapshot(
          SyncCollection.motivationMeasurementRuns,
          s.ownerId,
          opportunity['measurementRunId']! as String,
        )).payload;
      }
      return run['ownerId'] == s.ownerId &&
          run['permitId'] == p.id &&
          run['assignmentId'] == p.assignmentId &&
          run['protocolId'] == p.protocolId &&
          run['protocolVersion'] == p.protocolVersion &&
          run['treatment'] == p.assignedTreatment.name &&
          run['consentVersion'] == consent.consentVersion &&
          run['consentDecidedAtUtcMs'] == consent.decidedAtUtcMs &&
          run['state'] != 'withdrawn' &&
          (run['startedAtUtcMs']! as int) >=
              p.issuedAtUtc.millisecondsSinceEpoch;
    } on Object {
      return false;
    }
  }

  Future<bool> _referencesAllowed(
    ResearchSyncSnapshot s,
    ResearchParticipationPermit p,
    ResearchSyncPhase phase,
    String? uid,
    SyncServerReadProvenance? provenance,
  ) async {
    if (provenance != null &&
        (phase != ResearchSyncPhase.pull ||
            uid == null ||
            !provenance.matchesPayload(
              firebaseUid: uid,
              collection: s.collection,
              entityId: s.id,
              payload: s.payload,
            ))) {
      return false;
    }
    if (ResearchSyncContract.reference(
      p,
    ).entries.every((e) => s.payload[e.key] == e.value)) {
      return true;
    }
    if (phase != ResearchSyncPhase.pull ||
        s.payload['permitId'] != p.id ||
        (s.payload['permitRevision']! as int) < 1 ||
        (s.payload['permitRevision']! as int) >= p.localRevision) {
      return false;
    }
    ResearchSyncContract.digest(s.payload['permitPayloadSha256']);
    // Full entity binding is checked by apply before forwarding this marker.
    // Signature/receipts/current instrument pins remain the real authorizer's job.
    if (provenance != null) return true;
    final local = await snapshot(s.collection, s.ownerId, s.id);
    if (s.collection == SyncCollection.researchSessionProofs
        ? !ResearchSyncContract.same(local.payload, s.payload)
        : !_sameFact(local.payload, s.payload))
      return false;
    final admitted =
        await (database.select(database.outboxOperations)..where(
              (r) =>
                  r.operationId.equals(s.operationId) &
                  r.ownerId.equals(s.ownerId) &
                  r.entityId.equals(s.id) &
                  r.entityType.equals(s.entityType) &
                  r.operationKind.equals('upsert') &
                  r.payloadVersion.equals(1),
            ))
            .getSingleOrNull();
    return admitted != null &&
        (s.collection != SyncCollection.researchSessionProofs ||
            admitted.baseRevision == 0);
  }

  Future<ResearchSyncSnapshot> snapshot(
    SyncCollection c,
    String owner,
    String id,
  ) async {
    if (c == SyncCollection.researchWithdrawals) {
      final permit = await _row(
        SyncCollection.researchParticipationPermits,
        id,
      );
      if (permit == null || permit['owner_id'] != owner) {
        throw const InvalidSyncPayloadFailure();
      }
      return ResearchSyncSnapshot(
        c,
        owner,
        id,
        1,
        0,
        _utc(permit['issued_at_utc_ms']! as int),
        {'permitId': id, 'ownerId': owner},
      );
    }
    if (c == SyncCollection.neutralEventsV2) {
      final row =
          await (database.select(database.eventsV2)
                ..where((r) => r.eventId.equals(id) & r.ownerId.equals(owner)))
              .getSingleOrNull();
      if (row == null ||
          !ResearchSyncContract.eventTypes.contains(row.eventType) ||
          row.correlationId == null) {
        throw const InvalidSyncPayloadFailure();
      }
      final opportunity = await _row(
        SyncCollection.measurementOpportunities,
        row.correlationId!,
      );
      if (opportunity == null ||
          opportunity['owner_id'] != owner ||
          opportunity['is_deleted'] == 1) {
        throw const InvalidSyncPayloadFailure();
      }
      final permit = await _permit(owner, opportunity['permit_id']! as String);
      final envelope = _eventEnvelope(row);
      final payload = <String, Object?>{
        ...ResearchSyncContract.reference(permit),
        'envelope': envelope.toJson(),
      };
      return ResearchSyncSnapshot(
        c,
        owner,
        id,
        1,
        0,
        envelope.recordedAtUtc,
        payload,
        entityType: row.eventType,
      );
    }
    final row = await _row(c, id);
    if (row == null || row['owner_id'] != owner || row['is_deleted'] == 1) {
      throw const InvalidSyncPayloadFailure();
    }
    final revision = row['local_revision']! as int;
    final cloud = row['cloud_revision']! as int;
    if (c == SyncCollection.researchSessionProofs) {
      final proof = researchSessionProofFromRow(row);
      if (revision != 1) throw const InvalidSyncPayloadFailure();
      return ResearchSyncSnapshot(
        c,
        owner,
        id,
        1,
        0,
        _utc(proof.endedAtUtcMs ?? proof.startedAtUtcMs),
        proof.toJson(),
      );
    }
    if (c == SyncCollection.researchParticipationPermits) {
      final permit = _permitFromRow(row);
      return ResearchSyncSnapshot(
        c,
        owner,
        id,
        revision,
        revision - 1,
        permit.issuedAtUtc,
        ResearchSyncContract.permitPayload(permit),
      );
    }
    ResearchParticipationPermit permit;
    if (c == SyncCollection.measurementOpportunities) {
      permit = await _permit(owner, row['permit_id']! as String);
    } else {
      final run = c == SyncCollection.motivationMeasurementRuns
          ? row
          : await _row(
              SyncCollection.motivationMeasurementRuns,
              row['run_id']! as String,
            );
      if (run == null ||
          run['owner_id'] != owner ||
          run['is_deleted'] == 1 ||
          run['state'] == 'withdrawn') {
        throw const InvalidSyncPayloadFailure();
      }
      final permits = await database
          .customSelect(
            'SELECT * FROM research_participation_permits WHERE owner_id = ? AND assignment_id = ? AND protocol_id = ? AND protocol_version = ? AND is_deleted = 0',
            variables: [
              Variable(owner),
              Variable(run['assignment_id']! as String),
              Variable(run['protocol_id']! as String),
              Variable(run['protocol_version']! as String),
            ],
          )
          .get();
      if (permits.length != 1) throw const InvalidSyncPayloadFailure();
      permit = _permitFromRow(permits.single.data);
    }
    final keys = switch (c) {
      SyncCollection.motivationMeasurementRuns => ResearchSyncContract.runKeys,
      SyncCollection.motivationResponses => ResearchSyncContract.responseKeys,
      SyncCollection.measurementOpportunities =>
        ResearchSyncContract.opportunityKeys,
      _ => throw const InvalidSyncPayloadFailure(),
    };
    final payload = <String, Object?>{
      for (final k in keys.difference(ResearchSyncContract.referenceKeys))
        k: row[_snake(k)],
      ...ResearchSyncContract.reference(permit),
    };
    final at = switch (c) {
      SyncCollection.motivationMeasurementRuns =>
        row['closed_at_utc_ms'] ?? row['started_at_utc_ms'],
      SyncCollection.motivationResponses => row['answered_at_utc_ms'],
      _ => row['closed_at_utc_ms'] ?? row['opened_at_utc_ms'],
    };
    return ResearchSyncSnapshot(
      c,
      owner,
      id,
      revision,
      cloud,
      _utc(at! as int),
      payload,
    );
  }

  Future<void> acknowledge(db.OutboxOperation op, PushAcknowledged ack) async {
    final c = ResearchSyncContract.collectionForEntityType(op.entityType)!;
    if (c == SyncCollection.neutralEventsV2 ||
        c == SyncCollection.researchWithdrawals) {
      return;
    }
    // localRevision/cloudRevision are signed fields for a permit. They MUST NOT
    // be updated by transport acknowledgement or by owner mapping.
    final revisionSql = c == SyncCollection.researchParticipationPermits
        ? ''
        : 'cloud_revision = MAX(cloud_revision, ?), ';
    await database.customUpdate(
      'UPDATE ${_table(c)} SET ${revisionSql}last_acknowledged_at_utc_ms = ?, server_updated_at_utc_ms = ? WHERE id = ? AND owner_id = ?',
      variables: [
        if (revisionSql.isNotEmpty) Variable(ack.resultingRevision),
        Variable(ack.acknowledgedAtUtc.millisecondsSinceEpoch),
        Variable(ack.acknowledgedAtUtc.millisecondsSinceEpoch),
        Variable(op.entityId),
        Variable(op.ownerId),
      ],
      updates: _updates(c),
    );
  }

  /// Pulls only restore validated research facts. Local withdrawal/tombstones
  /// win permanently; conflicts retain the local row and never change learning.
  Future<void> apply(
    String owner,
    SyncEntity entity,
    String uid,
    String token,
    DateTime now,
  ) async {
    final provenance = entity.serverReadProvenance;
    if (provenance != null &&
        !provenance.matchesEntity(firebaseUid: uid, entity: entity)) {
      throw const InvalidSyncPayloadFailure();
    }
    ResearchSyncContract.validate(
      collection: entity.collection,
      entityId: entity.entityId,
      payload: entity.payload,
      revision: entity.revision,
      isDeleted: entity.isDeleted,
      phase: ResearchSyncPhase.pull,
    );
    if (ResearchSyncContract.ownerOf(entity.collection, entity.payload) !=
        owner) {
      throw const InvalidSyncPayloadFailure();
    }
    final c = entity.collection;
    if (c == SyncCollection.researchSessionProofs) {
      await _applyProof(owner, entity, uid, token, now);
      return;
    }
    final existing = await _row(c, entity.entityId);
    final permitPull = c == SyncCollection.researchParticipationPermits;
    if (existing != null && existing['owner_id'] != owner) {
      throw const InvalidSyncPayloadFailure();
    }
    if (permitPull) {
      final p = ResearchSyncContract.permitFromPayload(entity.payload);
      // Inactive unknown permits are a cutoff notification, never enrollment.
      if (existing == null &&
          (p.isDeleted ||
              p.revokedAtUtc != null ||
              !now.isBefore(p.expiresAtUtc))) {
        return;
      }
      if (existing != null) {
        final old = _permitFromRow(existing);
        if (p.localRevision < old.localRevision ||
            (old.isDeleted && !p.isDeleted) ||
            (old.revokedAtUtc != null && p.revokedAtUtc != old.revokedAtUtc)) {
          return;
        }
      }
    } else {
      if (existing != null &&
          (existing['is_deleted'] == 1 || existing['state'] == 'withdrawn')) {
        return;
      }
      final consent =
          await (database.select(database.researchConsents)
                ..where((r) => r.ownerId.equals(owner))
                ..orderBy([(r) => OrderingTerm.desc(r.decidedAtUtcMs)])
                ..limit(1))
              .getSingleOrNull();
      if (consent?.consentState == 'withdrawn' ||
          consent?.withdrawnAtUtcMs != null) {
        return;
      }
    }
    final incoming = ResearchSyncSnapshot(
      entity.collection,
      owner,
      entity.entityId,
      entity.revision,
      entity.revision - 1,
      entity.clientUpdatedAtUtc,
      entity.payload,
      phase: ResearchSyncPhase.pull,
      isDeleted: entity.isDeleted,
      entityType: entity.collection == SyncCollection.neutralEventsV2
          ? (entity.payload['envelope'] as Map)['eventType'] as String
          : null,
    );
    if (!await allowed(
      incoming,
      uid,
      token,
      now,
      ResearchSyncPhase.pull,
      serverReadProvenance: provenance,
    )) {
      // An unavailable authorizer is not a successfully consumed page. The
      // containing transaction rolls back, including its checkpoint.
      throw const ProviderUnavailableSyncFailure();
    }
    if (provenance != null &&
        !provenance.matchesEntity(firebaseUid: uid, entity: entity)) {
      throw const InvalidSyncPayloadFailure();
    }
    if (existing != null) {
      final oldPermit = permitPull ? _permitFromRow(existing) : null;
      final local = oldPermit == null
          ? await snapshot(c, owner, entity.entityId)
          : ResearchSyncSnapshot(
              c,
              owner,
              entity.entityId,
              oldPermit.localRevision,
              oldPermit.cloudRevision,
              oldPermit.issuedAtUtc,
              ResearchSyncContract.permitPayload(oldPermit),
              phase: ResearchSyncPhase.pull,
              isDeleted: oldPermit.isDeleted,
            );
      if (!permitPull &&
          _sameFact(local.payload, entity.payload) &&
          entity.revision <= local.revision) {
        // E1 was delivered, only the unsigned authority wrapper changed for E2.
        // Record delivery without rewriting facts, lifecycle times or signed pins.
        await _recordFactDelivery(
          local,
          incoming,
          entity.serverUpdatedAtUtc,
          now,
        );
        return;
      }
      if (!ResearchSyncContract.same(local.payload, entity.payload)) {
        // Never replace pins or reopen a terminal local run. Mutable research
        // state advances only from a clean local revision and immutable pins.
        if (!_mayAdvance(c, local, incoming)) {
          await _conflict(owner, local, entity, now);
          return;
        }
      } else if (entity.revision < local.revision) {
        return;
      }
    }
    if (c == SyncCollection.neutralEventsV2) {
      final envelope = EventEnvelopeV2.fromJson(
        Map<String, dynamic>.from(entity.payload['envelope']! as Map),
      );
      final collision =
          await (database.select(database.eventsV2)..where(
                (r) =>
                    r.ownerId.equals(owner) &
                    r.idempotencyKey.equals(envelope.idempotencyKey),
              ))
              .getSingleOrNull();
      if (collision != null && collision.eventId != entity.entityId) {
        throw const InvalidSyncPayloadFailure();
      }
      if (existing == null) await _insertEvent(envelope);
    } else {
      final p = entity.payload;
      final values = c == SyncCollection.researchParticipationPermits
          ? _permitColumns(ResearchSyncContract.permitFromPayload(p))
          : <String, Object?>{
              for (final e in p.entries)
                if (!ResearchSyncContract.referenceKeys.contains(e.key) ||
                    (c == SyncCollection.measurementOpportunities &&
                        e.key == 'permitId'))
                  _snake(e.key): e.value,
              'local_revision': entity.revision,
              'cloud_revision': entity.revision,
              'is_deleted': 0,
            };
      values['last_acknowledged_at_utc_ms'] =
          entity.serverUpdatedAtUtc.millisecondsSinceEpoch;
      values['server_updated_at_utc_ms'] =
          entity.serverUpdatedAtUtc.millisecondsSinceEpoch;
      final columns = values.keys.toList();
      final assignments = columns
          .where((k) => k != 'id' && k != 'owner_id')
          .map((k) => '$k = excluded.$k')
          .join(', ');
      await database.customInsert(
        'INSERT INTO ${_table(c)} (${columns.join(', ')}) VALUES (${columns.map((_) => '?').join(', ')}) ON CONFLICT(id) DO UPDATE SET $assignments',
        variables: values.values.map(_variable).toList(),
        updates: _updates(c),
      );
    }
    if (!permitPull) {
      final local = await snapshot(c, owner, entity.entityId);
      if (!_sameFact(local.payload, entity.payload)) {
        throw const InvalidSyncPayloadFailure();
      }
      await _recordFactDelivery(
        local,
        incoming,
        entity.serverUpdatedAtUtc,
        now,
      );
      return;
    }
    final pending =
        await (database.select(database.outboxOperations)..where(
              (r) =>
                  r.ownerId.equals(owner) &
                  r.entityType.equals(incoming.entityType) &
                  r.entityId.equals(entity.entityId) &
                  r.state.isIn(['pending', 'retryWaiting', 'inFlight']),
            ))
            .get();
    for (final op in pending) {
      if (op.operationId != incoming.operationId) continue;
      await (database.update(
        database.outboxOperations,
      )..where((r) => r.operationId.equals(op.operationId))).write(
        db.OutboxOperationsCompanion(
          state: const Value('acknowledged'),
          acknowledgedAtUtcMs: Value(now.millisecondsSinceEpoch),
          leaseToken: const Value(null),
          leaseExpiresAtUtcMs: const Value(null),
          nextAttemptAtUtcMs: const Value(null),
        ),
      );
    }
  }

  Future<void> _applyProof(
    String owner,
    SyncEntity entity,
    String uid,
    String token,
    DateTime now,
  ) async {
    final proof = ResearchSessionProof.decode(entity.payload);
    final updated = _utc(proof.endedAtUtcMs ?? proof.startedAtUtcMs);
    if (entity.clientUpdatedAtUtc != updated)
      throw const InvalidSyncPayloadFailure();
    final incoming = ResearchSyncSnapshot(
      SyncCollection.researchSessionProofs,
      owner,
      proof.id,
      1,
      0,
      updated,
      proof.toJson(),
      phase: ResearchSyncPhase.pull,
    );
    final previous = await _row(SyncCollection.researchSessionProofs, proof.id);
    if (previous != null) {
      if (previous['owner_id'] != owner)
        throw const InvalidSyncPayloadFailure();
      if (!ResearchSyncContract.same(
        researchSessionProofFromRow(previous).toJson(),
        proof.toJson(),
      )) {
        throw const InvalidSyncPayloadFailure();
      }
      // Deletion prevents resurrection, but never makes conflicting immutable
      // facts an acceptable replay of the retained proof.
      if (previous['is_deleted'] == 1) return;
    }
    final provenance = entity.serverReadProvenance;
    if (provenance == null) {
      final known = await _proofOperation(incoming);
      if (previous == null || known == null)
        throw const ProviderUnavailableSyncFailure();
    }
    if (!await allowed(
      incoming,
      uid,
      token,
      now,
      ResearchSyncPhase.pull,
      serverReadProvenance: provenance,
    )) {
      throw const ProviderUnavailableSyncFailure();
    }
    if (provenance != null &&
        !provenance.matchesEntity(firebaseUid: uid, entity: entity)) {
      throw const InvalidSyncPayloadFailure();
    }
    final existing = await _row(SyncCollection.researchSessionProofs, proof.id);
    if (existing != null &&
        (existing['owner_id'] != owner ||
            existing['is_deleted'] != 0 ||
            existing['local_revision'] != 1 ||
            !ResearchSyncContract.same(
              researchSessionProofFromRow(existing).toJson(),
              proof.toJson(),
            ))) {
      throw const InvalidSyncPayloadFailure();
    }
    final siblings = await database
        .customSelect(
          'SELECT * FROM research_session_proofs WHERE owner_id = ? AND measurement_run_id = ? '
          'AND permit_id = ? AND learning_session_id = ? ORDER BY proof_revision, id',
          variables: [
            Variable(owner),
            Variable(proof.measurementRunId),
            Variable(proof.permitId),
            Variable(proof.learningSessionId),
          ],
        )
        .get();
    for (final row in siblings) {
      if (!researchSessionProofFromRow(row.data).hasSameStartCore(proof)) {
        throw const InvalidSyncPayloadFailure();
      }
    }
    // Validate collision identity before any write. The enclosing page
    // transaction also rolls back a failed proof/receipt insertion as a unit.
    final operation = await _proofOperation(incoming);
    if (existing == null) {
      await database
          .into(database.researchSessionProofs)
          .insert(
            db.ResearchSessionProofsCompanion.insert(
              id: proof.id,
              ownerId: owner,
              measurementRunId: proof.measurementRunId,
              permitId: proof.permitId,
              learningSessionId: proof.learningSessionId,
              proofRevision: proof.proofRevision,
              activityType: proof.activityType,
              sessionState: proof.sessionState,
              startedAtUtcMs: proof.startedAtUtcMs,
              endedAtUtcMs: Value(proof.endedAtUtcMs),
              appVersion: proof.appVersion,
              buildId: proof.buildId,
              sessionConfigurationIdentity: Value(
                proof.sessionConfigurationIdentity,
              ),
              sessionConfigurationJson: Value(proof.sessionConfigurationJson),
              pairStartOperation: Value(proof.pairStartOperation),
              pairCheckpointEventVersion: Value(
                proof.pairCheckpointEventVersion,
              ),
              pairOwnerLineageJson: Value(
                proof.pairOwnerLineage == null
                    ? null
                    : jsonEncode(proof.pairOwnerLineage),
              ),
              permitPayloadSha256: proof.permitPayloadSha256,
              permitRevision: proof.permitRevision,
              cloudRevision: const Value(1),
              lastAcknowledgedAtUtcMs: Value(now.millisecondsSinceEpoch),
              serverUpdatedAtUtcMs: Value(
                entity.serverUpdatedAtUtc.millisecondsSinceEpoch,
              ),
            ),
          );
    } else {
      // Preserve immutable fields and the first acknowledgement. No refreshed
      // current-parent wrapper is written into a historical proof.
      await database.customUpdate(
        'UPDATE research_session_proofs SET cloud_revision = MAX(cloud_revision, 1), '
        'last_acknowledged_at_utc_ms = COALESCE(last_acknowledged_at_utc_ms, ?), '
        'server_updated_at_utc_ms = MAX(COALESCE(server_updated_at_utc_ms, 0), ?) '
        'WHERE id = ? AND owner_id = ? AND is_deleted = 0',
        variables: [
          Variable(now.millisecondsSinceEpoch),
          Variable(entity.serverUpdatedAtUtc.millisecondsSinceEpoch),
          Variable(proof.id),
          Variable(owner),
        ],
        updates: {database.researchSessionProofs},
      );
    }
    if (operation == null) {
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: incoming.operationId,
              ownerId: owner,
              entityType: incoming.entityType,
              entityId: proof.id,
              operationKind: 'upsert',
              createdAtUtcMs: now.millisecondsSinceEpoch,
              state: const Value('acknowledged'),
              acknowledgedAtUtcMs: Value(now.millisecondsSinceEpoch),
            ),
          );
    } else if (operation.state != 'acknowledged') {
      await (database.update(
        database.outboxOperations,
      )..where((row) => row.operationId.equals(incoming.operationId))).write(
        db.OutboxOperationsCompanion(
          state: const Value('acknowledged'),
          acknowledgedAtUtcMs: Value(now.millisecondsSinceEpoch),
          leaseToken: const Value(null),
          leaseExpiresAtUtcMs: const Value(null),
          nextAttemptAtUtcMs: const Value(null),
          failureCode: const Value(null),
        ),
      );
    }
  }

  Future<db.OutboxOperation?> _proofOperation(
    ResearchSyncSnapshot proof,
  ) async {
    final row =
        await (database.select(database.outboxOperations)
              ..where((row) => row.operationId.equals(proof.operationId)))
            .getSingleOrNull();
    if (row != null &&
        (row.ownerId != proof.ownerId ||
            row.entityId != proof.id ||
            row.entityType != proof.entityType ||
            row.operationKind != 'upsert' ||
            row.payloadVersion != 1 ||
            row.baseRevision != 0)) {
      throw const InvalidSyncPayloadFailure();
    }
    return row;
  }

  Future<void> _recordFactDelivery(
    ResearchSyncSnapshot local,
    ResearchSyncSnapshot incoming,
    DateTime serverAt,
    DateTime now,
  ) async {
    if (!_sameFact(local.payload, incoming.payload)) {
      throw const InvalidSyncPayloadFailure();
    }
    final events = local.collection == SyncCollection.neutralEventsV2;
    if (!events) {
      await database.customUpdate(
        'UPDATE ${_table(local.collection)} SET '
        'cloud_revision = MAX(cloud_revision, ?), '
        'last_acknowledged_at_utc_ms = ?, '
        'server_updated_at_utc_ms = MAX(COALESCE(server_updated_at_utc_ms, 0), ?) '
        'WHERE id = ? AND owner_id = ? AND is_deleted = 0',
        variables: [
          Variable(incoming.revision),
          Variable(now.millisecondsSinceEpoch),
          Variable(serverAt.millisecondsSinceEpoch),
          Variable(local.id),
          Variable(local.ownerId),
        ],
        updates: _updates(local.collection),
      );
    } else {
      // Events have no mutable sync revision column. Persist one ACK ledger row
      // for server-imported facts too, so a new device/restart cannot re-enqueue
      // an already delivered event under the current permit's wrapper.
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: local.operationId,
              ownerId: local.ownerId,
              entityType: local.entityType,
              entityId: local.id,
              operationKind: 'upsert',
              baseRevision: Value(local.baseRevision),
              createdAtUtcMs: now.millisecondsSinceEpoch,
              state: const Value('acknowledged'),
              acknowledgedAtUtcMs: Value(now.millisecondsSinceEpoch),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    // Never ACK every job for an entity. These exact identities bind the old
    // delivered wrapper and (only at the same fact revision) its current twin.
    final identities = {
      incoming.operationId,
      if (local.revision == incoming.revision) local.operationId,
    };
    await (database.update(database.outboxOperations)..where(
          (r) =>
              r.operationId.isIn(identities) &
              r.ownerId.equals(local.ownerId) &
              r.entityType.equals(local.entityType) &
              r.entityId.equals(local.id) &
              r.operationKind.equals('upsert') &
              r.payloadVersion.equals(1) &
              r.state.equals('acknowledged').not(),
        ))
        .write(
          db.OutboxOperationsCompanion(
            state: const Value('acknowledged'),
            acknowledgedAtUtcMs: Value(now.millisecondsSinceEpoch),
            leaseToken: const Value(null),
            leaseExpiresAtUtcMs: const Value(null),
            nextAttemptAtUtcMs: const Value(null),
            failureCode: const Value(null),
          ),
        );
  }

  bool _mayAdvance(
    SyncCollection c,
    ResearchSyncSnapshot local,
    ResearchSyncSnapshot incoming,
  ) {
    if (c == SyncCollection.researchParticipationPermits) {
      final old = ResearchSyncContract.permitFromPayload(local.payload);
      final next = ResearchSyncContract.permitFromPayload(incoming.payload);
      return next.localRevision > old.localRevision &&
          _samePermitPins(old, next) &&
          (!old.isDeleted || next.isDeleted) &&
          (old.revokedAtUtc == null || next.revokedAtUtc == old.revokedAtUtc);
    }
    if (local.baseRevision < local.revision ||
        incoming.revision <= local.revision) {
      return false;
    }
    final mutable = c == SyncCollection.motivationMeasurementRuns
        ? {'state', 'closedAtUtcMs'}
        : c == SyncCollection.measurementOpportunities
        ? {
            'effectivePresentation',
            'presentedEventId',
            'learningSessionId',
            'startedEventId',
            'completedEventId',
            'lastSwitchOrdinal',
            'suppressedSwitchCount',
            'closedAtUtcMs',
          }
        : <String>{};
    if (mutable.isEmpty ||
        (c == SyncCollection.motivationMeasurementRuns &&
            local.payload['state'] != 'started')) {
      return false;
    }
    for (final k in local.payload.keys) {
      if (ResearchSyncContract.referenceKeys.contains(k)) continue;
      if (!mutable.contains(k) &&
          !ResearchSyncContract.same(local.payload[k], incoming.payload[k])) {
        return false;
      }
    }
    if (c == SyncCollection.measurementOpportunities) {
      for (final k in [
        'presentedEventId',
        'learningSessionId',
        'startedEventId',
        'completedEventId',
        'closedAtUtcMs',
      ]) {
        if (local.payload[k] != null &&
            local.payload[k] != incoming.payload[k]) {
          return false;
        }
      }
      for (final k in ['lastSwitchOrdinal', 'suppressedSwitchCount']) {
        if ((incoming.payload[k]! as int) < (local.payload[k]! as int)) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _conflict(
    String owner,
    ResearchSyncSnapshot local,
    SyncEntity cloud,
    DateTime now,
  ) => database
      .into(database.syncConflicts)
      .insert(
        db.SyncConflictsCompanion.insert(
          id: 'research-conflict:${ResearchSyncContract.fingerprint({'id': cloud.entityId, 'revision': cloud.revision, 'payload': cloud.payload})}',
          ownerId: owner,
          entityType: local.entityType,
          entityId: cloud.entityId,
          localRevision: local.revision,
          cloudRevision: cloud.revision,
          resolutionPolicy: 'researchImmutablePins',
          outcome: 'preserveLocal',
          // Only bounded identities/hashes; never duplicate participant responses.
          resolvedAtUtcMs: now.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      )
      .then((_) {});

  Future<Map<String, Object?>?> _row(SyncCollection c, String id) async =>
      (await database
              .customSelect(
                'SELECT * FROM ${_table(c)} WHERE ${c == SyncCollection.neutralEventsV2 ? 'event_id' : 'id'} = ?',
                variables: [Variable(id)],
              )
              .getSingleOrNull())
          ?.data;
  Future<bool> _durableWithdrawalExists(ResearchSyncSnapshot snapshot) async =>
      await database
          .customSelect(
            '''
        SELECT 1 FROM outbox_operations o
        JOIN research_participation_permits p
          ON p.id = o.entity_id AND p.owner_id = o.owner_id
        WHERE o.operation_id = ? AND o.owner_id = ? AND o.entity_id = ?
          AND o.entity_type = 'researchWithdrawal'
          AND o.operation_kind = 'upsert' AND o.payload_version = 1
        LIMIT 1
      ''',
            variables: [
              Variable(snapshot.operationId),
              Variable(snapshot.ownerId),
              Variable(snapshot.id),
            ],
            readsFrom: {
              database.outboxOperations,
              database.researchParticipationPermits,
            },
          )
          .getSingleOrNull() !=
      null;

  Future<bool> _withdrawalPending(String owner, String id) async =>
      await database
          .customSelect(
            '''
        SELECT 1 FROM research_participation_permits p
        WHERE p.owner_id = ? AND p.id = ? AND ${_withdrawalScope('p')}
      ''',
            variables: [Variable(owner), Variable(id)],
          )
          .getSingleOrNull() !=
      null;
  Future<ResearchParticipationPermit> _permit(String owner, String id) async {
    final row = await _row(SyncCollection.researchParticipationPermits, id);
    if (row == null || row['owner_id'] != owner) {
      throw const InvalidSyncPayloadFailure();
    }
    final p = _permitFromRow(row);
    return ResearchSyncContract.permitFromPayload(
      ResearchSyncContract.permitPayload(p),
    );
  }

  Set<TableInfo> _updates(SyncCollection c) => {
    switch (c) {
      SyncCollection.researchParticipationPermits =>
        database.researchParticipationPermits,
      SyncCollection.motivationMeasurementRuns =>
        database.motivationMeasurementRuns,
      SyncCollection.motivationResponses => database.motivationResponses,
      SyncCollection.researchSessionProofs => database.researchSessionProofs,
      SyncCollection.measurementOpportunities =>
        database.measurementOpportunities,
      SyncCollection.neutralEventsV2 => database.eventsV2,
      _ => throw const InvalidSyncPayloadFailure(),
    },
  };
  Future<void> _insertEvent(EventEnvelopeV2 e) => database
      .into(database.eventsV2)
      .insert(
        db.EventsV2Companion.insert(
          eventId: e.eventId,
          eventType: e.eventType,
          eventVersion: e.eventVersion,
          occurredAtUtc: e.occurredAtUtc,
          recordedAtUtc: e.recordedAtUtc,
          actorIdentity: e.actorIdentity,
          ownerId: e.ownerIdentity,
          aggregateType: e.aggregateType,
          aggregateId: e.aggregateId,
          correlationId: Value(e.correlationId),
          idempotencyKey: e.idempotencyKey,
          consentContextJson: jsonEncode(e.consentContext.toJson()),
          experimentContextJson: Value(
            jsonEncode(e.experimentContext!.toJson()),
          ),
          contentRevision: Value(e.contentRevision),
          policyVersion: Value(e.policyVersion),
          appVersion: e.appVersion,
          buildId: e.buildId,
          privacyClassification: e.privacyClassification.name,
          payloadJson: jsonEncode(e.payload),
        ),
        mode: InsertMode.insertOrIgnore,
      )
      .then((_) {});
}

final class ResearchSyncSnapshot {
  ResearchSyncSnapshot(
    this.collection,
    this.ownerId,
    this.id,
    this.revision,
    this.baseRevision,
    this.updatedAt,
    this.payload, {
    String? entityType,
    ResearchSyncPhase phase = ResearchSyncPhase.push,
    bool isDeleted = false,
  }) : entityType = entityType ?? collection.entityType {
    ResearchSyncContract.validate(
      collection: collection,
      entityId: id,
      payload: payload,
      revision: revision,
      isDeleted: isDeleted,
      phase: phase,
    );
  }
  final SyncCollection collection;
  final String ownerId, id, entityType;
  final int revision, baseRevision;
  final DateTime updatedAt;
  final Map<String, Object?> payload;
  String get operationId => ResearchSyncContract.operationIdFor(
    collection: collection,
    entityId: id,
    payload: payload,
    revision: revision,
  );
}

String _table(SyncCollection c) => c == SyncCollection.neutralEventsV2
    ? 'events_v2'
    : ResearchSyncContract.collections.contains(c)
    ? c.wireName
    : throw const InvalidSyncPayloadFailure();
// Only call after current authority and historical provenance validation. These
// three wrapper fields are not part of the immutable research fact itself.
bool _sameFact(
  Map<String, Object?> a,
  Map<String, Object?> b,
) => ResearchSyncContract.same(
  {
    for (final e in a.entries)
      if (!ResearchSyncContract.referenceKeys.contains(e.key)) e.key: e.value,
  },
  {
    for (final e in b.entries)
      if (!ResearchSyncContract.referenceKeys.contains(e.key)) e.key: e.value,
  },
);
// Consent version is scoped through the existing run pins. A permit that has
// never started a run is still revocable. Keep a withdrawn run as fallback if a
// later consent decision replaces the mutable consent projection before retry.
String _withdrawalScope(String p) =>
    '''
  (EXISTS (SELECT 1 FROM research_consents c
    WHERE c.owner_id = $p.owner_id AND c.consent_state = 'withdrawn'
      AND c.withdrawn_at_utc_ms IS NOT NULL
      AND c.withdrawn_at_utc_ms >= $p.issued_at_utc_ms
      AND (EXISTS (SELECT 1 FROM motivation_measurement_runs r
          WHERE r.owner_id = $p.owner_id AND r.assignment_id = $p.assignment_id
            AND r.protocol_id = $p.protocol_id AND r.protocol_version = $p.protocol_version
            AND r.consent_version = c.consent_version)
        OR NOT EXISTS (SELECT 1 FROM motivation_measurement_runs r
          WHERE r.owner_id = $p.owner_id AND r.assignment_id = $p.assignment_id
            AND r.protocol_id = $p.protocol_id AND r.protocol_version = $p.protocol_version)))
    OR EXISTS (SELECT 1 FROM motivation_measurement_runs r
      WHERE r.owner_id = $p.owner_id AND r.assignment_id = $p.assignment_id
        AND r.protocol_id = $p.protocol_id AND r.protocol_version = $p.protocol_version
        AND r.state = 'withdrawn' AND r.started_at_utc_ms >= $p.issued_at_utc_ms))
''';
String _snake(String key) =>
    key.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
DateTime _utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
Variable _variable(Object? value) => switch (value) {
  int v => Variable<int>(v),
  String v => Variable<String>(v),
  null => const Variable<String>(null),
  _ => throw const InvalidSyncPayloadFailure(),
};
ResearchParticipationPermit _permitFromRow(Map<String, Object?> row) {
  final p = <String, Object?>{
    for (final k in ResearchSyncContract.permitKeys.difference({
      'schema',
      'issuedAtUtc',
      'expiresAtUtc',
      'revokedAtUtc',
      'isDeleted',
    }))
      k: row[_snake(k)],
    'schema': 'lexiquest.research-participation-permit.v1',
    'issuedAtUtc': _utc(row['issued_at_utc_ms']! as int).toIso8601String(),
    'expiresAtUtc': _utc(row['expires_at_utc_ms']! as int).toIso8601String(),
    'revokedAtUtc': row['revoked_at_utc_ms'] == null
        ? null
        : _utc(row['revoked_at_utc_ms']! as int).toIso8601String(),
    'isDeleted': row['is_deleted'] == 1 || row['is_deleted'] == true,
  };
  return ResearchSyncContract.permitFromPayload(p);
}

bool _samePermitPins(
  ResearchParticipationPermit a,
  ResearchParticipationPermit b,
) =>
    a.id == b.id &&
    a.ownerId == b.ownerId &&
    a.assignmentId == b.assignmentId &&
    a.protocolId == b.protocolId &&
    a.protocolVersion == b.protocolVersion &&
    a.assignedTreatment == b.assignedTreatment &&
    a.participantClass == b.participantClass &&
    a.ageBandCode == b.ageBandCode &&
    a.consentReceiptId == b.consentReceiptId &&
    a.guardianPermissionReceiptRef == b.guardianPermissionReceiptRef &&
    a.learnerAssentReceiptRef == b.learnerAssentReceiptRef &&
    a.issuedAtUtc == b.issuedAtUtc;
Map<String, Object?> _permitColumns(ResearchParticipationPermit p) => {
  for (final e in ResearchSyncContract.permitPayload(p).entries)
    if (!{
      'schema',
      'issuedAtUtc',
      'expiresAtUtc',
      'revokedAtUtc',
      'isDeleted',
    }.contains(e.key))
      _snake(e.key): e.value,
  'issued_at_utc_ms': p.issuedAtUtc.millisecondsSinceEpoch,
  'expires_at_utc_ms': p.expiresAtUtc.millisecondsSinceEpoch,
  'revoked_at_utc_ms': p.revokedAtUtc?.millisecondsSinceEpoch,
  'is_deleted': p.isDeleted ? 1 : 0,
};

EventEnvelopeV2 _eventEnvelope(db.EventsV2Data r) {
  // UUIDv7 prefix retains occurrence milliseconds despite the legacy Drift
  // DateTime column's seconds precision. Do not migrate the frozen table here.
  final occurred = researchEventOccurrence(r.eventId, r.occurredAtUtc.toUtc());
  return EventEnvelopeV2(
    eventId: r.eventId,
    eventType: r.eventType,
    eventVersion: r.eventVersion,
    occurredAtUtc: occurred,
    recordedAtUtc: r.recordedAtUtc.toUtc().isBefore(occurred)
        ? occurred
        : r.recordedAtUtc.toUtc(),
    actorIdentity: r.actorIdentity,
    ownerIdentity: r.ownerId,
    tenantContext: r.tenantContextJson == null
        ? null
        : TenantContext.fromJson(
            jsonDecode(r.tenantContextJson!) as Map<String, dynamic>,
          ),
    aggregateType: r.aggregateType,
    aggregateId: r.aggregateId,
    correlationId: r.correlationId,
    causationId: r.causationId,
    idempotencyKey: r.idempotencyKey,
    consentContext: ConsentContext.fromJson(
      jsonDecode(r.consentContextJson) as Map<String, dynamic>,
    ),
    experimentContext: r.experimentContextJson == null
        ? null
        : ExperimentContext.fromJson(
            jsonDecode(r.experimentContextJson!) as Map<String, dynamic>,
          ),
    contentRevision: r.contentRevision,
    policyVersion: r.policyVersion,
    appVersion: r.appVersion,
    buildId: r.buildId,
    providerProvenance: r.providerProvenanceJson == null
        ? null
        : ProviderProvenance.fromJson(
            jsonDecode(r.providerProvenanceJson!) as Map<String, dynamic>,
          ),
    privacyClassification: PrivacyClassification.values.byName(
      r.privacyClassification,
    ),
    payload: jsonDecode(r.payloadJson) as Map<String, dynamic>,
  );
}
