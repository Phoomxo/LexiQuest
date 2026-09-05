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
    final authenticity = validateAuthenticity(
      permit,
      expectedOwnerId: expectedOwnerId,
      expectedAssignmentId: expectedAssignmentId,
      evaluatedAtUtc: evaluatedAtUtc,
    );
    if (authenticity != ResearchPermitDenialReason.none) {
      return ResearchPermitValidationResult.denied(authenticity);
    }
    if (permit.isDeleted) {
      return const ResearchPermitValidationResult.denied(
        ResearchPermitDenialReason.deleted,
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
    // An authority may return a snapshot captured before its asynchronous lookup.
    // Re-read every required receipt after the first lookup round has completed.
    for (var pass = 0; pass < 2; pass++) {
      for (final receipt in [
        (
          permit.consentReceiptId,
          ResearchReceiptKind.consent,
          ResearchPermitDenialReason.consentUnavailable,
        ),
        if (permit.participantClass == ResearchParticipantClass.minor) ...[
          (
            permit.guardianPermissionReceiptRef!,
            ResearchReceiptKind.guardianPermission,
            ResearchPermitDenialReason.guardianPermissionUnavailable,
          ),
          (
            permit.learnerAssentReceiptRef!,
            ResearchReceiptKind.learnerAssent,
            ResearchPermitDenialReason.learnerAssentUnavailable,
          ),
        ],
      ]) {
        if (!await _receiptIsActive(
          permit,
          receipt.$1,
          receipt.$2,
          evaluatedAtUtc,
        )) {
          return ResearchPermitValidationResult.denied(receipt.$3);
        }
      }
    }
    // Signature authority may also have become unavailable while receipts awaited.
    final current = validateAuthenticity(
      permit,
      expectedOwnerId: expectedOwnerId,
      expectedAssignmentId: expectedAssignmentId,
      evaluatedAtUtc: evaluatedAtUtc,
    );
    if (current != ResearchPermitDenialReason.none) {
      return ResearchPermitValidationResult.denied(current);
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

  /// Authenticates issuer-signed state without granting active participation.
  /// Revocations must remain importable after expiry or withdrawal of receipts.
  ResearchPermitDenialReason validateAuthenticity(
    ResearchParticipationPermit permit, {
    required String expectedOwnerId,
    required String expectedAssignmentId,
    required DateTime evaluatedAtUtc,
  }) {
    if (!_canonical(expectedOwnerId) ||
        !_canonical(expectedAssignmentId) ||
        !_canonical(protocolId) ||
        !_canonical(protocolVersion) ||
        !_validUtc(evaluatedAtUtc) ||
        !_permitFieldsAreCanonical(permit)) {
      return ResearchPermitDenialReason.invalidInput;
    }
    if (permit.ownerId != expectedOwnerId) {
      return ResearchPermitDenialReason.ownerMismatch;
    }
    if (permit.assignmentId != expectedAssignmentId) {
      return ResearchPermitDenialReason.assignmentMismatch;
    }
    if (permit.protocolId != protocolId ||
        permit.protocolVersion != protocolVersion) {
      return ResearchPermitDenialReason.protocolMismatch;
    }
    if (permit.localRevision <= 0 ||
        permit.localRevision != permit.cloudRevision) {
      return ResearchPermitDenialReason.revisionMismatch;
    }
    if (permit.participantClass == ResearchParticipantClass.minor) {
      if (permit.guardianPermissionReceiptRef == null) {
        return ResearchPermitDenialReason.guardianPermissionUnavailable;
      }
      if (permit.learnerAssentReceiptRef == null) {
        return ResearchPermitDenialReason.learnerAssentUnavailable;
      }
    }
    final canonicalPayload = permit.canonicalPayload();
    final digest = sha256.convert(utf8.encode(canonicalPayload)).toString();
    if (permit.payloadSha256 != digest) {
      return ResearchPermitDenialReason.payloadMismatch;
    }
    try {
      return signatures.verify(
            issuerKeyId: permit.issuerKeyId,
            canonicalPayload: canonicalPayload,
            signature: permit.signature,
          )
          ? ResearchPermitDenialReason.none
          : ResearchPermitDenialReason.invalidSignature;
    } on Object {
      return ResearchPermitDenialReason.invalidSignature;
    }
  }

  Future<bool> _receiptIsActive(
    ResearchParticipationPermit permit,
    String receiptId,
    ResearchReceiptKind kind,
    DateTime evaluatedAtUtc,
  ) async {
    try {
      return await receipts.isActive(
        ownerId: permit.ownerId,
        receiptId: receiptId,
        kind: kind,
        evaluatedAtUtc: evaluatedAtUtc,
      );
    } on Object {
      return false;
    }
  }
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
      (permit.revokedAtUtc == null ||
          (_validUtc(permit.revokedAtUtc!) &&
              !permit.revokedAtUtc!.isBefore(permit.issuedAtUtc)));
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
