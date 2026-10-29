import 'package:drift/drift.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_json_codec.dart';

import 'research_participation_harness.dart';
import 'study_runtime_harness.dart';

export 'research_participation_harness.dart'
    show participationStart, participationOperation, participationPermit;

final class AuthorityCacheFixture {
  AuthorityCacheFixture(this.study);
  final StudyRuntimeFixture study;
  late LocalResearchAuthorityCache cache;
  late SyntheticAuthorityGateway gateway;
  ResearchAuthorityScope? scope;
  Duration elapsed = Duration.zero;
  int _nextRequest = 0;

  static Future<AuthorityCacheFixture> open() async {
    final study = await StudyRuntimeFixture.open();
    final result = AuthorityCacheFixture(study);
    result.scope = result.scopeFor('owner-a', 'uid-a', 1);
    result.gateway = SyntheticAuthorityGateway(result);
    result.cache = result.newCache();
    return result;
  }

  ResearchAuthorityScope scopeFor(
    String owner,
    String subject,
    int generation, {
    int? instrumentRevision,
  }) {
    final source = study.participation.assignments.authorizer.requirements;
    final binding = study.participation.assignments.binding;
    return ResearchAuthorityScope(
      binding: ResearchAuthorityBinding(
        ownerId: owner,
        authSubjectId: subject,
        generation: generation,
      ),
      requirements: ResearchPermitRequirements(
        supportedFormatVersion: source.supportedFormatVersion,
        trustedIssuerId: source.trustedIssuerId,
        trustedIssuerKeyId: source.trustedIssuerKeyId,
        signatureAlgorithm: source.signatureAlgorithm,
        assignmentId: owner == 'owner-a'
            ? source.assignmentId
            : participationAssignmentId(owner),
        assignmentRevision: source.assignmentRevision,
        protocolId: source.protocolId,
        protocolRevision: source.protocolRevision,
        instrumentId: source.instrumentId,
        instrumentRevision: instrumentRevision ?? source.instrumentRevision,
      ),
      protocolVersion: binding.study.protocolVersion,
      consentVersion: binding.study.consentVersion,
    );
  }

  LocalResearchAuthorityCache newCache({
    bool initiallyForeground = true,
    bool realMonotonicClock = false,
  }) => LocalResearchAuthorityCache(
    ownerWrites: study.participation.ownerWrites,
    currentScope: () => scope,
    gateway: gateway,
    operationSignatures: study.authorities.operationSignatures,
    participationSignatures: study.authorities.participationSignatures,
    generateRequestId: () => 'synthetic-refresh-${_nextRequest++}',
    maximumAcceptedAge: const Duration(minutes: 10),
    initiallyForeground: initiallyForeground,
    monotonicElapsed: realMonotonicClock ? null : () => elapsed,
  );

  void bindRuntime() {
    final original = study.authorities;
    study.authorities = StudyLocalAuthorities(
      binding: original.binding,
      permits: cache,
      states: cache,
      operationSignatures: original.operationSignatures,
      participationDocuments: cache,
      participationSignatures: original.participationSignatures,
      receipts: cache,
      trustedTime: cache,
      supportedFormatVersion: original.supportedFormatVersion,
      trustedIssuerId: original.trustedIssuerId,
      trustedIssuerKeyId: original.trustedIssuerKeyId,
      availability: original.availability,
      supportedPresentations: original.supportedPresentations,
    );
    study.runtime = study.newRuntime();
    study.bindLearning();
  }

  void advance(Duration duration) {
    elapsed += duration;
    study.participation.clock.now = study.participation.clock.now.add(duration);
  }

  Future<void> close() async {
    cache.dispose();
    await study.database.close();
  }
}

/// Explicitly synthetic trusted server boundary. These fields are not a real
/// wire/signature protocol or evidence of production authority/freshness.
final class SyntheticAuthorityGateway implements ResearchAuthorityGateway {
  SyntheticAuthorityGateway(this.fixture);
  final AuthorityCacheFixture fixture;
  int calls = 0;
  final transactionCalls = <bool>[];
  int snapshotRevision = 1;
  int operationRevision = 1;
  int stateRevision = 1;
  int receiptRevision = 1;
  bool revoked = false;
  bool receiptActive = true;
  bool corruptEd = false;
  bool corruptP256 = false;
  bool fail = false;
  bool unavailable = false;
  bool wrongRequest = false;
  bool wrongClockSession = false;
  bool futureObservation = false;
  bool oldObservation = false;
  bool wrongReceiptVersion = false;
  bool wrongReceiptDecision = false;
  String ageBandCode = 'synthetic-adult';
  int participationRevision = 1;
  DateTime? participationRevokedAt;
  Duration maximumAge = const Duration(minutes: 10);
  Future<void> Function(int)? onFetch;

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    final call = ++calls;
    final probe = _GatewayTransactionProbe();
    await fixture.study.database.runWithInterceptor(
      () => fixture.study.database
          .customSelect('SELECT 1 AS authority_gateway_probe')
          .getSingle(),
      interceptor: probe,
    );
    transactionCalls.add(
      probe.insideTransaction ??
          (throw StateError('Synthetic gateway executor was not observed')),
    );
    final packet = build(request);
    await onFetch?.call(call);
    if (fail) throw StateError('Synthetic authority unavailable');
    return unavailable ? null : packet;
  }

  ServerAttestedResearchAuthorityPacket build(
    ResearchAuthorityRefreshRequest request,
  ) {
    final now = fixture.study.participation.clock.now;
    final observed = request.monotonicElapsed();
    final permit = participationPermit(
      corruptSignature: corruptP256,
      ageBandCode: ageBandCode,
      revision: participationRevision,
      revokedAtUtc: participationRevokedAt,
    );
    final decision = participationStart.subtract(const Duration(hours: 1));
    return ServerAttestedResearchAuthorityPacket(
      scope: request.scope,
      requestId: wrongRequest ? 'old-request' : request.requestId,
      clockSessionId: wrongClockSession
          ? 'old-clock-session'
          : request.clockSessionId,
      monotonicEpoch: request.monotonicEpoch,
      snapshotRevision: snapshotRevision,
      anchorUtc: now,
      ageAtObservation: Duration.zero,
      observedAtMonotonic: futureObservation
          ? observed + const Duration(seconds: 1)
          : oldObservation
          ? request.startedAtMonotonic - const Duration(microseconds: 1)
          : observed,
      validUntilUtc: now.add(const Duration(hours: 1)),
      maximumAge: maximumAge,
      operationDocuments: [
        const ResearchPermitJsonCodec().encode(
          participationOperation(
            revision: operationRevision,
            corruptSignature: corruptEd,
          ),
        ),
      ],
      operationStates: {
        'synthetic-operation-permit': ResearchPermitState(
          currentRevision: stateRevision,
          revoked: revoked,
        ),
      },
      participationDocuments: [participationDocument(permit)],
      receipts: [
        ResearchAuthorityReceipt(
          ownerId: 'owner-a',
          receiptId: permit.consentReceiptId,
          kind: ResearchReceiptKind.consent,
          revision: receiptRevision,
          active: receiptActive,
          issuedAtUtc: decision,
          expiresAtUtc: participationStart.add(const Duration(hours: 1)),
          consentVersion: wrongReceiptVersion
              ? 1
              : request.scope.consentVersion,
          decidedAtUtc: wrongReceiptDecision
              ? decision.add(const Duration(milliseconds: 1))
              : decision,
        ),
      ],
    );
  }
}

final class _GatewayTransactionProbe extends QueryInterceptor {
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
