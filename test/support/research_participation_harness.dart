import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_participation_repository.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart'
    show experimentAssignmentId;
import 'package:vocab_learning_app/features/research/domain/experiment_assignment_admission.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_study_protocol.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_participant_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_trusted_time.dart';

import 'research_admission_signing.dart';

final participationStart = DateTime.utc(2026, 10, 29, 12);
const participationConsentVersion = 4;
const participationRotatedKeyId = 'synthetic-p256-rotated';
const participationColumns = {
  'id',
  'owner_id',
  'local_revision',
  'cloud_revision',
  'is_deleted',
  'participant_class',
  'age_band_code',
  'assignment_id',
  'assigned_treatment',
  'consent_receipt_id',
  'guardian_permission_receipt_ref',
  'learner_assent_receipt_ref',
  'protocol_id',
  'protocol_version',
  'issued_at_utc_ms',
  'expires_at_utc_ms',
  'revoked_at_utc_ms',
  'issuer_key_id',
  'payload_sha256',
  'signature',
};

String participationAssignmentId([String ownerId = 'owner-a']) =>
    experimentAssignmentId(
      ownerId: ownerId,
      experimentId: 'synthetic-experiment',
      experimentVersion: 2,
    );

String participationDocument(ResearchParticipationPermit permit) => jsonEncode({
  ...(jsonDecode(permit.canonicalPayload()) as Map<String, dynamic>),
  'payloadSha256': permit.payloadSha256,
  'signature': permit.signature,
});

final class ParticipationFixture {
  ParticipationFixture(this.database);

  final AppDatabase database;
  final clock = ParticipationClock();
  final documents = ParticipationDocuments();
  final operations = ParticipationOperations();
  final states = ParticipationStates();
  final receipts = ParticipationReceipts();
  late DriftResearchConsentRepository consent;
  late DriftOwnerWriteCoordinator ownerWrites;
  late DriftExperimentAssignmentRepository assignments;
  late DriftResearchParticipationRepository repository;
  late ResearchParticipationPermit current;

  static Future<ParticipationFixture> open({
    AppDatabase? database,
    bool seed = true,
  }) async {
    final result = ParticipationFixture(
      database ?? AppDatabase(NativeDatabase.memory()),
    );
    if (seed) {
      await result.database.customStatement('PRAGMA foreign_keys = ON');
      await result.database.customStatement(
        'INSERT INTO local_owners (id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES '
        "('owner-a', 'uid-a', 'firebaseBound', 1, 1), ('owner-b', 'uid-b', 'firebaseBound', 0, 2)",
      );
      await result.database.customStatement(
        'INSERT INTO research_consents (id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
        "VALUES ('synthetic-local-consent', 'owner-a', ?, 'accepted', ?)",
        [
          participationConsentVersion,
          participationStart
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ],
      );
    }
    result.use(participationPermit());
    result.operations.current = participationOperation();
    result.consent = DriftResearchConsentRepository(result.database);
    result.ownerWrites = DriftOwnerWriteCoordinator(
      result.database,
      nowUtc: () => result.clock.now,
    );
    final encodedPublic = ECCurve_secp256r1().G
        .getEncoded(false)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    result.assignments = DriftExperimentAssignmentRepository(
      result.database,
      binding: _binding(),
      authorizer: SignedPermitResearchOperationAuthorizer(
        permits: result.operations,
        states: result.states,
        verifier: admissionEd25519Verifier(),
        requirements: _requirements(),
        trustedTime: result.clock,
      ),
      trustedTime: result.clock,
      participationDocuments: result.documents,
      participationValidator: ResearchParticipationPermitValidator(
        protocolId: 'synthetic-protocol',
        protocolVersion: 'protocol-string-v7',
        signatures: ResearchP256SignatureVerifier(
          publicKeysSec1Hex: {
            syntheticAdmissionP256KeyId: encodedPublic,
            participationRotatedKeyId: encodedPublic,
          },
        ),
        receipts: result.receipts,
      ),
      consent: result.consent,
      ownerWrites: result.ownerWrites,
    );
    result.repository = DriftResearchParticipationRepository(
      result.database,
      assignments: result.assignments,
    );
    return result;
  }

  void use(ResearchParticipationPermit permit) {
    current = permit;
    documents.current[permit.id] = permit;
  }

  Future<bool> importCurrent({String ownerId = 'owner-a'}) =>
      repository.importDocument(
        ownerId: ownerId,
        document: participationDocument(current),
      );

  Future<ResearchParticipantSnapshot?> participant({
    String ownerId = 'owner-a',
    String? permitId,
  }) => repository.requireParticipant(
    ownerId: ownerId,
    permitId: permitId ?? current.id,
  );

  Future<void> withdraw() async {
    await consent.decide(
      ownerId: 'owner-a',
      version: participationConsentVersion,
      accepted: false,
      decidedAtUtc: clock.now,
    );
  }

  Future<Map<String, Object?>> stored([String? permitId]) async =>
      (await database
              .customSelect(
                'SELECT * FROM research_participation_permits WHERE id = ?',
                variables: [drift.Variable<String>(permitId ?? current.id)],
              )
              .getSingle())
          .data;
}

ResearchParticipationPermit participationPermit({
  String id = 'synthetic-participation',
  String ownerId = 'owner-a',
  String? assignmentId,
  TodayExperiencePresentation treatment = TodayExperiencePresentation.standard,
  String ageBandCode = 'synthetic-adult',
  String consentReceiptId = 'synthetic-consent-receipt',
  int revision = 1,
  int? cloudRevision,
  bool minor = false,
  bool deleted = false,
  String issuerKeyId = syntheticAdmissionP256KeyId,
  DateTime? issuedAtUtc,
  DateTime? expiresAtUtc,
  DateTime? revokedAtUtc,
  bool corruptSignature = false,
}) => signAdmissionParticipation(
  ResearchParticipationPermit(
    id: id,
    ownerId: ownerId,
    participantClass: minor
        ? ResearchParticipantClass.minor
        : ResearchParticipantClass.adult,
    ageBandCode: minor ? 'synthetic-minor' : ageBandCode,
    assignmentId: assignmentId ?? participationAssignmentId(ownerId),
    assignedTreatment: treatment,
    consentReceiptId: consentReceiptId,
    guardianPermissionReceiptRef: minor ? 'synthetic-guardian-receipt' : null,
    learnerAssentReceiptRef: minor ? 'synthetic-assent-receipt' : null,
    protocolId: 'synthetic-protocol',
    protocolVersion: 'protocol-string-v7',
    issuedAtUtc:
        issuedAtUtc ?? participationStart.subtract(const Duration(minutes: 5)),
    expiresAtUtc:
        expiresAtUtc ?? participationStart.add(const Duration(hours: 1)),
    revokedAtUtc: revokedAtUtc,
    issuerKeyId: issuerKeyId,
    payloadSha256: '0' * 64,
    signature: 'unsigned',
    localRevision: revision,
    cloudRevision: cloudRevision ?? revision,
    isDeleted: deleted,
  ),
  corruptSignature: corruptSignature,
);

ResearchPermit participationOperation({
  bool corruptSignature = false,
  int revision = 1,
  DateTime? issuedAtUtc,
  DateTime? expiresAtUtc,
}) => signAdmissionOperation(
  ResearchPermit(
    formatVersion: 1,
    permitId: 'synthetic-operation-permit',
    issuerId: 'synthetic-issuer',
    issuerKeyId: syntheticAdmissionEd25519KeyId,
    signatureAlgorithm: 'EdDSA',
    ownerId: 'owner-a',
    operation: ResearchOperation.collect,
    assignmentId: participationAssignmentId(),
    assignmentRevision: 11,
    protocolId: 'synthetic-protocol',
    protocolRevision: 5,
    instrumentId: 'synthetic-instrument',
    instrumentRevision: 9,
    revision: revision,
    issuedAtUtc:
        issuedAtUtc ?? participationStart.subtract(const Duration(minutes: 5)),
    expiresAtUtc:
        expiresAtUtc ?? participationStart.add(const Duration(hours: 4)),
    signature: const [1],
  ),
  corruptSignature: corruptSignature,
);

ExperimentAssignmentAdmissionBinding _binding() {
  final instrument = MotivationInstrument(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: 'instrument-string-v3',
    formId: 'synthetic-form',
    formVersion: 'form-v1',
    itemCatalogVersion: 'catalog-v1',
    items: [
      for (final point in MotivationTimepoint.values)
        MotivationItem(
          id: 'synthetic-${point.name}',
          timepoint: point,
          prompts: const {'th': 'ข้อมูลสังเคราะห์', 'en': 'Synthetic item'},
          options: [
            MotivationResponseOption(
              code: 'low',
              ordinalValue: 0,
              labels: const {'th': 'ต่ำ', 'en': 'Low'},
            ),
            MotivationResponseOption(
              code: 'high',
              ordinalValue: 1,
              labels: const {'th': 'สูง', 'en': 'High'},
            ),
          ],
        ),
    ],
  );
  return ExperimentAssignmentAdmissionBinding(
    study: MotivationStudyProtocol(
      protocolId: 'synthetic-protocol',
      protocolVersion: 'protocol-string-v7',
      consentVersion: participationConsentVersion,
      experimentId: 'synthetic-experiment',
      experimentVersion: 2,
      instrument: instrument,
      approvedInstrumentChecksum: instrument.checksumSha256,
      appVersion: 'synthetic-app',
      buildId: 'synthetic-build',
      contentRevision: 'content-v1',
      evidencePolicyVersion: 'evidence-v1',
      catalogVersion: 'catalog-v1',
    ),
    assignmentRevision: 11,
    protocolRevision: 5,
    instrumentRevision: 9,
  );
}

ResearchPermitRequirements _requirements() => ResearchPermitRequirements(
  supportedFormatVersion: 1,
  trustedIssuerId: 'synthetic-issuer',
  trustedIssuerKeyId: syntheticAdmissionEd25519KeyId,
  signatureAlgorithm: 'EdDSA',
  assignmentId: participationAssignmentId(),
  assignmentRevision: 11,
  protocolId: 'synthetic-protocol',
  protocolRevision: 5,
  instrumentId: 'synthetic-instrument',
  instrumentRevision: 9,
);

final class ParticipationClock implements ResearchTrustedTimeSource {
  DateTime now = participationStart;
  var available = true;
  var stale = false;
  @override
  Future<ResearchTrustedTime?> read() async => available
      ? ResearchTrustedTime(
          anchorUtc: now,
          validUntilUtc: now.add(const Duration(hours: 2)),
          age: stale ? const Duration(minutes: 2) : Duration.zero,
          maximumAge: const Duration(minutes: 1),
        )
      : null;
}

final class ParticipationDocuments
    implements ResearchParticipationDocumentSource {
  final current = <String, ResearchParticipationPermit>{};
  var available = true;
  var calls = 0;
  @override
  Future<ResearchParticipationPermit?> loadCurrent({
    required String ownerId,
    required String permitId,
  }) async {
    calls++;
    final permit = current[permitId];
    return available && permit?.ownerId == ownerId ? permit : null;
  }
}

final class ParticipationOperations implements ResearchPermitSource {
  ResearchPermit? current;
  var available = true;
  var calls = 0;
  @override
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  }) async {
    calls++;
    return available ? current : null;
  }
}

final class ParticipationStates implements ResearchPermitStateSource {
  var available = true;
  var revoked = false;
  var revision = 1;
  var calls = 0;
  Future<void> Function(int)? onRead;
  @override
  Future<ResearchPermitState?> loadState({required String permitId}) async {
    calls++;
    await onRead?.call(calls);
    return available
        ? ResearchPermitState(currentRevision: revision, revoked: revoked)
        : null;
  }
}

final class ParticipationReceipts implements ResearchReceiptAuthority {
  final inactive = <ResearchReceiptKind>{};
  var calls = 0;
  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    calls++;
    final expected = switch (kind) {
      ResearchReceiptKind.consent => 'synthetic-consent-receipt',
      ResearchReceiptKind.guardianPermission => 'synthetic-guardian-receipt',
      ResearchReceiptKind.learnerAssent => 'synthetic-assent-receipt',
    };
    return ownerId == 'owner-a' &&
        receiptId == expected &&
        !inactive.contains(kind);
  }
}

Future<void> expectParticipationArtifacts(
  AppDatabase database, {
  int assignments = 0,
  int permits = 0,
}) async {
  for (final expected in {
    'experiment_assignments': assignments,
    'research_participation_permits': permits,
    'events_v2': 0,
    'outbox_operations': 0,
  }.entries) {
    final row = await database
        .customSelect('SELECT COUNT(*) AS count FROM ${expected.key}')
        .getSingle();
    if (row.read<int>('count') != expected.value) {
      throw StateError(
        'Unexpected artifact count in ${expected.key}: ${row.read<int>('count')} != ${expected.value}',
      );
    }
  }
}

final class AfterParticipationWrite extends drift.QueryInterceptor {
  Future<void> Function()? afterWrite;
  var didFire = false;
  Future<void> _after(String statement) async {
    final callback = afterWrite;
    final normalized = statement.trimLeft().toLowerCase();
    if (callback != null &&
        normalized.contains('research_participation_permits') &&
        (normalized.startsWith('insert ') ||
            normalized.startsWith('update '))) {
      afterWrite = null;
      didFire = true;
      await callback();
    }
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    await _after(statement);
    return result;
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runUpdate(statement, args);
    await _after(statement);
    return result;
  }

  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    await _after(statement);
  }
}

final class AfterAuthorizedParticipationRead extends drift.QueryInterceptor {
  AfterAuthorizedParticipationRead({this.armAfterInsert = false});

  final bool armAfterInsert;
  var armed = false;
  var didInsert = false;
  var didFire = false;
  void Function()? afterRead;

  void _observeInsert(String statement) {
    final normalized = _normalize(statement);
    if (RegExp(
      r'^insert\s+into\s+research_participation_permits\b',
    ).hasMatch(normalized)) {
      didInsert = true;
      if (armAfterInsert) armed = true;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    final normalized = _normalize(statement);
    if (armed &&
        !didFire &&
        afterRead != null &&
        normalized.startsWith('select ') &&
        normalized.contains(' from research_participation_permits ') &&
        RegExp(r'\bwhere\s+id\s*=\s*\?').hasMatch(normalized)) {
      didFire = true;
      armed = false;
      afterRead!();
    }
    return result;
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    _observeInsert(statement);
    return result;
  }

  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    _observeInsert(statement);
  }

  static String _normalize(String statement) =>
      statement.replaceAll(RegExp(r'\s+'), ' ').trimLeft().toLowerCase();
}
