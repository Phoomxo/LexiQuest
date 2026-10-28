import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_document.dart';

// Synthetic canonical document independently signed and verified by .NET ECDsa,
// P-256/SHA-256/P1363. The ephemeral private key was disposed without export.
const _canonicalPayload =
    '{"schema":"lexiquest.research-participation-permit.v1",'
    '"id":"synthetic-permit-001","ownerId":"synthetic-owner-001",'
    '"participantClass":"adult","ageBandCode":"adult",'
    '"assignmentId":"synthetic-assignment-001","assignedTreatment":"adventure",'
    '"consentReceiptId":"synthetic-consent-001",'
    '"guardianPermissionReceiptRef":null,"learnerAssentReceiptRef":null,'
    '"protocolId":"synthetic-protocol","protocolVersion":"1.0.0",'
    '"issuedAtUtc":"2026-10-01T00:00:00.000Z",'
    '"expiresAtUtc":"2026-11-01T00:00:00.000Z","revokedAtUtc":null,'
    '"issuerKeyId":"synthetic-test-key","localRevision":1,'
    '"cloudRevision":1,"isDeleted":false}';
const _payloadSha256 =
    '1ca853e3e4e2578da3f65d70b26e53532b4cfc609e30c19906787a898c593954';
const _publicKey =
    '04'
    'ADBE42608B26E4BF062C44D9B0BEFC82EBB6BFC0E4933EC1BCE26FC082C69C4FD'
    'D1A0696164C93AA324FE375D1A6864B64370AED49DBDDD81571FD5B488D4A4E';
const _signature =
    'z+/3AdJpks+dzMEIEW2/LQoWW8KxGSujJtPEbcDZLClwCnHfL6M1c6G53f88HCO+'
    'qT2hJiFyTjuJ+ThZDfgoxA==';

void main() {
  late Map<String, dynamic> document;
  setUp(() {
    document = <String, dynamic>{
      ...jsonDecode(_canonicalPayload) as Map<String, dynamic>,
      'payloadSha256': _payloadSha256,
      'signature': _signature,
    };
  });

  test(
    'decoding preserves the exact signed schema and canonical field order',
    () {
      final permit = decodeResearchPermitDocument(jsonEncode(document));
      expect(permit.canonicalPayload(), _canonicalPayload);
      expect(permit.payloadSha256, _payloadSha256);
      expect(permit.signature, _signature);
      expect(
        sha256.convert(utf8.encode(permit.canonicalPayload())).toString(),
        _payloadSha256,
      );
    },
  );

  test(
    'the signed canonical fixture validates with the real P256 verifier',
    () async {
      final permit = decodeResearchPermitDocument(jsonEncode(document));
      final result = await _validateWithTrustedFixturePins(permit);
      expect(result.isActive, isTrue);
      expect(result.denialReason, ResearchPermitDenialReason.none);
      expect(result.activePermit?.ownerId, 'synthetic-owner-001');
      expect(result.activePermit?.assignmentId, 'synthetic-assignment-001');
      expect(
        result.activePermit?.assignedPresentation,
        TodayExperiencePresentation.adventure,
      );
    },
  );

  for (final change in <String, String>{
    'id': 'synthetic-permit-002',
    'ownerId': 'synthetic-owner-002',
    'assignmentId': 'synthetic-assignment-002',
    'assignedTreatment': 'standard',
    'protocolId': 'synthetic-protocol-2',
    'protocolVersion': '2.0.0',
    'consentReceiptId': 'synthetic-consent-002',
    'ageBandCode': 'adult-2',
    'issuedAtUtc': '2026-10-02T00:00:00.000Z',
    'expiresAtUtc': '2026-11-02T00:00:00.000Z',
  }.entries) {
    test(
      'a rehashed change to signed ${change.key} cannot grant participation',
      () async {
        document[change.key] = change.value;
        final changedPayload = Map<String, dynamic>.of(document)
          ..remove('payloadSha256')
          ..remove('signature');
        document['payloadSha256'] = sha256
            .convert(utf8.encode(jsonEncode(changedPayload)))
            .toString();
        final permit = decodeResearchPermitDocument(jsonEncode(document));
        // Bind the changed pins deliberately so signature verification rejects it.
        final result = await _validateWithTrustedFixturePins(permit);
        expect(result.activePermit, isNull);
        expect(
          result.denialReason,
          ResearchPermitDenialReason.invalidSignature,
        );
      },
    );
  }

  for (final invalid in <Object?>[null, [], 1, true, 'text']) {
    test('rejects non-object document $invalid', () {
      expect(
        () => decodeResearchPermitDocument(jsonEncode(invalid)),
        throwsFormatException,
      );
    });
  }

  test(
    'rejects unknown, missing, malformed, noncanonical or private fields',
    () {
      final changes = <void Function(Map<String, dynamic>)>[
        (d) => d['guardianName'] = 'SYNTHETIC_PRIVATE',
        (d) => d.remove('isDeleted'),
        (d) => d['localRevision'] = 1.5,
        (d) => d['cloudRevision'] = 0,
        (d) => d['ownerId'] = ' synthetic-owner-001',
        (d) => d['ownerId'] = 'synthetic@example.invalid',
        (d) => d['issuedAtUtc'] = '2026-10-01T07:00:00+07:00',
        (d) => d['issuedAtUtc'] = '2026-10-01T00:00:00.000001Z',
        (d) => d['participantClass'] = 'unknown',
        (d) => d['assignedTreatment'] = 'unknown',
        (d) => d['schema'] = 'lexiquest.research-operation-permit.v1',
        (d) => d['isDeleted'] = 0,
        (d) => d['payloadSha256'] = _payloadSha256.toUpperCase(),
        (d) => d['signature'] = '',
        (d) => d['signature'] = 'A' * 257,
      ];
      for (final change in changes) {
        final modified = Map<String, dynamic>.of(document);
        change(modified);
        expect(
          () => decodeResearchPermitDocument(jsonEncode(modified)),
          throwsFormatException,
        );
      }
      expect(
        () => decodeResearchPermitDocument(' ' * 16385),
        throwsFormatException,
      );
      expect(
        () => decodeResearchPermitDocument('ก' * 6000),
        throwsFormatException,
      );
    },
  );

  test('parse errors never echo the submitted document', () {
    try {
      decodeResearchPermitDocument('{"secret":"SYNTHETIC_PRIVATE"');
      fail('expected failure');
    } catch (error) {
      expect(error, isA<FormatException>());
      expect('$error', isNot(contains('SYNTHETIC_PRIVATE')));
    }
  });
}

Future<ResearchPermitValidationResult> _validateWithTrustedFixturePins(
  ResearchParticipationPermit permit,
) =>
    ResearchParticipationPermitValidator(
      protocolId: permit.protocolId,
      protocolVersion: permit.protocolVersion,
      signatures: ResearchP256SignatureVerifier(
        publicKeysSec1Hex: {'synthetic-test-key': _publicKey},
      ),
      receipts: const _SyntheticReceiptAuthority(),
    ).validate(
      permit,
      expectedOwnerId: permit.ownerId,
      expectedAssignmentId: permit.assignmentId,
      evaluatedAtUtc: DateTime.utc(2026, 10, 15),
    );

final class _SyntheticReceiptAuthority implements ResearchReceiptAuthority {
  const _SyntheticReceiptAuthority();

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async =>
      ownerId == 'synthetic-owner-001' &&
      receiptId == 'synthetic-consent-001' &&
      kind == ResearchReceiptKind.consent &&
      evaluatedAtUtc == DateTime.utc(2026, 10, 15);
}
