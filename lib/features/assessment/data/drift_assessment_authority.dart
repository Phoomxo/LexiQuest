import 'dart:convert';

import 'package:drift/drift.dart';

import '../../adventure/domain/adventure_entry.dart';
import '../../research/application/research_participation_permit_validator.dart';
import '../../research/data/local_research_authority_cache.dart';
import '../../research/domain/experiment_assignment.dart';
import '../../research/domain/research_authority_snapshot.dart';
import '../../research/domain/research_operation_authorizer.dart';
import '../../research/domain/research_participation_permit.dart';
import '../../research/domain/research_permit_document.dart';
import '../domain/assessment_authority.dart';
import '../domain/assessment_instrument_catalog.dart';
import '../domain/assessment_models.dart';

/// Uses the five verified local cache ports. Refresh/network IO belongs outside
/// the owner transaction; an Assessment catalog is never a Motivation instrument.
final class DriftAssessmentAuthority implements AssessmentAuthority {
  const DriftAssessmentAuthority({required this.cache, required this.mapping});

  final LocalResearchAuthorityCache cache;
  final AssessmentAuthorityMapping mapping;

  @override
  Future<AssessmentAuthorityReceipt> requireCurrent({
    required ResearchAuthorityScope expectedScope,
    required AssessmentInstrumentDefinition definition,
    required String expectedParticipationPermitId,
    AssessmentRun? pinnedRun,
  }) {
    AssessmentRun.validateCanonicalText(
      expectedParticipationPermitId,
      'expectedParticipationPermitId',
    );
    mapping.requireMatches(
      scope: expectedScope,
      definition: definition,
      pinnedRun: pinnedRun,
    );
    final generation = cache.readGeneration;
    void requireScope() {
      if (cache.readGeneration != generation ||
          cache.currentScope() != expectedScope) {
        _deny();
      }
    }

    requireScope();
    final ownerId = expectedScope.binding.ownerId;
    return cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        requireScope();
        final initial = await _local(
          expectedScope,
          expectedParticipationPermitId,
        );
        requireScope();
        _requiredReceipts(
          initial.permit,
          expectedScope,
          initial.consentDecidedAtUtc,
        );
        final operation =
            await SignedPermitResearchOperationAuthorizer(
              permits: cache,
              states: cache,
              verifier: cache.operationSignatures,
              requirements: expectedScope.requirements,
              trustedTime: cache,
            ).authorizeWithReceipt(
              ownerId: ownerId,
              operation: ResearchOperation.collect,
            );
        requireScope();
        if (operation == null) _deny();
        final document = await cache.loadCurrent(
          ownerId: ownerId,
          permitId: expectedParticipationPermitId,
        );
        requireScope();
        if (document == null || !_samePermit(initial.permit, document)) _deny();
        final reading = await cache.read();
        requireScope();
        if (reading == null || !reading.isFresh) _deny();
        final validator = ResearchParticipationPermitValidator(
          protocolId: mapping.protocolId,
          protocolVersion: mapping.protocolVersion,
          signatures: cache.participationSignatures,
          receipts: cache,
        );
        final validation = await validator.validate(
          document,
          expectedOwnerId: ownerId,
          expectedAssignmentId: expectedScope.requirements.assignmentId,
          evaluatedAtUtc: reading.effectiveNowUtc,
        );
        requireScope();
        if (!validation.isActive) _deny();

        // Final SQL facts follow the asynchronous authorization. These reads
        // share the caller's owner transaction and never repair cached rows.
        final current = await _local(
          expectedScope,
          expectedParticipationPermitId,
        );
        requireScope();
        if (current.assignment != initial.assignment ||
            current.consentDecidedAtUtc != initial.consentDecidedAtUtc ||
            !_samePermit(current.permit, document)) {
          _deny();
        }
        final receipts = _requiredReceipts(
          document,
          expectedScope,
          current.consentDecidedAtUtc,
        );
        final finalTime = await cache.read();
        requireScope();
        if (finalTime == null || !finalTime.isFresh) _deny();
        final now = finalTime.effectiveNowUtc;
        final permit = operation.permit;
        if (now.isBefore(operation.verifiedAtUtc) ||
            receipts.any(
              (receipt) =>
                  !receipt.active ||
                  now.isBefore(receipt.issuedAtUtc) ||
                  !now.isBefore(receipt.expiresAtUtc),
            ) ||
            !now.isBefore(permit.expiresAtUtc) ||
            now.isBefore(document.issuedAtUtc) ||
            !now.isBefore(document.expiresAtUtc) ||
            (document.revokedAtUtc != null &&
                !now.isBefore(document.revokedAtUtc!)) ||
            current.consentDecidedAtUtc.isAfter(
              current.assignment.assignedAtUtc,
            ) ||
            current.assignment.assignedAtUtc.isAfter(now) ||
            (pinnedRun != null &&
                (pinnedRun.cohort != current.assignment.cohort ||
                    pinnedRun.consentDecidedAtUtc !=
                        current.consentDecidedAtUtc ||
                    pinnedRun.participationPermitId != document.id ||
                    pinnedRun.participationPermitRevision !=
                        document.localRevision ||
                    pinnedRun.participationPermitPayloadSha256 !=
                        document.payloadSha256 ||
                    pinnedRun.startedAtUtc.isAfter(now)))) {
          _deny();
        }
        return _AssessmentAuthorityReceipt(
          scope: expectedScope,
          mapping: mapping,
          assignment: current.assignment,
          consentDecidedAtUtc: current.consentDecidedAtUtc,
          operation: operation,
          participationPermitId: document.id,
          participationPermitRevision: document.localRevision,
          participationPermitPayloadSha256: document.payloadSha256,
          verifiedAtUtc: now,
          validUntilUtc: [
            permit.expiresAtUtc,
            document.expiresAtUtc,
            ...receipts.map((receipt) => receipt.expiresAtUtc),
            finalTime.validUntilUtc,
            now.add(finalTime.maximumAge - finalTime.age),
          ].reduce((a, b) => a.isBefore(b) ? a : b),
        );
      },
    );
  }

  List<ResearchAuthorityReceipt> _requiredReceipts(
    ResearchParticipationPermit document,
    ResearchAuthorityScope scope,
    DateTime consentDecidedAtUtc,
  ) {
    final receipts = <ResearchAuthorityReceipt>[];
    for (final ref in [
      (document.consentReceiptId, ResearchReceiptKind.consent),
      if (document.participantClass == ResearchParticipantClass.minor) ...[
        (
          document.guardianPermissionReceiptRef!,
          ResearchReceiptKind.guardianPermission,
        ),
        (document.learnerAssentReceiptRef!, ResearchReceiptKind.learnerAssent),
      ],
    ]) {
      final receipt = cache.inspectReceipt(
        ownerId: scope.binding.ownerId,
        receiptId: ref.$1,
        kind: ref.$2,
      );
      if (receipt == null ||
          (ref.$2 == ResearchReceiptKind.consent &&
              (receipt.consentVersion != scope.consentVersion ||
                  receipt.decidedAtUtc != consentDecidedAtUtc))) {
        _deny();
      }
      receipts.add(receipt);
    }
    return receipts;
  }

  Future<_LocalAuthority> _local(
    ResearchAuthorityScope scope,
    String permitId,
  ) async {
    final database = cache.ownerWrites.database;
    final ownerId = scope.binding.ownerId;
    final owners = await database
        .customSelect(
          'SELECT id, firebase_uid, account_state FROM local_owners WHERE is_active = 1',
        )
        .get();
    if (owners.length != 1 ||
        owners.single.data['id'] != ownerId ||
        owners.single.data['firebase_uid'] != scope.binding.authSubjectId ||
        owners.single.data['account_state'] != 'firebaseBound') {
      _deny();
    }
    final consent = await database
        .customSelect(
          'SELECT * FROM research_consents WHERE owner_id = ? AND consent_version = ?',
          variables: [
            Variable<String>(ownerId),
            Variable<int>(scope.consentVersion),
          ],
        )
        .getSingleOrNull();
    if (consent == null ||
        consent.data['consent_state'] != 'accepted' ||
        consent.data['withdrawn_at_utc_ms'] != null) {
      _deny();
    }
    final row = await database
        .customSelect(
          'SELECT * FROM experiment_assignments WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(scope.requirements.assignmentId),
            Variable<String>(ownerId),
          ],
        )
        .getSingleOrNull();
    if (row == null ||
        row.data['experiment_id'] != mapping.experimentId ||
        row.data['experiment_version'] != mapping.experimentVersion ||
        row.data['protocol_version'] != mapping.protocolVersion ||
        row.data['id'] !=
            experimentAssignmentId(
              ownerId: ownerId,
              experimentId: mapping.experimentId,
              experimentVersion: mapping.experimentVersion,
            )) {
      _deny();
    }
    final assignment = ExperimentAssignment(
      id: row.data['id']! as String,
      ownerId: ownerId,
      experimentId: mapping.experimentId,
      experimentVersion: mapping.experimentVersion,
      cohort: row.data['cohort']! as String,
      protocolVersion: mapping.protocolVersion,
      assignedAtUtc: _utc(row.data['assigned_at_utc_ms']),
    );
    final rows = await database
        .customSelect(
          'SELECT * FROM research_participation_permits WHERE owner_id = ? AND assignment_id = ?',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(assignment.id),
          ],
        )
        .get();
    final now = await cache.read();
    if (now == null || !now.isFresh) _deny();
    final candidates = rows
        .map((row) => _decodePermit(row.data))
        .where(
          (permit) =>
              permit.protocolId == mapping.protocolId &&
              permit.protocolVersion == mapping.protocolVersion &&
              !permit.isDeleted &&
              !now.effectiveNowUtc.isBefore(permit.issuedAtUtc) &&
              now.effectiveNowUtc.isBefore(permit.expiresAtUtc) &&
              (permit.revokedAtUtc == null ||
                  now.effectiveNowUtc.isBefore(permit.revokedAtUtc!)),
        )
        .toList();
    if (candidates.length != 1 ||
        candidates.single.id != permitId ||
        candidates.single.assignedTreatment.wireName != assignment.cohort) {
      _deny();
    }
    return _LocalAuthority(
      assignment,
      _utc(consent.data['decided_at_utc_ms']),
      candidates.single,
    );
  }

  static ResearchParticipationPermit _decodePermit(Map<String, Object?> row) =>
      decodeResearchPermitDocument(
        jsonEncode({
          'schema': 'lexiquest.research-participation-permit.v1',
          'id': row['id'],
          'ownerId': row['owner_id'],
          'participantClass': row['participant_class'],
          'ageBandCode': row['age_band_code'],
          'assignmentId': row['assignment_id'],
          'assignedTreatment': row['assigned_treatment'],
          'consentReceiptId': row['consent_receipt_id'],
          'guardianPermissionReceiptRef':
              row['guardian_permission_receipt_ref'],
          'learnerAssentReceiptRef': row['learner_assent_receipt_ref'],
          'protocolId': row['protocol_id'],
          'protocolVersion': row['protocol_version'],
          'issuedAtUtc': _utc(row['issued_at_utc_ms']).toIso8601String(),
          'expiresAtUtc': _utc(row['expires_at_utc_ms']).toIso8601String(),
          'revokedAtUtc': row['revoked_at_utc_ms'] == null
              ? null
              : _utc(row['revoked_at_utc_ms']).toIso8601String(),
          'issuerKeyId': row['issuer_key_id'],
          'payloadSha256': row['payload_sha256'],
          'signature': row['signature'],
          'localRevision': row['local_revision'],
          'cloudRevision': row['cloud_revision'],
          'isDeleted': switch (row['is_deleted']) {
            true || 1 => true,
            false || 0 => false,
            _ => throw const FormatException(
              'Invalid participation deletion state',
            ),
          },
        }),
      );

  static bool _samePermit(
    ResearchParticipationPermit a,
    ResearchParticipationPermit b,
  ) =>
      a.canonicalPayload() == b.canonicalPayload() &&
      a.payloadSha256 == b.payloadSha256 &&
      a.signature == b.signature;

  static DateTime _utc(Object? value) {
    if (value is! int || value < 0 || value > 8640000000000000) _deny();
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static Never _deny() =>
      throw StateError('Current Assessment authority is unavailable.');
}

final class _LocalAuthority {
  const _LocalAuthority(this.assignment, this.consentDecidedAtUtc, this.permit);
  final ExperimentAssignment assignment;
  final DateTime consentDecidedAtUtc;
  final ResearchParticipationPermit permit;
}

final class _AssessmentAuthorityReceipt implements AssessmentAuthorityReceipt {
  const _AssessmentAuthorityReceipt({
    required this.scope,
    required this.mapping,
    required this.assignment,
    required this.consentDecidedAtUtc,
    required this.operation,
    required this.participationPermitId,
    required this.participationPermitRevision,
    required this.participationPermitPayloadSha256,
    required this.verifiedAtUtc,
    required this.validUntilUtc,
  });
  @override
  final ResearchAuthorityScope scope;
  @override
  final AssessmentAuthorityMapping mapping;
  @override
  final ExperimentAssignment assignment;
  @override
  final DateTime consentDecidedAtUtc;
  @override
  final AuthorizedResearchOperation operation;
  @override
  final String participationPermitId;
  @override
  final int participationPermitRevision;
  @override
  final String participationPermitPayloadSha256;
  @override
  final DateTime verifiedAtUtc;
  @override
  final DateTime validUntilUtc;
}
