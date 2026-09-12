import 'dart:convert';
import '../../learning/pair_matching/domain/pair_matching_session_purpose.dart';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../sync/domain/research_sync.dart';
import '../../sync/domain/sync_entity.dart';
import '../application/research_participation_permit_validator.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_event_identity.dart';
import '../domain/research_participation_permit.dart';
import '../domain/research_session_proof.dart';
import 'drift_experiment_assignment_repository.dart';
import 'drift_research_session_proof_repository.dart';

/// Read-only authorization inside the caller's existing Sync lease.
///
/// Does not acquire/renew a lease, lock an owner, or mutate capture/transport.
/// The caller must retain its lease through the subsequent transport operation.
/// Injected issuer/receipt authorities determine remote trust and freshness.
final class DriftResearchSyncAuthorizer {
  const DriftResearchSyncAuthorizer({
    required this.database,
    required this.study,
    required this.validator,
    required this.nowUtc,
  });

  final AppDatabase database;
  final MotivationStudyProtocol study;
  final ResearchParticipationPermitValidator validator;
  final DateTime Function() nowUtc;

  Future<bool> authorize(ResearchSyncRequest request) async {
    try {
      requireResearchUtc(request.evaluatedAtUtc);
      final started = _now();
      _require(!request.evaluatedAtUtc.isAfter(started));
      _require(
        validator.protocolId == study.protocolId &&
            validator.protocolVersion == study.protocolVersion,
      );
      _validateContract(request);
      final before = await _snapshot(request);
      final permit = before.permit;
      if (before.cutoff) {
        _authenticate(permit, request.ownerId, started);
      } else {
        final result = await validator.validate(
          permit,
          expectedOwnerId: request.ownerId,
          expectedAssignmentId: permit.assignmentId,
          evaluatedAtUtc: started,
        );
        _require(result.isActive);
      }
      // Never hold a new read transaction across external authority awaits:
      // reload exactly the local dependencies under the caller's existing gate.
      final after = await _snapshot(request);
      _require(ResearchSyncContract.same(before.rows, after.rows));
      final finished = _now();
      _require(!finished.isBefore(started));
      _authenticate(after.permit, request.ownerId, finished);
      if (!after.cutoff) _active(after.permit, finished);
      _require(after.gateExpiry > finished.millisecondsSinceEpoch);
      return true;
    } on Object {
      // Missing/malformed/unavailable authority denies only research.
      return false;
    }
  }

  DateTime _now() {
    final now = nowUtc();
    requireResearchUtc(now);
    return now;
  }

  void _validateContract(ResearchSyncRequest r) {
    final revision = r.collection == SyncCollection.researchParticipationPermits
        ? r.payload['localRevision'] as int
        : 1;
    // Signed cutoff state is structurally valid only on pull. The snapshot
    // below further requires a known, immutable, authentic predecessor.
    ResearchSyncContract.validate(
      collection: r.collection,
      entityId: r.entityId,
      payload: r.payload,
      revision: revision,
      phase: r.phase,
      isDeleted:
          r.collection == SyncCollection.researchParticipationPermits &&
          r.payload['isDeleted'] == true,
    );
    ResearchSyncContract.code(r.ownerId);
    _require(
      r.firebaseUid.isNotEmpty &&
          r.firebaseUid == r.firebaseUid.trim() &&
          r.firebaseUid.length <= 128,
    );
    _require(
      ResearchSyncContract.ownerOf(r.collection, r.payload) == r.ownerId,
    );
  }

  Future<_AuthorizationSnapshot> _snapshot(ResearchSyncRequest r) async {
    final provenance = r.serverReadProvenance;
    if (provenance != null) {
      _require(
        r.phase == ResearchSyncPhase.pull &&
            provenance.matchesPayload(
              firebaseUid: r.firebaseUid,
              collection: r.collection,
              entityId: r.entityId,
              payload: r.payload,
            ),
      );
    }
    final reads = _Reads(database);
    final gate = await _guard(r, reads);
    final isPermit =
        r.collection == SyncCollection.researchParticipationPermits;
    final permitId = isPermit ? r.entityId : r.payload['permitId']! as String;
    final previousRow = await reads.row(
      'research_participation_permits',
      permitId,
    );
    final previous = previousRow == null ? null : _permit(previousRow);
    final p = isPermit
        ? ResearchSyncContract.permitFromPayload(r.payload)
        : previous ?? (throw const FormatException('Missing signed permit'));
    _require(
      p.ownerId == r.ownerId &&
          p.protocolId == study.protocolId &&
          p.protocolVersion == study.protocolVersion,
    );
    final cutoff =
        isPermit &&
        r.phase == ResearchSyncPhase.pull &&
        (p.isDeleted || p.revokedAtUtc != null);
    if (previous != null) {
      _authenticate(previous, r.ownerId, _now());
    }
    if (isPermit && r.phase == ResearchSyncPhase.pull) {
      if (previous == null) {
        _require(!cutoff);
      } else {
        _require(
          _immutablePermit(previous, p) &&
              p.localRevision >= previous.localRevision,
        );
        _require(!previous.isDeleted || p.isDeleted);
        _require(
          previous.revokedAtUtc == null ||
              p.revokedAtUtc == previous.revokedAtUtc,
        );
        if (p.localRevision == previous.localRevision) {
          _require(_samePermit(previous, p));
        }
      }
    } else {
      _require(previous != null && _samePermit(previous, p));
    }
    final historical = !isPermit && await _historicalReferences(r, p, reads);

    final consent = await reads.one(
      'SELECT * FROM research_consents WHERE owner_id = ? AND consent_version = ?',
      [r.ownerId, study.consentVersion],
    );
    final assignment = await reads.row(
      'experiment_assignments',
      p.assignmentId,
    );
    _require(
      assignment != null &&
          assignment['owner_id'] == r.ownerId &&
          assignment['experiment_id'] == study.experimentId &&
          assignment['experiment_version'] == study.experimentVersion &&
          assignment['protocol_version'] == study.protocolVersion &&
          assignment['cohort'] == p.assignedTreatment.name &&
          (assignment['assigned_at_utc_ms']! as int) <=
              p.issuedAtUtc.millisecondsSinceEpoch,
    );
    // This existing repository's getter is read-only, including quarantine
    // conflict checks; do not call its assignment or participation mutations.
    final currentAssignment =
        await DriftExperimentAssignmentRepository(database).getAssignment(
          ownerId: r.ownerId,
          experimentId: study.experimentId,
          experimentVersion: study.experimentVersion,
        );
    _require(currentAssignment.id == p.assignmentId);

    if (!cutoff) {
      _active(p, _now());
      _require(
        consent != null &&
            consent['consent_state'] == 'accepted' &&
            consent['withdrawn_at_utc_ms'] == null &&
            (consent['decided_at_utc_ms']! as int) <=
                (assignment!['assigned_at_utc_ms']! as int),
      );
      final competing = await reads.all(
        'SELECT * FROM research_participation_permits WHERE owner_id = ? '
        'AND protocol_id = ? AND protocol_version = ? AND id <> ? '
        'AND is_deleted = 0 AND revoked_at_utc_ms IS NULL '
        'AND expires_at_utc_ms > ? ORDER BY id LIMIT 1',
        [
          r.ownerId,
          study.protocolId,
          study.protocolVersion,
          p.id,
          _now().millisecondsSinceEpoch,
        ],
      );
      _require(competing.isEmpty);
    }

    final runId = _identity('motivation', [
      r.ownerId,
      p.id,
      study.protocolId,
      study.protocolVersion,
      study.instrument.checksumSha256,
    ]);
    final localRun = await reads.row('motivation_measurement_runs', runId);
    if (!cutoff && localRun != null) {
      _liveRow(localRun, r.ownerId);
      _require(localRun['state'] != 'withdrawn');
      _run(
        _payload(localRun, ResearchSyncContract.runKeys, p),
        p,
        consent!,
        runId,
      );
    }
    if (!isPermit) {
      final incoming = r.payload;
      if (r.collection == SyncCollection.motivationMeasurementRuns) {
        _run(incoming, p, consent!, runId, historicalReferences: historical);
        _existing(
          r,
          localRun,
          ResearchSyncContract.runKeys,
          mutable: const {'state', 'closedAtUtcMs'},
        );
        if (localRun != null && localRun['state'] != 'started') {
          _require(
            incoming['state'] == localRun['state'] &&
                incoming['closedAtUtcMs'] == localRun['closed_at_utc_ms'],
          );
        }
      } else {
        _require(localRun != null);
        if (r.collection == SyncCollection.researchSessionProofs) {
          await _proof(r, localRun!, p, assignment!, reads);
        } else if (r.collection == SyncCollection.motivationResponses) {
          _response(incoming, localRun!, p);
          final existing = await reads.row('motivation_responses', r.entityId);
          _existing(r, existing, ResearchSyncContract.responseKeys);
          final collision = await reads.one(
            'SELECT id FROM motivation_responses '
            'WHERE run_id = ? AND item_id = ?',
            [runId, incoming['itemId']],
          );
          _require(collision == null || collision['id'] == r.entityId);
        } else if (r.collection == SyncCollection.measurementOpportunities) {
          final existing = await reads.row(
            'measurement_opportunities',
            r.entityId,
          );
          await _opportunity(
            incoming,
            localRun!,
            p,
            reads,
            request: r,
            allowMissingEvents: r.phase == ResearchSyncPhase.pull,
            historicalReferences: historical,
          );
          _existing(
            r,
            existing,
            ResearchSyncContract.opportunityKeys,
            mutable: const {
              'effectivePresentation',
              'presentedEventId',
              'learningSessionId',
              'startedEventId',
              'completedEventId',
              'lastSwitchOrdinal',
              'suppressedSwitchCount',
              'closedAtUtcMs',
            },
          );
          if (existing != null) {
            _require(existing['permit_id'] == p.id);
            for (final key in [
              'presentedEventId',
              'learningSessionId',
              'startedEventId',
              'completedEventId',
              'closedAtUtcMs',
            ]) {
              final value = existing[_snake(key)];
              _require(value == null || incoming[key] == value);
            }
            _require(
              (incoming['lastSwitchOrdinal']! as int) >=
                      (existing['last_switch_ordinal']! as int) &&
                  (incoming['suppressedSwitchCount']! as int) >=
                      (existing['suppressed_switch_count']! as int),
            );
          }
        } else {
          await _event(r, localRun!, p, assignment!, reads);
        }
      }
    }
    // Recheck actual owner/gate/fence after all asynchronous database reads too.
    final finalGuard = _Reads(database);
    final finalGate = await _guard(r, finalGuard);
    _require(
      ResearchSyncContract.same(reads.values.first, finalGuard.values.first) &&
          ResearchSyncContract.same(gate, finalGate),
    );
    return _AuthorizationSnapshot(
      p,
      cutoff,
      reads.values,
      finalGate['expires_at_utc_ms']! as int,
    );
  }

  Future<void> _proof(
    ResearchSyncRequest r,
    Map<String, Object?> run,
    ResearchParticipationPermit permit,
    Map<String, Object?> assignment,
    _Reads reads,
  ) async {
    if (r.phase == ResearchSyncPhase.pull) {
      await _pullProof(r, run, permit, reads);
      return;
    }
    _require(r.payload['measurementRunId'] == run['id']);
    final source = await readResearchSessionProofSource(
      read: reads.all,
      ownerId: r.ownerId,
      runId: run['id']! as String,
      permitId: permit.id,
      sessionId: r.payload['learningSessionId']! as String,
      phase: r.payload['proofRevision']! as int,
    );
    _require(ResearchSyncContract.same(source.proof.toJson(), r.payload));
    // The only missing-row exception is a DB-derived canonical enqueue. Claim
    // and push require the exact live immutable phase already persisted.
    _require(source.existing != null || r.phase == ResearchSyncPhase.enqueue);
    _timestamp(source.proof.startedAtUtcMs, permit);
    if (source.proof.endedAtUtcMs != null) {
      _timestamp(source.proof.endedAtUtcMs, permit);
    }
    // Validate authentic accepted linkage with the existing neutral-event
    // authority, including study/consent/configuration, deterministic identities
    // and full Pair purpose reads. _Reads records every dependency for replay
    // after the external receipt await, including absent proof/outbox rows.
    for (final event in source.events) {
      final eventRequest = ResearchSyncRequest(
        phase: r.phase,
        ownerId: r.ownerId,
        firebaseUid: r.firebaseUid,
        ownerGateToken: r.ownerGateToken,
        collection: SyncCollection.neutralEventsV2,
        entityId: event['event_id']! as String,
        payload: {
          ...ResearchSyncContract.reference(permit),
          'envelope': _eventMap(event),
        },
        evaluatedAtUtc: r.evaluatedAtUtc,
      );
      await _event(eventRequest, run, permit, assignment, reads);
    }
  }

  Future<void> _pullProof(
    ResearchSyncRequest r,
    Map<String, Object?> run,
    ResearchParticipationPermit permit,
    _Reads reads,
  ) async {
    final proof = ResearchSessionProof.decode(r.payload);
    _proofPins(proof, run, permit);
    final known = await _knownProofAdmission(proof, reads);
    // Canonical agreement validates consistency, not trust in a new received
    // JSON document. A new mirror must cross the bound server-read boundary.
    _require(r.serverReadProvenance != null || known);
    final siblings = await _proofSiblings(
      proof.ownerId,
      run['id']! as String,
      permit.id,
      proof.learningSessionId,
      reads,
    );
    for (final row in siblings) {
      final sibling = researchSessionProofFromRow(row);
      _require(sibling.hasSameStartCore(proof));
      if (sibling.id == proof.id) {
        _require(
          row['is_deleted'] == 0 &&
              ResearchSyncContract.same(sibling.toJson(), proof.toJson()),
        );
      }
    }
    final canonical = await _canonicalSource(r, proof.learningSessionId, reads);
    if (canonical != null) {
      _require(
        ResearchSyncContract.same(
          canonical.project(proof).toJson(),
          proof.toJson(),
        ),
      );
    }
  }

  void _proofPins(
    ResearchSessionProof proof,
    Map<String, Object?> run,
    ResearchParticipationPermit permit,
  ) {
    _require(
      proof.ownerId == permit.ownerId &&
          proof.permitId == permit.id &&
          proof.measurementRunId == run['id'] &&
          proof.appVersion == run['app_version'] &&
          proof.buildId == run['build_id'] &&
          proof.startedAtUtcMs >= (run['started_at_utc_ms']! as int),
    );
    final closed = run['closed_at_utc_ms'] as int?;
    _require(
      closed == null ||
          (proof.startedAtUtcMs <= closed &&
              (proof.endedAtUtcMs == null || proof.endedAtUtcMs! <= closed)),
    );
    _timestamp(proof.startedAtUtcMs, permit);
    if (proof.endedAtUtcMs != null) _timestamp(proof.endedAtUtcMs, permit);
  }

  Future<List<Map<String, Object?>>> _proofSiblings(
    String owner,
    String run,
    String permit,
    String session,
    _Reads reads,
  ) => reads.all(
    'SELECT * FROM research_session_proofs WHERE owner_id = ? AND measurement_run_id = ? '
    'AND permit_id = ? AND learning_session_id = ? ORDER BY proof_revision, id',
    [owner, run, permit, session],
  );

  Future<bool> _knownProofAdmission(
    ResearchSessionProof proof,
    _Reads reads,
  ) async {
    final row = await reads.row('research_session_proofs', proof.id);
    final id = ResearchSyncContract.operationIdFor(
      collection: SyncCollection.researchSessionProofs,
      entityId: proof.id,
      payload: proof.toJson(),
      revision: 1,
    );
    final operation = await reads.row(
      'outbox_operations',
      id,
      key: 'operation_id',
    );
    if (row == null) return false;
    _liveRow(row, proof.ownerId);
    _require(
      row['local_revision'] == 1 &&
          ResearchSyncContract.same(
            researchSessionProofFromRow(row).toJson(),
            proof.toJson(),
          ),
    );
    return operation != null &&
        operation['owner_id'] == proof.ownerId &&
        operation['entity_id'] == proof.id &&
        operation['entity_type'] == 'researchSessionProof' &&
        operation['operation_kind'] == 'upsert' &&
        operation['payload_version'] == 1 &&
        operation['base_revision'] == 0;
  }

  Future<_CanonicalProofSource?> _canonicalSource(
    ResearchSyncRequest r,
    String sessionId,
    _Reads reads,
  ) async {
    final session = await reads.row('learning_sessions', sessionId);
    if (session == null) return null;
    _require(session['owner_id'] == r.ownerId);
    if (session['activity_type'] == 'syncedEvidence' ||
        session['state'] == 'syncedEvidence') {
      _require(
        r.phase == ResearchSyncPhase.pull &&
            session['activity_type'] == 'syncedEvidence' &&
            session['state'] == 'syncedEvidence' &&
            session['app_version'] == 'unknown' &&
            session['build_id'] == 'synced' &&
            session['ended_at_utc_ms'] == null &&
            session['session_configuration_identity'] == null &&
            session['session_configuration_json'] == null,
      );
      final query = PairMatchingSessionPurpose.checkpointQuery(
        r.ownerId,
        sessionId,
      );
      _require((await reads.all(query.sql, query.args)).isEmpty);
      return null;
    }
    final query = PairMatchingSessionPurpose.checkpointQuery(
      r.ownerId,
      sessionId,
    );
    final checkpoints = session['activity_type'] == 'matching'
        ? await reads.all(query.sql, query.args)
        : <Map<String, Object?>>[];
    final actors = PairMatchingSessionPurpose.historicalOwnerQuery(
      r.ownerId,
      checkpoints,
    );
    final owners = await reads.all(actors.sql, actors.args);
    return _CanonicalProofSource(session, checkpoints, owners);
  }

  /// One authority path for both opportunity linkage and mission timestamps.
  /// Compact admitted mirrors are pull-only; capture and outbound retain their
  /// full canonical source requirement. No projection is written to learning.
  Future<Map<String, Object?>> _sessionAuthority(
    ResearchSyncRequest r,
    Map<String, Object?> run,
    ResearchParticipationPermit permit,
    String sessionId,
    int phase,
    _Reads reads,
  ) async {
    final canonical = await _canonicalSource(r, sessionId, reads);
    final rows = await _proofSiblings(
      r.ownerId,
      run['id']! as String,
      permit.id,
      sessionId,
      reads,
    );
    final proofs = [for (final row in rows) researchSessionProofFromRow(row)];
    for (var index = 0; index < proofs.length; index++) {
      final proof = proofs[index];
      _proofPins(proof, run, permit);
      _require(proofs.every(proof.hasSameStartCore));
      if (canonical != null) {
        _require(
          ResearchSyncContract.same(
            canonical.project(proof).toJson(),
            proof.toJson(),
          ),
        );
      }
    }
    if (canonical != null) {
      final proof = ResearchSessionProof.fromCanonicalSnapshot(
        ownerId: r.ownerId,
        permitId: permit.id,
        permitPayloadSha256: permit.payloadSha256,
        permitRevision: permit.localRevision,
        measurementRunId: run['id']! as String,
        proofRevision: phase,
        session: canonical.session,
        checkpoints: canonical.checkpoints,
        historicalOwners: canonical.owners,
      );
      _proofPins(proof, run, permit);
      return proof.toSessionProjection();
    }
    _require(r.phase == ResearchSyncPhase.pull);
    ResearchSessionProof? selected;
    for (var index = 0; index < proofs.length; index++) {
      final proof = proofs[index];
      if (rows[index]['is_deleted'] != 0 || proof.proofRevision < phase)
        continue;
      _require(await _knownProofAdmission(proof, reads));
      // Historical mirror pins rely on their own prior admission, not the
      // provenance marker of a different opportunity or event payload.
      final proofRequest = ResearchSyncRequest(
        phase: ResearchSyncPhase.pull,
        ownerId: r.ownerId,
        firebaseUid: r.firebaseUid,
        ownerGateToken: r.ownerGateToken,
        collection: SyncCollection.researchSessionProofs,
        entityId: proof.id,
        payload: proof.toJson(),
        evaluatedAtUtc: r.evaluatedAtUtc,
      );
      await _historicalReferences(proofRequest, permit, reads);
      selected ??= proof;
    }
    _require(selected != null);
    // The strict codec has already validated compact Pair purpose. Re-running
    // full terminal-prefix validation against this initial mirror is invalid.
    return selected!.toSessionProjection();
  }

  /// Old references are transport metadata, never a substitute for validating
  /// the current signed permit. New-device history relies on the authenticated
  /// server-read boundary and admission rules. Unmarked lost-ACK recovery needs
  /// both the exact known fact and a durable prior wrapper admission identity.
  Future<bool> _historicalReferences(
    ResearchSyncRequest r,
    ResearchParticipationPermit p,
    _Reads reads,
  ) async {
    if (ResearchSyncContract.reference(
      p,
    ).entries.every((e) => r.payload[e.key] == e.value)) {
      return false;
    }
    _require(
      r.phase == ResearchSyncPhase.pull &&
          r.payload['permitId'] == p.id &&
          (r.payload['permitRevision']! as int) > 0 &&
          (r.payload['permitRevision']! as int) < p.localRevision,
    );
    ResearchSyncContract.digest(r.payload['permitPayloadSha256']);
    if (r.serverReadProvenance != null) return true; // Bound in each snapshot.
    if (r.collection == SyncCollection.researchSessionProofs) {
      _require(
        await _knownProofAdmission(
          ResearchSessionProof.decode(r.payload),
          reads,
        ),
      );
      return true;
    }
    final events = r.collection == SyncCollection.neutralEventsV2;
    final row = await reads.row(
      events ? 'events_v2' : r.collection.wireName,
      r.entityId,
      key: events ? 'event_id' : 'id',
    );
    _require(row != null && row['owner_id'] == r.ownerId);
    final Map<String, Object?> local;
    if (events) {
      local = {'envelope': _eventMap(row!)};
    } else {
      _liveRow(row!, r.ownerId);
      final keys = switch (r.collection) {
        SyncCollection.motivationMeasurementRuns =>
          ResearchSyncContract.runKeys,
        SyncCollection.motivationResponses => ResearchSyncContract.responseKeys,
        SyncCollection.measurementOpportunities =>
          ResearchSyncContract.opportunityKeys,
        _ => throw const FormatException('Not a historical fact'),
      };
      local = {
        for (final k in keys.difference(ResearchSyncContract.referenceKeys))
          k: row[_snake(k)],
      };
    }
    _require(
      ResearchSyncContract.same(local, {
        for (final e in r.payload.entries)
          if (!ResearchSyncContract.referenceKeys.contains(e.key))
            e.key: e.value,
      }),
    );
    final revision = events ? 1 : row['local_revision']! as int;
    final operationId =
        'research-sync:${ResearchSyncContract.fingerprint({'collection': r.collection.wireName, 'id': r.entityId, 'payload': r.payload})}:$revision';
    final operation = await reads.row(
      'outbox_operations',
      operationId,
      key: 'operation_id',
    );
    _require(
      operation != null &&
          operation['owner_id'] == r.ownerId &&
          operation['entity_id'] == r.entityId &&
          operation['operation_kind'] == 'upsert' &&
          operation['payload_version'] == 1 &&
          operation['entity_type'] ==
              (events
                  ? (r.payload['envelope']! as Map)['eventType']
                  : r.collection.entityType),
    );
    return true;
  }

  Future<Map<String, Object?>> _guard(
    ResearchSyncRequest r,
    _Reads reads,
  ) async {
    final owners = await reads.all(
      'SELECT * FROM local_owners WHERE is_active = 1 ORDER BY id LIMIT 2',
      [],
    );
    _require(
      owners.length == 1 &&
          owners.single['id'] == r.ownerId &&
          owners.single['firebase_uid'] == r.firebaseUid,
    );
    final gate = await reads.one(
      'SELECT * FROM runtime_flags WHERE "key" = ?',
      [DriftOwnerOperationGate.gateKey],
    );
    _require(
      gate != null &&
          gate['bool_value'] == 1 &&
          gate['source'] is String &&
          (gate['source']! as String).trim().isNotEmpty &&
          gate['source'] == (gate['source']! as String).trim() &&
          (gate['source']! as String).length <= 256 &&
          gate['expires_at_utc_ms'] is int &&
          (gate['expires_at_utc_ms']! as int) > _now().millisecondsSinceEpoch,
    );
    _require(
      (r.phase == ResearchSyncPhase.push && r.ownerGateToken == null) ||
          (r.ownerGateToken != null && gate!['source'] == r.ownerGateToken),
    );
    _require(
      !await DriftOwnerOperationGate(
        database,
      ).isOwnerFenced(ownerId: r.ownerId, nowUtc: _now()),
    );
    _require(
      (gate!['expires_at_utc_ms']! as int) > _now().millisecondsSinceEpoch,
    );
    return gate;
  }

  void _authenticate(ResearchParticipationPermit p, String owner, DateTime at) {
    _require(
      validator.validateAuthenticity(
            p,
            expectedOwnerId: owner,
            expectedAssignmentId: p.assignmentId,
            evaluatedAtUtc: at,
          ) ==
          ResearchPermitDenialReason.none,
    );
  }

  void _active(ResearchParticipationPermit p, DateTime at) {
    _require(
      !p.isDeleted &&
          !at.isBefore(p.issuedAtUtc) &&
          at.isBefore(p.expiresAtUtc) &&
          (p.revokedAtUtc == null || at.isBefore(p.revokedAtUtc!)),
    );
  }

  void _run(
    Map<String, Object?> run,
    ResearchParticipationPermit p,
    Map<String, Object?> consent,
    String id, {
    bool historicalReferences = false,
  }) {
    ResearchSyncContract.validate(
      collection: SyncCollection.motivationMeasurementRuns,
      entityId: id,
      payload: run,
      revision: 1,
      isDeleted: false,
    );
    final instrument = study.instrument;
    final expected = <String, Object?>{
      if (!historicalReferences) ...ResearchSyncContract.reference(p),
      'id': id,
      'ownerId': p.ownerId,
      'assignmentId': p.assignmentId,
      'consentVersion': study.consentVersion,
      'consentDecidedAtUtcMs': consent['decided_at_utc_ms'],
      'protocolId': study.protocolId,
      'protocolVersion': study.protocolVersion,
      'treatment': p.assignedTreatment.name,
      'instrumentId': instrument.instrumentId,
      'instrumentVersion': instrument.instrumentVersion,
      'formId': instrument.formId,
      'formVersion': instrument.formVersion,
      'appVersion': study.appVersion,
      'buildId': study.buildId,
      'databaseSchemaVersion': AppDatabase.currentSchemaVersion,
      'contentRevision': study.contentRevision,
      'evidencePolicyVersion': study.evidencePolicyVersion,
    };
    _require(
      expected.entries.every((e) => run[e.key] == e.value) &&
          run['state'] != 'withdrawn',
    );
    _timestamp(run['startedAtUtcMs'], p);
    if (run['closedAtUtcMs'] != null) _timestamp(run['closedAtUtcMs'], p);
  }

  void _response(
    Map<String, Object?> response,
    Map<String, Object?> run,
    ResearchParticipationPermit p,
  ) {
    _require(
      response['runId'] == run['id'] &&
          response['ownerId'] == p.ownerId &&
          response['itemCatalogVersion'] == study.instrument.itemCatalogVersion,
    );
    final item = response['itemId']! as String;
    final option = study.instrument.response(
      item,
      response['responseCode']! as String,
    );
    _require(
      response['ordinalValue'] == option.ordinalValue &&
          response['id'] == _identity('response', [run['id'], item]),
    );
    final at = response['answeredAtUtcMs']! as int;
    _timestamp(at, p);
    _require(
      at >= (run['started_at_utc_ms']! as int) &&
          (run['closed_at_utc_ms'] == null ||
              at <= (run['closed_at_utc_ms']! as int)),
    );
  }

  Future<void> _opportunity(
    Map<String, Object?> o,
    Map<String, Object?> run,
    ResearchParticipationPermit p,
    _Reads reads, {
    required ResearchSyncRequest request,
    required bool allowMissingEvents,
    bool historicalReferences = false,
  }) async {
    _require(
      o['ownerId'] == p.ownerId &&
          o['measurementRunId'] == run['id'] &&
          o['assignedTreatment'] == p.assignedTreatment.name &&
          o['id'] ==
              _identity('opportunity', [
                p.ownerId,
                run['id'],
                p.id,
                o['entryAttemptId'],
              ]),
    );
    if (!historicalReferences) _references(o, p);
    final opened = o['openedAtUtcMs']! as int;
    _timestamp(opened, p);
    _require(opened >= (run['started_at_utc_ms']! as int));
    final closed = o['closedAtUtcMs'] as int?;
    if (closed != null) _timestamp(closed, p);
    _require(
      run['closed_at_utc_ms'] == null ||
          (opened <= (run['closed_at_utc_ms']! as int) &&
              (closed == null || closed <= (run['closed_at_utc_ms']! as int))),
    );
    if (o['learningSessionId'] != null) {
      final session = await _sessionAuthority(
        request,
        run,
        p,
        o['learningSessionId']! as String,
        o['completedEventId'] == null ? 1 : 2,
        reads,
      );
      _require(
        session['owner_id'] == p.ownerId &&
            (session['started_at_utc_ms']! as int) >= opened,
      );
    }
    for (final link in const {
      'presentedEventId': 'TodayExperiencePresented',
      'startedEventId': 'TodayExperienceMissionStarted',
      'completedEventId': 'TodayExperienceMissionCompleted',
    }.entries) {
      final id = o[link.key] as String?;
      if (id == null) continue;
      final event = await reads.row('events_v2', id, key: 'event_id');
      if (event == null && allowMissingEvents) continue;
      _require(
        event != null &&
            event['owner_id'] == p.ownerId &&
            event['correlation_id'] == o['id'] &&
            event['event_type'] == link.value,
      );
      final at = _eventMap(event!)['occurredAtUtc']! as String;
      final ms = DateTime.parse(at).millisecondsSinceEpoch;
      _require(ms >= opened && (closed == null || ms <= closed));
      if (link.key != 'presentedEventId') {
        _require(event['aggregate_id'] == o['learningSessionId']);
      }
    }
  }

  Future<void> _event(
    ResearchSyncRequest r,
    Map<String, Object?> run,
    ResearchParticipationPermit p,
    Map<String, Object?> assignment,
    _Reads reads,
  ) async {
    final e = EventEnvelopeV2.fromJson(
      Map<String, dynamic>.from(r.payload['envelope']! as Map),
    );
    final opportunity = await reads.row(
      'measurement_opportunities',
      e.correlationId!,
    );
    _require(opportunity != null);
    _liveRow(opportunity!, r.ownerId);
    _require(
      opportunity['permit_id'] == p.id &&
          opportunity['measurement_run_id'] == run['id'],
    );
    final o = _payload(opportunity, ResearchSyncContract.opportunityKeys, p);
    await _opportunity(
      o,
      run,
      p,
      reads,
      request: r,
      allowMissingEvents: r.phase == ResearchSyncPhase.pull,
    );
    final occurred = e.occurredAtUtc.millisecondsSinceEpoch;
    _timestamp(occurred, p);
    _require(
      !e.recordedAtUtc.isAfter(_now()) &&
          occurred >= (opportunity['opened_at_utc_ms']! as int) &&
          (opportunity['closed_at_utc_ms'] == null ||
              occurred <= (opportunity['closed_at_utc_ms']! as int)),
    );
    _require(
      e.appVersion == study.appVersion &&
          e.buildId == study.buildId &&
          e.contentRevision == study.contentRevision &&
          e.policyVersion == study.evidencePolicyVersion &&
          e.consentContext.researchConsentVersion == study.consentVersion &&
          e.experimentContext!.experimentId == study.experimentId &&
          e.experimentContext!.variantId == p.assignedTreatment.name &&
          e.experimentContext!.assignedAtUtc.millisecondsSinceEpoch ==
              assignment['assigned_at_utc_ms'] &&
          e.payload['assignedTreatment'] == p.assignedTreatment.name,
    );
    final ordinal = e.eventType == 'TodayExperiencePresentationChanged'
        ? e.payload['switchOrdinal']! as int
        : 0;
    final identity = _identity('research', [o['id'], e.eventType, ordinal]);
    _require(
      e.idempotencyKey == identity &&
          e.eventId == researchEventId(identity, e.occurredAtUtc),
    );
    switch (e.eventType) {
      case 'TodayExperiencePresented':
        _require(
          e.payload['catalogVersion'] == study.catalogVersion &&
              e.payload['entryAttemptId'] == o['entryAttemptId'] &&
              o['presentedEventId'] == e.eventId,
        );
      case 'TodayExperiencePresentationChanged':
        _require(
          ordinal <= (o['lastSwitchOrdinal']! as int) &&
              o['presentedEventId'] != null,
        );
      case 'TodayExperienceMissionStarted':
      case 'TodayExperienceMissionCompleted':
        _require(e.aggregateId == o['learningSessionId']);
        final complete = e.eventType == 'TodayExperienceMissionCompleted';
        _require(
          o[complete ? 'completedEventId' : 'startedEventId'] == e.eventId,
        );
        final session = await _sessionAuthority(
          r,
          run,
          p,
          e.aggregateId,
          complete ? 2 : 1,
          reads,
        );
        _require(
          occurred ==
              session[complete ? 'ended_at_utc_ms' : 'started_at_utc_ms'],
        );
        if (complete) _require(session['state'] == 'completed');
      default:
        throw const FormatException('Unknown neutral event');
    }
    final existing = await reads.row('events_v2', r.entityId, key: 'event_id');
    _require(existing != null || r.phase == ResearchSyncPhase.pull);
    if (existing != null) {
      _require(ResearchSyncContract.same(_eventMap(existing), e.toJson()));
    }
    final collision = await reads.one(
      'SELECT event_id FROM events_v2 WHERE owner_id = ? AND idempotency_key = ?',
      [r.ownerId, e.idempotencyKey],
    );
    _require(collision == null || collision['event_id'] == r.entityId);
  }

  void _timestamp(Object? value, ResearchParticipationPermit p) {
    ResearchSyncContract.integer(value);
    final ms = value! as int;
    _require(
      ms >= p.issuedAtUtc.millisecondsSinceEpoch &&
          ms < p.expiresAtUtc.millisecondsSinceEpoch &&
          ms <= _now().millisecondsSinceEpoch &&
          (p.revokedAtUtc == null ||
              ms < p.revokedAtUtc!.millisecondsSinceEpoch),
    );
  }

  void _existing(
    ResearchSyncRequest r,
    Map<String, Object?>? row,
    Set<String> keys, {
    Set<String> mutable = const {},
  }) {
    _require(row != null || r.phase == ResearchSyncPhase.pull);
    if (row == null) return;
    _liveRow(row, r.ownerId);
    for (final key in keys.difference(ResearchSyncContract.referenceKeys)) {
      if (r.phase == ResearchSyncPhase.pull && mutable.contains(key)) continue;
      _require(r.payload[key] == row[_snake(key)]);
    }
  }
}

void _require(bool value) {
  if (!value) throw const FormatException('Research authority denied');
}

void _liveRow(Map<String, Object?> row, String owner) =>
    _require(row['owner_id'] == owner && row['is_deleted'] == 0);
void _references(Map<String, Object?> payload, ResearchParticipationPermit p) =>
    _require(
      ResearchSyncContract.reference(
        p,
      ).entries.every((e) => payload[e.key] == e.value),
    );
String _identity(String prefix, List<Object?> fields) =>
    '$prefix:${sha256.convert(utf8.encode(jsonEncode(fields)))}';
String _snake(String key) =>
    key.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
DateTime _utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
Map<String, Object?> _payload(
  Map<String, Object?> row,
  Set<String> keys,
  ResearchParticipationPermit p,
) => {
  for (final key in keys.difference(ResearchSyncContract.referenceKeys))
    key: row[_snake(key)],
  ...ResearchSyncContract.reference(p),
};
ResearchParticipationPermit _permit(Map<String, Object?> row) =>
    ResearchSyncContract.permitFromPayload({
      for (final key in ResearchSyncContract.permitKeys.difference(const {
        'schema',
        'issuedAtUtc',
        'expiresAtUtc',
        'revokedAtUtc',
        'isDeleted',
      }))
        key: row[_snake(key)],
      'schema': 'lexiquest.research-participation-permit.v1',
      'issuedAtUtc': _utc(row['issued_at_utc_ms']! as int).toIso8601String(),
      'expiresAtUtc': _utc(row['expires_at_utc_ms']! as int).toIso8601String(),
      'revokedAtUtc': row['revoked_at_utc_ms'] == null
          ? null
          : _utc(row['revoked_at_utc_ms']! as int).toIso8601String(),
      'isDeleted': row['is_deleted'] == 1,
    });
bool _samePermit(
  ResearchParticipationPermit a,
  ResearchParticipationPermit b,
) => ResearchSyncContract.same(
  ResearchSyncContract.permitPayload(a),
  ResearchSyncContract.permitPayload(b),
);
bool _immutablePermit(
  ResearchParticipationPermit a,
  ResearchParticipationPermit b,
) {
  final previous = ResearchSyncContract.permitPayload(a);
  final next = ResearchSyncContract.permitPayload(b);
  return ResearchSyncContract.permitKeys
      .difference(const {
        'expiresAtUtc',
        'revokedAtUtc',
        'issuerKeyId',
        'localRevision',
        'cloudRevision',
        'isDeleted',
        'payloadSha256',
        'signature',
      })
      .every((key) => previous[key] == next[key]);
}

Map<String, dynamic> _eventMap(Map<String, Object?> row) {
  final occurred = researchEventOccurrence(
    row['event_id']! as String,
    _utc((row['occurred_at_utc']! as int) * 1000),
  );
  final storedRecorded = _utc((row['recorded_at_utc']! as int) * 1000);
  final envelope = <String, dynamic>{
    'schemaVersion': 2,
    for (final key in [
      'eventId',
      'eventType',
      'eventVersion',
      'actorIdentity',
      'aggregateType',
      'aggregateId',
      'idempotencyKey',
      'appVersion',
      'buildId',
      'privacyClassification',
    ])
      key: row[_snake(key)],
    'ownerIdentity': row['owner_id'],
    'occurredAtUtc': occurred.toIso8601String(),
    'recordedAtUtc':
        (storedRecorded.isBefore(occurred) ? occurred : storedRecorded)
            .toIso8601String(),
    for (final key in [
      'correlationId',
      'causationId',
      'contentRevision',
      'policyVersion',
    ])
      if (row[_snake(key)] != null) key: row[_snake(key)],
    for (final key in [
      'tenantContext',
      'consentContext',
      'experimentContext',
      'providerProvenance',
      'payload',
    ])
      if (row['${_snake(key)}_json'] != null)
        key: jsonDecode(row['${_snake(key)}_json']! as String),
  };
  ResearchSyncContract.validateEvent(envelope, row['event_id']! as String);
  return envelope;
}

final class _CanonicalProofSource {
  const _CanonicalProofSource(this.session, this.checkpoints, this.owners);
  final Map<String, Object?> session;
  final List<Map<String, Object?>> checkpoints, owners;

  ResearchSessionProof project(ResearchSessionProof pins) =>
      ResearchSessionProof.fromCanonicalSnapshot(
        ownerId: pins.ownerId,
        permitId: pins.permitId,
        permitPayloadSha256: pins.permitPayloadSha256,
        permitRevision: pins.permitRevision,
        measurementRunId: pins.measurementRunId,
        proofRevision: pins.proofRevision,
        session: session,
        checkpoints: checkpoints,
        historicalOwners: owners,
      );
}

final class _AuthorizationSnapshot {
  const _AuthorizationSnapshot(
    this.permit,
    this.cutoff,
    this.rows,
    this.gateExpiry,
  );
  final ResearchParticipationPermit permit;
  final bool cutoff;
  final List<Object?> rows;
  final int gateExpiry;
}

final class _Reads {
  _Reads(this.database);
  final AppDatabase database;
  final values = <Object?>[];
  Future<List<Map<String, Object?>>> all(String sql, List<Object?> args) async {
    final result = await database
        .customSelect(
          sql,
          variables: [
            for (final arg in args)
              switch (arg) {
                String v => Variable<String>(v),
                int v => Variable<int>(v),
                _ => throw const FormatException('Invalid query identity'),
              },
          ],
        )
        .get();
    final rows = [for (final row in result) row.data];
    values.add(rows);
    return rows;
  }

  Future<Map<String, Object?>?> one(String sql, List<Object?> args) async {
    final rows = await all(sql, args);
    _require(rows.length <= 1);
    return rows.firstOrNull;
  }

  Future<Map<String, Object?>?> row(
    String table,
    String id, {
    String key = 'id',
  }) => one('SELECT * FROM $table WHERE $key = ?', [id]);
}
