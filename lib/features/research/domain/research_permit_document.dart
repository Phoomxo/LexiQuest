import 'dart:convert';
import '../../adventure/domain/adventure_entry.dart';
import 'motivation_study_protocol.dart';
import 'research_participation_permit.dart';

/// Decodes a bounded externally signed document; decoding never grants authority.
ResearchParticipationPermit decodeResearchPermitDocument(String document) {
  try {
    if (document.length > 16384 || utf8.encode(document).length > 16384) {
      throw const FormatException();
    }
    final decoded = jsonDecode(document);
    const keys = {
      'schema',
      'id',
      'ownerId',
      'participantClass',
      'ageBandCode',
      'assignmentId',
      'assignedTreatment',
      'consentReceiptId',
      'guardianPermissionReceiptRef',
      'learnerAssentReceiptRef',
      'protocolId',
      'protocolVersion',
      'issuedAtUtc',
      'expiresAtUtc',
      'revokedAtUtc',
      'issuerKeyId',
      'localRevision',
      'cloudRevision',
      'isDeleted',
      'payloadSha256',
      'signature',
    };
    if (decoded is! Map<String, dynamic> ||
        decoded.length != keys.length ||
        !decoded.keys.every(keys.contains) ||
        decoded['schema'] != 'lexiquest.research-participation-permit.v1') {
      throw const FormatException();
    }
    String text(String key) {
      final value = decoded[key];
      if (value is! String) throw const FormatException();
      return value;
    }

    String code(String key) {
      final value = text(key);
      requireResearchCode(value);
      return value;
    }

    String? optionalCode(String key) => decoded[key] == null ? null : code(key);
    int revision(String key) {
      final value = decoded[key];
      if (value is! int || value < 1) throw const FormatException();
      return value;
    }

    DateTime time(String key) {
      final value = text(key);
      final result = DateTime.parse(value);
      requireResearchUtc(result);
      if (result.toIso8601String() != value) throw const FormatException();
      return result;
    }

    final deleted = decoded['isDeleted'];
    if (deleted is! bool) throw const FormatException();
    final hash = text('payloadSha256');
    final signature = text('signature');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        signature.isEmpty ||
        signature.length > 256) {
      throw const FormatException();
    }
    return ResearchParticipationPermit(
      id: code('id'),
      ownerId: code('ownerId'),
      participantClass: ResearchParticipantClass.values.byName(
        code('participantClass'),
      ),
      ageBandCode: code('ageBandCode'),
      assignmentId: code('assignmentId'),
      assignedTreatment: TodayExperiencePresentationCodec.decode(
        code('assignedTreatment'),
      ),
      consentReceiptId: code('consentReceiptId'),
      guardianPermissionReceiptRef: optionalCode(
        'guardianPermissionReceiptRef',
      ),
      learnerAssentReceiptRef: optionalCode('learnerAssentReceiptRef'),
      protocolId: code('protocolId'),
      protocolVersion: code('protocolVersion'),
      issuedAtUtc: time('issuedAtUtc'),
      expiresAtUtc: time('expiresAtUtc'),
      revokedAtUtc: decoded['revokedAtUtc'] == null
          ? null
          : time('revokedAtUtc'),
      issuerKeyId: code('issuerKeyId'),
      payloadSha256: hash,
      signature: signature,
      localRevision: revision('localRevision'),
      cloudRevision: revision('cloudRevision'),
      isDeleted: deleted,
    );
  } on Object {
    // Parser diagnostics must never include submitted receipt/signature content.
    throw const FormatException('Invalid signed research document');
  }
}
