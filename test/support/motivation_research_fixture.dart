import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_participation_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_study_protocol.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

/// Synthetic fixture only: not an approved questionnaire or issuer.
MotivationInstrument syntheticMotivationInstrument() => MotivationInstrument(
  instrumentId: 'synthetic',
  instrumentVersion: '1',
  formId: 'paired',
  formVersion: '1',
  itemCatalogVersion: '1',
  items: [
    for (final point in MotivationTimepoint.values)
      MotivationItem(
        id: point.name,
        timepoint: point,
        prompts: const {'th': 'คำถามทดสอบ', 'en': 'Synthetic test item'},
        options: [
          MotivationResponseOption(
            code: 'low',
            ordinalValue: 1,
            labels: const {'th': 'น้อย', 'en': 'Low'},
          ),
          MotivationResponseOption(
            code: 'high',
            ordinalValue: 5,
            labels: const {'th': 'มาก', 'en': 'High'},
          ),
        ],
      ),
  ],
);

final class ResearchTestAuthority
    implements ResearchPermitSignatureVerifier, ResearchReceiptAuthority {
  bool validSignature = true;
  bool receiptsActive = true;
  Future<void> Function()? onRead;
  @override
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  }) => validSignature && signature == 'synthetic-signature';
  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    await onRead?.call();
    return receiptsActive;
  }
}

final class MotivationResearchFixture {
  final database = AppDatabase(NativeDatabase.memory());
  final authority = ResearchTestAuthority();
  DateTime now = DateTime.utc(2026, 9, 5, 12);
  late final instrument = syntheticMotivationInstrument();
  late final study = MotivationStudyProtocol(
    protocolId: 'motivation',
    protocolVersion: '1',
    consentVersion: 1,
    experimentId: 'motivation',
    experimentVersion: 1,
    instrument: instrument,
    approvedInstrumentChecksum: instrument.checksumSha256,
    appVersion: '1',
    buildId: 'test',
    contentRevision: 'content1',
    evidencePolicyVersion: 'policy1',
    catalogVersion: 'catalog1',
  );
  late final participation = DriftResearchParticipationRepository(
    database,
    study: study,
    validator: ResearchParticipationPermitValidator(
      protocolId: study.protocolId,
      protocolVersion: study.protocolVersion,
      signatures: authority,
      receipts: authority,
    ),
    nowUtc: () => now,
  );
  late final measurements = DriftMotivationMeasurementRepository(
    database,
    study: study,
    participation: participation,
    nowUtc: () => now,
  );
  String get assignmentId =>
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'owner:a',
        experimentId: 'motivation',
        experimentVersion: 1,
      );
  ResearchParticipationPermit permit({
    String id = 'permit:a',
    ResearchParticipantClass participantClass = ResearchParticipantClass.adult,
    DateTime? expiresAtUtc,
    String? guardian,
    String? assent,
  }) {
    final unsigned = ResearchParticipationPermit(
      id: id,
      ownerId: 'owner:a',
      participantClass: participantClass,
      ageBandCode: participantClass.name,
      assignmentId: assignmentId,
      assignedTreatment: TodayExperiencePresentation.adventure,
      consentReceiptId: 'receipt:a',
      protocolId: study.protocolId,
      protocolVersion: study.protocolVersion,
      issuedAtUtc: DateTime.utc(2026, 9, 5, 11),
      expiresAtUtc: expiresAtUtc ?? DateTime.utc(2026, 9, 8),
      issuerKeyId: 'synthetic',
      payloadSha256: '',
      signature: 'synthetic-signature',
      localRevision: 1,
      cloudRevision: 1,
      isDeleted: false,
      guardianPermissionReceiptRef: guardian,
      learnerAssentReceiptRef: assent,
    );
    return unsigned.copyWith(
      payloadSha256: sha256
          .convert(utf8.encode(unsigned.canonicalPayload()))
          .toString(),
    );
  }

  Future<void> initialize({bool enroll = true}) async {
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner:a',
            createdAtUtcMs: DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.researchConsents)
        .insert(
          ResearchConsentsCompanion.insert(
            id: 'consent:owner:a:1',
            ownerId: 'owner:a',
            consentVersion: 1,
            consentState: 'accepted',
            decidedAtUtcMs: DateTime.utc(2026, 9, 5, 10).millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.experimentAssignments)
        .insert(
          ExperimentAssignmentsCompanion.insert(
            id: assignmentId,
            ownerId: 'owner:a',
            experimentId: 'motivation',
            experimentVersion: 1,
            cohort: 'adventure',
            protocolVersion: '1',
            assignedAtUtcMs: DateTime.utc(
              2026,
              9,
              5,
              10,
              30,
            ).millisecondsSinceEpoch,
          ),
        );
    if (enroll) await participation.importPermit(permit());
  }
}
