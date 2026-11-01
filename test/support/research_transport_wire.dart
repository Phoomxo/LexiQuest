import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/research/data/http_research_authority_gateway.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';

Map<String, Object?> researchAuthorityWire(
  ServerAttestedResearchAuthorityPacket packet,
  Object? scope,
) => {
  'schemaVersion': 1,
  'scope': scope,
  'requestId': packet.requestId,
  'clockSessionId': packet.clockSessionId,
  'monotonicEpoch': packet.monotonicEpoch,
  'snapshotRevision': packet.snapshotRevision,
  'anchorUtc': packet.anchorUtc.toIso8601String(),
  'validUntilUtc': packet.validUntilUtc.toIso8601String(),
  'maximumAgeMs': packet.maximumAge.inMilliseconds,
  'operationDocuments': [
    for (final bytes in packet.operationDocuments) base64.encode(bytes),
  ],
  'operationStates': {
    for (final entry in packet.operationStates.entries)
      entry.key: {
        'currentRevision': entry.value.currentRevision,
        'revoked': entry.value.revoked,
      },
  },
  'participationDocuments': packet.participationDocuments,
  'receipts': [
    for (final receipt in packet.receipts)
      {
        'ownerId': receipt.ownerId,
        'receiptId': receipt.receiptId,
        'kind': receipt.kind.name,
        'revision': receipt.revision,
        'active': receipt.active,
        'issuedAtUtc': receipt.issuedAtUtc.toIso8601String(),
        'expiresAtUtc': receipt.expiresAtUtc.toIso8601String(),
        'consentVersion': receipt.consentVersion,
        'decidedAtUtc': receipt.decidedAtUtc?.toIso8601String(),
      },
  ],
};

/// Explicit synthetic HTTP boundary around the existing real signed fixtures.
/// No socket, enrollment, database write or production key is involved.
final class SyntheticHttpResearchAuthorityGateway
    implements ResearchAuthorityGateway {
  SyntheticHttpResearchAuthorityGateway({
    required this.inner,
    required this.currentBinding,
  });
  final ResearchAuthorityGateway inner;
  final ResearchAuthorityBinding? Function() currentBinding;
  int requests = 0;

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    final client = MockClient((httpRequest) async {
      requests++;
      final body = jsonDecode(httpRequest.body) as Map<String, dynamic>;
      final packet = await inner.fetchCurrent(request);
      return http.Response(
        packet == null
            ? '{}'
            : jsonEncode(researchAuthorityWire(packet, body['scope'])),
        packet == null ? 503 : 200,
        headers: {'content-type': 'application/json'},
      );
    });
    try {
      return await HttpResearchTransport(
        client: client,
        baseUri: Uri.https('synthetic-research.invalid'),
        currentBinding: currentBinding,
        loadIdToken: (_) async => 'synthetic-test-token',
      ).fetchCurrent(request);
    } finally {
      client.close();
    }
  }
}
