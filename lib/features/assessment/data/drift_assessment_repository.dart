import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_models.dart';
import '../../research/data/drift_experiment_assignment_repository.dart';
import '../../sync/domain/sync_entity.dart';
import '../domain/assessment_models.dart';
import '../domain/assessment_repository.dart';

final class DriftAssessmentRepository implements AssessmentRepository {
  DriftAssessmentRepository(this._database);

  static const String _tableName = 'assessment_runs';
  static const List<String> _columns = [
    'id',
    'owner_id',
    'learning_session_id',
    'study_cycle_id',
    'phase',
    'state',
    'protocol_id',
    'protocol_version',
    'experiment_id',
    'experiment_version',
    'assignment_id',
    'cohort',
    'consent_version',
    'consent_decided_at_utc_ms',
    'instrument_id',
    'instrument_version',
    'form_id',
    'form_version',
    'instrument_checksum_sha256',
    'form_checksum_sha256',
    'app_version',
    'build_id',
    'database_schema_version',
    'content_revision',
    'evidence_policy_version',
    'feature_contract_revision',
    'feature_contract_hash',
    'started_at_utc_ms',
    'completed_at_utc_ms',
    'abandoned_at_utc_ms',
  ];

  final AppDatabase _database;
  final Map<String, Future<void>> _runSerializationTails =
      <String, Future<void>>{};

  static String canonicalOutboxOperationId({
    required String runId,
    required int revision,
  }) {
    AssessmentRun.validateRunId(runId);
    if (revision != 1 && revision != 2) {
      throw ArgumentError.value(revision, 'revision', 'must be 1 or 2');
    }
    return 'assessmentRun:$runId:$revision';
  }

  @override
  Future<AssessmentRun> start(AssessmentRun run) async {
    if (run.state != AssessmentRunState.active) {
      throw ArgumentError.value(
        run.state,
        'run.state',
        'start accepts only an Active assessment run',
      );
    }

    return _database.transaction(() async {
      await _validateReferences(run);

      final existingById = await _findById(run.id);
      if (existingById != null) {
        if (existingById == run) {
          await _ensureOutbox(existingById, revision: 1);
          return existingById;
        }
        throw _conflict(run.id, 'run id is bound to different metadata');
      }

      await _validateStartConsent(run);

      final sessionCollision = await _findByLearningSession(
        run.learningSessionId,
      );
      if (sessionCollision != null) {
        throw _conflict(
          run.id,
          'learningSessionId is already bound to another assessment run',
        );
      }
      final phaseCollision = await _findByOwnerCyclePhase(run);
      if (phaseCollision != null) {
        throw _conflict(
          run.id,
          'owner, study cycle, and phase are already bound',
        );
      }

      await _database.customInsert(
        'INSERT OR IGNORE INTO $_tableName(${_columns.join(',')}) '
        'VALUES ('
        '${List<String>.filled(_columns.length - 2, '?').join(',')},'
        'NULLIF(?, -1),NULLIF(?, -1))',
        variables: _variablesFor(run),
      );

      final persisted = await _findById(run.id);
      if (persisted != null && persisted == run) {
        await _ensureOutbox(persisted, revision: 1);
        return persisted;
      }
      throw _conflict(run.id, 'assessment run insert conflicted');
    });
  }

  /// Persists the latest canonical cloud snapshot without creating a local
  /// echo operation. A fresh device may receive revision two without first
  /// observing revision one; local command transitions remain Active-only.
  Future<AssessmentRun> persistRemote(AssessmentRun run) {
    return _serialize(
      run.id,
      () => _database.transaction(() async {
        await _ensureRemoteLearningSession(run);
        await _validateReferences(run);
        final existing = await _findById(run.id);
        if (existing != null && existing == run) {
          await _ensureRemoteActiveBaseline(existing);
          return existing;
        }

        if (existing == null) {
          if (await _findByLearningSession(run.learningSessionId) != null ||
              await _findByOwnerCyclePhase(run) != null) {
            throw _conflict(run.id, 'remote run conflicts logically');
          }
          await _insertRun(run);
          final persisted = await _findById(run.id);
          if (persisted != null && persisted == run) {
            await _ensureRemoteActiveBaseline(persisted);
            return persisted;
          }
          throw _conflict(run.id, 'remote run insert conflicted');
        }

        if (run.state == AssessmentRunState.active) {
          throw _conflict(run.id, 'remote Active replay changed metadata');
        }
        if (existing.state != AssessmentRunState.active) {
          throw _conflict(run.id, 'remote terminal run cannot reopen or swap');
        }
        final terminalAtUtc = run.state == AssessmentRunState.completed
            ? run.completedAtUtc!
            : run.abandonedAtUtc!;
        final expected = existing.withTerminalState(
          state: run.state,
          terminalAtUtc: terminalAtUtc,
        );
        if (expected != run) {
          throw _conflict(run.id, 'remote terminal run changed immutable pins');
        }
        final updated = await _writeTerminal(expected);
        if (updated != 1) {
          throw _conflict(run.id, 'remote terminal transition conflicted');
        }
        final persisted = await _findById(run.id);
        if (persisted != null && persisted == run) return persisted;
        throw _conflict(run.id, 'remote terminal persistence conflicted');
      }),
    );
  }

  @override
  Future<AssessmentRun> getRun(String runId) async {
    AssessmentRun.validateRunId(runId);
    final run = await _findById(runId);
    if (run == null) throw _conflict(runId, 'assessment run does not exist');
    return run;
  }

  @override
  Future<AssessmentRun> complete({
    required String runId,
    required DateTime completedAtUtc,
  }) {
    return _serialize(
      runId,
      () => _transition(
        runId: runId,
        terminalState: AssessmentRunState.completed,
        terminalAtUtc: completedAtUtc,
      ),
    );
  }

  @override
  Future<AssessmentRun> abandon({
    required String runId,
    required DateTime abandonedAtUtc,
  }) {
    return _serialize(
      runId,
      () => _transition(
        runId: runId,
        terminalState: AssessmentRunState.abandoned,
        terminalAtUtc: abandonedAtUtc,
      ),
    );
  }

  @override
  Future<AssessmentRun> requireActiveForResponse({
    required String runId,
    required DateTime occurredAtUtc,
  }) async {
    return _requireActiveForResponse(
      runId: runId,
      occurredAtUtc: occurredAtUtc,
    );
  }

  @override
  Future<T> serializeActiveResponse<T>({
    required String runId,
    required DateTime occurredAtUtc,
    required AssessmentActiveResponseWork<T> work,
  }) {
    AssessmentRun.validateRunId(runId);
    AssessmentRun.validateUtcTimestamp(occurredAtUtc, 'occurredAtUtc');
    return _serialize(
      runId,
      () => _database.transaction(() async {
        final run = await _requireActiveForResponse(
          runId: runId,
          occurredAtUtc: occurredAtUtc,
        );
        return work(run);
      }),
    );
  }

  @override
  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  }) {
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateCanonicalText(studyCycleId, 'studyCycleId');
    return _database
        .customSelect(
          'SELECT ${_columns.join(',')} FROM $_tableName '
          'WHERE owner_id = ? AND study_cycle_id = ? ORDER BY phase, id',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(studyCycleId),
          ],
        )
        .map(_readRun)
        .get();
  }

  @override
  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  }) {
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateCanonicalText(learningSessionId, 'learningSessionId');
    return _database
        .customSelect(
          'SELECT id, owner_id, session_id, word_id, prompt_mode, is_correct, '
          'occurred_at_utc_ms, evidence_class, evidence_context_json '
          'FROM answer_attempts '
          'WHERE owner_id = ? AND session_id = ? '
          'ORDER BY occurred_at_utc_ms, id',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(learningSessionId),
          ],
        )
        .map((row) {
          final sourceEvidenceId = row.read<String>('id');
          try {
            final decoded = jsonDecode(
              row.read<String>('evidence_context_json'),
            );
            if (decoded is! Map) {
              throw const FormatException('Evidence context is not an object.');
            }
            return AssessmentOutcomeEvidence(
              sourceEvidenceId: sourceEvidenceId,
              ownerId: row.read<String>('owner_id'),
              learningSessionId: row.read<String>('session_id'),
              wordId: row.read<String>('word_id'),
              promptMode: row.read<String>('prompt_mode'),
              isCorrect: row.read<bool>('is_correct'),
              occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('occurred_at_utc_ms'),
                isUtc: true,
              ),
              persistedEvidenceClass: row.read<String>('evidence_class'),
              evidenceContext: EvidenceContext.fromJson(
                decoded.cast<String, Object?>(),
              ),
            );
          } on Object {
            throw _conflict(
              sourceEvidenceId,
              'canonical assessment outcome evidence is malformed',
            );
          }
        })
        .get();
  }

  Future<AssessmentRun> _requireActiveForResponse({
    required String runId,
    required DateTime occurredAtUtc,
  }) async {
    AssessmentRun.validateRunId(runId);
    AssessmentRun.validateUtcTimestamp(occurredAtUtc, 'occurredAtUtc');
    final run = await getRun(runId);
    if (run.state != AssessmentRunState.active) {
      throw _conflict(runId, 'responses require an Active assessment run');
    }
    if (occurredAtUtc.isBefore(run.startedAtUtc)) {
      throw ArgumentError.value(
        occurredAtUtc,
        'occurredAtUtc',
        'must not be before the assessment run started',
      );
    }
    return run;
  }

  Future<T> _serialize<T>(String runId, Future<T> Function() work) async {
    final previous = _runSerializationTails[runId] ?? Future<void>.value();
    final completion = Completer<void>();
    final tail = completion.future;
    _runSerializationTails[runId] = tail;
    await previous;
    try {
      return await work();
    } finally {
      completion.complete();
      if (identical(_runSerializationTails[runId], tail)) {
        _runSerializationTails.remove(runId);
      }
    }
  }

  Future<AssessmentRun> _transition({
    required String runId,
    required AssessmentRunState terminalState,
    required DateTime terminalAtUtc,
  }) {
    AssessmentRun.validateRunId(runId);
    AssessmentRun.validateUtcTimestamp(terminalAtUtc, 'terminalAtUtc');

    return _database.transaction(() async {
      final existing = await _findById(runId);
      if (existing == null) {
        throw _conflict(runId, 'assessment run does not exist');
      }

      if (existing.state == terminalState) {
        final persistedTerminal = terminalState == AssessmentRunState.completed
            ? existing.completedAtUtc
            : existing.abandonedAtUtc;
        if (persistedTerminal == terminalAtUtc) {
          await _ensureOutbox(existing, revision: 2);
          return existing;
        }
        throw _conflict(runId, 'terminal timestamp is immutable');
      }
      if (existing.state != AssessmentRunState.active) {
        throw _conflict(runId, 'terminal assessment state cannot change');
      }

      final terminal = existing.withTerminalState(
        state: terminalState,
        terminalAtUtc: terminalAtUtc,
      );
      final updated = await _writeTerminal(terminal);
      if (updated == 1) {
        final persisted = await _findById(runId);
        if (persisted != null && persisted == terminal) {
          await _ensureOutbox(persisted, revision: 2);
          return persisted;
        }
      } else {
        final concurrent = await _findById(runId);
        if (concurrent != null && concurrent.state == terminalState) {
          final persistedTerminal =
              terminalState == AssessmentRunState.completed
              ? concurrent.completedAtUtc
              : concurrent.abandonedAtUtc;
          if (persistedTerminal == terminalAtUtc) {
            await _ensureOutbox(concurrent, revision: 2);
            return concurrent;
          }
        }
      }
      throw _conflict(runId, 'assessment state transition conflicted');
    });
  }

  Future<int> _writeTerminal(AssessmentRun terminal) {
    return _database.customUpdate(
      'UPDATE $_tableName SET state = ?, '
      'completed_at_utc_ms = NULLIF(?, -1), '
      'abandoned_at_utc_ms = NULLIF(?, -1) '
      "WHERE id = ? AND state = 'active' "
      'AND completed_at_utc_ms IS NULL AND abandoned_at_utc_ms IS NULL',
      variables: [
        Variable<String>(terminal.state.name),
        Variable<int>(terminal.completedAtUtc?.millisecondsSinceEpoch ?? -1),
        Variable<int>(terminal.abandonedAtUtc?.millisecondsSinceEpoch ?? -1),
        Variable<String>(terminal.id),
      ],
    );
  }

  Future<void> _insertRun(AssessmentRun run) {
    return _database.customInsert(
      'INSERT OR IGNORE INTO $_tableName(${_columns.join(',')}) '
      'VALUES ('
      '${List<String>.filled(_columns.length - 2, '?').join(',')},'
      'NULLIF(?, -1),NULLIF(?, -1))',
      variables: _variablesFor(run),
    );
  }

  Future<void> _ensureOutbox(AssessmentRun run, {required int revision}) async {
    final operationId = canonicalOutboxOperationId(
      runId: run.id,
      revision: revision,
    );
    final createdAtUtc = switch (revision) {
      1 => run.startedAtUtc,
      2 => run.completedAtUtc ?? run.abandonedAtUtc!,
      _ => throw ArgumentError.value(revision, 'revision'),
    };
    await _database
        .into(_database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: operationId,
            ownerId: run.ownerId,
            entityType: SyncCollection.assessmentRuns.entityType,
            entityId: run.id,
            operationKind: SyncOperationKind.upsert.name,
            payloadVersion: const Value(1),
            baseRevision: Value(revision - 1),
            createdAtUtcMs: createdAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final persisted = await (_database.select(
      _database.outboxOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
    if (persisted == null ||
        persisted.ownerId != run.ownerId ||
        persisted.entityType != SyncCollection.assessmentRuns.entityType ||
        persisted.entityId != run.id ||
        persisted.operationKind != SyncOperationKind.upsert.name ||
        persisted.payloadVersion != 1 ||
        persisted.baseRevision != revision - 1 ||
        persisted.createdAtUtcMs != createdAtUtc.millisecondsSinceEpoch) {
      throw _conflict(run.id, 'assessment outbox identity conflicted');
    }
  }

  Future<void> _ensureRemoteActiveBaseline(AssessmentRun run) async {
    if (run.state != AssessmentRunState.active) return;
    await _ensureOutbox(run, revision: 1);
    final operationId = canonicalOutboxOperationId(runId: run.id, revision: 1);
    await (_database.update(_database.outboxOperations)..where(
          (row) =>
              row.operationId.equals(operationId) &
              row.state.isNotIn(const <String>[
                'acknowledged',
                'conflictResolved',
              ]),
        ))
        .write(
          const OutboxOperationsCompanion(
            state: Value('conflictResolved'),
            nextAttemptAtUtcMs: Value(null),
            leaseToken: Value(null),
            leaseExpiresAtUtcMs: Value(null),
            failureCode: Value('identicalCloudEvidence'),
          ),
        );
  }

  Future<void> _validateReferences(AssessmentRun run) async {
    final session = await _database
        .customSelect(
          'SELECT owner_id FROM learning_sessions WHERE id = ? LIMIT 1',
          variables: [Variable<String>(run.learningSessionId)],
        )
        .getSingleOrNull();
    if (session == null) {
      throw ArgumentError.value(
        run.learningSessionId,
        'run.learningSessionId',
        'must reference an existing LearningSession',
      );
    }
    if (session.read<String>('owner_id') != run.ownerId) {
      throw ArgumentError.value(
        run.learningSessionId,
        'run.learningSessionId',
        'must belong to run.ownerId',
      );
    }

    final assignment = await _database
        .customSelect(
          'SELECT owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms '
          'FROM experiment_assignments WHERE id = ? LIMIT 1',
          variables: [Variable<String>(run.assignmentId)],
        )
        .getSingleOrNull();
    if (assignment == null) {
      throw ArgumentError.value(
        run.assignmentId,
        'run.assignmentId',
        'must reference an existing ExperimentAssignment',
      );
    }
    if (assignment.read<String>('owner_id') != run.ownerId) {
      throw ArgumentError.value(
        run.assignmentId,
        'run.assignmentId',
        'must belong to run.ownerId',
      );
    }

    final expectedAssignmentId =
        DriftExperimentAssignmentRepository.canonicalAssignmentId(
          ownerId: run.ownerId,
          experimentId: run.experimentId,
          experimentVersion: run.experimentVersion,
        );
    final assignmentMatches =
        run.assignmentId == expectedAssignmentId &&
        assignment.read<String>('experiment_id') == run.experimentId &&
        assignment.read<int>('experiment_version') == run.experimentVersion &&
        assignment.read<String>('cohort') == run.cohort &&
        assignment.read<String>('protocol_version') == run.protocolVersion;
    if (!assignmentMatches) {
      throw _conflict(
        run.id,
        'assignment identity differs from the immutable run pins',
      );
    }

    final assignedAtUtc = DateTime.fromMillisecondsSinceEpoch(
      assignment.read<int>('assigned_at_utc_ms'),
      isUtc: true,
    );
    if (run.startedAtUtc.isBefore(assignedAtUtc)) {
      throw ArgumentError.value(
        run.startedAtUtc,
        'run.startedAtUtc',
        'assignment must exist before the run starts',
      );
    }
  }

  Future<void> _validateStartConsent(AssessmentRun run) async {
    final consent = await _database
        .customSelect(
          'SELECT consent_state, decided_at_utc_ms, withdrawn_at_utc_ms '
          'FROM research_consents WHERE owner_id = ? '
          'AND consent_version = ? LIMIT 1',
          variables: [
            Variable<String>(run.ownerId),
            Variable<int>(run.consentVersion),
          ],
          readsFrom: {_database.researchConsents},
        )
        .getSingleOrNull();
    if (consent == null) {
      throw ArgumentError.value(
        run.consentVersion,
        'run.consentVersion',
        'must reference persisted research consent',
      );
    }
    final decidedAtUtcMs = consent.read<int>('decided_at_utc_ms');
    if (consent.read<String>('consent_state') != 'accepted' ||
        decidedAtUtcMs < 0 ||
        decidedAtUtcMs != run.consentDecidedAtUtc.millisecondsSinceEpoch ||
        consent.readNullable<int>('withdrawn_at_utc_ms') != null) {
      throw ArgumentError.value(
        run.consentVersion,
        'run.consentVersion',
        'must reference the exact granted non-withdrawn research consent',
      );
    }
  }

  Future<void> _ensureRemoteLearningSession(AssessmentRun run) async {
    var session = await _learningSession(run.learningSessionId);
    if (session == null) {
      await DriftLearningRepository(_database).startSession(
        LearningSessionDraft(
          id: run.learningSessionId,
          ownerId: run.ownerId,
          activityType: 'assessment',
          startedAtUtc: run.startedAtUtc,
          appVersion: run.appVersion,
          buildId: run.buildId,
        ),
      );
      session = await _learningSession(run.learningSessionId);
    }
    if (session == null ||
        session.read<String>('owner_id') != run.ownerId ||
        session.read<String>('activity_type') != 'assessment' ||
        session.read<String>('state') != 'active' ||
        session.read<int>('started_at_utc_ms') !=
            run.startedAtUtc.millisecondsSinceEpoch ||
        session.readNullable<int>('ended_at_utc_ms') != null ||
        session.read<String>('app_version') != run.appVersion ||
        session.read<String>('build_id') != run.buildId) {
      throw _conflict(
        run.id,
        'remote assessment LearningSession identity conflicts',
      );
    }
  }

  Future<QueryRow?> _learningSession(String sessionId) {
    return _database
        .customSelect(
          'SELECT owner_id, activity_type, state, started_at_utc_ms, '
          'ended_at_utc_ms, app_version, build_id '
          'FROM learning_sessions WHERE id = ? LIMIT 1',
          variables: [Variable<String>(sessionId)],
          readsFrom: {_database.learningSessions},
        )
        .getSingleOrNull();
  }

  Future<AssessmentRun?> _findById(String id) {
    return _database
        .customSelect(
          'SELECT ${_columns.join(',')} FROM $_tableName '
          'WHERE id = ? LIMIT 1',
          variables: [Variable<String>(id)],
        )
        .map(_readRun)
        .getSingleOrNull();
  }

  Future<AssessmentRun?> _findByLearningSession(String sessionId) {
    return _database
        .customSelect(
          'SELECT ${_columns.join(',')} FROM $_tableName '
          'WHERE learning_session_id = ? LIMIT 1',
          variables: [Variable<String>(sessionId)],
        )
        .map(_readRun)
        .getSingleOrNull();
  }

  Future<AssessmentRun?> _findByOwnerCyclePhase(AssessmentRun run) {
    return _database
        .customSelect(
          'SELECT ${_columns.join(',')} FROM $_tableName '
          'WHERE owner_id = ? AND study_cycle_id = ? AND phase = ? LIMIT 1',
          variables: [
            Variable<String>(run.ownerId),
            Variable<String>(run.studyCycleId),
            Variable<String>(run.phase.name),
          ],
        )
        .map(_readRun)
        .getSingleOrNull();
  }

  AssessmentRun _readRun(QueryRow row) {
    AssessmentPhase phase;
    AssessmentRunState state;
    try {
      phase = AssessmentPhase.values.byName(row.read<String>('phase'));
      state = AssessmentRunState.values.byName(row.read<String>('state'));
    } on ArgumentError {
      throw _conflict(
        row.read<String>('id'),
        'persisted phase or state is unsupported',
      );
    }
    try {
      return AssessmentRun(
        id: row.read<String>('id'),
        ownerId: row.read<String>('owner_id'),
        learningSessionId: row.read<String>('learning_session_id'),
        studyCycleId: row.read<String>('study_cycle_id'),
        phase: phase,
        state: state,
        protocolId: row.read<String>('protocol_id'),
        protocolVersion: row.read<String>('protocol_version'),
        experimentId: row.read<String>('experiment_id'),
        experimentVersion: row.read<int>('experiment_version'),
        assignmentId: row.read<String>('assignment_id'),
        cohort: row.read<String>('cohort'),
        consentVersion: row.read<int>('consent_version'),
        consentDecidedAtUtc: _readUtc(row, 'consent_decided_at_utc_ms')!,
        instrumentId: row.read<String>('instrument_id'),
        instrumentVersion: row.read<String>('instrument_version'),
        formId: row.read<String>('form_id'),
        formVersion: row.read<String>('form_version'),
        instrumentChecksumSha256: row.read<String>(
          'instrument_checksum_sha256',
        ),
        formChecksumSha256: row.read<String>('form_checksum_sha256'),
        appVersion: row.read<String>('app_version'),
        buildId: row.read<String>('build_id'),
        databaseSchemaVersion: row.read<int>('database_schema_version'),
        contentRevision: row.read<String>('content_revision'),
        evidencePolicyVersion: row.read<String>('evidence_policy_version'),
        featureContractRevision: row.read<String>('feature_contract_revision'),
        featureContractHash: row.read<String>('feature_contract_hash'),
        startedAtUtc: _readUtc(row, 'started_at_utc_ms')!,
        completedAtUtc: _readUtc(row, 'completed_at_utc_ms'),
        abandonedAtUtc: _readUtc(row, 'abandoned_at_utc_ms'),
      );
    } on ArgumentError {
      throw _conflict(
        row.read<String>('id'),
        'persisted assessment metadata is malformed',
      );
    }
  }

  DateTime? _readUtc(QueryRow row, String column) {
    final value = row.readNullable<int>(column);
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  List<Variable<Object>> _variablesFor(AssessmentRun run) {
    return <Variable<Object>>[
      Variable<String>(run.id),
      Variable<String>(run.ownerId),
      Variable<String>(run.learningSessionId),
      Variable<String>(run.studyCycleId),
      Variable<String>(run.phase.name),
      Variable<String>(run.state.name),
      Variable<String>(run.protocolId),
      Variable<String>(run.protocolVersion),
      Variable<String>(run.experimentId),
      Variable<int>(run.experimentVersion),
      Variable<String>(run.assignmentId),
      Variable<String>(run.cohort),
      Variable<int>(run.consentVersion),
      Variable<int>(run.consentDecidedAtUtc.millisecondsSinceEpoch),
      Variable<String>(run.instrumentId),
      Variable<String>(run.instrumentVersion),
      Variable<String>(run.formId),
      Variable<String>(run.formVersion),
      Variable<String>(run.instrumentChecksumSha256),
      Variable<String>(run.formChecksumSha256),
      Variable<String>(run.appVersion),
      Variable<String>(run.buildId),
      Variable<int>(run.databaseSchemaVersion),
      Variable<String>(run.contentRevision),
      Variable<String>(run.evidencePolicyVersion),
      Variable<String>(run.featureContractRevision),
      Variable<String>(run.featureContractHash),
      Variable<int>(run.startedAtUtc.millisecondsSinceEpoch),
      Variable<int>(run.completedAtUtc?.millisecondsSinceEpoch ?? -1),
      Variable<int>(run.abandonedAtUtc?.millisecondsSinceEpoch ?? -1),
    ];
  }

  AssessmentRunConflict _conflict(String runId, String reason) {
    return AssessmentRunConflict(runId: runId, reason: reason);
  }
}
