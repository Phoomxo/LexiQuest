import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_cycle_reader.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_json_codec.dart';

import 'research_admission_signing.dart';
import 'research_participation_harness.dart';
import 'study_runtime_harness.dart';

export 'research_participation_harness.dart'
    show participationStart, participationPermit;
export 'study_runtime_harness.dart' show studyEntryId;

/// Synthetic configuration and real non-production signatures. The existing R3
/// Motivation instrument remains distinct from this Assessment instrument.
final class AssessmentAuthorityFixture {
  AssessmentAuthorityFixture(this.study);
  final StudyRuntimeFixture study;
  late final AssessmentInstrumentDefinition definition;
  late final AssessmentAuthorityMapping mapping;
  late final LocalResearchAuthorityCache cache;
  late final AssessmentSyntheticGateway gateway;
  late final DriftAssessmentAuthority authority;
  late ResearchAuthorityScope? scope;
  Duration elapsed = Duration.zero;
  int _request = 0;

  static Future<AssessmentAuthorityFixture> open() async {
    final result = AssessmentAuthorityFixture(await StudyRuntimeFixture.open());
    result.definition = assessmentDefinition();
    final d = result.definition;
    result.mapping = AssessmentAuthorityMapping(
      protocolId: d.protocolId,
      protocolVersion: 'protocol-string-v7',
      protocolRevision: 5,
      instrumentId: d.instrumentId,
      instrumentRevision: 41,
      instrumentVersion: d.instrumentVersion,
      formId: d.formId,
      formVersion: d.formVersion,
      formContentRevision: d.formContentRevision,
      instrumentChecksumSha256: d.instrumentChecksumSha256,
      formChecksumSha256: d.formChecksumSha256,
      experimentId: d.experimentId,
      experimentVersion: d.experimentVersion,
      contentRevision: d.contentRevision,
    );
    result.scope = result.scopeFor();
    result.gateway = AssessmentSyntheticGateway(result);
    result.cache = LocalResearchAuthorityCache(
      ownerWrites: result.study.participation.ownerWrites,
      currentScope: () => result.scope,
      gateway: result.gateway,
      operationSignatures: admissionEd25519Verifier(),
      participationSignatures: admissionP256Verifier(),
      generateRequestId: () =>
          'synthetic-assessment-refresh-${result._request++}',
      maximumAcceptedAge: const Duration(minutes: 10),
      initiallyForeground: true,
      monotonicElapsed: () => result.elapsed,
    );
    result.authority = DriftAssessmentAuthority(
      cache: result.cache,
      mapping: result.mapping,
    );
    return result;
  }

  ResearchAuthorityScope scopeFor({
    String owner = 'owner-a',
    String uid = 'uid-a',
    int generation = 1,
  }) {
    final source = study.participation.assignments.authorizer.requirements;
    return ResearchAuthorityScope(
      binding: ResearchAuthorityBinding(
        ownerId: owner,
        authSubjectId: uid,
        generation: generation,
      ),
      requirements: ResearchPermitRequirements(
        supportedFormatVersion: source.supportedFormatVersion,
        trustedIssuerId: source.trustedIssuerId,
        trustedIssuerKeyId: source.trustedIssuerKeyId,
        signatureAlgorithm: source.signatureAlgorithm,
        assignmentId: participationAssignmentId(owner),
        assignmentRevision: source.assignmentRevision,
        protocolId: source.protocolId,
        protocolRevision: source.protocolRevision,
        instrumentId: definition.instrumentId,
        instrumentRevision: 41,
      ),
      protocolVersion: 'protocol-string-v7',
      consentVersion: 4,
    );
  }

  DriftAssessmentCycleReader cycleReader() {
    final measurements =
        study.runtime.measurementsFor('owner-a')
            as DriftMotivationMeasurementRepository;
    return DriftAssessmentCycleReader(
      study.database,
      measurements: measurements,
      opportunities: DriftMeasurementOpportunityRepository(
        study.database,
        measurements: measurements,
        timing: measurements.timing as DriftMotivationMeasurementTimingReader,
      ),
      learning: study.repository,
    );
  }

  Future<AssessmentAuthorityReceipt> require({
    AssessmentRun? pinnedRun,
    ResearchAuthorityScope? expectedScope,
  }) => authority.requireCurrent(
    expectedScope: expectedScope ?? scope!,
    definition: definition,
    expectedParticipationPermitId: 'synthetic-participation',
    pinnedRun: pinnedRun,
  );

  AssessmentRun run({
    required String cycleId,
    AssessmentPhase phase = AssessmentPhase.pre,
    DateTime? startedAtUtc,
    String ownerId = 'owner-a',
    String? assignmentId,
    int assignmentRevision = 11,
    int protocolRevision = 5,
    String? permitHash,
    int permitRevision = 1,
  }) => AssessmentRun(
    id: 'synthetic-assessment-${phase.name}',
    ownerId: ownerId,
    learningSessionId: 'synthetic-assessment-session-${phase.name}',
    studyCycleId: cycleId,
    phase: phase,
    state: AssessmentRunState.active,
    protocolId: mapping.protocolId,
    protocolVersion: mapping.protocolVersion,
    protocolRevision: protocolRevision,
    experimentId: mapping.experimentId,
    experimentVersion: mapping.experimentVersion,
    assignmentId: assignmentId ?? participationAssignmentId(ownerId),
    assignmentRevision: assignmentRevision,
    cohort: 'standard',
    consentVersion: 4,
    consentDecidedAtUtc: participationStart.subtract(const Duration(hours: 1)),
    instrumentId: mapping.instrumentId,
    instrumentVersion: mapping.instrumentVersion,
    instrumentRevision: mapping.instrumentRevision,
    formId: mapping.formId,
    formVersion: mapping.formVersion,
    formContentRevision: mapping.formContentRevision,
    instrumentChecksumSha256: mapping.instrumentChecksumSha256,
    formChecksumSha256: mapping.formChecksumSha256,
    participationPermitId: 'synthetic-participation',
    participationPermitRevision: permitRevision,
    participationPermitPayloadSha256:
        permitHash ?? participationPermit().payloadSha256,
    appVersion: study.runtime.context.buildInfo.version,
    buildId: study.runtime.context.buildInfo.buildId,
    databaseSchemaVersion: study.database.schemaVersion,
    contentRevision: mapping.contentRevision,
    evidencePolicyVersion: 'synthetic-assessment-policy',
    featureContractRevision: 'synthetic-frozen-contract',
    featureContractHash: 'a' * 64,
    startedAtUtc: startedAtUtc ?? study.participation.clock.now,
    completedAtUtc: null,
    abandonedAtUtc: null,
  );

  void advance(Duration duration) {
    elapsed += duration;
    study.participation.clock.now = study.participation.clock.now.add(duration);
  }

  Future<void> close() async {
    cache.dispose();
    await study.database.close();
  }
}

AssessmentInstrumentDefinition assessmentDefinition({
  String contentRevision = 'synthetic-assessment-content',
}) {
  const items = [
    AssessmentItemDefinition(
      itemId: 'synthetic-assessment-item',
      prompt: 'Synthetic Assessment item',
      wordId: 'synthetic-study-word',
      promptMode: 'meaningChoice',
      scoringRuleVersion: 'synthetic-assessment-scoring-v1',
      responses: {
        'synthetic yes': AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'synthetic no': AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      },
    ),
  ];
  final instrumentBytes = utf8.encode(
    'synthetic Assessment instrument bytes; no validated instrument',
  );
  final formBytes = AssessmentInstrumentDefinition.canonicalFormBytes(
    instrumentId: 'synthetic-assessment-instrument',
    instrumentVersion: 'artifact-v2',
    formId: 'synthetic-assessment-form',
    formVersion: 'form-v3',
    formContentRevision: 3,
    items: items,
  );
  return AssessmentInstrumentDefinition(
    instrumentId: 'synthetic-assessment-instrument',
    instrumentVersion: 'artifact-v2',
    formId: 'synthetic-assessment-form',
    formVersion: 'form-v3',
    formContentRevision: 3,
    sourceState: AssessmentCatalogSourceState.approved,
    reviewState: AssessmentCatalogReviewState.approved,
    protocolId: 'synthetic-protocol',
    experimentId: 'synthetic-experiment',
    experimentVersion: 2,
    contentRevision: contentRevision,
    instrumentBytes: instrumentBytes,
    formBytes: formBytes,
    instrumentChecksumSha256: sha256.convert(instrumentBytes).toString(),
    formChecksumSha256: sha256.convert(formBytes).toString(),
    items: items,
  );
}

final class AssessmentSyntheticGateway implements ResearchAuthorityGateway {
  AssessmentSyntheticGateway(this.fixture);
  final AssessmentAuthorityFixture fixture;
  bool revoked = false;
  bool receiptActive = true;
  bool corruptEd = false;
  bool corruptP256 = false;
  bool motivationGrant = false;
  int revision = 1;
  int calls = 0;
  Duration receiptLifetime = const Duration(hours: 1);
  final transactionCalls = <bool>[];

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    calls++;
    final probe = _AssessmentGatewayProbe();
    await fixture.study.database.runWithInterceptor(
      () => fixture.study.database
          .customSelect('SELECT 1 AS assessment_gateway_probe')
          .getSingle(),
      interceptor: probe,
    );
    transactionCalls.add(
      probe.insideTransaction ??
          (throw StateError('Unobserved gateway transaction')),
    );
    final pins = request.scope.requirements;
    final source = participationOperation();
    final operation = signAdmissionOperation(
      ResearchPermit(
        formatVersion: pins.supportedFormatVersion,
        permitId: 'synthetic-assessment-operation',
        issuerId: pins.trustedIssuerId,
        issuerKeyId: pins.trustedIssuerKeyId,
        signatureAlgorithm: pins.signatureAlgorithm,
        ownerId: request.scope.binding.ownerId,
        operation: ResearchOperation.collect,
        assignmentId: pins.assignmentId,
        assignmentRevision: pins.assignmentRevision,
        protocolId: pins.protocolId,
        protocolRevision: pins.protocolRevision,
        instrumentId: motivationGrant ? source.instrumentId : pins.instrumentId,
        instrumentRevision: motivationGrant
            ? source.instrumentRevision
            : pins.instrumentRevision,
        revision: revision,
        issuedAtUtc: source.issuedAtUtc,
        expiresAtUtc: source.expiresAtUtc,
        signature: const [1],
      ),
      corruptSignature: corruptEd,
    );
    final permit = participationPermit(corruptSignature: corruptP256);
    final now = fixture.study.participation.clock.now;
    final decision = participationStart.subtract(const Duration(hours: 1));
    return ServerAttestedResearchAuthorityPacket(
      scope: request.scope,
      requestId: request.requestId,
      clockSessionId: request.clockSessionId,
      monotonicEpoch: request.monotonicEpoch,
      snapshotRevision: revision,
      anchorUtc: now,
      ageAtObservation: Duration.zero,
      observedAtMonotonic: request.monotonicElapsed(),
      validUntilUtc: now.add(const Duration(hours: 1)),
      maximumAge: const Duration(minutes: 10),
      operationDocuments: [const ResearchPermitJsonCodec().encode(operation)],
      operationStates: {
        operation.permitId: ResearchPermitState(
          currentRevision: revision,
          revoked: revoked,
        ),
      },
      participationDocuments: [participationDocument(permit)],
      receipts: [
        ResearchAuthorityReceipt(
          ownerId: request.scope.binding.ownerId,
          receiptId: permit.consentReceiptId,
          kind: ResearchReceiptKind.consent,
          revision: revision,
          active: receiptActive,
          issuedAtUtc: decision,
          expiresAtUtc: participationStart.add(receiptLifetime),
          consentVersion: request.scope.consentVersion,
          decidedAtUtc: decision,
        ),
      ],
    );
  }
}

final class _AssessmentGatewayProbe extends QueryInterceptor {
  bool? insideTransaction;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    insideTransaction = executor is TransactionExecutor;
    return executor.runSelect(statement, args);
  }
}
