import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';

void main() {
  test(
    'a permit expiring while authority state is loaded is rejected',
    () async {
      final issuedAt = DateTime.utc(2026, 10, 28);
      var now = issuedAt;
      final permit = ResearchPermit(
        formatVersion: 1,
        permitId: 'synthetic-permit',
        issuerId: 'synthetic-issuer',
        issuerKeyId: 'synthetic-key',
        signatureAlgorithm: 'ed25519',
        ownerId: 'synthetic-owner',
        operation: ResearchOperation.export,
        assignmentId: 'synthetic-assignment',
        assignmentRevision: 1,
        protocolId: 'synthetic-protocol',
        protocolRevision: 1,
        instrumentId: 'synthetic-instrument',
        instrumentRevision: 1,
        revision: 1,
        issuedAtUtc: issuedAt,
        expiresAtUtc: issuedAt.add(const Duration(seconds: 1)),
        signature: [1],
      );
      final authorizer = SignedPermitResearchOperationAuthorizer(
        permits: _SyntheticPermitSource(permit),
        verifier: _SyntheticVerifier(),
        states: _SyntheticStateSource(
          () => now = issuedAt.add(const Duration(seconds: 2)),
        ),
        nowUtc: () => now,
        requirements: const ResearchPermitRequirements(
          supportedFormatVersion: 1,
          trustedIssuerId: 'synthetic-issuer',
          trustedIssuerKeyId: 'synthetic-key',
          signatureAlgorithm: 'ed25519',
          assignmentId: 'synthetic-assignment',
          assignmentRevision: 1,
          protocolId: 'synthetic-protocol',
          protocolRevision: 1,
          instrumentId: 'synthetic-instrument',
          instrumentRevision: 1,
        ),
      );
      final allowed = await authorizer.authorize(
        ownerId: 'synthetic-owner',
        operation: ResearchOperation.export,
      );
      expect(now.isAfter(permit.expiresAtUtc), isTrue);
      expect(
        allowed,
        isFalse,
        reason: 'Authorization must use time at the final boundary.',
      );
    },
  );
}

class _SyntheticPermitSource implements ResearchPermitSource {
  _SyntheticPermitSource(this.permit);
  final ResearchPermit permit;
  @override
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  }) async => permit;
}

class _SyntheticStateSource implements ResearchPermitStateSource {
  _SyntheticStateSource(this.advanceTime);
  final void Function() advanceTime;
  @override
  Future<ResearchPermitState?> loadState({required String permitId}) async {
    advanceTime();
    return const ResearchPermitState(currentRevision: 1, revoked: false);
  }
}

class _SyntheticVerifier implements ResearchPermitSignatureVerifier {
  @override
  Future<bool> verify({
    required String algorithm,
    required String issuerKeyId,
    required Uint8List message,
    required Uint8List signature,
  }) async => true;
}
