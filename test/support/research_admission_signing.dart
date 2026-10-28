import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart'
    show EdDSAPrivateKey, JWTAlgorithm;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/ed25519_research_permit_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

const syntheticAdmissionP256KeyId = 'synthetic-p256';
const syntheticAdmissionEd25519KeyId = 'synthetic-ed25519';

// NON-PRODUCTION test keys. P-256 scalar one and the public RFC 8032 test seed.
final _curve = ECCurve_secp256r1();
const _edSeed =
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
const _edPublic =
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';

ResearchP256SignatureVerifier admissionP256Verifier() =>
    ResearchP256SignatureVerifier(
      publicKeysSec1Hex: {
        syntheticAdmissionP256KeyId: _curve.G
            .getEncoded(false)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      },
    );

Ed25519ResearchPermitSignatureVerifier admissionEd25519Verifier() =>
    Ed25519ResearchPermitSignatureVerifier({
      syntheticAdmissionEd25519KeyId: _hex(_edPublic),
    });

ResearchParticipationPermit signAdmissionParticipation(
  ResearchParticipationPermit unsigned, {
  bool corruptSignature = false,
}) {
  final payload = unsigned.canonicalPayload();
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(
      true,
      PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(BigInt.one, _curve)),
    );
  final signature =
      signer.generateSignature(Uint8List.fromList(utf8.encode(payload)))
          as ECSignature;
  final raw = _hex(
    '${signature.r.toRadixString(16).padLeft(64, '0')}'
    '${signature.s.toRadixString(16).padLeft(64, '0')}',
  );
  if (corruptSignature) raw[0] ^= 1;
  return ResearchParticipationPermit(
    id: unsigned.id,
    ownerId: unsigned.ownerId,
    participantClass: unsigned.participantClass,
    ageBandCode: unsigned.ageBandCode,
    assignmentId: unsigned.assignmentId,
    assignedTreatment: unsigned.assignedTreatment,
    consentReceiptId: unsigned.consentReceiptId,
    guardianPermissionReceiptRef: unsigned.guardianPermissionReceiptRef,
    learnerAssentReceiptRef: unsigned.learnerAssentReceiptRef,
    protocolId: unsigned.protocolId,
    protocolVersion: unsigned.protocolVersion,
    issuedAtUtc: unsigned.issuedAtUtc,
    expiresAtUtc: unsigned.expiresAtUtc,
    revokedAtUtc: unsigned.revokedAtUtc,
    issuerKeyId: unsigned.issuerKeyId,
    payloadSha256: sha256.convert(utf8.encode(payload)).toString(),
    signature: base64Encode(raw),
    localRevision: unsigned.localRevision,
    cloudRevision: unsigned.cloudRevision,
    isDeleted: unsigned.isDeleted,
  );
}

ResearchPermit signAdmissionOperation(
  ResearchPermit unsigned, {
  bool corruptSignature = false,
}) {
  final signature = JWTAlgorithm.EdDSA.sign(
    EdDSAPrivateKey(_hex(_edSeed)),
    unsigned.signedPayload(),
  );
  if (corruptSignature) signature[0] ^= 1;
  return ResearchPermit(
    formatVersion: unsigned.formatVersion,
    permitId: unsigned.permitId,
    issuerId: unsigned.issuerId,
    issuerKeyId: unsigned.issuerKeyId,
    signatureAlgorithm: unsigned.signatureAlgorithm,
    ownerId: unsigned.ownerId,
    operation: unsigned.operation,
    assignmentId: unsigned.assignmentId,
    assignmentRevision: unsigned.assignmentRevision,
    protocolId: unsigned.protocolId,
    protocolRevision: unsigned.protocolRevision,
    instrumentId: unsigned.instrumentId,
    instrumentRevision: unsigned.instrumentRevision,
    revision: unsigned.revision,
    issuedAtUtc: unsigned.issuedAtUtc,
    expiresAtUtc: unsigned.expiresAtUtc,
    signature: signature,
  );
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);
