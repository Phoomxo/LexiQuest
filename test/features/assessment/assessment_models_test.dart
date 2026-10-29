import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';

// Synthetic domain fixtures only; these are not an approved study or instrument.
void main() {
  test('equivalent immutable run pins identify an exact replay', () {
    final first = _run();
    final retry = _run();
    expect(retry, first);
    expect(retry.hashCode, first.hashCode);
    expect({first, retry}, hasLength(1));
  });

  final changedPins = <String, Object?>{
    'id': 'synthetic-run-2',
    'ownerId': 'synthetic-owner-2',
    'learningSessionId': 'synthetic-session-2',
    'studyCycleId': 'synthetic-cycle-2',
    'phase': AssessmentPhase.post,
    'protocolId': 'synthetic-protocol-2',
    'protocolVersion': '2',
    'protocolRevision': 2,
    'experimentId': 'synthetic-experiment-2',
    'experimentVersion': 2,
    'assignmentId': 'synthetic-assignment-2',
    'assignmentRevision': 2,
    'cohort': 'synthetic-adventure',
    'consentVersion': 5,
    'consentDecidedAtUtc': DateTime.utc(2026, 1, 1, 0, 0, 1),
    'instrumentId': 'synthetic-instrument-2',
    'instrumentVersion': '2',
    'instrumentRevision': 2,
    'formId': 'synthetic-form-2',
    'formVersion': '2',
    'formContentRevision': 2,
    'participationPermitId': 'synthetic-participation-2',
    'participationPermitRevision': 2,
    'participationPermitPayloadSha256': 'e' * 64,
    'instrumentChecksumSha256': 'b' * 64,
    'formChecksumSha256': 'c' * 64,
    'appVersion': 'synthetic-app-2',
    'buildId': 'synthetic-build-2',
    'databaseSchemaVersion': 17,
    'contentRevision': 'synthetic-content-2',
    'evidencePolicyVersion': 'synthetic-policy-2',
    'featureContractRevision': 'synthetic-contract-2',
    'featureContractHash': 'd' * 64,
    'startedAtUtc': DateTime.utc(2026, 1, 1, 0, 1, 1),
  };
  for (final pin in changedPins.entries) {
    final name = pin.key;
    test('changing $name does not count as an exact run replay', () {
      expect(_run({name: pin.value}), isNot(_run()));
      expect({
        _run(),
        _run({name: pin.value}),
      }, hasLength(2));
    });
  }

  test('terminal states preserve pins and exact terminal retries', () {
    final active = _run();
    final end = DateTime.utc(2026, 1, 1, 0, 2);
    for (final state in [
      AssessmentRunState.completed,
      AssessmentRunState.abandoned,
    ]) {
      final terminal = active.withTerminalState(
        state: state,
        terminalAtUtc: end,
      );
      expect(terminal.state, state);
      expect(
        terminal,
        _run({
          'state': state,
          'completedAtUtc': state == AssessmentRunState.completed ? end : null,
          'abandonedAtUtc': state == AssessmentRunState.abandoned ? end : null,
        }),
      );
      expect(terminal.ownerId, active.ownerId);
      expect(terminal.learningSessionId, active.learningSessionId);
      expect(
        terminal.instrumentChecksumSha256,
        active.instrumentChecksumSha256,
      );
      expect(terminal.formChecksumSha256, active.formChecksumSha256);
      expect(terminal.protocolRevision, active.protocolRevision);
      expect(terminal.assignmentRevision, active.assignmentRevision);
      expect(terminal.instrumentRevision, active.instrumentRevision);
      expect(terminal.formContentRevision, active.formContentRevision);
      expect(terminal.participationPermitId, active.participationPermitId);
      expect(
        terminal.participationPermitRevision,
        active.participationPermitRevision,
      );
      expect(
        terminal.participationPermitPayloadSha256,
        active.participationPermitPayloadSha256,
      );
      expect(terminal.startedAtUtc, active.startedAtUtc);
      expect(
        terminal.withTerminalState(state: state, terminalAtUtc: end),
        same(terminal),
      );
      expect(
        () => terminal.withTerminalState(
          state: state,
          terminalAtUtc: end.add(const Duration(milliseconds: 1)),
        ),
        throwsStateError,
      );
      expect(
        () => terminal.withTerminalState(
          state: state,
          terminalAtUtc: end.toLocal(),
        ),
        throwsArgumentError,
      );
      expect(
        () => terminal.withTerminalState(
          state: state == AssessmentRunState.completed
              ? AssessmentRunState.abandoned
              : AssessmentRunState.completed,
          terminalAtUtc: end,
        ),
        throwsStateError,
      );
    }
  });

  test('terminal timestamp and state participate in replay identity', () {
    final end = DateTime.utc(2026, 1, 1, 0, 2);
    final completed = _run().withTerminalState(
      state: AssessmentRunState.completed,
      terminalAtUtc: end,
    );
    expect(completed, isNot(_run()));
    expect(
      completed,
      isNot(
        _run({
          'state': AssessmentRunState.completed,
          'completedAtUtc': end.add(const Duration(milliseconds: 1)),
        }),
      ),
    );
    expect(
      completed,
      isNot(
        _run().withTerminalState(
          state: AssessmentRunState.abandoned,
          terminalAtUtc: end,
        ),
      ),
    );
  });

  test('mapping cannot reinterpret stored run pins after restart', () {
    final definition = _definitionFor(_run());
    final pins = <String, Object?>{
      'instrumentChecksumSha256': definition.instrumentChecksumSha256,
      'formChecksumSha256': definition.formChecksumSha256,
    };
    final run = _run(pins);
    final mapping = AssessmentAuthorityMapping(
      protocolId: run.protocolId,
      protocolVersion: run.protocolVersion,
      protocolRevision: run.protocolRevision,
      instrumentId: run.instrumentId,
      instrumentRevision: run.instrumentRevision,
      instrumentVersion: run.instrumentVersion,
      formId: run.formId,
      formVersion: run.formVersion,
      formContentRevision: run.formContentRevision,
      instrumentChecksumSha256: run.instrumentChecksumSha256,
      formChecksumSha256: run.formChecksumSha256,
      experimentId: run.experimentId,
      experimentVersion: run.experimentVersion,
      contentRevision: run.contentRevision,
    );
    final scope = ResearchAuthorityScope(
      binding: ResearchAuthorityBinding(
        ownerId: run.ownerId,
        authSubjectId: 'synthetic-subject',
        generation: 1,
      ),
      requirements: ResearchPermitRequirements(
        supportedFormatVersion: 1,
        trustedIssuerId: 'synthetic-issuer',
        trustedIssuerKeyId: 'synthetic-key',
        signatureAlgorithm: 'ed25519',
        assignmentId: run.assignmentId,
        assignmentRevision: run.assignmentRevision,
        protocolId: run.protocolId,
        protocolRevision: run.protocolRevision,
        instrumentId: run.instrumentId,
        instrumentRevision: run.instrumentRevision,
      ),
      protocolVersion: run.protocolVersion,
      consentVersion: run.consentVersion,
    );
    mapping.requireMatches(
      scope: scope,
      definition: definition,
      pinnedRun: run,
    );
    for (final key in [
      'ownerId',
      'assignmentId',
      'assignmentRevision',
      'consentVersion',
      'protocolId',
      'protocolVersion',
      'protocolRevision',
      'instrumentId',
      'instrumentVersion',
      'instrumentRevision',
      'formId',
      'formVersion',
      'formContentRevision',
      'instrumentChecksumSha256',
      'formChecksumSha256',
      'experimentId',
      'experimentVersion',
      'contentRevision',
    ]) {
      expect(
        () => mapping.requireMatches(
          scope: scope,
          definition: definition,
          pinnedRun: _run({...pins, key: changedPins[key]}),
        ),
        throwsStateError,
        reason: 'stored $key must remain original',
      );
    }
  });

  final textPins = changedPins.keys.where((key) => changedPins[key] is String);
  for (final name in textPins) {
    test('run rejects noncanonical $name', () {
      expect(() => _run({name: ' synthetic '}), throwsArgumentError);
    });
  }
  for (final name in [
    'experimentVersion',
    'consentVersion',
    'databaseSchemaVersion',
    'protocolRevision',
    'assignmentRevision',
    'instrumentRevision',
    'formContentRevision',
    'participationPermitRevision',
  ]) {
    test('run rejects nonpositive $name', () {
      expect(() => _run({name: 0}), throwsArgumentError);
      expect(() => _run({name: -1}), throwsArgumentError);
    });
  }
  for (final name in [
    'instrumentChecksumSha256',
    'formChecksumSha256',
    'featureContractHash',
    'participationPermitPayloadSha256',
  ]) {
    test('run requires lowercase SHA256 for $name', () {
      expect(() => _run({name: 'A' * 64}), throwsArgumentError);
      expect(() => _run({name: 'a' * 63}), throwsArgumentError);
    });
  }
  test('run bounds Unicode identities and validates millisecond UTC time', () {
    expect(() => _run({'id': '😀' * 241}), throwsArgumentError);
    expect(_run({'id': '😀' * 240}).id.runes, hasLength(240));
    expect(() => _run({'ownerId': '😀' * 257}), throwsArgumentError);
    for (final bad in [
      DateTime(2026),
      DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
      DateTime.utc(2026).add(const Duration(microseconds: 1)),
    ]) {
      expect(() => _run({'startedAtUtc': bad}), throwsArgumentError);
      expect(() => _run({'consentDecidedAtUtc': bad}), throwsArgumentError);
    }
    expect(
      () => _run({'consentDecidedAtUtc': DateTime.utc(2026, 1, 1, 0, 2)}),
      throwsArgumentError,
    );
  });
  test('run rejects partial or regressing terminal state', () {
    final end = DateTime.utc(2026, 1, 1, 0, 2);
    for (final pins in [
      {'completedAtUtc': end},
      {'abandonedAtUtc': end},
      {'state': AssessmentRunState.completed},
      {'state': AssessmentRunState.abandoned},
      {
        'state': AssessmentRunState.completed,
        'completedAtUtc': end,
        'abandonedAtUtc': end,
      },
      {
        'state': AssessmentRunState.completed,
        'completedAtUtc': DateTime.utc(2026),
      },
    ]) {
      expect(() => _run(pins), throwsArgumentError);
    }
    expect(
      () => _run().withTerminalState(
        state: AssessmentRunState.active,
        terminalAtUtc: end,
      ),
      throwsArgumentError,
    );
  });

  test('presentation copies options, items and answered identities', () {
    final options = ['synthetic one', 'synthetic two'];
    final item = AssessmentPresentationItem(
      itemId: 'synthetic-item',
      prompt: 'Synthetic prompt',
      options: options,
    );
    final items = [item];
    final answered = {'synthetic-item'};
    final presentation = AssessmentPresentation(
      run: _run(),
      verifiedAtUtc: DateTime.utc(2026, 1, 1, 0, 1),
      validUntilUtc: DateTime.utc(2026, 1, 1, 0, 5),
      items: items,
      answeredItemIds: answered,
    );
    options.clear();
    items.clear();
    answered.clear();
    expect(presentation.items.single.options, hasLength(2));
    expect(presentation.answeredItemIds, {'synthetic-item'});
    expect(() => presentation.items.clear(), throwsUnsupportedError);
    expect(() => item.options.add('synthetic three'), throwsUnsupportedError);
    expect(() => presentation.answeredItemIds.clear(), throwsUnsupportedError);
    expect(
      AssessmentSubmissionReceipt(
        itemId: item.itemId,
        inserted: false,
      ).inserted,
      isFalse,
    );
  });
  test('presentation rejects ambiguous, missing and terminal items', () {
    AssessmentPresentationItem item() => AssessmentPresentationItem(
      itemId: 'synthetic-item',
      prompt: 'Synthetic prompt',
      options: const ['synthetic one', 'synthetic two'],
    );
    for (final options in [
      <String>[],
      ['only one'],
      ['same', 'same'],
      [' untrimmed ', 'valid'],
      List.generate(65, (index) => 'synthetic-$index'),
    ]) {
      expect(
        () => AssessmentPresentationItem(
          itemId: 'synthetic-item',
          prompt: 'Synthetic prompt',
          options: options,
        ),
        throwsArgumentError,
      );
    }
    for (final items in [
      <AssessmentPresentationItem>[],
      [item(), item()],
    ]) {
      expect(
        () => AssessmentPresentation(
          run: _run(),
          verifiedAtUtc: DateTime.utc(2026, 1, 1, 0, 1),
          validUntilUtc: DateTime.utc(2026, 1, 1, 0, 5),
          items: items,
          answeredItemIds: {},
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => AssessmentPresentation(
        run: _run(),
        verifiedAtUtc: DateTime.utc(2026, 1, 1, 0, 1),
        validUntilUtc: DateTime.utc(2026, 1, 1, 0, 5),
        items: [item()],
        answeredItemIds: {'unknown'},
      ),
      throwsArgumentError,
    );
    expect(
      () => AssessmentPresentation(
        run: _run().withTerminalState(
          state: AssessmentRunState.completed,
          terminalAtUtc: DateTime.utc(2026, 1, 1, 0, 2),
        ),
        verifiedAtUtc: DateTime.utc(2026, 1, 1, 0, 2),
        validUntilUtc: DateTime.utc(2026, 1, 1, 0, 5),
        items: [item()],
        answeredItemIds: {},
      ),
      throwsArgumentError,
    );
  });
  test('presentation exposes only a bounded UTC read lease', () {
    final run = _run();
    final verified = run.startedAtUtc;
    final deadline = verified.add(const Duration(microseconds: 1));
    AssessmentPresentation build(DateTime at, DateTime until) =>
        AssessmentPresentation(
          run: run,
          verifiedAtUtc: at,
          validUntilUtc: until,
          items: [
            AssessmentPresentationItem(
              itemId: 'synthetic-item',
              prompt: 'Synthetic prompt',
              options: ['one', 'two'],
            ),
          ],
          answeredItemIds: {},
        );
    final presentation = build(verified, deadline);
    expect(presentation.verifiedAtUtc, verified);
    expect(presentation.validUntilUtc, deadline);
    for (final pair in [
      (verified.toLocal(), deadline),
      (verified, deadline.toLocal()),
      (verified, verified),
      (verified, verified.subtract(const Duration(microseconds: 1))),
      (verified.subtract(const Duration(microseconds: 1)), deadline),
    ]) {
      expect(() => build(pair.$1, pair.$2), throwsArgumentError);
    }
  });
  test('repository conflicts retain the exact run and reason', () {
    const conflict = AssessmentRunConflict(
      runId: 'synthetic-run',
      reason: 'synthetic immutable-pin conflict',
    );
    expect(conflict.runId, 'synthetic-run');
    expect(conflict.reason, 'synthetic immutable-pin conflict');
  });
  test(
    'outcome evidence retains canonical references and bounds latency and UTC',
    () {
      final context = EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.assessment,
        skillId: 'synthetic-word',
        hintLevel: 0,
        contentRevision: 'synthetic-content',
        rolloutMode: EvidencePolicyRolloutMode.enforced,
        protocolId: 'synthetic-protocol',
        protocolVersion: '1',
        experimentId: 'synthetic-experiment',
        experimentVersion: 1,
        assignmentId: 'synthetic-assignment',
        cohort: 'synthetic-standard',
        researchConsentVersion: 4,
        instrumentId: 'synthetic-instrument',
        instrumentVersion: '1',
        formId: 'synthetic-form',
        formVersion: '1',
        assessmentItemId: 'synthetic-item',
        assessmentResponseCode: 'correct',
        scoringRuleVersion: 'synthetic-score-1',
      );
      AssessmentOutcomeEvidence build({
        int latency = 0,
        DateTime? at,
        String wordId = 'synthetic-word',
      }) => AssessmentOutcomeEvidence(
        sourceEvidenceId: 'synthetic-evidence',
        ownerId: 'synthetic-owner',
        learningSessionId: 'synthetic-session',
        wordId: wordId,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: latency,
        occurredAtUtc: at ?? DateTime.utc(2026),
        persistedEvidenceClass: 'assessment',
        evidenceContext: context,
      );
      final evidence = build();
      expect(evidence.sourceEvidenceId, 'synthetic-evidence');
      expect(evidence.learningSessionId, 'synthetic-session');
      expect(evidence.evidenceContext, same(context));
      expect(
        build(
          latency: LearningEvidenceContract.maxResponseTimeMs,
        ).responseTimeMs,
        LearningEvidenceContract.maxResponseTimeMs,
      );
      expect(() => build(latency: -1), throwsArgumentError);
      expect(
        () => build(latency: LearningEvidenceContract.maxResponseTimeMs + 1),
        throwsArgumentError,
      );
      expect(() => build(wordId: ' synthetic '), throwsArgumentError);
      expect(() => build(at: DateTime(2026)), throwsArgumentError);
    },
  );
}

AssessmentRun _run([Map<String, Object?> changes = const {}]) {
  final pins = <String, Object?>{
    'id': 'synthetic-run',
    'ownerId': 'synthetic-owner',
    'learningSessionId': 'synthetic-session',
    'studyCycleId': 'synthetic-cycle',
    'phase': AssessmentPhase.pre,
    'state': AssessmentRunState.active,
    'protocolId': 'synthetic-protocol',
    'protocolVersion': '1',
    'protocolRevision': 1,
    'experimentId': 'synthetic-experiment',
    'experimentVersion': 1,
    'assignmentId': 'synthetic-assignment',
    'assignmentRevision': 1,
    'cohort': 'synthetic-standard',
    'consentVersion': 4,
    'consentDecidedAtUtc': DateTime.utc(2026),
    'instrumentId': 'synthetic-instrument',
    'instrumentVersion': '1',
    'instrumentRevision': 1,
    'formId': 'synthetic-form',
    'formVersion': '1',
    'formContentRevision': 1,
    'participationPermitId': 'synthetic-participation',
    'participationPermitRevision': 1,
    'participationPermitPayloadSha256': 'a' * 64,
    'instrumentChecksumSha256': 'a' * 64,
    'formChecksumSha256': 'a' * 64,
    'appVersion': 'synthetic-app',
    'buildId': 'synthetic-build',
    'databaseSchemaVersion': 16,
    'contentRevision': 'synthetic-content',
    'evidencePolicyVersion': 'synthetic-policy',
    'featureContractRevision': 'synthetic-contract',
    'featureContractHash': 'a' * 64,
    'startedAtUtc': DateTime.utc(2026, 1, 1, 0, 1),
    'completedAtUtc': null,
    'abandonedAtUtc': null,
    ...changes,
  };
  return AssessmentRun(
    id: pins['id']! as String,
    ownerId: pins['ownerId']! as String,
    learningSessionId: pins['learningSessionId']! as String,
    studyCycleId: pins['studyCycleId']! as String,
    phase: pins['phase']! as AssessmentPhase,
    state: pins['state']! as AssessmentRunState,
    protocolId: pins['protocolId']! as String,
    protocolVersion: pins['protocolVersion']! as String,
    protocolRevision: pins['protocolRevision']! as int,
    experimentId: pins['experimentId']! as String,
    experimentVersion: pins['experimentVersion']! as int,
    assignmentId: pins['assignmentId']! as String,
    assignmentRevision: pins['assignmentRevision']! as int,
    cohort: pins['cohort']! as String,
    consentVersion: pins['consentVersion']! as int,
    consentDecidedAtUtc: pins['consentDecidedAtUtc']! as DateTime,
    instrumentId: pins['instrumentId']! as String,
    instrumentVersion: pins['instrumentVersion']! as String,
    instrumentRevision: pins['instrumentRevision']! as int,
    formId: pins['formId']! as String,
    formVersion: pins['formVersion']! as String,
    formContentRevision: pins['formContentRevision']! as int,
    participationPermitId: pins['participationPermitId']! as String,
    participationPermitRevision: pins['participationPermitRevision']! as int,
    participationPermitPayloadSha256:
        pins['participationPermitPayloadSha256']! as String,
    instrumentChecksumSha256: pins['instrumentChecksumSha256']! as String,
    formChecksumSha256: pins['formChecksumSha256']! as String,
    appVersion: pins['appVersion']! as String,
    buildId: pins['buildId']! as String,
    databaseSchemaVersion: pins['databaseSchemaVersion']! as int,
    contentRevision: pins['contentRevision']! as String,
    evidencePolicyVersion: pins['evidencePolicyVersion']! as String,
    featureContractRevision: pins['featureContractRevision']! as String,
    featureContractHash: pins['featureContractHash']! as String,
    startedAtUtc: pins['startedAtUtc']! as DateTime,
    completedAtUtc: pins['completedAtUtc'] as DateTime?,
    abandonedAtUtc: pins['abandonedAtUtc'] as DateTime?,
  );
}

AssessmentInstrumentDefinition _definitionFor(AssessmentRun run) {
  final instrumentBytes = utf8.encode('synthetic instrument bytes');
  const items = [
    AssessmentItemDefinition(
      itemId: 'synthetic-item',
      prompt: 'Synthetic prompt',
      wordId: 'synthetic-word',
      promptMode: 'meaningChoice',
      scoringRuleVersion: 'synthetic-scoring',
      responses: {
        'synthetic-yes': AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'synthetic-no': AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      },
    ),
  ];
  final formBytes = AssessmentInstrumentDefinition.canonicalFormBytes(
    instrumentId: run.instrumentId,
    instrumentVersion: run.instrumentVersion,
    formId: run.formId,
    formVersion: run.formVersion,
    formContentRevision: run.formContentRevision,
    items: items,
  );
  return AssessmentInstrumentDefinition(
    instrumentId: run.instrumentId,
    instrumentVersion: run.instrumentVersion,
    formId: run.formId,
    formVersion: run.formVersion,
    formContentRevision: run.formContentRevision,
    sourceState: AssessmentCatalogSourceState.approved,
    reviewState: AssessmentCatalogReviewState.approved,
    protocolId: run.protocolId,
    experimentId: run.experimentId,
    experimentVersion: run.experimentVersion,
    contentRevision: run.contentRevision,
    instrumentBytes: instrumentBytes,
    formBytes: formBytes,
    instrumentChecksumSha256: sha256.convert(instrumentBytes).toString(),
    formChecksumSha256: sha256.convert(formBytes).toString(),
    items: items,
  );
}
