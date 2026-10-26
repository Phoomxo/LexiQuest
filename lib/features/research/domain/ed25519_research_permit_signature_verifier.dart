import 'dart:typed_data';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'research_operation_authorizer.dart';

final class Ed25519ResearchPermitSignatureVerifier
    implements ResearchPermitSignatureVerifier {
  Ed25519ResearchPermitSignatureVerifier(Map<String, List<int>> publicKeys)
    : _publicKeys = {
        for (final entry in publicKeys.entries)
          entry.key: Uint8List.fromList(entry.value),
      };

  static const algorithm = 'EdDSA';

  final Map<String, Uint8List> _publicKeys;

  @override
  Future<bool> verify({
    required String algorithm,
    required String issuerKeyId,
    required Uint8List message,
    required Uint8List signature,
  }) async {
    final publicKey = _publicKeys[issuerKeyId];
    if (algorithm != Ed25519ResearchPermitSignatureVerifier.algorithm ||
        publicKey == null ||
        publicKey.length != 32 ||
        signature.length != 64 ||
        _hasSmallOrder(publicKey) ||
        _hasSmallOrder(signature.sublist(0, 32))) {
      return false;
    }
    try {
      return JWTAlgorithm.EdDSA.verify(
        EdDSAPublicKey(publicKey),
        message,
        signature,
      );
    } on Object {
      return false;
    }
  }
}

final BigInt _ed25519Prime = (BigInt.one << 255) - BigInt.from(19);
final BigInt _ed25519D =
    (-BigInt.from(121665) * BigInt.from(121666).modInverse(_ed25519Prime)) %
    _ed25519Prime;

bool _hasSmallOrder(List<int> encodedPoint) {
  final bytes = Uint8List.fromList(encodedPoint);
  bytes[31] &= 0x7f;
  var y = BigInt.zero;
  for (var index = bytes.length - 1; index >= 0; index--) {
    y = (y << 8) | BigInt.from(bytes[index]);
  }
  if (y >= _ed25519Prime) return true;

  final ySquared = (y * y) % _ed25519Prime;
  final denominator = (_ed25519D * ySquared + BigInt.one) % _ed25519Prime;
  if (denominator == BigInt.zero) return true;
  final xSquared =
      ((ySquared - BigInt.one) * denominator.modInverse(_ed25519Prime)) %
      _ed25519Prime;

  // The order-dividing-eight points satisfy x=0, y=0, or x=±i*y.
  return xSquared == BigInt.zero ||
      y == BigInt.zero ||
      (xSquared + ySquared) % _ed25519Prime == BigInt.zero;
}
