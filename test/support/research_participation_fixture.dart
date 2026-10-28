import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import 'research_admission_signing.dart';

Future<ResearchParticipationPermit> insertOwnerParticipation(
  AppDatabase database,
  String ownerId, {
  required String assignmentId,
}) async {
  final permit = signAdmissionParticipation(
    ResearchParticipationPermit(
      id: 'synthetic-permit:$ownerId',
      ownerId: ownerId,
      participantClass: ResearchParticipantClass.adult,
      ageBandCode: 'synthetic-adult',
      assignmentId: assignmentId,
      assignedTreatment: TodayExperiencePresentation.standard,
      consentReceiptId: 'synthetic-receipt:$ownerId',
      protocolId: 'synthetic-protocol',
      protocolVersion: 'synthetic-protocol-v1',
      issuedAtUtc: DateTime.fromMillisecondsSinceEpoch(20, isUtc: true),
      expiresAtUtc: DateTime.utc(2030),
      issuerKeyId: syntheticAdmissionP256KeyId,
      payloadSha256: '',
      signature: '',
      localRevision: 1,
      cloudRevision: 1,
      isDeleted: false,
    ),
  );
  await database.customStatement(
    'INSERT INTO research_participation_permits '
    '(id, owner_id, local_revision, cloud_revision, is_deleted, participant_class, '
    'age_band_code, assignment_id, assigned_treatment, consent_receipt_id, '
    'guardian_permission_receipt_ref, learner_assent_receipt_ref, protocol_id, '
    'protocol_version, issued_at_utc_ms, expires_at_utc_ms, revoked_at_utc_ms, '
    'issuer_key_id, payload_sha256, signature) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      permit.id,
      permit.ownerId,
      permit.localRevision,
      permit.cloudRevision,
      permit.isDeleted ? 1 : 0,
      permit.participantClass.name,
      permit.ageBandCode,
      permit.assignmentId,
      permit.assignedTreatment.wireName,
      permit.consentReceiptId,
      permit.guardianPermissionReceiptRef,
      permit.learnerAssentReceiptRef,
      permit.protocolId,
      permit.protocolVersion,
      permit.issuedAtUtc.millisecondsSinceEpoch,
      permit.expiresAtUtc.millisecondsSinceEpoch,
      permit.revokedAtUtc?.millisecondsSinceEpoch,
      permit.issuerKeyId,
      permit.payloadSha256,
      permit.signature,
    ],
  );
  return permit;
}
