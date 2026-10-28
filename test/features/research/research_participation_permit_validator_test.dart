import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

void main() {
  final now = DateTime.utc(2026, 9, 4, 10);

  test(
    'RSH-016 valid adult permit creates only the active projection',
    () async {
      final receipts = _Receipts(<String>{'consent-001'});
      final permit = _permit();
      final validator = _validator(receipts: receipts);

      final result = await validator.validate(
        permit,
        expectedOwnerId: 'owner-001',
        expectedAssignmentId: 'assignment-001',
        evaluatedAtUtc: now,
      );

      expect(result.isActive, isTrue);
      expect(result.denialReason, ResearchPermitDenialReason.none);
      expect(result.activePermit?.permitId, 'permit-001');
      expect(
        result.activePermit?.assignedPresentation,
        TodayExperiencePresentation.adventure,
      );
      expect(result.activePermit?.assignmentId, 'assignment-001');
      expect(receipts.verifiedKinds, <ResearchReceiptKind>{
        ResearchReceiptKind.consent,
      });
    },
  );

  test(
    'RSH-017 valid minor requires verified guardian and assent refs',
    () async {
      final receipts = _Receipts(<String>{
        'consent-001',
        'guardian-001',
        'assent-001',
      });
      final result = await _validator(receipts: receipts).validate(
        _permit(
          participantClass: ResearchParticipantClass.minor,
          guardianPermissionReceiptRef: 'guardian-001',
          learnerAssentReceiptRef: 'assent-001',
        ),
        expectedOwnerId: 'owner-001',
        expectedAssignmentId: 'assignment-001',
        evaluatedAtUtc: now,
      );

      expect(result.isActive, isTrue);
      expect(receipts.verifiedKinds, <ResearchReceiptKind>{
        ResearchReceiptKind.consent,
        ResearchReceiptKind.guardianPermission,
        ResearchReceiptKind.learnerAssent,
      });
    },
  );

  for (final scenario
      in <
        ({
          String id,
          ResearchParticipationPermit permit,
          ResearchPermitDenialReason reason,
        })
      >[
        (
          id: 'RSH-018',
          permit: _permit(participantClass: ResearchParticipantClass.minor),
          reason: ResearchPermitDenialReason.guardianPermissionUnavailable,
        ),
        (
          id: 'RSH-019',
          permit: _permit(
            participantClass: ResearchParticipantClass.minor,
            guardianPermissionReceiptRef: 'guardian-001',
          ),
          reason: ResearchPermitDenialReason.learnerAssentUnavailable,
        ),
      ]) {
    test('${scenario.id} missing minor authority fails closed', () async {
      final result =
          await _validator(
            receipts: _Receipts(<String>{
              'consent-001',
              'guardian-001',
              'assent-001',
            }),
          ).validate(
            scenario.permit,
            expectedOwnerId: 'owner-001',
            expectedAssignmentId: 'assignment-001',
            evaluatedAtUtc: now,
          );

      expect(result.activePermit, isNull);
      expect(result.denialReason, scenario.reason);
    });
  }

  group('RSH-020 permit mismatch matrix fails closed', () {
    final cases =
        <
          ({
            String name,
            ResearchParticipationPermit permit,
            String owner,
            String assignment,
            ResearchPermitDenialReason reason,
            bool signatureAccepted,
          })
        >[
          (
            name: 'signature',
            permit: _permit(signature: 'bad-signature'),
            owner: 'owner-001',
            assignment: 'assignment-001',
            reason: ResearchPermitDenialReason.invalidSignature,
            signatureAccepted: false,
          ),
          (
            name: 'owner',
            permit: _permit(),
            owner: 'owner-002',
            assignment: 'assignment-001',
            reason: ResearchPermitDenialReason.ownerMismatch,
            signatureAccepted: true,
          ),
          (
            name: 'assignment',
            permit: _permit(),
            owner: 'owner-001',
            assignment: 'assignment-002',
            reason: ResearchPermitDenialReason.assignmentMismatch,
            signatureAccepted: true,
          ),
          (
            name: 'protocol',
            permit: _permit(protocolVersion: '2.0.0'),
            owner: 'owner-001',
            assignment: 'assignment-001',
            reason: ResearchPermitDenialReason.protocolMismatch,
            signatureAccepted: true,
          ),
          (
            name: 'expiry',
            permit: _permit(expiresAtUtc: DateTime.utc(2026, 9, 4, 9)),
            owner: 'owner-001',
            assignment: 'assignment-001',
            reason: ResearchPermitDenialReason.expired,
            signatureAccepted: true,
          ),
          (
            name: 'revocation',
            permit: _permit(revokedAtUtc: DateTime.utc(2026, 9, 4, 8)),
            owner: 'owner-001',
            assignment: 'assignment-001',
            reason: ResearchPermitDenialReason.revoked,
            signatureAccepted: true,
          ),
          (
            name: 'revision',
            permit: _permit(localRevision: 2, cloudRevision: 1),
            owner: 'owner-001',
            assignment: 'assignment-001',
            reason: ResearchPermitDenialReason.revisionMismatch,
            signatureAccepted: true,
          ),
        ];

    for (final item in cases) {
      test(item.name, () async {
        final result =
            await _validator(
              receipts: _Receipts(<String>{'consent-001'}),
              signatureAccepted: item.signatureAccepted,
            ).validate(
              item.permit,
              expectedOwnerId: item.owner,
              expectedAssignmentId: item.assignment,
              evaluatedAtUtc: now,
            );

        expect(result.activePermit, isNull);
        expect(result.denialReason, item.reason);
      });
    }
  });

  for (final scenario in [
    (
      name: 'not yet issued',
      permit: _permit(issuedAtUtc: now.add(const Duration(seconds: 1))),
      reason: ResearchPermitDenialReason.notYetValid,
    ),
    (
      name: 'expiry boundary',
      permit: _permit(expiresAtUtc: now),
      reason: ResearchPermitDenialReason.expired,
    ),
    (
      name: 'deleted signed state',
      permit: _permit(isDeleted: true),
      reason: ResearchPermitDenialReason.deleted,
    ),
    (
      name: 'changed digest',
      permit: _permit().copyWith(payloadSha256: '0' * 64),
      reason: ResearchPermitDenialReason.payloadMismatch,
    ),
  ]) {
    test('rejects ${scenario.name} without an active projection', () async {
      final result = await _validator(receipts: _Receipts({'consent-001'}))
          .validate(
            scenario.permit,
            expectedOwnerId: 'owner-001',
            expectedAssignmentId: 'assignment-001',
            evaluatedAtUtc: now,
          );
      expect(result.activePermit, isNull);
      expect(result.denialReason, scenario.reason);
    });
  }

  test(
    'authentic expired state remains importable without participation',
    () async {
      final validator = _validator(receipts: _Receipts({}));
      final permit = _permit(expiresAtUtc: now);
      expect(
        validator.validateAuthenticity(
          permit,
          expectedOwnerId: 'owner-001',
          expectedAssignmentId: 'assignment-001',
          evaluatedAtUtc: now,
        ),
        ResearchPermitDenialReason.none,
      );
      final result = await validator.validate(
        permit,
        expectedOwnerId: 'owner-001',
        expectedAssignmentId: 'assignment-001',
        evaluatedAtUtc: now,
      );
      expect(result.activePermit, isNull);
      expect(result.denialReason, ResearchPermitDenialReason.expired);
    },
  );

  test('non-UTC caller time cannot grant participation', () async {
    final result = await _validator(receipts: _Receipts({'consent-001'}))
        .validate(
          _permit(),
          expectedOwnerId: 'owner-001',
          expectedAssignmentId: 'assignment-001',
          evaluatedAtUtc: DateTime(2026, 9, 4, 10),
        );
    expect(result.activePermit, isNull);
    expect(result.denialReason, ResearchPermitDenialReason.invalidInput);
  });

  test(
    'receipt revocation during lookup is caught by the second pass',
    () async {
      final receipts = _RevokingReceipts();
      final result = await _validator(receipts: receipts).validate(
        _permit(),
        expectedOwnerId: 'owner-001',
        expectedAssignmentId: 'assignment-001',
        evaluatedAtUtc: now,
      );
      expect(receipts.calls, 2);
      expect(result.activePermit, isNull);
      expect(
        result.denialReason,
        ResearchPermitDenialReason.consentUnavailable,
      );
    },
  );

  test('signature authority is rechecked after receipt lookups', () async {
    final signatures = _RevokingSignatures();
    final result =
        await _validator(
          receipts: _Receipts({'consent-001'}),
          signatures: signatures,
        ).validate(
          _permit(),
          expectedOwnerId: 'owner-001',
          expectedAssignmentId: 'assignment-001',
          evaluatedAtUtc: now,
        );
    expect(signatures.calls, 2);
    expect(result.activePermit, isNull);
    expect(result.denialReason, ResearchPermitDenialReason.invalidSignature);
  });

  test('unavailable signature authority fails closed', () async {
    final result =
        await _validator(
          receipts: _Receipts({'consent-001'}),
          signatures: const _ThrowingSignatures(),
        ).validate(
          _permit(),
          expectedOwnerId: 'owner-001',
          expectedAssignmentId: 'assignment-001',
          evaluatedAtUtc: now,
        );
    expect(result.activePermit, isNull);
    expect(result.denialReason, ResearchPermitDenialReason.invalidSignature);
  });

  test('unavailable receipt authority fails closed', () async {
    final result = await _validator(receipts: const _ThrowingReceipts())
        .validate(
          _permit(),
          expectedOwnerId: 'owner-001',
          expectedAssignmentId: 'assignment-001',
          evaluatedAtUtc: now,
        );
    expect(result.activePermit, isNull);
    expect(result.denialReason, ResearchPermitDenialReason.consentUnavailable);
  });
}

ResearchParticipationPermitValidator _validator({
  required ResearchReceiptAuthority receipts,
  bool signatureAccepted = true,
  ResearchParticipationSignatureVerifier? signatures,
}) => ResearchParticipationPermitValidator(
  protocolId: 'amm-pilot',
  protocolVersion: '1.0.0',
  signatures: signatures ?? _Signatures(signatureAccepted),
  receipts: receipts,
);

ResearchParticipationPermit _permit({
  ResearchParticipantClass participantClass = ResearchParticipantClass.adult,
  String? guardianPermissionReceiptRef,
  String? learnerAssentReceiptRef,
  String protocolVersion = '1.0.0',
  DateTime? issuedAtUtc,
  DateTime? expiresAtUtc,
  DateTime? revokedAtUtc,
  String signature = 'signature-001',
  int localRevision = 1,
  int cloudRevision = 1,
  bool isDeleted = false,
}) {
  final unsigned = ResearchParticipationPermit(
    id: 'permit-001',
    ownerId: 'owner-001',
    participantClass: participantClass,
    ageBandCode: participantClass == ResearchParticipantClass.minor
        ? '13-17'
        : '18+',
    assignmentId: 'assignment-001',
    assignedTreatment: TodayExperiencePresentation.adventure,
    consentReceiptId: 'consent-001',
    guardianPermissionReceiptRef: guardianPermissionReceiptRef,
    learnerAssentReceiptRef: learnerAssentReceiptRef,
    protocolId: 'amm-pilot',
    protocolVersion: protocolVersion,
    issuedAtUtc: issuedAtUtc ?? DateTime.utc(2026, 9, 1),
    expiresAtUtc: expiresAtUtc ?? DateTime.utc(2026, 10, 1),
    revokedAtUtc: revokedAtUtc,
    issuerKeyId: 'research-key-001',
    payloadSha256: 'pending',
    signature: signature,
    localRevision: localRevision,
    cloudRevision: cloudRevision,
    isDeleted: isDeleted,
  );
  return unsigned.copyWith(
    payloadSha256: sha256
        .convert(utf8.encode(unsigned.canonicalPayload()))
        .toString(),
  );
}

final class _Signatures implements ResearchParticipationSignatureVerifier {
  const _Signatures(this.accepted);

  final bool accepted;

  @override
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  }) => accepted && signature == 'signature-001';
}

final class _Receipts implements ResearchReceiptAuthority {
  _Receipts(this.activeReceiptIds);

  final Set<String> activeReceiptIds;
  final Set<ResearchReceiptKind> verifiedKinds = <ResearchReceiptKind>{};

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    verifiedKinds.add(kind);
    return ownerId == 'owner-001' && activeReceiptIds.contains(receiptId);
  }
}

final class _RevokingSignatures
    implements ResearchParticipationSignatureVerifier {
  int calls = 0;

  @override
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  }) => ++calls == 1;
}

final class _ThrowingSignatures
    implements ResearchParticipationSignatureVerifier {
  const _ThrowingSignatures();

  @override
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  }) => throw StateError('synthetic signature authority unavailable');
}

final class _RevokingReceipts implements ResearchReceiptAuthority {
  int calls = 0;

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async => ++calls == 1;
}

final class _ThrowingReceipts implements ResearchReceiptAuthority {
  const _ThrowingReceipts();

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async => throw StateError('synthetic receipt authority unavailable');
}
