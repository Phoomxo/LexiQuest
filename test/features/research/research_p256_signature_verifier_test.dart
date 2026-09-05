import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';

// RFC 6979, Appendix A.2.5, P-256/SHA-256 deterministic signatures.
// Independently verified with .NET ECDsa.VerifyData (IEEE P1363 encoding).
// Only public verification material is retained.
const _rfcPublicKey =
    '04'
    '60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6'
    '7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299';
const _sampleSignature =
    '79SLKqy2qP0RQN2c1F6B1p0sh3tWqvmRw00OqE6vNxb3yxyULWV8QdQ2x6G24p9l'
    '8+kA27mv9AZNxKsvhDrNqA==';
const _testSignature =
    '8auwI1GDUc1x2IFWex6mY+0+/PbFEys1TyjTsLfTg2cBn0ETdCorFL0lkmtJxkkV'
    'XyZ+YNOBS0wMyEJQ5G8Agw==';

// Fixed UTF-8 fixture signed and verified independently by .NET ECDsa on
// nistP256, SHA-256, IeeeP1363FixedFieldConcatenation. The ephemeral signing
// key was disposed without exporting or saving its private parameters.
const _fixturePublicKey =
    '04'
    '7390D6DFCED5289B62A5ECD433B92DE2E973DDEBC063D066CE76CE8700A2E58FC8'
    '3E8A90B466738BDC1E88BA7C3864F7B538E4394BB6EC8264F5FF69ACF74063';
const _fixturePayload =
    '{"permitId":"permit-001","ownerId":"ผู้เรียน-001",'
    '"issuerKeyId":"fixture-2026"}';
const _fixtureSignature =
    '3791f+05XcbefDs8daWjGbtyqmIN75IV06JjBFk5xhjOQBT8qq33krmWeLHi2xcO'
    'zH9Wvq46Ur/3ZKI7COUQ+g==';
const _replacementCharacterSignature =
    '/28ZA3DORiwyHrdLcliX7Y6e6c1TCn4Re4QZamE0WI7Djza9jlykY85bxMcC71Jo'
    'NmOu4EOEKvjQbudc/RIytA==';
const _orderHex =
    'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551';
const _primeHex =
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff';

void main() {
  late ResearchPermitSignatureVerifier verifier;

  setUp(() {
    verifier = ResearchP256SignatureVerifier(
      publicKeysSec1Hex: <String, String>{
        'rfc-6979': _rfcPublicKey,
        'fixture-2026': _fixturePublicKey,
      },
    );
  });

  test('verifies RFC 6979 P-256 SHA-256 sample vector', () {
    expect(
      verifier.verify(
        issuerKeyId: 'rfc-6979',
        canonicalPayload: 'sample',
        signature: _sampleSignature,
      ),
      isTrue,
    );
  });

  test('verifies RFC 6979 P-256 SHA-256 test vector', () {
    expect(
      verifier.verify(
        issuerKeyId: 'rfc-6979',
        canonicalPayload: 'test',
        signature: _testSignature,
      ),
      isTrue,
    );
  });

  test('verifies independent signed UTF-8 permit fixture', () {
    expect(base64Decode(_fixtureSignature), hasLength(64));
    expect(
      verifier.verify(
        issuerKeyId: 'fixture-2026',
        canonicalPayload: _fixturePayload,
        signature: _fixtureSignature,
      ),
      isTrue,
    );
  });

  for (final payload in <String>[
    'Sample',
    'sample ',
    ' sample',
    'sample\n',
    'samplf',
    '',
  ]) {
    test('rejects changed payload ${jsonEncode(payload)}', () {
      expect(
        verifier.verify(
          issuerKeyId: 'rfc-6979',
          canonicalPayload: payload,
          signature: _sampleSignature,
        ),
        isFalse,
      );
    });
  }

  test('rejects a changed field in the signed UTF-8 fixture', () {
    expect(
      verifier.verify(
        issuerKeyId: 'fixture-2026',
        canonicalPayload: _fixturePayload.replaceFirst('001', '002'),
        signature: _fixtureSignature,
      ),
      isFalse,
    );
  });

  test('does not reuse digest state between successive calls', () {
    for (var i = 0; i < 3; i++) {
      expect(
        verifier.verify(
          issuerKeyId: 'rfc-6979',
          canonicalPayload: 'sample',
          signature: _sampleSignature,
        ),
        isTrue,
      );
      expect(
        verifier.verify(
          issuerKeyId: 'fixture-2026',
          canonicalPayload: 'tampered',
          signature: _fixtureSignature,
        ),
        isFalse,
      );
    }
  });

  for (final issuer in <String>['unknown', '', 'RFC-6979', 'rfc-6979 ']) {
    test('rejects unknown issuer ${jsonEncode(issuer)}', () {
      expect(
        verifier.verify(
          issuerKeyId: issuer,
          canonicalPayload: 'sample',
          signature: _sampleSignature,
        ),
        isFalse,
      );
    });
  }

  test('rejects the signature of a different allowlisted issuer', () {
    expect(
      verifier.verify(
        issuerKeyId: 'fixture-2026',
        canonicalPayload: 'sample',
        signature: _sampleSignature,
      ),
      isFalse,
    );
  });

  test('an empty allowlist trusts no issuer', () {
    final empty = ResearchP256SignatureVerifier(publicKeysSec1Hex: {});
    expect(
      empty.verify(
        issuerKeyId: 'rfc-6979',
        canonicalPayload: 'sample',
        signature: _sampleSignature,
      ),
      isFalse,
    );
  });

  test('snapshots the allowlist against replacement, addition and removal', () {
    final keys = <String, String>{
      'retained': _rfcPublicKey,
      'replaced': _rfcPublicKey,
    };
    final immutable = ResearchP256SignatureVerifier(publicKeysSec1Hex: keys);
    keys.remove('retained');
    keys['replaced'] = _fixturePublicKey;
    keys['added'] = _rfcPublicKey;

    for (final issuer in <String>['retained', 'replaced', 'added']) {
      expect(
        immutable.verify(
          issuerKeyId: issuer,
          canonicalPayload: 'sample',
          signature: _sampleSignature,
        ),
        issuer == 'added' ? isFalse : isTrue,
        reason: issuer,
      );
    }
  });

  for (final offset in <int>[0, 31, 32, 63]) {
    test('rejects a signature bit flip at byte $offset', () {
      final bytes = base64Decode(_sampleSignature);
      bytes[offset] ^= 1;
      expect(
        verifier.verify(
          issuerKeyId: 'rfc-6979',
          canonicalPayload: 'sample',
          signature: base64Encode(bytes),
        ),
        isFalse,
      );
    });
  }

  final rawSample = base64Decode(_sampleSignature);
  final malformedSignatures = <String, String>{
    'empty': '',
    'invalid alphabet': '${'!' * 86}==',
    '63 bytes': base64Encode(rawSample.sublist(0, 63)),
    '65 bytes': base64Encode(<int>[...rawSample, 0]),
    '66 bytes': base64Encode(<int>[...rawSample, 0, 0]),
    'oversized': 'A' * 4096,
    'DER encoded': base64Encode(<int>[
      0x30,
      0x46,
      0x02,
      0x21,
      0,
      ...rawSample.sublist(0, 32),
      0x02,
      0x21,
      0,
      ...rawSample.sublist(32),
    ]),
    'unpadded': _sampleSignature.substring(0, 86),
    'partially padded': _sampleSignature.substring(0, 87),
    'extra padding': '$_sampleSignature=',
    'base64url plus': _sampleSignature.replaceAll('+', '-'),
    'base64url slash': _testSignature.replaceAll('/', '_'),
    'percent escape': _sampleSignature.replaceAll('+', '%2B'),
    'escaped padding': _sampleSignature.replaceAll('=', '%3D'),
    'leading whitespace': ' $_sampleSignature',
    'trailing newline': '$_sampleSignature\n',
    'embedded whitespace': _sampleSignature.replaceFirst('K', ' '),
    'nonzero pad bits': '${_sampleSignature.substring(0, 85)}B==',
  };
  for (final entry in malformedSignatures.entries) {
    test('rejects malformed signature: ${entry.key}', () {
      expect(
        verifier.verify(
          issuerKeyId: 'rfc-6979',
          canonicalPayload: entry.key == 'base64url slash' ? 'test' : 'sample',
          signature: entry.value,
        ),
        isFalse,
      );
    });
  }

  final order = BigInt.parse(_orderHex, radix: 16);
  for (final offset in <int>[0, 32]) {
    for (final scalar in <BigInt>[
      BigInt.zero,
      order,
      order + BigInt.one,
      (BigInt.one << 256) - BigInt.one,
    ]) {
      test('rejects out-of-range scalar at $offset: $scalar', () {
        final bytes = base64Decode(_sampleSignature);
        final hex = scalar.toRadixString(16).padLeft(64, '0');
        for (var i = 0; i < 32; i++) {
          bytes[offset + i] = int.parse(
            hex.substring(i * 2, i * 2 + 2),
            radix: 16,
          );
        }
        expect(
          verifier.verify(
            issuerKeyId: 'rfc-6979',
            canonicalPayload: 'sample',
            signature: base64Encode(bytes),
          ),
          isFalse,
        );
      });
    }
  }

  for (final key in <String>[
    _rfcPublicKey.toLowerCase(),
    _rfcPublicKey.toUpperCase(),
  ]) {
    test('accepts hexadecimal case ${key.substring(2, 10)}', () {
      final configured = ResearchP256SignatureVerifier(
        publicKeysSec1Hex: {'issuer': key},
      );
      expect(
        configured.verify(
          issuerKeyId: 'issuer',
          canonicalPayload: 'sample',
          signature: _sampleSignature,
        ),
        isTrue,
      );
    });
  }

  final malformedKeys = <String, String>{
    'empty': '',
    'infinity': '00',
    'padded infinity': '00${'0' * 128}',
    'short': _rfcPublicKey.substring(0, 128),
    'odd length': _rfcPublicKey.substring(0, 129),
    'long': '${_rfcPublicKey}00',
    'oversized': '04${'0' * 4096}',
    'compressed': '03${_rfcPublicKey.substring(2, 66)}',
    'hybrid even': '06${_rfcPublicKey.substring(2)}',
    'hybrid odd': '07${_rfcPublicKey.substring(2)}',
    'unknown prefix': '05${_rfcPublicKey.substring(2)}',
    'nonhex': '04GG${_rfcPublicKey.substring(4)}',
    'signed byte': '04+0${_rfcPublicKey.substring(4)}',
    'leading whitespace': ' $_rfcPublicKey',
    'trailing newline': '$_rfcPublicKey\n',
    'hex prefix': '0x$_rfcPublicKey',
    'off curve zero': '04${'0' * 128}',
    'off curve altered y': '${_rfcPublicKey.substring(0, 128)}98',
    'x equals field prime': '04$_primeHex${_rfcPublicKey.substring(66)}',
    'y equals field prime': '${_rfcPublicKey.substring(0, 66)}$_primeHex',
    'x greater than field prime': '04${'F' * 64}${_rfcPublicKey.substring(66)}',
    'y greater than field prime':
        '${_rfcPublicKey.substring(0, 66)}${'F' * 64}',
    'secp256k1 point':
        '0479BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798'
        '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8',
  };
  for (final entry in malformedKeys.entries) {
    test('disables invalid public key without throwing: ${entry.key}', () {
      final configured = ResearchP256SignatureVerifier(
        publicKeysSec1Hex: {'invalid': entry.value, 'valid': _rfcPublicKey},
      );
      expect(
        configured.verify(
          issuerKeyId: 'invalid',
          canonicalPayload: 'sample',
          signature: _sampleSignature,
        ),
        isFalse,
      );
      expect(
        configured.verify(
          issuerKeyId: 'valid',
          canonicalPayload: 'sample',
          signature: _sampleSignature,
        ),
        isTrue,
      );
    });
  }

  test('accepts a literal Unicode replacement character', () {
    expect(
      verifier.verify(
        issuerKeyId: 'fixture-2026',
        canonicalPayload: 'permit:\uFFFD',
        signature: _replacementCharacterSignature,
      ),
      isTrue,
    );
  });

  for (final surrogate in <String>['\uD800', '\uDC00']) {
    test('rejects unpaired surrogate ${surrogate.codeUnitAt(0)}', () {
      expect(
        verifier.verify(
          issuerKeyId: 'fixture-2026',
          canonicalPayload: 'permit:$surrogate',
          signature: _replacementCharacterSignature,
        ),
        isFalse,
      );
    });
  }
}
