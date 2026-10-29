import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/research/domain/research_trusted_time.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

// Synthetic application facts only. No fixture is an approved study instrument.
DateTime syntheticTime(int minute) => DateTime.utc(2026, 1, 1, 0, minute);

AssessmentInstrumentDefinition syntheticDefinition({bool aliases = false}) {
  final items = [
    for (final id in ['b', 'a'])
      AssessmentItemDefinition(
        itemId: 'synthetic-item-$id',
        prompt: 'Synthetic prompt $id',
        wordId: 'synthetic-word-$id',
        promptMode: 'meaningChoice',
        scoringRuleVersion: 'synthetic-score-$id',
        responses: {
          'Z choice': const AssessmentControlledResponse(
            responseCode: 'incorrect',
            isCorrect: false,
          ),
          'A choice': const AssessmentControlledResponse(
            responseCode: 'correct',
            isCorrect: true,
          ),
          if (aliases)
            'Another A choice': const AssessmentControlledResponse(
              responseCode: 'correct',
              isCorrect: true,
            ),
          if (aliases)
            'Another wrong choice': const AssessmentControlledResponse(
              responseCode: 'other-incorrect',
              isCorrect: false,
            ),
        },
      ),
  ];
  final instrument = utf8.encode('synthetic assessment instrument');
  final form = AssessmentInstrumentDefinition.canonicalFormBytes(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: 'supplied-version',
    formId: 'synthetic-form',
    formVersion: 'supplied-form-version',
    formContentRevision: 7,
    items: items,
  );
  return AssessmentInstrumentDefinition(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: 'supplied-version',
    formId: 'synthetic-form',
    formVersion: 'supplied-form-version',
    formContentRevision: 7,
    sourceState: AssessmentCatalogSourceState.approved,
    reviewState: AssessmentCatalogReviewState.approved,
    protocolId: 'synthetic-protocol',
    experimentId: 'synthetic-experiment',
    experimentVersion: 2,
    contentRevision: 'synthetic-content',
    instrumentBytes: instrument,
    formBytes: form,
    instrumentChecksumSha256: sha256.convert(instrument).toString(),
    formChecksumSha256: sha256.convert(form).toString(),
    items: items,
  );
}

AssessmentRun syntheticRun({
  AssessmentPhase phase = AssessmentPhase.pre,
  AssessmentRunState state = AssessmentRunState.active,
  Map<String, Object?> changes = const {},
}) {
  final definition = syntheticDefinition();
  final pins = <String, Object?>{
    'id': 'synthetic-${phase.name}',
    'ownerId': 'synthetic-owner',
    'learningSessionId': 'synthetic-assessment-session-${phase.name}',
    'studyCycleId': 'synthetic-r3-cycle',
    'phase': phase,
    'state': state,
    'protocolId': definition.protocolId,
    'protocolVersion': 'supplied-protocol-version',
    'protocolRevision': 3,
    'experimentId': definition.experimentId,
    'experimentVersion': definition.experimentVersion,
    'assignmentId': 'synthetic-assignment',
    'assignmentRevision': 4,
    'cohort': 'standard',
    'consentVersion': 5,
    'consentDecidedAtUtc': syntheticTime(0),
    'instrumentId': definition.instrumentId,
    'instrumentVersion': definition.instrumentVersion,
    'instrumentRevision': 6,
    'formId': definition.formId,
    'formVersion': definition.formVersion,
    'formContentRevision': definition.formContentRevision,
    'participationPermitId': 'synthetic-participation',
    'participationPermitRevision': 8,
    'participationPermitPayloadSha256': 'a' * 64,
    'instrumentChecksumSha256': definition.instrumentChecksumSha256,
    'formChecksumSha256': definition.formChecksumSha256,
    'appVersion': 'synthetic-app',
    'buildId': 'synthetic-build',
    'databaseSchemaVersion': 18,
    'contentRevision': definition.contentRevision,
    'evidencePolicyVersion': EvidenceContext.currentPolicyVersion,
    'featureContractRevision': currentFeatureContractIdentity.revision,
    'featureContractHash': currentFeatureContractIdentity.semanticHash,
    'startedAtUtc': syntheticTime(phase == AssessmentPhase.pre ? 10 : 50),
    'completedAtUtc': state == AssessmentRunState.completed
        ? syntheticTime(phase == AssessmentPhase.pre ? 20 : 60)
        : null,
    'abandonedAtUtc': state == AssessmentRunState.abandoned
        ? syntheticTime(phase == AssessmentPhase.pre ? 20 : 60)
        : null,
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

AssessmentStartCommand syntheticStart(AssessmentRun run) =>
    AssessmentStartCommand(
      runId: run.id,
      learningSessionId: run.learningSessionId,
      studyCycleId: run.studyCycleId,
      phase: run.phase,
      instrumentId: run.instrumentId,
      instrumentVersion: run.instrumentVersion,
      formId: run.formId,
      formVersion: run.formVersion,
    );

String syntheticResponseId(String runId, String itemId) =>
    'assessment-response:${sha256.convert(utf8.encode(jsonEncode([runId, itemId])))}';

AssessmentOutcomeEvidence syntheticEvidence(
  AssessmentRun run,
  int itemIndex, {
  bool correct = true,
  Map<String, Object?> changes = const {},
  Map<String, Object?> contextChanges = const {},
}) {
  final item = syntheticDefinition().items[itemIndex];
  final context = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: item.wordId,
    hintLevel: 0,
    contentRevision: run.contentRevision,
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: run.protocolId,
    protocolVersion: run.protocolVersion,
    experimentId: run.experimentId,
    experimentVersion: run.experimentVersion,
    assignmentId: run.assignmentId,
    cohort: run.cohort,
    researchConsentVersion: run.consentVersion,
    instrumentId: run.instrumentId,
    instrumentVersion: run.instrumentVersion,
    formId: run.formId,
    formVersion: run.formVersion,
    assessmentItemId: item.itemId,
    assessmentResponseCode: correct ? 'correct' : 'incorrect',
    scoringRuleVersion: item.scoringRuleVersion,
  );
  return AssessmentOutcomeEvidence(
    sourceEvidenceId:
        changes['sourceEvidenceId'] as String? ??
        syntheticResponseId(run.id, item.itemId),
    ownerId: changes['ownerId'] as String? ?? run.ownerId,
    learningSessionId:
        changes['learningSessionId'] as String? ?? run.learningSessionId,
    wordId: changes['wordId'] as String? ?? item.wordId,
    promptMode: changes['promptMode'] as String? ?? item.promptMode,
    isCorrect: changes['isCorrect'] as bool? ?? correct,
    responseTimeMs: changes['responseTimeMs'] as int? ?? 250,
    occurredAtUtc:
        changes['occurredAtUtc'] as DateTime? ??
        run.startedAtUtc.add(const Duration(minutes: 5)),
    persistedEvidenceClass: 'assessment',
    evidenceContext: EvidenceContext.fromJson({
      ...context.toJson(),
      ...contextChanges,
    }),
  );
}

final class SyntheticContentAuthority
    implements AssessmentFormContentAuthority {
  SyntheticContentAuthority(this.definition);
  final AssessmentInstrumentDefinition definition;
  AssessmentVerifiedFormContent? returned;
  void Function()? onRead;
  int reads = 0;

  @override
  Future<AssessmentVerifiedFormContent> requireVerified(
    AssessmentFormContentIdentity identity,
  ) async {
    reads++;
    onRead?.call();
    return returned ??
        AssessmentVerifiedFormContent(
          identity: AssessmentFormContentIdentity(
            formId: definition.formId,
            revision: definition.formContentRevision,
          ),
          checksumSha256: definition.formChecksumSha256,
          bytes: definition.formBytes,
        );
  }
}

final class SyntheticAssessmentRepository implements AssessmentRepository {
  SyntheticAssessmentRepository(
    this.runs, {
    AssessmentInstrumentDefinition? definition,
  }) : definition = definition ?? syntheticDefinition();
  final List<AssessmentRun> runs;
  final AssessmentInstrumentDefinition definition;
  final evidence = <String, List<AssessmentOutcomeEvidence>>{};
  bool shareEvidenceLists = false;
  final calls = <Map<String, Object?>>[];
  void Function()? beforeReturn;
  AssessmentResponseResult? responseResult;
  bool denyPresentation = false;
  int presentationChecks = 0;

  @override
  Future<AssessmentPresentationRead> requireActivePresentation({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async {
    presentationChecks++;
    if (denyPresentation || !stillVisible()) {
      throw StateError('synthetic current authority/phase denied');
    }
    final run = await getRun(ownerId: ownerId, runId: runId);
    return (
      run: run,
      verifiedAtUtc: run.startedAtUtc.add(const Duration(minutes: 9)),
      validUntilUtc: run.startedAtUtc.add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<AssessmentRun> start(
    AssessmentStartCommand command, {
    required String ownerId,
    required bool Function() stillVisible,
  }) async {
    calls.add({'method': 'start', 'command': command, 'ownerId': ownerId});
    final run = runs.firstWhere((run) => run.id == command.runId);
    beforeReturn?.call();
    return run;
  }

  @override
  Future<AssessmentRun> getRun({
    required String ownerId,
    required String runId,
  }) async => runs.firstWhere((run) => run.id == runId);

  @override
  Future<AssessmentResponseResult> recordResponse({
    required String ownerId,
    required String runId,
    required String itemId,
    required String option,
    required int responseTimeMs,
    required bool Function() stillVisible,
  }) async {
    calls.add({
      'method': 'response',
      'ownerId': ownerId,
      'runId': runId,
      'itemId': itemId,
      'option': option,
      'responseTimeMs': responseTimeMs,
      'visible': stillVisible(),
    });
    beforeReturn?.call();
    final controlled = definition.item(itemId).responses[option]!;
    return responseResult ??
        AssessmentResponseResult(
          sourceEvidenceId: syntheticResponseId(runId, itemId),
          responseCode: controlled.responseCode,
          isCorrect: controlled.isCorrect,
          inserted: true,
        );
  }

  @override
  Future<AssessmentRun> complete({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async => _terminal(ownerId, runId, AssessmentRunState.completed);

  @override
  Future<AssessmentRun> abandon({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async => _terminal(ownerId, runId, AssessmentRunState.abandoned);

  AssessmentRun _terminal(
    String ownerId,
    String runId,
    AssessmentRunState state,
  ) {
    calls.add({'method': state.name, 'ownerId': ownerId, 'runId': runId});
    beforeReturn?.call();
    return runs
        .firstWhere((run) => run.id == runId)
        .withTerminalState(state: state, terminalAtUtc: syntheticTime(60));
  }

  @override
  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  }) async => [...runs];

  @override
  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  }) async {
    final saved = evidence[learningSessionId] ?? <AssessmentOutcomeEvidence>[];
    return shareEvidenceLists ? saved : [...saved];
  }
}

final class SyntheticCycleReceipt implements AssessmentCycleReceipt {
  SyntheticCycleReceipt({
    this.ownerId = 'synthetic-owner',
    this.studyCycleId = 'synthetic-r3-cycle',
    this.phase = AssessmentPhase.post,
    this.opportunityId = 'synthetic-opportunity',
    DateTime? firstExposureAtUtc,
    this.interventionSessionId = 'synthetic-canonical-index',
    DateTime? interventionStartedAtUtc,
    DateTime? interventionCompletedAtUtc,
  }) : firstExposureAtUtc = firstExposureAtUtc ?? syntheticTime(30),
       interventionStartedAtUtc = interventionStartedAtUtc ?? syntheticTime(31),
       interventionCompletedAtUtc =
           interventionCompletedAtUtc ?? syntheticTime(40);
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

final class SyntheticCycleReader implements AssessmentCycleReader {
  AssessmentCycleReceipt receipt = SyntheticCycleReceipt();
  bool denied = false;
  final readRuns = <AssessmentRun>[];
  void Function()? onRead;
  @override
  Future<AssessmentCycleReceipt> requirePhase({
    required AssessmentRun run,
  }) async {
    readRuns.add(run);
    onRead?.call();
    if (denied) {
      throw StateError('synthetic canonical proof unavailable');
    }
    return receipt;
  }
}

final class SyntheticTrustedTime implements ResearchTrustedTimeSource {
  ResearchTrustedTime? value = ResearchTrustedTime(
    anchorUtc: syntheticTime(70),
    validUntilUtc: syntheticTime(80),
    age: Duration.zero,
    maximumAge: const Duration(minutes: 10),
  );
  void Function()? onRead;
  @override
  Future<ResearchTrustedTime?> read() async {
    onRead?.call();
    return value;
  }
}
