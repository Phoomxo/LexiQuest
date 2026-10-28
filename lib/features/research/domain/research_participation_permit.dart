import 'dart:convert';

import '../../adventure/domain/adventure_entry.dart';

enum ResearchParticipantClass { adult, minor }

enum ResearchReceiptKind { consent, guardianPermission, learnerAssent }

enum ResearchPermitDenialReason {
  none,
  invalidInput,
  ownerMismatch,
  assignmentMismatch,
  protocolMismatch,
  notYetValid,
  expired,
  revoked,
  deleted,
  revisionMismatch,
  payloadMismatch,
  invalidSignature,
  consentUnavailable,
  guardianPermissionUnavailable,
  learnerAssentUnavailable,
}

final class ResearchParticipationPermit {
  const ResearchParticipationPermit({
    required this.id,
    required this.ownerId,
    required this.participantClass,
    required this.ageBandCode,
    required this.assignmentId,
    required this.assignedTreatment,
    required this.consentReceiptId,
    required this.protocolId,
    required this.protocolVersion,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.issuerKeyId,
    required this.payloadSha256,
    required this.signature,
    required this.localRevision,
    required this.cloudRevision,
    required this.isDeleted,
    this.guardianPermissionReceiptRef,
    this.learnerAssentReceiptRef,
    this.revokedAtUtc,
  });

  final String id;
  final String ownerId;
  final ResearchParticipantClass participantClass;
  final String ageBandCode;
  final String assignmentId;
  final TodayExperiencePresentation assignedTreatment;
  final String consentReceiptId;
  final String? guardianPermissionReceiptRef;
  final String? learnerAssentReceiptRef;
  final String protocolId;
  final String protocolVersion;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final DateTime? revokedAtUtc;
  final String issuerKeyId;
  final String payloadSha256;
  final String signature;
  final int localRevision;
  final int cloudRevision;
  final bool isDeleted;

  String canonicalPayload() => jsonEncode(<String, Object?>{
    'schema': 'lexiquest.research-participation-permit.v1',
    'id': id,
    'ownerId': ownerId,
    'participantClass': participantClass.name,
    'ageBandCode': ageBandCode,
    'assignmentId': assignmentId,
    'assignedTreatment': assignedTreatment.wireName,
    'consentReceiptId': consentReceiptId,
    'guardianPermissionReceiptRef': guardianPermissionReceiptRef,
    'learnerAssentReceiptRef': learnerAssentReceiptRef,
    'protocolId': protocolId,
    'protocolVersion': protocolVersion,
    'issuedAtUtc': issuedAtUtc.toIso8601String(),
    'expiresAtUtc': expiresAtUtc.toIso8601String(),
    'revokedAtUtc': revokedAtUtc?.toIso8601String(),
    'issuerKeyId': issuerKeyId,
    'localRevision': localRevision,
    'cloudRevision': cloudRevision,
    'isDeleted': isDeleted,
  });

  ResearchParticipationPermit copyWith({String? payloadSha256}) =>
      ResearchParticipationPermit(
        id: id,
        ownerId: ownerId,
        participantClass: participantClass,
        ageBandCode: ageBandCode,
        assignmentId: assignmentId,
        assignedTreatment: assignedTreatment,
        consentReceiptId: consentReceiptId,
        protocolId: protocolId,
        protocolVersion: protocolVersion,
        issuedAtUtc: issuedAtUtc,
        expiresAtUtc: expiresAtUtc,
        issuerKeyId: issuerKeyId,
        payloadSha256: payloadSha256 ?? this.payloadSha256,
        signature: signature,
        localRevision: localRevision,
        cloudRevision: cloudRevision,
        isDeleted: isDeleted,
        guardianPermissionReceiptRef: guardianPermissionReceiptRef,
        learnerAssentReceiptRef: learnerAssentReceiptRef,
        revokedAtUtc: revokedAtUtc,
      );
}

final class ResearchPermitValidationResult {
  const ResearchPermitValidationResult._({
    required this.denialReason,
    this.activePermit,
  });

  const ResearchPermitValidationResult.active(ActivePresentationPermit permit)
    : this._(
        denialReason: ResearchPermitDenialReason.none,
        activePermit: permit,
      );

  const ResearchPermitValidationResult.denied(ResearchPermitDenialReason reason)
    : this._(denialReason: reason);

  final ResearchPermitDenialReason denialReason;
  final ActivePresentationPermit? activePermit;

  bool get isActive => activePermit != null;
}

abstract interface class ActivePresentationPermitReader {
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  });
}

final class NoActivePresentationPermitReader
    implements ActivePresentationPermitReader {
  const NoActivePresentationPermitReader();

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async => null;
}
