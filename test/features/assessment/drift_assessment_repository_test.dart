import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  late AppDatabase database;
  late DriftAssessmentRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftAssessmentRepository(database);
    await _seedOwner(database, _ownerId);
    await _seedOwner(database, _otherOwnerId);
    await _seedConsent(database, ownerId: _ownerId);
    await _seedConsent(database, ownerId: _otherOwnerId);
    await _seedSession(database, ownerId: _ownerId, sessionId: _sessionId);
    await _seedSession(
      database,
      ownerId: _ownerId,
      sessionId: _secondSessionId,
    );
    await _seedSession(
      database,
      ownerId: _otherOwnerId,
      sessionId: _otherSessionId,
    );
    await _seedAssignment(database, ownerId: _ownerId);
    await _seedAssignment(database, ownerId: _otherOwnerId);
  });

  tearDown(() => database.close());

  test(
    'start persists one active run linked to the existing session and assignment',
    () async {
      final run = _run();

      final persisted = await repository.start(run);

      expect(persisted, sameAssessmentRunAs(run));
      expect(await _runCount(database), 1);
      expect(await _rowSnapshot(database, _runId), <String, Object?>{
        'id': _runId,
        'owner_id': _ownerId,
        'learning_session_id': _sessionId,
        'study_cycle_id': _studyCycleId,
        'phase': AssessmentPhase.pre.name,
        'state': AssessmentRunState.active.name,
        'protocol_id': _protocolId,
        'protocol_version': _protocolVersion,
        'experiment_id': _experimentId,
        'experiment_version': _experimentVersion,
        'assignment_id': _assignmentId(_ownerId),
        'cohort': _cohort,
        'consent_version': _consentVersion,
        'consent_decided_at_utc_ms':
            _consentDecidedAtUtc.millisecondsSinceEpoch,
        'instrument_id': _instrumentId,
        'instrument_version': _instrumentVersion,
        'form_id': _formId,
        'form_version': _formVersion,
        'instrument_checksum_sha256': _instrumentChecksum,
        'form_checksum_sha256': _formChecksum,
        'app_version': _appVersion,
        'build_id': _buildId,
        'database_schema_version': 15,
        'content_revision': _contentRevision,
        'evidence_policy_version': _evidencePolicyVersion,
        'feature_contract_revision': currentFeatureContractIdentity.revision,
        'feature_contract_hash': currentFeatureContractIdentity.semanticHash,
        'started_at_utc_ms': _startedAtUtc.millisecondsSinceEpoch,
        'completed_at_utc_ms': null,
        'abandoned_at_utc_ms': null,
      });
    },
  );

  test(
    'start rejects an absent persisted consent without persistence',
    () async {
      await database.customUpdate(
        'DELETE FROM research_consents WHERE owner_id = ?',
        variables: const [Variable<String>(_ownerId)],
      );

      await expectLater(repository.start(_run()), throwsArgumentError);

      expect(await _runCount(database), 0);
      expect(
        await database
            .customSelect(
              "SELECT COUNT(*) AS total FROM outbox_operations "
              "WHERE entity_type = 'assessmentRun'",
            )
            .map((row) => row.read<int>('total'))
            .getSingle(),
        0,
      );
    },
  );

  test(
    'completed run round-trips exactly after a file-backed reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-assessment-run-',
      );
      final path =
          '${directory.path}${Platform.pathSeparator}assessment.sqlite';
      AppDatabase? fileDatabase;

      try {
        fileDatabase = AppDatabase(NativeDatabase(File(path)));
        await _seedOwner(fileDatabase, _ownerId);
        await _seedConsent(fileDatabase, ownerId: _ownerId);
        await _seedSession(
          fileDatabase,
          ownerId: _ownerId,
          sessionId: _sessionId,
        );
        await _seedAssignment(fileDatabase, ownerId: _ownerId);
        final firstRepository = DriftAssessmentRepository(fileDatabase);
        await firstRepository.start(_run());
        final completed = await firstRepository.complete(
          runId: _runId,
          completedAtUtc: _completedAtUtc,
        );
        await fileDatabase.close();
        fileDatabase = null;

        fileDatabase = AppDatabase(NativeDatabase(File(path)));
        final reopenedRepository = DriftAssessmentRepository(fileDatabase);
        final reopened = await reopenedRepository.getRun(_runId);

        expect(reopened, sameAssessmentRunAs(completed));
        expect(reopened.state, AssessmentRunState.completed);
        expect(reopened.completedAtUtc, _completedAtUtc);
        expect(reopened.abandonedAtUtc, isNull);
        expect(await _runCount(fileDatabase), 1);
        await expectLater(
          reopenedRepository.start(_run()),
          throwsA(isA<AssessmentRunConflict>()),
          reason: 'A terminal run cannot reopen as Active after restart.',
        );
        expect(await _runCount(fileDatabase), 1);
      } finally {
        await fileDatabase?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test('byte-equivalent start replay returns one immutable row', () async {
    final first = await repository.start(_run());
    final replay = await repository.start(_run());

    expect(replay, sameAssessmentRunAs(first));
    expect(await _runCount(database), 1);
  });

  test(
    'same run id with changed metadata conflicts without mutation',
    () async {
      final original = await repository.start(_run());

      await expectLater(
        repository.start(_run(formVersion: 'form-v2')),
        throwsA(isA<AssessmentRunConflict>()),
      );

      expect(await repository.getRun(_runId), sameAssessmentRunAs(original));
      expect(await _runCount(database), 1);
    },
  );

  test(
    'unique session and owner cycle phase collisions are typed and fail closed',
    () async {
      final original = await repository.start(_run());
      final sessionCollision = _run(
        id: 'assessment-run-session-collision',
        studyCycleId: 'study-cycle-session-collision',
        phase: AssessmentPhase.post,
      );
      final cyclePhaseCollision = _run(
        id: 'assessment-run-cycle-collision',
        learningSessionId: _secondSessionId,
      );

      await expectLater(
        repository.start(sessionCollision),
        throwsA(isA<AssessmentRunConflict>()),
      );
      await expectLater(
        repository.start(cyclePhaseCollision),
        throwsA(isA<AssessmentRunConflict>()),
      );

      expect(await repository.getRun(_runId), sameAssessmentRunAs(original));
      expect(await _runCount(database), 1);
    },
  );

  test('Active completes once and rejects every incompatible replay', () async {
    await repository.start(_run());

    final completed = await repository.complete(
      runId: _runId,
      completedAtUtc: _completedAtUtc,
    );
    final replay = await repository.complete(
      runId: _runId,
      completedAtUtc: _completedAtUtc,
    );

    expect(completed.state, AssessmentRunState.completed);
    expect(completed.completedAtUtc, _completedAtUtc);
    expect(completed.abandonedAtUtc, isNull);
    expect(replay, sameAssessmentRunAs(completed));
    await expectLater(
      repository.complete(
        runId: _runId,
        completedAtUtc: _completedAtUtc.add(const Duration(seconds: 1)),
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    await expectLater(
      repository.abandon(runId: _runId, abandonedAtUtc: _abandonedAtUtc),
      throwsA(isA<AssessmentRunConflict>()),
    );
    await expectLater(
      repository.requireActiveForResponse(
        runId: _runId,
        occurredAtUtc: _responseAtUtc,
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    expect(await _runCount(database), 1);
  });

  test('Active abandons once and can never complete or change time', () async {
    await repository.start(_run());

    final abandoned = await repository.abandon(
      runId: _runId,
      abandonedAtUtc: _abandonedAtUtc,
    );
    final replay = await repository.abandon(
      runId: _runId,
      abandonedAtUtc: _abandonedAtUtc,
    );

    expect(abandoned.state, AssessmentRunState.abandoned);
    expect(abandoned.completedAtUtc, isNull);
    expect(abandoned.abandonedAtUtc, _abandonedAtUtc);
    expect(replay, sameAssessmentRunAs(abandoned));
    await expectLater(
      repository.abandon(
        runId: _runId,
        abandonedAtUtc: _abandonedAtUtc.add(const Duration(seconds: 1)),
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    await expectLater(
      repository.complete(runId: _runId, completedAtUtc: _completedAtUtc),
      throwsA(isA<AssessmentRunConflict>()),
    );
    await expectLater(
      repository.requireActiveForResponse(
        runId: _runId,
        occurredAtUtc: _responseAtUtc,
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    expect(await _runCount(database), 1);
  });

  test('terminal transitions require an existing Active run', () async {
    await expectLater(
      repository.complete(
        runId: 'missing-assessment-run',
        completedAtUtc: _completedAtUtc,
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    await expectLater(
      repository.abandon(
        runId: 'missing-assessment-run',
        abandonedAtUtc: _abandonedAtUtc,
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    expect(await _runCount(database), 0);
  });

  test(
    'active response boundary validates occurrence without mutation',
    () async {
      final active = await repository.start(_run());

      expect(
        await repository.requireActiveForResponse(
          runId: _runId,
          occurredAtUtc: _responseAtUtc,
        ),
        sameAssessmentRunAs(active),
      );
      await expectLater(
        repository.requireActiveForResponse(
          runId: _runId,
          occurredAtUtc: _startedAtUtc.subtract(
            const Duration(milliseconds: 1),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.requireActiveForResponse(
          runId: _runId,
          occurredAtUtc: DateTime(2026, 8, 14, 10, 1),
        ),
        throwsArgumentError,
      );
      expect(await _runCount(database), 1);
    },
  );

  test(
    'missing or mismatched owner session and assignment fail before persistence',
    () async {
      await _seedMalformedAssignment(database);
      final cases = <({String name, AssessmentRun run, Matcher failure})>[
        (
          name: 'missing learning session',
          run: _run(learningSessionId: 'missing-session'),
          failure: throwsArgumentError,
        ),
        (
          name: 'learning session belongs to another owner',
          run: _run(learningSessionId: _otherSessionId),
          failure: throwsArgumentError,
        ),
        (
          name: 'missing assignment',
          run: _run(assignmentId: 'missing-assignment'),
          failure: throwsArgumentError,
        ),
        (
          name: 'assignment belongs to another owner',
          run: _run(assignmentId: _assignmentId(_otherOwnerId)),
          failure: throwsArgumentError,
        ),
        (
          name: 'assignment cohort differs from pinned run',
          run: _run(cohort: 'different-cohort'),
          failure: throwsA(isA<AssessmentRunConflict>()),
        ),
        (
          name: 'assignment experiment differs from pinned run',
          run: _run(experimentId: 'different-experiment'),
          failure: throwsA(isA<AssessmentRunConflict>()),
        ),
        (
          name: 'assignment id is not canonical for its immutable identity',
          run: _run(
            assignmentId: _malformedAssignmentId,
            experimentId: _malformedExperimentId,
          ),
          failure: throwsA(isA<AssessmentRunConflict>()),
        ),
        (
          name: 'run starts before the immutable assignment',
          run: _run(
            startedAtUtc: _assignedAtUtc.subtract(
              const Duration(milliseconds: 1),
            ),
            consentDecidedAtUtc: _assignedAtUtc.subtract(
              const Duration(seconds: 1),
            ),
          ),
          failure: throwsArgumentError,
        ),
      ];

      for (final invalid in cases) {
        await expectLater(
          repository.start(invalid.run),
          invalid.failure,
          reason: invalid.name,
        );
        expect(
          await _runCount(database),
          0,
          reason: '${invalid.name} persisted a partial assessment run',
        );
      }
    },
  );

  test(
    'model rejects noncanonical bounded pins and malformed hashes',
    () async {
      final overlong = List<String>.filled(257, 'x').join();
      final invalid = <({String name, AssessmentRun Function() build})>[
        (name: 'blank run id', build: () => _run(id: '')),
        (name: 'untrimmed owner id', build: () => _run(ownerId: ' $_ownerId')),
        (
          name: 'overlong session id',
          build: () => _run(learningSessionId: overlong),
        ),
        (name: 'blank study cycle', build: () => _run(studyCycleId: '')),
        (name: 'blank protocol id', build: () => _run(protocolId: '')),
        (
          name: 'untrimmed protocol version',
          build: () => _run(protocolVersion: ' $_protocolVersion'),
        ),
        (name: 'blank experiment id', build: () => _run(experimentId: '')),
        (
          name: 'non-positive experiment version',
          build: () => _run(experimentVersion: 0),
        ),
        (name: 'blank assignment id', build: () => _run(assignmentId: '')),
        (name: 'blank cohort', build: () => _run(cohort: '')),
        (
          name: 'non-positive consent version',
          build: () => _run(consentVersion: 0),
        ),
        (name: 'blank instrument id', build: () => _run(instrumentId: '')),
        (
          name: 'overlong instrument version',
          build: () => _run(instrumentVersion: overlong),
        ),
        (name: 'blank form id', build: () => _run(formId: '')),
        (name: 'untrimmed form version', build: () => _run(formVersion: ' v1')),
        (
          name: 'invalid instrument checksum',
          build: () => _run(instrumentChecksumSha256: 'ABC'),
        ),
        (
          name: 'invalid form checksum',
          build: () => _run(formChecksumSha256: 'short'),
        ),
        (name: 'blank app version', build: () => _run(appVersion: '')),
        (name: 'blank build id', build: () => _run(buildId: '')),
        (
          name: 'non-positive database schema',
          build: () => _run(databaseSchemaVersion: 0),
        ),
        (
          name: 'blank content revision',
          build: () => _run(contentRevision: ''),
        ),
        (
          name: 'blank evidence policy version',
          build: () => _run(evidencePolicyVersion: ''),
        ),
        (
          name: 'blank feature contract revision',
          build: () => _run(featureContractRevision: ''),
        ),
        (
          name: 'invalid feature contract hash',
          build: () => _run(featureContractHash: 'not-a-sha256'),
        ),
      ];

      for (final item in invalid) {
        expect(item.build, throwsArgumentError, reason: item.name);
        expect(await _runCount(database), 0, reason: item.name);
      }
    },
  );

  test(
    'model enforces UTC nonnegative and exact state timestamp shapes',
    () async {
      final invalid = <({String name, AssessmentRun Function() build})>[
        (
          name: 'non-UTC consent decision',
          build: () => _run(consentDecidedAtUtc: DateTime(2026, 8, 2)),
        ),
        (
          name: 'pre-epoch consent decision',
          build: () => _run(
            consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              -1,
              isUtc: true,
            ),
          ),
        ),
        (
          name: 'consent decision after start',
          build: () => _run(
            consentDecidedAtUtc: _startedAtUtc.add(
              const Duration(milliseconds: 1),
            ),
          ),
        ),
        (
          name: 'non-UTC started time',
          build: () => _run(startedAtUtc: DateTime(2026, 8, 14, 10)),
        ),
        (
          name: 'pre-epoch started time',
          build: () => _run(
            startedAtUtc: DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
            consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              0,
              isUtc: true,
            ),
          ),
        ),
        (
          name: 'Active cannot have completed time',
          build: () => _run(completedAtUtc: _completedAtUtc),
        ),
        (
          name: 'Active cannot have abandoned time',
          build: () => _run(abandonedAtUtc: _abandonedAtUtc),
        ),
        (
          name: 'Completed requires completed time',
          build: () => _run(state: AssessmentRunState.completed),
        ),
        (
          name: 'Completed cannot have abandoned time',
          build: () => _run(
            state: AssessmentRunState.completed,
            completedAtUtc: _completedAtUtc,
            abandonedAtUtc: _abandonedAtUtc,
          ),
        ),
        (
          name: 'Completed cannot precede start',
          build: () => _run(
            state: AssessmentRunState.completed,
            completedAtUtc: _startedAtUtc.subtract(
              const Duration(milliseconds: 1),
            ),
          ),
        ),
        (
          name: 'Abandoned requires abandoned time',
          build: () => _run(state: AssessmentRunState.abandoned),
        ),
        (
          name: 'Abandoned cannot have completed time',
          build: () => _run(
            state: AssessmentRunState.abandoned,
            completedAtUtc: _completedAtUtc,
            abandonedAtUtc: _abandonedAtUtc,
          ),
        ),
        (
          name: 'Abandoned cannot precede start',
          build: () => _run(
            state: AssessmentRunState.abandoned,
            abandonedAtUtc: _startedAtUtc.subtract(
              const Duration(milliseconds: 1),
            ),
          ),
        ),
      ];

      for (final item in invalid) {
        expect(item.build, throwsArgumentError, reason: item.name);
        expect(await _runCount(database), 0, reason: item.name);
      }
    },
  );

  test('repository start accepts only an Active run shape', () async {
    await expectLater(
      repository.start(
        _run(
          state: AssessmentRunState.completed,
          completedAtUtc: _completedAtUtc,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.start(
        _run(
          state: AssessmentRunState.abandoned,
          abandonedAtUtc: _abandonedAtUtc,
        ),
      ),
      throwsArgumentError,
    );
    expect(await _runCount(database), 0);
  });
}

const _ownerId = 'owner-assessment';
const _otherOwnerId = 'owner-other';
const _sessionId = 'session-assessment';
const _secondSessionId = 'session-assessment-second';
const _otherSessionId = 'session-other';
const _runId = 'assessment-run-pre';
const _studyCycleId = 'study-cycle-2026';
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1.0.0';
const _experimentId = 'assessment-experiment';
const _experimentVersion = 1;
const _cohort = 'shadow';
const _consentVersion = 1;
const _instrumentId = 'instrument-core';
const _instrumentVersion = 'instrument-v1';
const _formId = 'form-a';
const _formVersion = 'form-v1';
const _instrumentChecksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _formChecksum =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _appVersion = '1.0.0';
const _buildId = 'task-12-red';
const _contentRevision = 'assessment-content-v1';
const _evidencePolicyVersion = 'learning-evidence-v1';
const _malformedAssignmentId = 'malformed-assignment-id';
const _malformedExperimentId = 'malformed-experiment';
final _consentDecidedAtUtc = DateTime.utc(2026, 8, 2, 8);
final _assignedAtUtc = DateTime.utc(2026, 8, 3, 8);
final _startedAtUtc = DateTime.utc(2026, 8, 14, 10);
final _responseAtUtc = DateTime.utc(2026, 8, 14, 10, 5);
final _completedAtUtc = DateTime.utc(2026, 8, 14, 10, 30);
final _abandonedAtUtc = DateTime.utc(2026, 8, 14, 10, 20);

String _assignmentId(String ownerId) =>
    DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: ownerId,
      experimentId: _experimentId,
      experimentVersion: _experimentVersion,
    );

AssessmentRun _run({
  String id = _runId,
  String ownerId = _ownerId,
  String learningSessionId = _sessionId,
  String studyCycleId = _studyCycleId,
  AssessmentPhase phase = AssessmentPhase.pre,
  AssessmentRunState state = AssessmentRunState.active,
  String protocolId = _protocolId,
  String protocolVersion = _protocolVersion,
  String experimentId = _experimentId,
  int experimentVersion = _experimentVersion,
  String? assignmentId,
  String cohort = _cohort,
  int consentVersion = _consentVersion,
  DateTime? consentDecidedAtUtc,
  String instrumentId = _instrumentId,
  String instrumentVersion = _instrumentVersion,
  String formId = _formId,
  String formVersion = _formVersion,
  String instrumentChecksumSha256 = _instrumentChecksum,
  String formChecksumSha256 = _formChecksum,
  String appVersion = _appVersion,
  String buildId = _buildId,
  int databaseSchemaVersion = 15,
  String contentRevision = _contentRevision,
  String evidencePolicyVersion = _evidencePolicyVersion,
  String? featureContractRevision,
  String? featureContractHash,
  DateTime? startedAtUtc,
  DateTime? completedAtUtc,
  DateTime? abandonedAtUtc,
}) {
  return AssessmentRun(
    id: id,
    ownerId: ownerId,
    learningSessionId: learningSessionId,
    studyCycleId: studyCycleId,
    phase: phase,
    state: state,
    protocolId: protocolId,
    protocolVersion: protocolVersion,
    experimentId: experimentId,
    experimentVersion: experimentVersion,
    assignmentId: assignmentId ?? _assignmentId(ownerId),
    cohort: cohort,
    consentVersion: consentVersion,
    consentDecidedAtUtc: consentDecidedAtUtc ?? _consentDecidedAtUtc,
    instrumentId: instrumentId,
    instrumentVersion: instrumentVersion,
    formId: formId,
    formVersion: formVersion,
    instrumentChecksumSha256: instrumentChecksumSha256,
    formChecksumSha256: formChecksumSha256,
    appVersion: appVersion,
    buildId: buildId,
    databaseSchemaVersion: databaseSchemaVersion,
    contentRevision: contentRevision,
    evidencePolicyVersion: evidencePolicyVersion,
    featureContractRevision:
        featureContractRevision ?? currentFeatureContractIdentity.revision,
    featureContractHash:
        featureContractHash ?? currentFeatureContractIdentity.semanticHash,
    startedAtUtc: startedAtUtc ?? _startedAtUtc,
    completedAtUtc: completedAtUtc,
    abandonedAtUtc: abandonedAtUtc,
  );
}

Matcher sameAssessmentRunAs(AssessmentRun expected) => isA<AssessmentRun>()
    .having((run) => run.id, 'id', expected.id)
    .having((run) => run.ownerId, 'ownerId', expected.ownerId)
    .having(
      (run) => run.learningSessionId,
      'learningSessionId',
      expected.learningSessionId,
    )
    .having((run) => run.studyCycleId, 'studyCycleId', expected.studyCycleId)
    .having((run) => run.phase, 'phase', expected.phase)
    .having((run) => run.state, 'state', expected.state)
    .having((run) => run.protocolId, 'protocolId', expected.protocolId)
    .having(
      (run) => run.protocolVersion,
      'protocolVersion',
      expected.protocolVersion,
    )
    .having((run) => run.experimentId, 'experimentId', expected.experimentId)
    .having(
      (run) => run.experimentVersion,
      'experimentVersion',
      expected.experimentVersion,
    )
    .having((run) => run.assignmentId, 'assignmentId', expected.assignmentId)
    .having((run) => run.cohort, 'cohort', expected.cohort)
    .having(
      (run) => run.consentVersion,
      'consentVersion',
      expected.consentVersion,
    )
    .having(
      (run) => run.consentDecidedAtUtc,
      'consentDecidedAtUtc',
      expected.consentDecidedAtUtc,
    )
    .having((run) => run.instrumentId, 'instrumentId', expected.instrumentId)
    .having(
      (run) => run.instrumentVersion,
      'instrumentVersion',
      expected.instrumentVersion,
    )
    .having((run) => run.formId, 'formId', expected.formId)
    .having((run) => run.formVersion, 'formVersion', expected.formVersion)
    .having(
      (run) => run.instrumentChecksumSha256,
      'instrumentChecksumSha256',
      expected.instrumentChecksumSha256,
    )
    .having(
      (run) => run.formChecksumSha256,
      'formChecksumSha256',
      expected.formChecksumSha256,
    )
    .having((run) => run.appVersion, 'appVersion', expected.appVersion)
    .having((run) => run.buildId, 'buildId', expected.buildId)
    .having(
      (run) => run.databaseSchemaVersion,
      'databaseSchemaVersion',
      expected.databaseSchemaVersion,
    )
    .having(
      (run) => run.contentRevision,
      'contentRevision',
      expected.contentRevision,
    )
    .having(
      (run) => run.evidencePolicyVersion,
      'evidencePolicyVersion',
      expected.evidencePolicyVersion,
    )
    .having(
      (run) => run.featureContractRevision,
      'featureContractRevision',
      expected.featureContractRevision,
    )
    .having(
      (run) => run.featureContractHash,
      'featureContractHash',
      expected.featureContractHash,
    )
    .having((run) => run.startedAtUtc, 'startedAtUtc', expected.startedAtUtc)
    .having(
      (run) => run.completedAtUtc,
      'completedAtUtc',
      expected.completedAtUtc,
    )
    .having(
      (run) => run.abandonedAtUtc,
      'abandonedAtUtc',
      expected.abandonedAtUtc,
    );

Future<void> _seedOwner(AppDatabase database, String ownerId) {
  return database.customInsert(
    'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?)',
    variables: [
      Variable<String>(ownerId),
      const Variable<String>('localGuest'),
      Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<void> _seedConsent(
  AppDatabase database, {
  required String ownerId,
}) {
  return database.customInsert(
    'INSERT INTO research_consents('
    'id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
    'withdrawn_at_utc_ms) VALUES (?, ?, ?, ?, ?, NULL)',
    variables: [
      Variable<String>('consent:$ownerId:$_consentVersion'),
      Variable<String>(ownerId),
      const Variable<int>(_consentVersion),
      const Variable<String>('accepted'),
      Variable<int>(_consentDecidedAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<void> _seedSession(
  AppDatabase database, {
  required String ownerId,
  required String sessionId,
}) {
  return database.customInsert(
    'INSERT INTO learning_sessions('
    'id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id'
    ') VALUES (?, ?, ?, ?, ?, ?, ?)',
    variables: [
      Variable<String>(sessionId),
      Variable<String>(ownerId),
      const Variable<String>('assessment'),
      const Variable<String>('active'),
      Variable<int>(_startedAtUtc.millisecondsSinceEpoch),
      const Variable<String>(_appVersion),
      const Variable<String>(_buildId),
    ],
  );
}

Future<void> _seedAssignment(AppDatabase database, {required String ownerId}) {
  return database.customInsert(
    'INSERT INTO experiment_assignments('
    'id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms'
    ') VALUES (?, ?, ?, ?, ?, ?, ?)',
    variables: [
      Variable<String>(_assignmentId(ownerId)),
      Variable<String>(ownerId),
      const Variable<String>(_experimentId),
      const Variable<int>(_experimentVersion),
      const Variable<String>(_cohort),
      const Variable<String>(_protocolVersion),
      Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<void> _seedMalformedAssignment(AppDatabase database) {
  return database.customInsert(
    'INSERT INTO experiment_assignments('
    'id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms'
    ') VALUES (?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>(_malformedAssignmentId),
      const Variable<String>(_ownerId),
      const Variable<String>(_malformedExperimentId),
      const Variable<int>(_experimentVersion),
      const Variable<String>(_cohort),
      const Variable<String>(_protocolVersion),
      Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<int> _runCount(AppDatabase database) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM assessment_runs')
      .map((row) => row.read<int>('count'))
      .getSingle();
}

Future<Map<String, Object?>> _rowSnapshot(AppDatabase database, String runId) {
  return database
      .customSelect(
        'SELECT * FROM assessment_runs WHERE id = ?',
        variables: [Variable<String>(runId)],
      )
      .map((row) => Map<String, Object?>.unmodifiable(row.data))
      .getSingle();
}
