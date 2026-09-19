import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/pair_matching/domain/pair_matching_session_purpose.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../sync/domain/research_sync.dart';
import '../../sync/domain/sync_entity.dart';
import '../domain/research_event_identity.dart';
import '../domain/research_session_proof.dart';

/// Prepares historical transport from accepted canonical learning only. The
/// constructor callback is composed by the adapter; it is not proof authority.
final class DriftResearchSessionProofRepository {
  const DriftResearchSessionProofRepository(
    this.database, {
    required this.rollout,
    required this.authorizeCandidate,
    required this.nowUtc,
  });

  // Scheduling hints have no authority and are never persisted for denials.
  // Database scope survives repository reconstruction, but not database reopen.
  static final _scanHints = Expando<Map<String, _ProofScanCursor>>();

  final AppDatabase database;
  final ResearchMeasurementSyncRollout rollout;
  final ResearchSyncAuthorizer? authorizeCandidate;
  final DateTime Function() nowUtc;

  // Local scheduling only. Never a SyncCollection or a server pull cursor.
  static const _checkpointCollection =
      'local:research-session-proof-preparation:v1';

  Future<int> prepareForOwner({
    required String ownerId,
    required String firebaseUid,
    required String ownerGateToken,
    required int limit,
  }) async {
    if (limit < 1 || limit > 50) throw RangeError.range(limit, 1, 50);
    if (!rollout.allowsSync || authorizeCandidate == null) return 0;
    return database.transaction(() async {
      DateTime firstStarted;
      try {
        firstStarted = _now();
        await _guard(ownerId, firebaseUid, ownerGateToken, firstStarted);
      } on FormatException {
        return 0;
      }
      final checkpointBefore = await _checkpoint(ownerId);
      final hints = _scanHints[database] ??= <String, _ProofScanCursor>{};
      final hintKey = jsonEncode([ownerId, firebaseUid]);
      final cursor = hints[hintKey] ?? _ProofScanCursor.decode(checkpointBefore);
      final candidates = await _candidates(ownerId, cursor, limit);
      if (candidates.isNotEmpty) hints[hintKey] = candidates.last.cursor;
      var inserted = 0;
      var first = true;
      _ProofScanCursor? frontier;
      final admitted = <String, _ProofCursorAdmission>{};
      for (final candidate in candidates) {
        ResearchSessionProofSource before;
        DateTime started;
        List<Map<String, Object?>> guard;
        try {
          started = first ? firstStarted : _now();
          first = false;
          guard = await _guard(ownerId, firebaseUid, ownerGateToken, started);
          before = await readResearchSessionProofSource(
            read: _read,
            ownerId: ownerId,
            runId: candidate.row['measurement_run_id']! as String,
            permitId: candidate.row['permit_id']! as String,
            sessionId: candidate.row['learning_session_id']! as String,
            phase: candidate.cursor.phase,
          );
          _current(before, started);
        } on FormatException {
          continue;
        }
        final proof = before.proof;
        final request = ResearchSyncRequest(
          phase: ResearchSyncPhase.enqueue,
          ownerId: ownerId,
          firebaseUid: firebaseUid,
          ownerGateToken: ownerGateToken,
          collection: SyncCollection.researchSessionProofs,
          entityId: proof.id,
          payload: proof.toJson(),
          evaluatedAtUtc: started,
        );
        if (!await authorizeResearchSync(authorizeCandidate, request)) continue;
        DateTime finished;
        ResearchSessionProofSource after;
        try {
          finished = _now();
          _require(!finished.isBefore(started));
          after = await readResearchSessionProofSource(
            read: _read,
            ownerId: ownerId,
            runId: proof.measurementRunId,
            permitId: proof.permitId,
            sessionId: proof.learningSessionId,
            phase: proof.proofRevision,
          );
          _require(ResearchSyncContract.same(before.rows, after.rows));
          _current(after, finished);
          final finalGuard = await _guard(
            ownerId,
            firebaseUid,
            ownerGateToken,
            finished,
          );
          _require(ResearchSyncContract.same(guard, finalGuard));
          final last = _now();
          _require(!last.isBefore(finished));
          _current(after, last);
          _require(
            (finalGuard.last['expires_at_utc_ms']! as int) >
                last.millisecondsSinceEpoch,
          );
          finished = last;
        } on FormatException {
          continue;
        }
        // Mutation failures deliberately escape the transaction: no orphan
        // proof may survive a failed outbox insert. Existing metadata is never
        // replaced, even when preparing the other phase after an ACK.
        if (after.existing == null) {
          await database
              .into(database.researchSessionProofs)
              .insert(
                ResearchSessionProofsCompanion.insert(
                  id: proof.id,
                  ownerId: proof.ownerId,
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
                  sessionConfigurationJson: Value(
                    proof.sessionConfigurationJson,
                  ),
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
                ),
              );
        }
        if (after.operation == null) {
          await database
              .into(database.outboxOperations)
              .insert(
                OutboxOperationsCompanion.insert(
                  operationId: after.operationId,
                  ownerId: ownerId,
                  entityType: 'researchSessionProof',
                  entityId: proof.id,
                  operationKind: 'upsert',
                  createdAtUtcMs: finished.millisecondsSinceEpoch,
                ),
              );
          inserted++;
        }
        // Capture expected post-write rows, including delivery metadata. Only
        // our proof/outbox insertions may differ from the admitted source.
        final committed = await _source(proof);
        _require(
          ResearchSyncContract.same(after.sourceRows, committed.sourceRows),
        );
        final tuple = jsonEncode([
          proof.measurementRunId,
          proof.permitId,
          proof.learningSessionId,
        ]);
        admitted[tuple] = _ProofCursorAdmission(committed, guard, finished);
        frontier = candidate.cursor;
      }
      if (frontier != null) {
        // A later denial/withdrawal must not turn an earlier approval into a
        // late scheduling write. Reread every admitted tuple, not only the last.
        try {
          for (final admission in admitted.values) {
            final current = await _source(admission.source.proof);
            _require(
              ResearchSyncContract.same(admission.source.rows, current.rows),
            );
            final at = _now();
            _require(!at.isBefore(admission.at));
            _current(current, at);
            final guard = await _guard(
              ownerId,
              firebaseUid,
              ownerGateToken,
              at,
            );
            _require(ResearchSyncContract.same(admission.guard, guard));
          }
          _require(
            ResearchSyncContract.same(
              checkpointBefore,
              await _checkpoint(ownerId),
            ),
          );
          final finalAt = _now();
          final finalGuard = await _guard(
            ownerId,
            firebaseUid,
            ownerGateToken,
            finalAt,
          );
          final writeAt = _now();
          _require(!writeAt.isBefore(finalAt));
          _require(
            _integer(finalGuard.last['expires_at_utc_ms']) >
                writeAt.millisecondsSinceEpoch,
          );
          for (final admission in admitted.values) {
            _require(!writeAt.isBefore(admission.at));
            _require(ResearchSyncContract.same(admission.guard, finalGuard));
            _current(admission.source, writeAt);
          }
        } on FormatException {
          return inserted;
        }
        // An executor/write failure escapes and rolls back all three records.
        await database
            .into(database.syncCheckpoints)
            .insertOnConflictUpdate(
              SyncCheckpointsCompanion.insert(
                id: '$ownerId:$_checkpointCollection',
                ownerId: ownerId,
                collectionName: _checkpointCollection,
                serverCursor: Value(frontier.encode()),
                lastSuccessAtUtcMs: const Value(null),
              ),
            );
      }
      return inserted;
    });
  }

  DateTime _now() {
    final value = nowUtc();
    _require(value.isUtc && value.microsecondsSinceEpoch >= 0);
    return value;
  }

  Future<ResearchSessionProofSource> _source(ResearchSessionProof proof) =>
      readResearchSessionProofSource(
        read: _read,
        ownerId: proof.ownerId,
        runId: proof.measurementRunId,
        permitId: proof.permitId,
        sessionId: proof.learningSessionId,
        phase: proof.proofRevision,
      );

  Future<List<Map<String, Object?>>> _checkpoint(String owner) => _read(
    'SELECT * FROM sync_checkpoints WHERE owner_id = ? AND collection_name = ?',
    [owner, _checkpointCollection],
  );

  // SQL selects only bounded keys. Exact immutable payload hashing is done by
  // the shared Dart source reader; any other same-entity intent is irrelevant.
  Future<List<_ProofScanCandidate>> _candidates(
    String owner,
    _ProofScanCursor? cursor,
    int limit,
  ) async {
    Future<String?> upper() async {
      // A scalar opportunity boundary, not an extra inspected phase.
      final rows = await _read(
        '''
        SELECT MAX(o.id) AS upper_id FROM measurement_opportunities o
        JOIN learning_sessions s ON s.id = o.learning_session_id AND s.owner_id = o.owner_id
        WHERE o.owner_id = ? AND o.is_deleted = 0
          AND o.presented_event_id IS NOT NULL AND o.started_event_id IS NOT NULL
      ''',
        [owner],
      );
      final value = rows.single['upper_id'];
      return value == null ? null : _string(value);
    }

    final ceiling = cursor?.upper ?? await upper();
    if (ceiling == null) return [];
    final tail = await _read(
      '$_phaseQuery AND o.id <= ? '
      '${cursor == null ? '' : 'AND (o.id > ? OR (o.id = ? AND phases.phase > ?)) '}'
      'ORDER BY o.id, phases.phase LIMIT ?',
      [
        owner,
        ceiling,
        if (cursor != null) ...[cursor.id, cursor.id, cursor.phase],
        limit,
      ],
    );
    final result = [for (final row in tail) _ProofScanCandidate(row, ceiling)];
    if (cursor == null || result.length == limit) return result;
    // Finish this finite cycle once. Snapshot the next cycle ceiling so
    // continuously appended upper keys cannot postpone older work forever.
    final nextCeiling = await upper();
    if (nextCeiling == null) return result;
    final head = await _read(
      '$_phaseQuery AND o.id <= ? '
      'AND NOT (o.id <= ? AND (o.id > ? OR (o.id = ? AND phases.phase > ?))) '
      'ORDER BY o.id, phases.phase LIMIT ?',
      [
        owner,
        nextCeiling,
        ceiling,
        cursor.id,
        cursor.id,
        cursor.phase,
        limit - result.length,
      ],
    );
    result.addAll([
      for (final row in head) _ProofScanCandidate(row, nextCeiling),
    ]);
    return result;
  }

  static const _phaseQuery = '''
    WITH phases(phase) AS (VALUES (1), (2))
    SELECT o.id, o.measurement_run_id, o.permit_id, o.learning_session_id, phases.phase
    FROM measurement_opportunities o CROSS JOIN phases
    JOIN learning_sessions s ON s.id = o.learning_session_id AND s.owner_id = o.owner_id
    WHERE o.owner_id = ? AND o.is_deleted = 0
      AND o.presented_event_id IS NOT NULL AND o.started_event_id IS NOT NULL
      AND (phases.phase = 1 OR (s.state = 'completed' AND s.ended_at_utc_ms IS NOT NULL))
  ''';

  Future<List<Map<String, Object?>>> _read(
    String sql,
    List<Object?> args,
  ) async => [
    for (final row
        in await database
            .customSelect(
              sql,
              variables: [
                for (final arg in args)
                  switch (arg) {
                    String value => Variable<String>(value),
                    int value => Variable<int>(value),
                    _ => throw const FormatException('Invalid proof query'),
                  },
              ],
            )
            .get())
      row.data,
  ];

  Future<List<Map<String, Object?>>> _guard(
    String owner,
    String uid,
    String token,
    DateTime at,
  ) async {
    _require(
      uid.isNotEmpty &&
          uid == uid.trim() &&
          token.isNotEmpty &&
          token == token.trim(),
    );
    final owners = await _read(
      'SELECT * FROM local_owners WHERE is_active = 1 ORDER BY id LIMIT 2',
      [],
    );
    _require(
      owners.length == 1 &&
          owners.single['id'] == owner &&
          owners.single['firebase_uid'] == uid,
    );
    final gates = await _read('SELECT * FROM runtime_flags WHERE "key" = ?', [
      DriftOwnerOperationGate.gateKey,
    ]);
    _require(
      gates.length == 1 &&
          gates.single['bool_value'] == 1 &&
          gates.single['source'] == token &&
          gates.single['expires_at_utc_ms'] is int &&
          (gates.single['expires_at_utc_ms']! as int) >
              at.millisecondsSinceEpoch,
    );
    _require(
      !await DriftOwnerOperationGate(
        database,
      ).isOwnerFenced(ownerId: owner, nowUtc: at),
    );
    return [...owners, ...gates];
  }

  void _current(ResearchSessionProofSource source, DateTime at) {
    final permit = source.permit;
    final ms = at.millisecondsSinceEpoch;
    _require(
      permit['is_deleted'] == 0 &&
          permit['revoked_at_utc_ms'] == null &&
          _integer(permit['issued_at_utc_ms']) <= ms &&
          _integer(permit['expires_at_utc_ms']) > ms &&
          source.proof.startedAtUtcMs <= ms &&
          (source.proof.endedAtUtcMs == null ||
              (source.proof.endedAtUtcMs! <= ms &&
                  source.proof.endedAtUtcMs! <
                      _integer(permit['expires_at_utc_ms']))),
    );
  }
}

/// Shared source consistency reader. The authorizer supplies its tracked _Reads
/// query function and independently authenticates the permit and linked events.
/// These values alone never authorize upload or receiver admission.
final class ResearchSessionProofSource {
  const ResearchSessionProofSource(
    this.proof,
    this.rows,
    this.sourceRows,
    this.permit,
    this.events,
    this.existing,
    this.operation,
    this.operationId,
  );
  final ResearchSessionProof proof;
  final List<Object?> rows;
  // Complete canonical/participant inputs, excluding only proof delivery rows
  // that this repository itself inserts after admission.
  final List<Object?> sourceRows;
  final Map<String, Object?> permit;
  final List<Map<String, Object?>> events;
  final Map<String, Object?>? existing, operation;
  final String operationId;
}

Future<ResearchSessionProofSource> readResearchSessionProofSource({
  required Future<List<Map<String, Object?>>> Function(String, List<Object?>)
  read,
  required String ownerId,
  required String runId,
  required String permitId,
  required String sessionId,
  required int phase,
}) async {
  final captured = <Object?>[];
  Future<List<Map<String, Object?>>> all(String sql, List<Object?> args) async {
    final rows = await read(sql, args);
    captured.add(rows);
    return rows;
  }

  Future<Map<String, Object?>> one(String table, String id) async {
    final rows = await all('SELECT * FROM $table WHERE id = ?', [id]);
    _require(rows.length == 1 && rows.single['owner_id'] == ownerId);
    return rows.single;
  }

  final opportunities = await all(
    'SELECT * FROM measurement_opportunities WHERE owner_id = ? AND measurement_run_id = ? AND permit_id = ? AND learning_session_id = ? ORDER BY id LIMIT 2',
    [ownerId, runId, permitId, sessionId],
  );
  _require(opportunities.length == 1);
  final opportunity = opportunities.single;
  _require(
    opportunity['is_deleted'] == 0 &&
        opportunity['presented_event_id'] is String &&
        opportunity['started_event_id'] is String,
  );
  final run = await one('motivation_measurement_runs', runId);
  final permit = await one('research_participation_permits', permitId);
  final assignment = await one(
    'experiment_assignments',
    _string(permit['assignment_id']),
  );
  // Capture competing permit and assignment/quarantine changes too. Eligibility
  // remains the composed authorizer's policy; exact read-set changes deny.
  await all(
    'SELECT * FROM research_participation_permits WHERE owner_id = ? AND protocol_id = ? AND protocol_version = ? ORDER BY id',
    [ownerId, permit['protocol_id'], permit['protocol_version']],
  );
  await all(
    'SELECT * FROM experiment_assignments WHERE owner_id = ? ORDER BY id',
    [ownerId],
  );
  await all(
    "SELECT * FROM sync_conflicts WHERE owner_id = ? AND entity_type = 'experimentAssignment' AND outcome = 'quarantined' ORDER BY id",
    [ownerId],
  );
  final consents = await all(
    'SELECT * FROM research_consents WHERE owner_id = ? ORDER BY decided_at_utc_ms DESC, consent_version DESC',
    [ownerId],
  );
  _require(
    consents.isNotEmpty &&
        consents.first['consent_state'] == 'accepted' &&
        consents.first['withdrawn_at_utc_ms'] == null &&
        consents.first['consent_version'] == run['consent_version'] &&
        consents.first['decided_at_utc_ms'] == run['consent_decided_at_utc_ms'],
  );
  _require(
    run['is_deleted'] == 0 &&
        run['state'] != 'withdrawn' &&
        permit['is_deleted'] == 0 &&
        permit['revoked_at_utc_ms'] == null &&
        permit['assignment_id'] == run['assignment_id'] &&
        permit['protocol_id'] == run['protocol_id'] &&
        permit['protocol_version'] == run['protocol_version'] &&
        assignment['cohort'] == run['treatment'] &&
        permit['assigned_treatment'] == run['treatment'] &&
        opportunity['assigned_treatment'] == run['treatment'],
  );
  final session = await one('learning_sessions', sessionId);
  _require(
    session['activity_type'] != 'syncedEvidence' &&
        {'active', 'completed', 'abandoned'}.contains(session['state']),
  );
  final query = PairMatchingSessionPurpose.checkpointQuery(ownerId, sessionId);
  final checkpoints = session['activity_type'] == 'matching'
      ? await all(query.sql, query.args)
      : <Map<String, Object?>>[];
  final actors = PairMatchingSessionPurpose.historicalOwnerQuery(
    ownerId,
    checkpoints,
  );
  final owners = await all(actors.sql, actors.args);
  final proof = ResearchSessionProof.fromCanonicalSnapshot(
    ownerId: ownerId,
    permitId: permitId,
    permitPayloadSha256: _string(permit['payload_sha256']),
    permitRevision: _integer(permit['local_revision']),
    measurementRunId: runId,
    proofRevision: phase,
    session: session,
    checkpoints: checkpoints,
    historicalOwners: owners,
  );
  _require(
    proof.appVersion == run['app_version'] &&
        proof.buildId == run['build_id'] &&
        proof.startedAtUtcMs >= _integer(opportunity['opened_at_utc_ms']) &&
        proof.startedAtUtcMs >= _integer(permit['issued_at_utc_ms']) &&
        proof.startedAtUtcMs < _integer(permit['expires_at_utc_ms']),
  );
  final events = <Map<String, Object?>>[];
  for (final link in const {
    'presented_event_id': 'TodayExperiencePresented',
    'started_event_id': 'TodayExperienceMissionStarted',
    'completed_event_id': 'TodayExperienceMissionCompleted',
  }.entries) {
    final id = opportunity[link.key];
    if (id == null) continue;
    final rows = await all('SELECT * FROM events_v2 WHERE event_id = ?', [id]);
    _require(rows.length == 1);
    final event = rows.single;
    _require(
      event['owner_id'] == ownerId &&
          event['event_type'] == link.value &&
          event['correlation_id'] == opportunity['id'],
    );
    final occurred = researchEventOccurrence(
      _string(id),
      DateTime.fromMillisecondsSinceEpoch(
        _integer(event['occurred_at_utc']) * 1000,
        isUtc: true,
      ),
    ).millisecondsSinceEpoch;
    if (link.key == 'presented_event_id') {
      _require(
        event['aggregate_type'] == 'MeasurementOpportunity' &&
            event['aggregate_id'] == opportunity['id'] &&
            occurred <= proof.startedAtUtcMs,
      );
    } else {
      _require(
        event['aggregate_type'] == 'LearningSession' &&
            event['aggregate_id'] == sessionId &&
            occurred ==
                session[link.key == 'started_event_id'
                    ? 'started_at_utc_ms'
                    : 'ended_at_utc_ms'],
      );
      if (link.key == 'started_event_id' &&
          proof.sessionConfigurationJson != null) {
        final payload = jsonDecode(_string(event['payload_json']));
        _require(payload is Map);
        final configuration = SessionConfiguration.fromStableSerialization(
          proof.sessionConfigurationJson!,
        );
        _require((payload as Map)['mode'] == configuration.mode.id);
      }
    }
    events.add(event);
  }
  final sourceRows = List<Object?>.of(captured);
  final siblings = await all(
    'SELECT * FROM research_session_proofs WHERE owner_id = ? AND measurement_run_id = ? AND permit_id = ? AND learning_session_id = ? ORDER BY proof_revision, id',
    [ownerId, runId, permitId, sessionId],
  );
  Map<String, Object?>? existing;
  for (final row in siblings) {
    final stored = researchSessionProofFromRow(row);
    _require(row['is_deleted'] == 0 && stored.hasSameStartCore(proof));
    if (stored.proofRevision == phase) {
      _require(
        existing == null &&
            row['is_deleted'] == 0 &&
            row['local_revision'] == 1 &&
            ResearchSyncContract.same(stored.toJson(), proof.toJson()),
      );
      existing = row;
    }
  }
  // Record global identity absence as well as tuple siblings: wrong-owner
  // collisions must deny before invoking any authority callback.
  final identities = await all(
    'SELECT * FROM research_session_proofs WHERE id = ?',
    [proof.id],
  );
  _require(
    existing == null
        ? identities.isEmpty
        : identities.length == 1 &&
              ResearchSyncContract.same(identities.single, existing),
  );
  final operationId = ResearchSyncContract.operationIdFor(
    collection: SyncCollection.researchSessionProofs,
    entityId: proof.id,
    payload: proof.toJson(),
    revision: 1,
  );
  final operations = await all(
    "SELECT * FROM outbox_operations WHERE operation_id = ? OR (owner_id = ? AND entity_type = 'researchSessionProof' AND entity_id IN (SELECT id FROM research_session_proofs WHERE owner_id = ? AND measurement_run_id = ? AND permit_id = ? AND learning_session_id = ?)) ORDER BY operation_id",
    [operationId, ownerId, ownerId, runId, permitId, sessionId],
  );
  Map<String, Object?>? operation;
  for (final row in operations) {
    if (row['operation_id'] != operationId) continue;
    _require(
      row['owner_id'] == ownerId &&
          row['entity_id'] == proof.id &&
          row['entity_type'] == 'researchSessionProof' &&
          row['operation_kind'] == 'upsert' &&
          row['payload_version'] == 1,
    );
    operation = row;
  }
  return ResearchSessionProofSource(
    proof,
    captured,
    sourceRows,
    permit,
    events,
    existing,
    operation,
    operationId,
  );
}

ResearchSessionProof researchSessionProofFromRow(Map<String, Object?> row) =>
    ResearchSessionProof.decode({
      'schema': ResearchSessionProof.schema,
      for (final key in const [
        'id',
        'ownerId',
        'measurementRunId',
        'permitId',
        'learningSessionId',
        'proofRevision',
        'activityType',
        'sessionState',
        'startedAtUtcMs',
        'endedAtUtcMs',
        'appVersion',
        'buildId',
        'sessionConfigurationIdentity',
        'sessionConfigurationJson',
        'pairStartOperation',
        'pairCheckpointEventVersion',
        'permitPayloadSha256',
        'permitRevision',
      ])
        key:
            row[key.replaceAllMapped(
              RegExp('[A-Z]'),
              (match) => '_${match[0]!.toLowerCase()}',
            )],
      'pairOwnerLineage': row['pair_owner_lineage_json'] == null
          ? null
          : jsonDecode(_string(row['pair_owner_lineage_json'])),
    });

final class _ProofCursorAdmission {
  const _ProofCursorAdmission(this.source, this.guard, this.at);
  final ResearchSessionProofSource source;
  final List<Map<String, Object?>> guard;
  final DateTime at;
}

final class _ProofScanCandidate {
  _ProofScanCandidate(this.row, String upper)
    : cursor = _ProofScanCursor(
        row['id']! as String,
        row['phase']! as int,
        upper,
      );
  final Map<String, Object?> row;
  final _ProofScanCursor cursor;
}

final class _ProofScanCursor {
  const _ProofScanCursor(this.id, this.phase, this.upper);
  final String id, upper;
  final int phase;
  static const _schema = 'local-research-proof-scan.v1';

  String encode() => jsonEncode({
    'schema': _schema,
    'afterOpportunityId': id,
    'afterPhase': phase,
    'upperOpportunityId': upper,
  });

  static _ProofScanCursor? decode(List<Map<String, Object?>> rows) {
    if (rows.length != 1) return null;
    final text = rows.single['server_cursor'];
    if (text is! String || text.length > 1024) return null;
    try {
      final value = jsonDecode(text);
      if (value is! Map ||
          value.length != 4 ||
          value['schema'] != _schema ||
          !value.keys.every(
            const {
              'schema',
              'afterOpportunityId',
              'afterPhase',
              'upperOpportunityId',
            }.contains,
          ))
        return null;
      final id = value['afterOpportunityId'];
      final upper = value['upperOpportunityId'];
      final phase = value['afterPhase'];
      if (id is! String ||
          upper is! String ||
          phase is! int ||
          (phase != 1 && phase != 2) ||
          !RegExp(r'^[A-Za-z0-9_.:\-]{1,128}$').hasMatch(id) ||
          !RegExp(r'^[A-Za-z0-9_.:\-]{1,128}$').hasMatch(upper) ||
          id.compareTo(upper) > 0)
        return null;
      return _ProofScanCursor(id, phase, upper);
    } on FormatException {
      return null;
    }
  }
}

void _require(bool value) {
  if (!value) throw const FormatException('Research proof source unavailable');
}

String _string(Object? value) {
  if (value is! String)
    throw const FormatException('Invalid proof source field');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Invalid proof source field');
  return value;
}
