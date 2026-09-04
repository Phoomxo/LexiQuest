import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../adventure/domain/adventure_entry.dart';
import '../domain/research_participation_permit.dart';

abstract interface class ResearchPermitSignatureVerifier {
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  });
}

abstract interface class ResearchReceiptAuthority {
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  });
}

final class ResearchParticipationPermitValidator {
  const ResearchParticipationPermitValidator({
    required this.protocolId,
    required this.protocolVersion,
    required this.signatures,
    required this.receipts,
  });

  final String protocolId;
  final String protocolVersion;
  final ResearchPermitSignatureVerifier signatures;
  final ResearchReceiptAuthority receipts;

  Future<ResearchPermitValidationResult> validate(
    ResearchParticipationPermit permit, {
    required String expectedOwnerId,
    required String expectedAssignmentId,
    required DateTime evaluatedAtUtc,
  }) async {
    if (!_canonical(expectedOwnerId) ||
        !_canonical(expectedAssignmentId) ||
        !_canonical(protocolId) ||
        !_canonical(protocolVersion) ||
        !_validUtc(evaluatedAtUtc) ||
        !_permitFieldsAreCanonical(permit)) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.invalidInput,
      );
    }
    if (permit.ownerId != expectedOwnerId) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.ownerMismatch,
      );
    }
    if (permit.assignmentId != expectedAssignmentId) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.assignmentMismatch,
      );
    }
    if (permit.protocolId != protocolId ||
        permit.protocolVersion != protocolVersion) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.protocolMismatch,
      );
    }
    if (permit.isDeleted) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.deleted,
      );
    }
    if (permit.localRevision <= 0 ||
        permit.localRevision != permit.cloudRevision) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.revisionMismatch,
      );
    }
    if (evaluatedAtUtc.isBefore(permit.issuedAtUtc)) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.notYetValid,
      );
    }
    if (!evaluatedAtUtc.isBefore(permit.expiresAtUtc)) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.expired,
      );
    }
    if (permit.revokedAtUtc != null &&
        !evaluatedAtUtc.isBefore(permit.revokedAtUtc!)) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.revoked,
      );
    }
    final canonicalPayload = permit.canonicalPayload();
    final digest = sha256.convert(utf8.encode(canonicalPayload)).toString();
    if (permit.payloadSha256 != digest) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.payloadMismatch,
      );
    }
    if (!signatures.verify(
      issuerKeyId: permit.issuerKeyId,
      canonicalPayload: canonicalPayload,
      signature: permit.signature,
    )) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.invalidSignature,
      );
    }
    if (!await _receiptIsActive(
      permit,
      permit.consentReceiptId,
      ResearchReceiptKind.consent,
      evaluatedAtUtc,
    )) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.consentUnavailable,
      );
    }
    if (permit.participantClass == ResearchParticipantClass.minor) {
      final guardian = permit.guardianPermissionReceiptRef;
      if (guardian == null ||
          !await _receiptIsActive(
            permit,
            guardian,
            ResearchReceiptKind.guardianPermission,
            evaluatedAtUtc,
          )) {
        return const ResearchPermitValidationResult.denied(
          ResearchPermitDenialReason.guardianPermissionUnavailable,
        );
      }
      final assent = permit.learnerAssentReceiptRef;
      if (assent == null ||
          !await _receiptIsActive(
            permit,
            assent,
            ResearchReceiptKind.learnerAssent,
            evaluatedAtUtc,
          )) {
        return const ResearchPermitValidationResult.denied(
          ResearchPermitDenialReason.learnerAssentUnavailable,
        );
      }
    }
    return ResearchPermitValidationResult.active(
      ActivePresentationPermit(
        permitId: permit.id,
        ownerId: permit.ownerId,
        assignedPresentation: permit.assignedTreatment,
        protocolId: permit.protocolId,
        protocolVersion: permit.protocolVersion,
        assignmentId: permit.assignmentId,
        expiresAtUtc: permit.expiresAtUtc,
      ),
    );
  }

  Future<bool> _receiptIsActive(
    ResearchParticipationPermit permit,
    String receiptId,
    ResearchReceiptKind kind,
    DateTime evaluatedAtUtc,
  ) => receipts.isActive(
    ownerId: permit.ownerId,
    receiptId: receiptId,
    kind: kind,
    evaluatedAtUtc: evaluatedAtUtc,
  );
}

bool _permitFieldsAreCanonical(ResearchParticipationPermit permit) {
  final requiredText = <String>[
    permit.id,
    permit.ownerId,
    permit.ageBandCode,
    permit.assignmentId,
    permit.consentReceiptId,
    permit.protocolId,
    permit.protocolVersion,
    permit.issuerKeyId,
    permit.payloadSha256,
    permit.signature,
  ];
  return requiredText.every(_canonical) &&
      (permit.guardianPermissionReceiptRef == null ||
          _canonical(permit.guardianPermissionReceiptRef!)) &&
      (permit.learnerAssentReceiptRef == null ||
          _canonical(permit.learnerAssentReceiptRef!)) &&
      _validUtc(permit.issuedAtUtc) &&
      _validUtc(permit.expiresAtUtc) &&
      permit.expiresAtUtc.isAfter(permit.issuedAtUtc) &&
      (permit.revokedAtUtc == null || _validUtc(permit.revokedAtUtc!));
}

bool _canonical(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.runes.length <= 256 &&
    !value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'));

bool _validUtc(DateTime value) =>
    value.isUtc &&
    value.millisecondsSinceEpoch >= 0 &&
    value.microsecondsSinceEpoch % Duration.microsecondsPerMillisecond == 0;
