import 'dart:convert';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';

import '../application/research_participation_permit_validator.dart';

final class ResearchP256SignatureVerifier
    implements ResearchPermitSignatureVerifier {
  ResearchP256SignatureVerifier({
    required Map<String, String> publicKeysSec1Hex,
  }) : _publicKeysSec1Hex = Map.unmodifiable(publicKeysSec1Hex);

  static final _parameters = ECCurve_secp256r1();
  static final _uncompressedKeyHex = RegExp(r'^04[0-9a-fA-F]{128}$');
  final Map<String, String> _publicKeysSec1Hex;

  @override
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  }) {
    final hex = _publicKeysSec1Hex[issuerKeyId];
    if (hex == null ||
        hex.length != 130 ||
        !_uncompressedKeyHex.hasMatch(hex) ||
        signature.length != 88) {
      return false;
    }

    try {
      final bytes = base64Decode(signature);
      // Round-trip equality excludes alternate alphabets and noncanonical padding.
      if (bytes.length != 64 || base64Encode(bytes) != signature) return false;

      final message = utf8.encode(canonicalPayload);
      // The encoder replaces unpaired UTF-16 surrogates; do not verify aliases.
      if (utf8.decode(message) != canonicalPayload) return false;

      final curve = _parameters.curve;
      final point = curve.decodePoint(<int>[
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      if (point == null || point.isInfinity) return false;
      final x = point.x!;
      final y = point.y!;
      // PointyCastle bounds coordinates but does not validate uncompressed points.
      // Check membership using its field operations; P-256 has cofactor one.
      if (y.square() != x * (x.square() + curve.a!) + curve.b!) return false;

      BigInt scalar(int offset) => BigInt.parse(
        bytes
            .sublist(offset, offset + 32)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
        radix: 16,
      );
      final r = scalar(0);
      final s = scalar(32);
      if (r <= BigInt.zero ||
          r >= _parameters.n ||
          s <= BigInt.zero ||
          s >= _parameters.n) {
        return false;
      }

      final signer = ECDSASigner(SHA256Digest())
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(ECPublicKey(point, _parameters)),
        );
      return signer.verifySignature(message, ECSignature(r, s));
    } on FormatException {
      return false;
    } on ArgumentError {
      // Includes out-of-field coordinates rejected by PointyCastle.
      return false;
    }
  }
}
