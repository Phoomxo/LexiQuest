import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/ed25519_research_permit_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_json_codec.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_trusted_time.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);

  test('valid signed permit authorizes the exact pinned operation', () async {
    final verifier = _SignatureVerifier();
    final authorizer = _authorizer(
      permit: _permit(),
      verifier: verifier,
      now: now,
    );

    expect(
      await authorizer.authorize(
        ownerId: 'owner-a',
        operation: ResearchOperation.export,
      ),
      isTrue,
    );
    expect(verifier.calls, 1);
    expect(verifier.algorithms, ['synthetic-signature-v1']);
    expect(verifier.issuerKeyIds, ['issuer-key-1']);
    expect(verifier.signatures.single, [1, 2, 3, 4]);
    expect(
      utf8.decode(verifier.messages.single),
      '{"formatVersion":1,"permitId":"permit-1","issuerId":"issuer-1",'
      '"issuerKeyId":"issuer-key-1",'
      '"signatureAlgorithm":"synthetic-signature-v1","ownerId":"owner-a",'
      '"operation":"export","assignmentId":"assignment-1",'
      '"assignmentRevision":3,"protocolId":"protocol-1",'
      '"protocolRevision":5,"instrumentId":"instrument-1",'
      '"instrumentRevision":7,"revision":2,'
      '"issuedAtUtcMs":1792800000000,"expiresAtUtcMs":1792886400000}',
    );
  });

  group('canonical permit JSON', () {
    const codec = ResearchPermitJsonCodec();

    test('encodes and decodes the one canonical representation', () {
      final permit = _permit(
        signature: List<int>.generate(64, (index) => index),
      );
      final encoded = codec.encode(permit);

      expect(
        utf8.decode(encoded),
        '{"formatVersion":1,"permitId":"permit-1","issuerId":"issuer-1",'
        '"issuerKeyId":"issuer-key-1","signatureAlgorithm":"synthetic-signature-v1",'
        '"ownerId":"owner-a","operation":"export",'
        '"assignmentId":"assignment-1","assignmentRevision":3,'
        '"protocolId":"protocol-1","protocolRevision":5,'
        '"instrumentId":"instrument-1","instrumentRevision":7,'
        '"revision":2,"issuedAtUtcMs":1792800000000,'
        '"expiresAtUtcMs":1792886400000,'
        '"signature":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-Pw"}',
      );
      final decoded = codec.decode(encoded);
      expect(decoded.signedPayload(), permit.signedPayload());
      expect(decoded.signature, permit.signature);
    });

    for (final invalid in <String, String Function(String)>{
      'leading whitespace': (json) => ' $json',
      'unknown field': (json) => json.replaceFirst(
        '"formatVersion":1',
        '"unknown":0,"formatVersion":1',
      ),
      'wrong field type': (json) =>
          json.replaceFirst('"formatVersion":1', '"formatVersion":"1"'),
      'padded signature': (json) => json.replaceFirst('Pw"}', 'Pw=="}'),
    }.entries) {
      test('rejects ${invalid.key}', () {
        final canonical = utf8.decode(
          codec.encode(
            _permit(signature: List<int>.generate(64, (index) => index)),
          ),
        );

        expect(
          () => codec.decode(
            Uint8List.fromList(utf8.encode(invalid.value(canonical))),
          ),
          throwsFormatException,
        );
      });
    }

    test('normalizes out-of-range timestamps to FormatException', () {
      final canonical = utf8.decode(
        codec.encode(
          _permit(signature: List<int>.generate(64, (index) => index)),
        ),
      );

      expect(
        () => codec.decode(
          Uint8List.fromList(
            utf8.encode(
              canonical.replaceFirst(
                '"issuedAtUtcMs":1792800000000',
                '"issuedAtUtcMs":9000000000000001',
              ),
            ),
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('Ed25519 permit signature verifier', () {
    final publicKey = _hex(
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
    );
    final signature = _hex(
      'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
      '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
    );

    test('accepts RFC 8032 test vector 1', () async {
      final verifier = Ed25519ResearchPermitSignatureVerifier({
        'rfc8032-key-1': publicKey,
      });

      expect(
        await verifier.verify(
          algorithm: Ed25519ResearchPermitSignatureVerifier.algorithm,
          issuerKeyId: 'rfc8032-key-1',
          message: Uint8List(0),
          signature: signature,
        ),
        isTrue,
      );
    });

    test(
      'rejects tampering, wrong key, algorithm, and malformed lengths',
      () async {
        final verifier = Ed25519ResearchPermitSignatureVerifier({
          'good': publicKey,
          'wrong': _hex(
            '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
          ),
          'short': publicKey.sublist(1),
        });

        Future<bool> verify({
          String algorithm = Ed25519ResearchPermitSignatureVerifier.algorithm,
          String keyId = 'good',
          Uint8List? message,
          Uint8List? candidateSignature,
        }) => verifier.verify(
          algorithm: algorithm,
          issuerKeyId: keyId,
          message: message ?? Uint8List(0),
          signature: candidateSignature ?? signature,
        );

        expect(await verify(message: Uint8List.fromList([0])), isFalse);
        expect(
          await verify(
            candidateSignature: Uint8List.fromList(signature)..[0] ^= 1,
          ),
          isFalse,
        );
        expect(await verify(keyId: 'wrong'), isFalse);
        expect(await verify(algorithm: 'Ed25519'), isFalse);
        expect(await verify(candidateSignature: signature.sublist(1)), isFalse);
        expect(await verify(keyId: 'short'), isFalse);
        expect(await verify(keyId: 'missing'), isFalse);
      },
    );

    test('rejects identity public key and identity R forgery', () async {
      final identity = Uint8List(32)..[0] = 1;
      final forgedSignature = Uint8List(64)..[0] = 1;
      final verifier = Ed25519ResearchPermitSignatureVerifier({
        'weak': identity,
      });

      expect(
        await verifier.verify(
          algorithm: Ed25519ResearchPermitSignatureVerifier.algorithm,
          issuerKeyId: 'weak',
          message: Uint8List.fromList(utf8.encode('forged permit')),
          signature: forgedSignature,
        ),
        isFalse,
      );
    });
  });

  group('trusted time', () {
    test('fresh trusted time permits the normal authorization path', () async {
      final authorizer = _authorizer(
        permit: _permit(),
        trustedTime: _TrustedTimeSource(
          ResearchTrustedTime(
            anchorUtc: now,
            validUntilUtc: now.add(const Duration(minutes: 1)),
            age: const Duration(seconds: 1),
            maximumAge: const Duration(minutes: 1),
          ),
        ),
      );

      expect(
        await authorizer.authorize(
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        isTrue,
      );
    });

    for (final entry in <String, ResearchTrustedTime?>{
      'unavailable': null,
      'expired lease': ResearchTrustedTime(
        anchorUtc: now,
        validUntilUtc: now,
        age: Duration.zero,
        maximumAge: const Duration(minutes: 1),
      ),
      'stale cached record': ResearchTrustedTime(
        anchorUtc: now,
        validUntilUtc: now.add(const Duration(days: 1)),
        age: const Duration(days: 2),
        maximumAge: const Duration(minutes: 1),
      ),
    }.entries) {
      test(
        '${entry.key} trusted time fails closed before permit reads',
        () async {
          final permitSource = _PermitSource(_permit());
          final authorizer = SignedPermitResearchOperationAuthorizer(
            permits: permitSource,
            states: _PermitStateSource(_activeState),
            verifier: _SignatureVerifier(),
            requirements: _requirements(),
            trustedTime: _TrustedTimeSource(entry.value),
          );

          expect(
            await authorizer.authorize(
              ownerId: 'owner-a',
              operation: ResearchOperation.export,
            ),
            isFalse,
          );
          expect(permitSource.calls, 0);
        },
      );
    }

    test('cache age advances trusted time past permit expiry', () async {
      final authorizer = _authorizer(
        permit: _permit(expiresAtUtc: now.add(const Duration(seconds: 30))),
        trustedTime: _TrustedTimeSource(
          ResearchTrustedTime(
            anchorUtc: now,
            validUntilUtc: now.add(const Duration(minutes: 1)),
            age: const Duration(seconds: 50),
            maximumAge: const Duration(minutes: 1),
          ),
        ),
      );

      expect(
        await authorizer.authorize(
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        isFalse,
      );
    });

    test('cache age advances trusted time to the lease boundary', () {
      final reading = ResearchTrustedTime(
        anchorUtc: now,
        validUntilUtc: now.add(const Duration(minutes: 1)),
        age: const Duration(minutes: 1),
        maximumAge: const Duration(minutes: 2),
      );

      expect(reading.isFresh, isFalse);
    });

    test('requires exactly one clock authority at runtime', () {
      SignedPermitResearchOperationAuthorizer build({
        DateTime Function()? nowUtc,
        ResearchTrustedTimeSource? trustedTime,
      }) => SignedPermitResearchOperationAuthorizer(
        permits: _PermitSource(_permit()),
        states: _PermitStateSource(_activeState),
        verifier: _SignatureVerifier(),
        requirements: _requirements(),
        nowUtc: nowUtc,
        trustedTime: trustedTime,
      );

      expect(() => build(), throwsArgumentError);
      expect(
        () => build(
          nowUtc: () => now,
          trustedTime: _TrustedTimeSource(
            ResearchTrustedTime(
              anchorUtc: now,
              validUntilUtc: now.add(const Duration(minutes: 1)),
              age: Duration.zero,
              maximumAge: const Duration(minutes: 1),
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  final mismatches =
      <
        String,
        ({
          ResearchPermit permit,
          ResearchPermitRequirements requirements,
          String ownerId,
          ResearchOperation operation,
        })
      >{
        'owner': (
          permit: _permit(ownerId: 'owner-b'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'operation': (
          permit: _permit(operation: ResearchOperation.collect),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'assignment id': (
          permit: _permit(assignmentId: 'assignment-other'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'assignment revision': (
          permit: _permit(assignmentRevision: 4),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'protocol id': (
          permit: _permit(protocolId: 'protocol-other'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'protocol revision': (
          permit: _permit(protocolRevision: 6),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'instrument id': (
          permit: _permit(instrumentId: 'instrument-other'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'instrument revision': (
          permit: _permit(instrumentRevision: 8),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'issuer': (
          permit: _permit(issuerId: 'issuer-other'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'issuer key': (
          permit: _permit(issuerKeyId: 'issuer-key-other'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'signature algorithm': (
          permit: _permit(signatureAlgorithm: 'other-signature'),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'format version': (
          permit: _permit(formatVersion: 2),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'future issue time': (
          permit: _permit(
            issuedAtUtc: now.add(const Duration(milliseconds: 1)),
          ),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'expiry boundary': (
          permit: _permit(expiresAtUtc: now),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'non-positive revision': (
          permit: _permit(revision: 0),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        'blank permit id': (
          permit: _permit(permitId: ' '),
          requirements: _requirements(),
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
      };

  for (final entry in mismatches.entries) {
    test('denies a signed permit with mismatched ${entry.key}', () async {
      final verifier = _SignatureVerifier();
      final value = entry.value;
      final authorizer = _authorizer(
        permit: value.permit,
        requirements: value.requirements,
        verifier: verifier,
        now: now,
      );

      expect(
        await authorizer.authorize(
          ownerId: value.ownerId,
          operation: value.operation,
        ),
        isFalse,
      );
      expect(verifier.calls, 0);
    });
  }

  for (final stateCase in <String, ResearchPermitState?>{
    'missing status': null,
    'stale revision': const ResearchPermitState(
      currentRevision: 3,
      revoked: false,
    ),
    'revoked status': const ResearchPermitState(
      currentRevision: 2,
      revoked: true,
    ),
  }.entries) {
    test('denies ${stateCase.key}', () async {
      final authorizer = _authorizer(
        permit: _permit(),
        state: stateCase.value,
        now: now,
      );

      expect(
        await authorizer.authorize(
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        isFalse,
      );
    });
  }

  test('denies missing permits before signature or status reads', () async {
    final permitSource = _PermitSource(null);
    final stateSource = _PermitStateSource(_activeState);
    final verifier = _SignatureVerifier();
    final authorizer = SignedPermitResearchOperationAuthorizer(
      permits: permitSource,
      states: stateSource,
      verifier: verifier,
      requirements: _requirements(),
      nowUtc: () => now,
    );

    expect(
      await authorizer.authorize(
        ownerId: 'owner-a',
        operation: ResearchOperation.export,
      ),
      isFalse,
    );
    expect(stateSource.calls, 0);
    expect(verifier.calls, 0);
  });

  test('denies an invalid signature before consulting live state', () async {
    final stateSource = _PermitStateSource(_activeState);
    final authorizer = _authorizer(
      permit: _permit(),
      stateSource: stateSource,
      verifier: _SignatureVerifier(valid: false),
      now: now,
    );

    expect(
      await authorizer.authorize(
        ownerId: 'owner-a',
        operation: ResearchOperation.export,
      ),
      isFalse,
    );
    expect(stateSource.calls, 0);
  });

  test('authority dependency failures are fail closed', () async {
    for (final failurePoint in ['permit', 'signature', 'state']) {
      final permitSource = _PermitSource(_permit())
        ..failure = failurePoint == 'permit'
            ? StateError('private-permit')
            : null;
      final verifier = _SignatureVerifier()
        ..failure = failurePoint == 'signature'
            ? StateError('private-signature')
            : null;
      final stateSource = _PermitStateSource(
        _activeState,
      )..failure = failurePoint == 'state' ? StateError('private-state') : null;
      final authorizer = SignedPermitResearchOperationAuthorizer(
        permits: permitSource,
        states: stateSource,
        verifier: verifier,
        requirements: _requirements(),
        nowUtc: () => now,
      );

      expect(
        await authorizer.authorize(
          ownerId: 'owner-a',
          operation: ResearchOperation.export,
        ),
        isFalse,
        reason: failurePoint,
      );
    }
  });
}

const _activeState = ResearchPermitState(currentRevision: 2, revoked: false);

ResearchPermitRequirements _requirements() => const ResearchPermitRequirements(
  supportedFormatVersion: 1,
  trustedIssuerId: 'issuer-1',
  trustedIssuerKeyId: 'issuer-key-1',
  signatureAlgorithm: 'synthetic-signature-v1',
  assignmentId: 'assignment-1',
  assignmentRevision: 3,
  protocolId: 'protocol-1',
  protocolRevision: 5,
  instrumentId: 'instrument-1',
  instrumentRevision: 7,
);

ResearchPermit _permit({
  int formatVersion = 1,
  String permitId = 'permit-1',
  String issuerId = 'issuer-1',
  String issuerKeyId = 'issuer-key-1',
  String signatureAlgorithm = 'synthetic-signature-v1',
  String ownerId = 'owner-a',
  ResearchOperation operation = ResearchOperation.export,
  String assignmentId = 'assignment-1',
  int assignmentRevision = 3,
  String protocolId = 'protocol-1',
  int protocolRevision = 5,
  String instrumentId = 'instrument-1',
  int instrumentRevision = 7,
  int revision = 2,
  DateTime? issuedAtUtc,
  DateTime? expiresAtUtc,
  List<int> signature = const [1, 2, 3, 4],
}) => ResearchPermit(
  formatVersion: formatVersion,
  permitId: permitId,
  issuerId: issuerId,
  issuerKeyId: issuerKeyId,
  signatureAlgorithm: signatureAlgorithm,
  ownerId: ownerId,
  operation: operation,
  assignmentId: assignmentId,
  assignmentRevision: assignmentRevision,
  protocolId: protocolId,
  protocolRevision: protocolRevision,
  instrumentId: instrumentId,
  instrumentRevision: instrumentRevision,
  revision: revision,
  issuedAtUtc: issuedAtUtc ?? DateTime.utc(2026, 10, 24, 0),
  expiresAtUtc: expiresAtUtc ?? DateTime.utc(2026, 10, 25, 0),
  signature: signature,
);

SignedPermitResearchOperationAuthorizer _authorizer({
  required ResearchPermit permit,
  ResearchPermitRequirements? requirements,
  ResearchPermitState? state = _activeState,
  _PermitStateSource? stateSource,
  _SignatureVerifier? verifier,
  DateTime? now,
  ResearchTrustedTimeSource? trustedTime,
}) => SignedPermitResearchOperationAuthorizer(
  permits: _PermitSource(permit),
  states: stateSource ?? _PermitStateSource(state),
  verifier: verifier ?? _SignatureVerifier(),
  requirements: requirements ?? _requirements(),
  nowUtc: trustedTime == null ? () => now! : null,
  trustedTime: trustedTime,
);

final class _TrustedTimeSource implements ResearchTrustedTimeSource {
  _TrustedTimeSource(this.value);

  final ResearchTrustedTime? value;

  @override
  Future<ResearchTrustedTime?> read() async => value;
}

final class _PermitSource implements ResearchPermitSource {
  _PermitSource(this.permit);

  ResearchPermit? permit;
  Object? failure;
  int calls = 0;

  @override
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  }) async {
    calls++;
    if (failure case final error?) throw error;
    return permit;
  }
}

final class _PermitStateSource implements ResearchPermitStateSource {
  _PermitStateSource(this.state);

  ResearchPermitState? state;
  Object? failure;
  int calls = 0;

  @override
  Future<ResearchPermitState?> loadState({required String permitId}) async {
    calls++;
    if (failure case final error?) throw error;
    return state;
  }
}

final class _SignatureVerifier implements ResearchPermitSignatureVerifier {
  _SignatureVerifier({this.valid = true});

  bool valid;
  Object? failure;
  int calls = 0;
  final issuerKeyIds = <String>[];
  final algorithms = <String>[];
  final messages = <Uint8List>[];
  final signatures = <Uint8List>[];

  @override
  Future<bool> verify({
    required String algorithm,
    required String issuerKeyId,
    required Uint8List message,
    required Uint8List signature,
  }) async {
    calls++;
    if (failure case final error?) throw error;
    algorithms.add(algorithm);
    issuerKeyIds.add(issuerKeyId);
    messages.add(Uint8List.fromList(message));
    signatures.add(Uint8List.fromList(signature));
    return valid;
  }
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);
