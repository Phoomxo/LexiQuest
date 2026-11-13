import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';

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
  signature: Uint8List.fromList([1, 2, 3, 4]),
);

SignedPermitResearchOperationAuthorizer _authorizer({
  required ResearchPermit permit,
  ResearchPermitRequirements? requirements,
  ResearchPermitState? state = _activeState,
  _PermitStateSource? stateSource,
  _SignatureVerifier? verifier,
  required DateTime now,
}) => SignedPermitResearchOperationAuthorizer(
  permits: _PermitSource(permit),
  states: stateSource ?? _PermitStateSource(state),
  verifier: verifier ?? _SignatureVerifier(),
  requirements: requirements ?? _requirements(),
  nowUtc: () => now,
);

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
