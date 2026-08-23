import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_protocol_mode_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';

void main() {
  test('assessment application stays on the shared learning port', () {
    final source = File(
      'lib/features/assessment/application/assessment_use_cases.dart',
    ).readAsStringSync();

    expect(source, contains('LearningUseCases'));
    expect(source, isNot(contains('package:drift')));
    expect(source, isNot(contains('AppDatabase')));
    expect(source, isNot(contains('AnswerAttemptsCompanion')));
    expect(source, isNot(contains('assessmentRuns')));
    expect(source, isNot(contains('eventsV2')));
    expect(source, isNot(contains('outboxOperations')));
    expect(source, isNot(contains('customInsert')));
  });

  group('AssessmentInstrumentCatalog', () {
    test('returns only one exact approved byte-verified instrument form', () {
      final definition = _definition();
      final catalog = AssessmentInstrumentCatalog(entries: [definition]);

      expect(
        catalog.lookup(
          instrumentId: _instrumentId,
          instrumentVersion: _instrumentVersion,
          formId: _formId,
          formVersion: _formVersion,
        ),
        same(definition),
      );
    });

    test(
      'fails closed for stale missing malformed and unsupported identity',
      () {
        final invalidLookups = <String, void Function()>{
          'missing instrument': () =>
              AssessmentInstrumentCatalog(entries: [_definition()]).lookup(
                instrumentId: 'missing-instrument',
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
          'duplicate exact identity': () =>
              AssessmentInstrumentCatalog(
                entries: [_definition(), _definition()],
              ).lookup(
                instrumentId: _instrumentId,
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
          'stale form version': () =>
              AssessmentInstrumentCatalog(entries: [_definition()]).lookup(
                instrumentId: _instrumentId,
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: 'form-v0',
              ),
          'malformed identity': () =>
              AssessmentInstrumentCatalog(entries: [_definition()]).lookup(
                instrumentId: ' $_instrumentId',
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
          'unsupported source': () =>
              AssessmentInstrumentCatalog(
                entries: [
                  _definition(
                    sourceState: AssessmentCatalogSourceState.unsupported,
                  ),
                ],
              ).lookup(
                instrumentId: _instrumentId,
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
          'unapproved review': () =>
              AssessmentInstrumentCatalog(
                entries: [
                  _definition(reviewState: AssessmentCatalogReviewState.draft),
                ],
              ).lookup(
                instrumentId: _instrumentId,
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
          'instrument checksum mismatch': () =>
              AssessmentInstrumentCatalog(
                entries: [_definition(instrumentChecksum: _otherSha256)],
              ).lookup(
                instrumentId: _instrumentId,
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
          'form checksum mismatch': () =>
              AssessmentInstrumentCatalog(
                entries: [_definition(formChecksum: _otherSha256)],
              ).lookup(
                instrumentId: _instrumentId,
                instrumentVersion: _instrumentVersion,
                formId: _formId,
                formVersion: _formVersion,
              ),
        };

        for (final invalid in invalidLookups.entries) {
          expect(
            invalid.value,
            throwsA(isA<AssessmentCatalogException>()),
            reason: invalid.key,
          );
        }
      },
    );

    test('deep-freezes controlled response semantics at construction', () {
      final callerResponses = <String, AssessmentControlledResponse>{
        'choice-a': const AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'choice-b': const AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      };
      final catalog = AssessmentInstrumentCatalog(
        entries: [_definition(responses: callerResponses)],
      );
      final before = catalog.lookup(
        instrumentId: _instrumentId,
        instrumentVersion: _instrumentVersion,
        formId: _formId,
        formVersion: _formVersion,
      );

      callerResponses['choice-a'] = const AssessmentControlledResponse(
        responseCode: 'incorrect',
        isCorrect: false,
      );
      callerResponses['choice-c'] = const AssessmentControlledResponse(
        responseCode: 'injected',
        isCorrect: true,
      );

      final after = catalog.lookup(
        instrumentId: _instrumentId,
        instrumentVersion: _instrumentVersion,
        formId: _formId,
        formVersion: _formVersion,
      );
      final item = after.item(_itemId);
      expect(after.instrumentChecksumSha256, before.instrumentChecksumSha256);
      expect(after.formChecksumSha256, before.formChecksumSha256);
      expect(item.scoringRuleVersion, _scoringRuleVersion);
      expect(item.responses.keys, <String>['choice-a', 'choice-b']);
      expect(item.responses['choice-a']!.responseCode, 'correct');
      expect(item.responses['choice-a']!.isCorrect, isTrue);
      expect(
        () => item.responses['choice-a'] = const AssessmentControlledResponse(
          responseCode: 'tampered',
          isCorrect: false,
        ),
        throwsUnsupportedError,
      );
    });
  });

  test(
    'start derives every immutable pin and replays byte-equivalently',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);

      final first = await harness.useCases.start(_startCommand());
      final replay = await harness.useCases.start(_startCommand());

      expect(replay, sameAssessmentRunAs(first));
      expect(harness.owners.activeOwnerReads, 2);
      expect(first.id, _runId);
      expect(first.ownerId, _ownerId);
      expect(first.learningSessionId, _sessionId);
      expect(first.studyCycleId, _studyCycleId);
      expect(first.phase, AssessmentPhase.pre);
      expect(first.state, AssessmentRunState.active);
      expect(first.protocolId, _protocolId);
      expect(first.protocolVersion, _protocolVersion);
      expect(first.experimentId, _experimentId);
      expect(first.experimentVersion, _experimentVersion);
      expect(first.assignmentId, _assignmentId(_ownerId));
      expect(first.cohort, _cohort);
      expect(first.consentVersion, _consentVersion);
      expect(first.consentDecidedAtUtc, _consentDecidedAtUtc);
      expect(first.instrumentId, _instrumentId);
      expect(first.instrumentVersion, _instrumentVersion);
      expect(first.formId, _formId);
      expect(first.formVersion, _formVersion);
      expect(first.instrumentChecksumSha256, _instrumentSha256);
      expect(first.formChecksumSha256, _formSha256);
      expect(first.appVersion, _appVersion);
      expect(first.buildId, _buildId);
      expect(first.databaseSchemaVersion, AppDatabase.currentSchemaVersion);
      expect(first.contentRevision, _contentRevision);
      expect(first.evidencePolicyVersion, EvidenceContext.currentPolicyVersion);
      expect(
        first.featureContractRevision,
        currentFeatureContractIdentity.revision,
      );
      expect(
        first.featureContractHash,
        currentFeatureContractIdentity.semanticHash,
      );
      expect(first.startedAtUtc, _startedAtUtc);
      expect(await _count(harness.database, 'assessment_runs'), 1);
      expect(await _count(harness.database, 'learning_sessions'), 1);
    },
  );

  test('same-intent start retry reuses durable time after reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-assessment-start-retry-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}assessment.sqlite',
    );
    AppDatabase? database;
    var clockTick = 0;
    DateTime advancingNow() => _startedAtUtc.add(
      Duration(seconds: clockTick++),
    );
    try {
      database = AppDatabase(NativeDatabase(file));
      final initial = await _Harness.create(
        databaseOverride: database,
        nowUtc: advancingNow,
      );
      await initial.useCases.start(_startCommand());
      await database.close();

      database = AppDatabase(NativeDatabase(file));
      final retry = await _Harness.create(
        databaseOverride: database,
        seedFixture: false,
        nowUtc: advancingNow,
      );
      final replay = await retry.useCases.start(_startCommand());
      expect(replay.startedAtUtc, _startedAtUtc);
      expect(await _count(database, 'assessment_runs'), 1);
      expect(
        await _assessmentOutboxOperationIds(database, _runId),
        <String>['assessmentRun:$_runId:1'],
      );
    } finally {
      await database?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  for (final terminalCase in <({String name, AssessmentRunState state})>[
    (name: 'complete', state: AssessmentRunState.completed),
    (name: 'abandon', state: AssessmentRunState.abandoned),
  ]) {
    test(
      'same-intent public start retry after ${terminalCase.name} returns '
      'durable terminal after reopen',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-assessment-${terminalCase.name}-retry-',
        );
        final file = File(
          '${directory.path}${Platform.pathSeparator}assessment.sqlite',
        );
        AppDatabase? database;
        var clockTick = 0;
        DateTime advancingNow() => _startedAtUtc.add(
          Duration(seconds: clockTick++),
        );
        final runId = '$_runId-${terminalCase.name}';
        try {
          database = AppDatabase(NativeDatabase(file));
          final initial = await _Harness.create(
            databaseOverride: database,
            nowUtc: advancingNow,
          );
          await initial.useCases.start(_startCommand(runId: runId));
          final firstTerminal = terminalCase.state ==
                  AssessmentRunState.completed
              ? await initial.useCases.complete(runId)
              : await initial.useCases.abandon(runId);
          final durableTerminalAt = _startedAtUtc.add(
            const Duration(seconds: 1),
          );
          expect(
            firstTerminal.completedAtUtc ?? firstTerminal.abandonedAtUtc,
            durableTerminalAt,
          );
          await database.close();

          database = AppDatabase(NativeDatabase(file));
          final terminalRetry = await _Harness.create(
            databaseOverride: database,
            seedFixture: false,
            nowUtc: advancingNow,
          );
          final startReplay = await terminalRetry.useCases.start(
            _startCommand(runId: runId),
          );
          expect(startReplay, sameAssessmentRunAs(firstTerminal));
          final replay = terminalCase.state == AssessmentRunState.completed
              ? await terminalRetry.useCases.complete(runId)
              : await terminalRetry.useCases.abandon(runId);
          expect(replay, sameAssessmentRunAs(firstTerminal));
          expect(
            clockTick,
            2,
            reason: 'a durable terminal replay must not sample a new clock',
          );
          expect(await _count(database, 'assessment_runs'), 1);
          expect(
            await _assessmentOutboxOperationIds(database, runId),
            <String>[
              'assessmentRun:$runId:1',
              'assessmentRun:$runId:2',
            ],
          );
        } finally {
          await database?.close();
          if (await directory.exists()) await directory.delete(recursive: true);
        }
      },
    );
  }

  test(
    'start binds the active owner exactly once before provider resolution',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final owners = _ChangingOwners();
      final useCases = harness.withOwners(owners);

      final run = await useCases.start(_startCommand());

      expect(owners.calls, 1);
      expect(run.ownerId, _ownerId);
      expect(await _count(harness.database, 'assessment_runs'), 1);
    },
  );

  test(
    'withdrawal after authorization aborts the start transaction without outbox',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final repository = _WithdrawBeforeStartRepository(
        harness.repository,
        () async {
          await harness.database.customUpdate(
            'UPDATE research_consents SET withdrawn_at_utc_ms = ? '
            'WHERE owner_id = ? AND consent_version = ?',
            variables: [
              Variable<int>(_startedAtUtc.millisecondsSinceEpoch),
              const Variable<String>(_ownerId),
              const Variable<int>(_consentVersion),
            ],
          );
        },
      );

      await expectLater(
        harness.withRepository(repository).start(_startCommand()),
        throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
      );
      expect(await _count(harness.database, 'assessment_runs'), 0);
      expect(
        await _assessmentOutboxOperationIds(harness.database, _runId),
        isEmpty,
      );
    },
  );

  test(
    'start rejects every unavailable research or catalog authority',
    () async {
      final cases = <({String name, Future<_Harness> Function() build})>[
        (
          name: 'Legacy rollout',
          build: () => _Harness.create(mode: EvidencePolicyRolloutMode.legacy),
        ),
        (
          name: 'Shadow rollout',
          build: () => _Harness.create(mode: EvidencePolicyRolloutMode.shadow),
        ),
        (
          name: 'missing consent',
          build: () => _Harness.create(seedConsent: false),
        ),
        (
          name: 'declined consent',
          build: () => _Harness.create(consentState: 'declined'),
        ),
        (
          name: 'withdrawn consent',
          build: () => _Harness.create(withdrawConsent: true),
        ),
        (
          name: 'malformed consent timestamp',
          build: () => _Harness.create(
            consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              -1,
              isUtc: true,
            ),
          ),
        ),
        (
          name: 'missing protocol mapping',
          build: () => _Harness.create(includeProtocolMapping: false),
        ),
        (
          name: 'missing assignment',
          build: () => _Harness.create(seedAssignment: false),
        ),
        (
          name: 'conflicting assignment identity',
          build: () => _Harness.create(canonicalAssignmentId: false),
        ),
        (
          name: 'session belongs to another owner',
          build: () => _Harness.create(sessionOwnerId: _otherOwnerId),
        ),
        (
          name: 'catalog source is not Approved',
          build: () => _Harness.create(
            definition: _definition(
              sourceState: AssessmentCatalogSourceState.unsupported,
            ),
          ),
        ),
        (
          name: 'catalog review is not Approved',
          build: () => _Harness.create(
            definition: _definition(
              reviewState: AssessmentCatalogReviewState.rejected,
            ),
          ),
        ),
        (
          name: 'packaged checksum differs',
          build: () => _Harness.create(
            definition: _definition(formChecksum: _otherSha256),
          ),
        ),
      ];

      for (final invalid in cases) {
        final harness = await invalid.build();
        try {
          await expectLater(
            harness.useCases.start(_startCommand()),
            throwsA(
              anyOf(isA<StateError>(), isA<AssessmentCatalogException>()),
            ),
            reason: invalid.name,
          );
          expect(
            await _count(harness.database, 'assessment_runs'),
            0,
            reason: '${invalid.name} persisted a partial run',
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'same run id with changed derived catalog metadata stays a typed conflict',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.useCases.start(_startCommand());
      final changed = harness.withDefinition(
        _definition(contentRevision: 'assessment-content-v2'),
      );

      await expectLater(
        changed.start(_startCommand()),
        throwsA(isA<AssessmentRunConflict>()),
      );
      expect(await _count(harness.database, 'assessment_runs'), 1);
    },
  );

  test(
    'recordResponse derives declared assessment evidence and exact replay',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.useCases.start(_startCommand());

      final first = await harness.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: _sourceEvidenceId,
        itemId: _itemId,
        submittedResponse: 'choice-a',
        responseTimeMs: 700,
        occurredAtUtc: _responseAtUtc,
      );
      final replay = await harness.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: _sourceEvidenceId,
        itemId: _itemId,
        submittedResponse: 'choice-a',
        responseTimeMs: 700,
        occurredAtUtc: _responseAtUtc,
      );

      expect(first.sourceEvidenceId, _sourceEvidenceId);
      expect(first.responseCode, 'correct');
      expect(first.isCorrect, isTrue);
      expect(first.inserted, isTrue);
      expect(replay.inserted, isFalse);
      final attempt = await harness.database
          .select(harness.database.answerAttempts)
          .getSingle();
      expect(attempt.id, _sourceEvidenceId);
      expect(attempt.ownerId, _ownerId);
      expect(attempt.sessionId, _sessionId);
      expect(attempt.wordId, _wordId);
      expect(attempt.promptMode, _promptMode);
      expect(attempt.isCorrect, isTrue);
      expect(attempt.responseTimeMs, 700);
      expect(attempt.occurredAtUtcMs, _responseAtUtc.millisecondsSinceEpoch);
      final evidence = EvidenceContext.fromJson(
        (jsonDecode(attempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      expect(evidence.evidenceClass, EvidenceClass.assessment);
      expect(
        evidence.classificationSource,
        EvidenceClassificationSource.declared,
      );
      expect(evidence.rolloutMode, EvidencePolicyRolloutMode.enforced);
      expect(evidence.protocolId, _protocolId);
      expect(evidence.protocolVersion, _protocolVersion);
      expect(evidence.experimentId, _experimentId);
      expect(evidence.experimentVersion, _experimentVersion);
      expect(evidence.assignmentId, _assignmentId(_ownerId));
      expect(evidence.cohort, _cohort);
      expect(evidence.researchConsentVersion, _consentVersion);
      expect(evidence.instrumentId, _instrumentId);
      expect(evidence.instrumentVersion, _instrumentVersion);
      expect(evidence.formId, _formId);
      expect(evidence.formVersion, _formVersion);
      expect(evidence.assessmentItemId, _itemId);
      expect(evidence.assessmentResponseCode, 'correct');
      expect(evidence.scoringRuleVersion, _scoringRuleVersion);
      expect(evidence.engagementAllowed, isFalse);
      expect(evidence.contentRevision, _contentRevision);
      expect(
        evidence.featureContractRevision,
        currentFeatureContractIdentity.revision,
      );
      expect(
        evidence.featureContractHash,
        currentFeatureContractIdentity.semanticHash,
      );
      final correlated =
          await (harness.database.select(harness.database.eventsV2)..where(
                (row) =>
                    row.eventId.equals('learning-event:$_sourceEvidenceId'),
              ))
              .get();
      expect(correlated, hasLength(1));
      expect(correlated.single.privacyClassification, 'anonymized');
      expect(await _forbiddenAssessmentTableNames(harness.database), isEmpty);

      await expectLater(
        harness.useCases.recordResponse(
          runId: _runId,
          sourceEvidenceId: _sourceEvidenceId,
          itemId: _itemId,
          submittedResponse: 'choice-b',
          responseTimeMs: 700,
          occurredAtUtc: _responseAtUtc,
        ),
        throwsStateError,
      );
      await expectLater(
        harness.useCases.recordResponse(
          runId: _runId,
          sourceEvidenceId: _sourceEvidenceId,
          itemId: _itemId,
          submittedResponse: 'choice-a',
          responseTimeMs: 701,
          occurredAtUtc: _responseAtUtc,
        ),
        throwsStateError,
      );
      expect(await _count(harness.database, 'answer_attempts'), 1);
    },
  );

  test(
    'recordResponse rejects uncontrolled input invalid timing and identity',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.useCases.start(_startCommand());
      final invalid =
          <
            ({
              String name,
              Object response,
              String itemId,
              int time,
              DateTime at,
            })
          >[
            (
              name: 'unknown arbitrary free text',
              response: 'an unbounded response that is not a catalog option',
              itemId: _itemId,
              time: 700,
              at: _responseAtUtc,
            ),
            (
              name: 'non-string response object',
              response: const <String, Object?>{'raw': 'choice-a'},
              itemId: _itemId,
              time: 700,
              at: _responseAtUtc,
            ),
            (
              name: 'unknown item',
              response: 'choice-a',
              itemId: 'missing-item',
              time: 700,
              at: _responseAtUtc,
            ),
            (
              name: 'negative response time',
              response: 'choice-a',
              itemId: _itemId,
              time: -1,
              at: _responseAtUtc,
            ),
            (
              name: 'unbounded response time',
              response: 'choice-a',
              itemId: _itemId,
              time: 2147483648,
              at: _responseAtUtc,
            ),
            (
              name: 'response before run start',
              response: 'choice-a',
              itemId: _itemId,
              time: 700,
              at: _startedAtUtc.subtract(const Duration(milliseconds: 1)),
            ),
            (
              name: 'non-UTC response time',
              response: 'choice-a',
              itemId: _itemId,
              time: 700,
              at: DateTime(2026, 8, 14, 10, 5),
            ),
          ];

      for (final item in invalid) {
        await expectLater(
          harness.useCases.recordResponse(
            runId: _runId,
            sourceEvidenceId: 'evidence-${item.name.hashCode.abs()}',
            itemId: item.itemId,
            submittedResponse: item.response,
            responseTimeMs: item.time,
            occurredAtUtc: item.at,
          ),
          throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
          reason: item.name,
        );
      }
      await expectLater(
        harness.useCases.recordResponse(
          runId: 'missing-run',
          sourceEvidenceId: 'missing-run-evidence',
          itemId: _itemId,
          submittedResponse: 'choice-a',
          responseTimeMs: 700,
          occurredAtUtc: _responseAtUtc,
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
      expect(await _count(harness.database, 'answer_attempts'), 0);
    },
  );

  test('withdrawal and terminal state block every later response', () async {
    final withdrawn = await _Harness.create();
    addTearDown(withdrawn.close);
    await withdrawn.useCases.start(_startCommand());
    await withdrawn.database.customUpdate(
      'UPDATE research_consents SET withdrawn_at_utc_ms = ? WHERE owner_id = ?',
      variables: [
        Variable<int>(
          _responseAtUtc
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
        const Variable<String>(_ownerId),
      ],
    );
    await expectLater(
      withdrawn.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: 'withdrawn-evidence',
        itemId: _itemId,
        submittedResponse: 'choice-a',
        responseTimeMs: 700,
        occurredAtUtc: _responseAtUtc,
      ),
      throwsStateError,
    );

    final terminal = await _Harness.create();
    addTearDown(terminal.close);
    await terminal.useCases.start(_startCommand());
    await terminal.useCases.complete(_runId);
    await expectLater(
      terminal.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: 'terminal-evidence',
        itemId: _itemId,
        submittedResponse: 'choice-a',
        responseTimeMs: 700,
        occurredAtUtc: _responseAtUtc,
      ),
      throwsA(isA<AssessmentRunConflict>()),
    );
    expect(await _count(withdrawn.database, 'answer_attempts'), 0);
    expect(await _count(terminal.database, 'answer_attempts'), 0);
  });

  test(
    'recordResponse reloads the exact pinned catalog identity and bytes',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.useCases.start(_startCommand());

      final staleForm = harness.withDefinition(
        _definition(formVersion: 'form-v2'),
      );
      final changedBytes = harness.withDefinition(
        _definition(instrumentChecksum: _otherSha256),
      );
      for (final useCases in [staleForm, changedBytes]) {
        await expectLater(
          useCases.recordResponse(
            runId: _runId,
            sourceEvidenceId: 'catalog-drift-${useCases.hashCode}',
            itemId: _itemId,
            submittedResponse: 'choice-a',
            responseTimeMs: 700,
            occurredAtUtc: _responseAtUtc,
          ),
          throwsA(isA<AssessmentCatalogException>()),
        );
      }
      expect(await _count(harness.database, 'answer_attempts'), 0);
    },
  );

  test('complete and abandon preserve repository terminal semantics', () async {
    final completed = await _Harness.create();
    addTearDown(completed.close);
    await completed.useCases.start(_startCommand());
    final first = await completed.useCases.complete(_runId);
    final replay = await completed.useCases.complete(_runId);
    expect(first.state, AssessmentRunState.completed);
    expect(replay, sameAssessmentRunAs(first));
    await expectLater(
      completed.useCases.abandon(_runId),
      throwsA(isA<AssessmentRunConflict>()),
    );

    final abandoned = await _Harness.create();
    addTearDown(abandoned.close);
    await abandoned.useCases.start(_startCommand());
    final abandonedFirst = await abandoned.useCases.abandon(_runId);
    final abandonedReplay = await abandoned.useCases.abandon(_runId);
    expect(abandonedFirst.state, AssessmentRunState.abandoned);
    expect(abandonedReplay, sameAssessmentRunAs(abandonedFirst));
    await expectLater(
      abandoned.useCases.complete(_runId),
      throwsA(isA<AssessmentRunConflict>()),
    );
  });
}

final class _Harness {
  _Harness({
    required this.database,
    required this.owners,
    required this.useCases,
    required this.learning,
    required this.repository,
    required this.experiments,
    required this.consents,
    required this.rollout,
    required this.protocolCatalog,
  });

  final AppDatabase database;
  final _Owners owners;
  final AssessmentUseCases useCases;
  final LearningUseCases learning;
  final DriftAssessmentRepository repository;
  final DriftExperimentRegistry experiments;
  final DriftConsentRegistry consents;
  final PersistedEvidencePolicyRolloutModeProvider rollout;
  final ResearchProtocolModeCatalog protocolCatalog;

  static Future<_Harness> create({
    EvidencePolicyRolloutMode mode = EvidencePolicyRolloutMode.enforced,
    bool seedConsent = true,
    String consentState = 'accepted',
    bool withdrawConsent = false,
    bool seedAssignment = true,
    bool canonicalAssignmentId = true,
    String sessionOwnerId = _ownerId,
    AssessmentInstrumentDefinition? definition,
    DateTime? consentDecidedAtUtc,
    bool includeProtocolMapping = true,
    AppDatabase? databaseOverride,
    bool seedFixture = true,
    DateTime Function()? nowUtc,
  }) async {
    final database = databaseOverride ?? AppDatabase(NativeDatabase.memory());
    if (seedFixture) {
      await _seedOwner(database, _ownerId);
      await _seedOwner(database, _otherOwnerId);
      await _seedVocabulary(database);
      await DriftLearningRepository(database).startSession(
        LearningSessionDraft(
          id: _sessionId,
          ownerId: sessionOwnerId,
          activityType: 'assessment',
          startedAtUtc: _sessionStartedAtUtc,
          appVersion: _appVersion,
          buildId: _buildId,
        ),
      );
      if (seedConsent) {
        await database.customInsert(
          'INSERT INTO research_consents('
          'id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
          'withdrawn_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            const Variable<String>('consent-assessment-v1'),
            const Variable<String>(_ownerId),
            const Variable<int>(_consentVersion),
            Variable<String>(consentState),
            Variable<int>(
              (consentDecidedAtUtc ?? _consentDecidedAtUtc)
                  .millisecondsSinceEpoch,
            ),
            Variable<int>(
              withdrawConsent
                  ? _assignedAtUtc
                        .add(const Duration(days: 1))
                        .millisecondsSinceEpoch
                  : -1,
            ),
          ],
        );
        if (!withdrawConsent) {
          await database.customUpdate(
            'UPDATE research_consents SET withdrawn_at_utc_ms = NULL '
            'WHERE id = ?',
            variables: [const Variable<String>('consent-assessment-v1')],
          );
        }
      }
      if (seedAssignment) {
        await database.customInsert(
          'INSERT INTO experiment_assignments('
          'id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable<String>(
              canonicalAssignmentId
                  ? _assignmentId(_ownerId)
                  : 'assignment-conflict',
            ),
            const Variable<String>(_ownerId),
            const Variable<String>(_experimentId),
            const Variable<int>(_experimentVersion),
            const Variable<String>(_cohort),
            const Variable<String>(_protocolVersion),
            Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
          ],
        );
      }
    }
    final protocolCatalog = ResearchProtocolModeCatalog(
      mappings: includeProtocolMapping
          ? [
              ResearchProtocolModeMapping(
                protocolId: _protocolId,
                experimentId: _experimentId,
                experimentVersion: _experimentVersion,
                protocolVersion: _protocolVersion,
                consentVersion: _consentVersion,
                mode: mode,
              ),
            ]
          : const <ResearchProtocolModeMapping>[],
    );
    final experiments = DriftExperimentRegistry(
      DriftExperimentAssignmentRepository(database),
    );
    final consents = DriftConsentRegistry(database);
    final eventContexts = AssignedLearningEventContextProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: protocolCatalog,
    );
    final rollout = PersistedEvidencePolicyRolloutModeProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: protocolCatalog,
      currentActivityResearchStateProvider: eventContexts,
    );
    final owners = _Owners(_ownerId);
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        database,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      ),
      generateId: () => 'unused-assessment-learning-id',
      nowUtc: () => _responseAtUtc,
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      eventContextProvider: eventContexts,
    );
    final repository = DriftAssessmentRepository(database);
    final useCases = AssessmentUseCases(
      owners: owners,
      repository: repository,
      learning: learning,
      experimentRegistry: experiments,
      consentRegistry: consents,
      rolloutModeProvider: rollout,
      protocolModeCatalog: protocolCatalog,
      instrumentCatalog: AssessmentInstrumentCatalog(
        entries: [definition ?? _definition()],
      ),
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      nowUtc: nowUtc ?? () => _startedAtUtc,
    );
    return _Harness(
      database: database,
      owners: owners,
      useCases: useCases,
      learning: learning,
      repository: repository,
      experiments: experiments,
      consents: consents,
      rollout: rollout,
      protocolCatalog: protocolCatalog,
    );
  }

  AssessmentUseCases withDefinition(AssessmentInstrumentDefinition definition) {
    return AssessmentUseCases(
      owners: owners,
      repository: repository,
      learning: learning,
      experimentRegistry: experiments,
      consentRegistry: consents,
      rolloutModeProvider: rollout,
      protocolModeCatalog: protocolCatalog,
      instrumentCatalog: AssessmentInstrumentCatalog(entries: [definition]),
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      nowUtc: () => _startedAtUtc,
    );
  }

  AssessmentUseCases withOwners(LocalOwnerRepository ownerRepository) {
    return AssessmentUseCases(
      owners: ownerRepository,
      repository: repository,
      learning: learning,
      experimentRegistry: experiments,
      consentRegistry: consents,
      rolloutModeProvider: rollout,
      protocolModeCatalog: protocolCatalog,
      instrumentCatalog: AssessmentInstrumentCatalog(entries: [_definition()]),
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      nowUtc: () => _startedAtUtc,
    );
  }

  AssessmentUseCases withRepository(AssessmentRepository assessmentRepository) {
    return AssessmentUseCases(
      owners: owners,
      repository: assessmentRepository,
      learning: learning,
      experimentRegistry: experiments,
      consentRegistry: consents,
      rolloutModeProvider: rollout,
      protocolModeCatalog: protocolCatalog,
      instrumentCatalog: AssessmentInstrumentCatalog(entries: [_definition()]),
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      nowUtc: () => _startedAtUtc,
    );
  }

  Future<void> close() => database.close();
}

AssessmentStartCommand _startCommand({
  String runId = _runId,
  String sessionId = _sessionId,
  String studyCycleId = _studyCycleId,
  AssessmentPhase phase = AssessmentPhase.pre,
}) {
  return AssessmentStartCommand(
    runId: runId,
    learningSessionId: sessionId,
    studyCycleId: studyCycleId,
    phase: phase,
    instrumentId: _instrumentId,
    instrumentVersion: _instrumentVersion,
    formId: _formId,
    formVersion: _formVersion,
  );
}

AssessmentInstrumentDefinition _definition({
  AssessmentCatalogSourceState sourceState =
      AssessmentCatalogSourceState.approved,
  AssessmentCatalogReviewState reviewState =
      AssessmentCatalogReviewState.approved,
  String? instrumentChecksum,
  String? formChecksum,
  String contentRevision = _contentRevision,
  String instrumentId = _instrumentId,
  String instrumentVersion = _instrumentVersion,
  String formId = _formId,
  String formVersion = _formVersion,
  Map<String, AssessmentControlledResponse>? responses,
}) {
  return AssessmentInstrumentDefinition(
    instrumentId: instrumentId,
    instrumentVersion: instrumentVersion,
    formId: formId,
    formVersion: formVersion,
    sourceState: sourceState,
    reviewState: reviewState,
    protocolId: _protocolId,
    experimentId: _experimentId,
    experimentVersion: _experimentVersion,
    contentRevision: contentRevision,
    instrumentBytes: _instrumentBytes,
    formBytes: _formBytes,
    instrumentChecksumSha256: instrumentChecksum ?? _instrumentSha256,
    formChecksumSha256: formChecksum ?? _formSha256,
    items: [
      AssessmentItemDefinition(
        itemId: _itemId,
        wordId: _wordId,
        promptMode: _promptMode,
        scoringRuleVersion: _scoringRuleVersion,
        responses:
            responses ??
            const <String, AssessmentControlledResponse>{
              'choice-a': AssessmentControlledResponse(
                responseCode: 'correct',
                isCorrect: true,
              ),
              'choice-b': AssessmentControlledResponse(
                responseCode: 'incorrect',
                isCorrect: false,
              ),
            },
      ),
    ],
  );
}

final class _WithdrawBeforeStartRepository implements AssessmentRepository {
  _WithdrawBeforeStartRepository(this._delegate, this._withdraw);

  final AssessmentRepository _delegate;
  final Future<void> Function() _withdraw;
  bool _didWithdraw = false;

  @override
  Future<AssessmentRun> start(AssessmentRun run) async {
    if (!_didWithdraw) {
      _didWithdraw = true;
      await _withdraw();
    }
    return _delegate.start(run);
  }

  @override
  Future<AssessmentRun> getRun(String runId) => _delegate.getRun(runId);

  @override
  Future<AssessmentRun> complete({
    required String runId,
    required DateTime completedAtUtc,
  }) => _delegate.complete(runId: runId, completedAtUtc: completedAtUtc);

  @override
  Future<AssessmentRun> abandon({
    required String runId,
    required DateTime abandonedAtUtc,
  }) => _delegate.abandon(runId: runId, abandonedAtUtc: abandonedAtUtc);

  @override
  Future<AssessmentRun> requireActiveForResponse({
    required String runId,
    required DateTime occurredAtUtc,
  }) => _delegate.requireActiveForResponse(
    runId: runId,
    occurredAtUtc: occurredAtUtc,
  );

  @override
  Future<T> serializeActiveResponse<T>({
    required String runId,
    required DateTime occurredAtUtc,
    required AssessmentActiveResponseWork<T> work,
  }) => _delegate.serializeActiveResponse(
    runId: runId,
    occurredAtUtc: occurredAtUtc,
    work: work,
  );

  @override
  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  }) => _delegate.listRunsForStudyCycle(
    ownerId: ownerId,
    studyCycleId: studyCycleId,
  );

  @override
  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  }) => _delegate.listOutcomeEvidence(
    ownerId: ownerId,
    learningSessionId: learningSessionId,
  );
}

final class _Owners implements LocalOwnerRepository {
  _Owners(this.ownerId);

  final String ownerId;
  int activeOwnerReads = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    activeOwnerReads++;
    return identity.LocalOwner(id: ownerId, createdAtUtc: _consentDecidedAtUtc);
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => identity.LocalOwner(
    id: this.ownerId,
    firebaseUid: firebaseUid,
    createdAtUtc: _consentDecidedAtUtc,
  );
}

final class _ChangingOwners implements LocalOwnerRepository {
  int calls = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    calls++;
    return identity.LocalOwner(
      id: calls == 1 ? _ownerId : _otherOwnerId,
      createdAtUtc: _consentDecidedAtUtc,
    );
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => identity.LocalOwner(
    id: ownerId,
    firebaseUid: firebaseUid,
    createdAtUtc: _consentDecidedAtUtc,
  );
}

Future<void> _seedOwner(AppDatabase database, String ownerId) {
  return database.customInsert(
    'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?)',
    variables: [
      Variable<String>(ownerId),
      const Variable<String>('localGuest'),
      Variable<int>(_consentDecidedAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<void> _seedVocabulary(AppDatabase database) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: _categoryId,
          ownerId: _ownerId,
          name: 'Assessment',
          normalizedName: 'assessment',
          createdAtUtcMs: _consentDecidedAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: _consentDecidedAtUtc.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: _wordId,
          ownerId: _ownerId,
          categoryId: _categoryId,
          spelling: 'evaluate',
          normalizedSpelling: 'evaluate',
          meaning: 'assess',
          normalizedMeaning: 'assess',
          partOfSpeech: 'verb',
          createdAtUtcMs: _consentDecidedAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: _consentDecidedAtUtc.millisecondsSinceEpoch,
        ),
      );
}

Future<int> _count(AppDatabase database, String tableName) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM $tableName')
      .map((row) => row.read<int>('count'))
      .getSingle();
}

Future<List<String>> _assessmentOutboxOperationIds(
  AppDatabase database,
  String runId,
) async {
  final rows = await database.customSelect(
    'SELECT operation_id FROM outbox_operations '
    "WHERE entity_type = 'assessmentRun' AND entity_id = ? "
    'ORDER BY base_revision, operation_id',
    variables: [Variable<String>(runId)],
  ).get();
  return rows.map((row) => row.read<String>('operation_id')).toList();
}

Future<Set<String>> _forbiddenAssessmentTableNames(AppDatabase database) {
  return database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ("
        "'assessment_attempts','assessment_responses','assessment_scores')",
      )
      .map((row) => row.read<String>('name'))
      .get()
      .then((rows) => rows.toSet());
}

Matcher sameAssessmentRunAs(AssessmentRun expected) => isA<AssessmentRun>()
    .having((run) => run.id, 'id', expected.id)
    .having((run) => run.ownerId, 'ownerId', expected.ownerId)
    .having(
      (run) => run.learningSessionId,
      'session',
      expected.learningSessionId,
    )
    .having((run) => run.studyCycleId, 'cycle', expected.studyCycleId)
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
      (run) => run.instrumentChecksumSha256,
      'instrument checksum',
      expected.instrumentChecksumSha256,
    )
    .having(
      (run) => run.formChecksumSha256,
      'form checksum',
      expected.formChecksumSha256,
    )
    .having(
      (run) => run.contentRevision,
      'content revision',
      expected.contentRevision,
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

const _ownerId = 'owner-assessment';
const _otherOwnerId = 'owner-other';
const _categoryId = 'category-assessment';
const _wordId = 'word-assessment';
const _sessionId = 'session-assessment';
const _runId = 'assessment-run-pre';
const _studyCycleId = 'study-cycle-2026';
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1.0.0';
const _experimentId = 'assessment-experiment';
const _experimentVersion = 1;
const _cohort = 'enforced';
const _consentVersion = 1;
const _instrumentId = 'instrument-core';
const _instrumentVersion = 'instrument-v1';
const _formId = 'form-a';
const _formVersion = 'form-v1';
const _itemId = 'item-meaning-1';
const _promptMode = 'assessmentResponse';
const _scoringRuleVersion = 'score-v1';
const _contentRevision = 'assessment-content-v1';
const _sourceEvidenceId = 'assessment-evidence-1';
const _appVersion = '1.0.0';
const _buildId = 'task-12-batch-2';
const _instrumentBytes = <int>[1, 2, 3, 4, 5];
const _formBytes = <int>[6, 7, 8, 9];
const _otherSha256 =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
final _instrumentSha256 = sha256.convert(_instrumentBytes).toString();
final _formSha256 = sha256.convert(_formBytes).toString();
final _consentDecidedAtUtc = DateTime.utc(2026, 8, 1, 8);
final _assignedAtUtc = DateTime.utc(2026, 8, 2, 8);
final _sessionStartedAtUtc = DateTime.utc(2026, 8, 14, 9, 59);
final _startedAtUtc = DateTime.utc(2026, 8, 14, 10);
final _responseAtUtc = DateTime.utc(2026, 8, 14, 10, 5);

String _assignmentId(String ownerId) =>
    DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: ownerId,
      experimentId: _experimentId,
      experimentVersion: _experimentVersion,
    );
