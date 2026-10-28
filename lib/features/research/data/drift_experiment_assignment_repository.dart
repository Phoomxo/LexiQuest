import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../adventure/domain/adventure_entry.dart';
import '../../consent/data/drift_research_consent_repository.dart';
import '../../consent/domain/research_consent.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../application/research_participation_permit_validator.dart';
import '../domain/ed25519_research_permit_signature_verifier.dart';
import '../domain/experiment_assignment.dart';
import '../domain/experiment_assignment_admission.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_participation_permit.dart';
import '../domain/research_trusted_time.dart';
import 'research_p256_signature_verifier.dart';

final class DriftExperimentAssignmentRepository {
  DriftExperimentAssignmentRepository(
    this._database, {
    required this.binding,
    required this.authorizer,
    required this.trustedTime,
    required this.participationDocuments,
    required this.participationValidator,
    required this.consent,
    required this.ownerWrites,
  }) {
    final study = binding.study;
    final pins = authorizer.requirements;
    if (!identical(authorizer.trustedTime, trustedTime) ||
        authorizer.nowUtc != null ||
        authorizer.verifier is! Ed25519ResearchPermitSignatureVerifier ||
        pins.signatureAlgorithm !=
            Ed25519ResearchPermitSignatureVerifier.algorithm ||
        participationValidator.signatures is! ResearchP256SignatureVerifier ||
        !identical(consent.database, _database) ||
        !identical(ownerWrites.database, _database) ||
        participationValidator.protocolId != study.protocolId ||
        participationValidator.protocolVersion != study.protocolVersion ||
        pins.protocolId != study.protocolId ||
        pins.protocolRevision != binding.protocolRevision ||
        pins.instrumentId != study.instrument.instrumentId ||
        pins.instrumentRevision != binding.instrumentRevision ||
        pins.assignmentRevision != binding.assignmentRevision) {
      throw ArgumentError('Inconsistent research admission authorities');
    }
  }

  final AppDatabase _database;
  final ExperimentAssignmentAdmissionBinding binding;
  final SignedPermitResearchOperationAuthorizer authorizer;
  final ResearchTrustedTimeSource trustedTime;
  final ResearchParticipationDocumentSource participationDocuments;
  final ResearchParticipationPermitValidator participationValidator;
  final DriftResearchConsentRepository consent;
  final DriftOwnerWriteCoordinator ownerWrites;

  Future<ExperimentAssignment?> admit({
    required String ownerId,
    required ResearchParticipationPermit participationPermit,
  }) async => (await admitWithReceipt(
    ownerId: ownerId,
    participationPermit: participationPermit,
  ))?.assignment;

  Future<AuthorizedExperimentAssignment?> admitWithReceipt({
    required String ownerId,
    required ResearchParticipationPermit participationPermit,
  }) async {
    final study = binding.study;
    if (ownerId.isEmpty ||
        ownerId != ownerId.trim() ||
        ownerId.runes.length > 256 ||
        ownerId.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'))) {
      return null;
    }
    final id = experimentAssignmentId(
      ownerId: ownerId,
      experimentId: study.experimentId,
      experimentVersion: study.experimentVersion,
    );
    if (participationPermit.ownerId != ownerId ||
        participationPermit.assignmentId != id ||
        authorizer.requirements.assignmentId != id) {
      return null;
    }
    if (await _checkAuthorities(ownerId, id, participationPermit) == null) {
      return null;
    }
    try {
      return await ownerWrites.writeForActiveOwner(
        expectedOwnerId: ownerId,
        write: () async {
          final proof = await _checkAuthorities(
            ownerId,
            id,
            participationPermit,
          );
          if (proof == null) return null;
          final localConsent = await consent.load(
            ownerId: ownerId,
            version: study.consentVersion,
          );
          final rows = await _database
              .customSelect(
                'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
                'protocol_version, assigned_at_utc_ms FROM experiment_assignments '
                'WHERE owner_id = ? AND experiment_id = ? AND experiment_version = ?',
                variables: [
                  Variable<String>(ownerId),
                  Variable<String>(study.experimentId),
                  Variable<int>(study.experimentVersion),
                ],
              )
              .get();
          if (rows.length > 1) _conflict(ownerId);
          if (rows.isEmpty) {
            final collision = await _database
                .customSelect(
                  'SELECT id FROM experiment_assignments WHERE id = ?',
                  variables: [Variable<String>(id)],
                )
                .getSingleOrNull();
            if (collision != null) _conflict(ownerId);
          }

          // Recheck after the last local read as well as after authority awaits.
          final now = await _trustedNow();
          if (now == null ||
              !_proofIsCurrent(proof, participationPermit, ownerId, id, now) ||
              !_consentIsCurrent(localConsent, ownerId, now)) {
            return null;
          }
          final cohort = proof.participation.assignedTreatment.wireName;
          if (rows.isNotEmpty) {
            final row = rows.single.data;
            final assignedAt = row['assigned_at_utc_ms'];
            if (row['id'] != id ||
                row['owner_id'] != ownerId ||
                row['experiment_id'] != study.experimentId ||
                row['experiment_version'] != study.experimentVersion ||
                row['cohort'] != cohort ||
                row['protocol_version'] != study.protocolVersion ||
                assignedAt is! int ||
                assignedAt < 0 ||
                assignedAt > 8640000000000000 ||
                assignedAt > now.millisecondsSinceEpoch ||
                assignedAt <
                    localConsent.decidedAtUtc!.millisecondsSinceEpoch) {
              _conflict(ownerId);
            }
            return AuthorizedExperimentAssignment._(
              assignment: ExperimentAssignment(
                id: id,
                ownerId: ownerId,
                experimentId: study.experimentId,
                experimentVersion: study.experimentVersion,
                cohort: cohort,
                protocolVersion: study.protocolVersion,
                assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                  assignedAt,
                  isUtc: true,
                ),
              ),
              operation: proof.operation,
            );
          }
          final assignedAt = _milliseconds(now);
          await _database.customInsert(
            'INSERT INTO experiment_assignments '
            '(id, owner_id, experiment_id, experiment_version, cohort, '
            'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
            variables: [
              Variable<String>(id),
              Variable<String>(ownerId),
              Variable<String>(study.experimentId),
              Variable<int>(study.experimentVersion),
              Variable<String>(cohort),
              Variable<String>(study.protocolVersion),
              Variable<int>(assignedAt.millisecondsSinceEpoch),
            ],
          );
          return AuthorizedExperimentAssignment._(
            assignment: ExperimentAssignment(
              id: id,
              ownerId: ownerId,
              experimentId: study.experimentId,
              experimentVersion: study.experimentVersion,
              cohort: cohort,
              protocolVersion: study.protocolVersion,
              assignedAtUtc: assignedAt,
            ),
            operation: proof.operation,
          );
        },
      );
    } on AccountDeletionException {
      return null;
    }
  }

  Future<_AdmissionProof?> _checkAuthorities(
    String ownerId,
    String assignmentId,
    ResearchParticipationPermit candidate,
  ) async {
    try {
      final before = await _trustedNow();
      if (before == null) return null;
      final current = await participationDocuments.loadCurrent(
        ownerId: ownerId,
        permitId: candidate.id,
      );
      if (current == null || !_sameSignedDocument(candidate, current)) {
        return null;
      }
      final validated = await participationValidator.validate(
        current,
        expectedOwnerId: ownerId,
        expectedAssignmentId: assignmentId,
        evaluatedAtUtc: _milliseconds(before),
      );
      if (!validated.isActive) return null;
      final operation = await authorizer.authorizeWithReceipt(
        ownerId: ownerId,
        operation: ResearchOperation.collect,
      );
      if (operation == null) return null;
      final latest = await participationDocuments.loadCurrent(
        ownerId: ownerId,
        permitId: candidate.id,
      );
      if (latest == null || !_sameSignedDocument(current, latest)) return null;
      final proof = _AdmissionProof(
        participation: latest,
        operation: operation,
      );
      final now = await _trustedNow();
      return now != null &&
              _proofIsCurrent(proof, candidate, ownerId, assignmentId, now)
          ? proof
          : null;
    } on Object {
      return null;
    }
  }

  bool _proofIsCurrent(
    _AdmissionProof proof,
    ResearchParticipationPermit candidate,
    String ownerId,
    String assignmentId,
    DateTime now,
  ) {
    final participation = proof.participation;
    final operation = proof.operation.permit;
    final pins = authorizer.requirements;
    return _sameSignedDocument(candidate, participation) &&
        participation.ownerId == ownerId &&
        participation.assignmentId == assignmentId &&
        !participation.isDeleted &&
        !now.isBefore(participation.issuedAtUtc) &&
        now.isBefore(participation.expiresAtUtc) &&
        (participation.revokedAtUtc == null ||
            now.isBefore(participation.revokedAtUtc!)) &&
        operation.ownerId == ownerId &&
        operation.operation == ResearchOperation.collect &&
        operation.assignmentId == assignmentId &&
        operation.assignmentRevision == binding.assignmentRevision &&
        operation.protocolId == binding.study.protocolId &&
        operation.protocolRevision == binding.protocolRevision &&
        operation.instrumentId == binding.study.instrument.instrumentId &&
        operation.instrumentRevision == binding.instrumentRevision &&
        operation.formatVersion == pins.supportedFormatVersion &&
        operation.issuerId == pins.trustedIssuerId &&
        operation.issuerKeyId == pins.trustedIssuerKeyId &&
        operation.signatureAlgorithm == pins.signatureAlgorithm &&
        _canonicalTime(operation.issuedAtUtc) &&
        _canonicalTime(operation.expiresAtUtc) &&
        !now.isBefore(operation.issuedAtUtc) &&
        now.isBefore(operation.expiresAtUtc) &&
        !proof.operation.verifiedAtUtc.isAfter(now);
  }

  bool _consentIsCurrent(
    ResearchConsentStatus value,
    String ownerId,
    DateTime now,
  ) =>
      value.ownerId == ownerId &&
      value.version == binding.study.consentVersion &&
      value.accepted &&
      value.withdrawnAtUtc == null &&
      value.decidedAtUtc != null &&
      value.decidedAtUtc!.isUtc &&
      value.decidedAtUtc!.millisecondsSinceEpoch >= 0 &&
      !value.decidedAtUtc!.isAfter(now);

  Future<DateTime?> _trustedNow() async {
    try {
      final reading = await trustedTime.read();
      if (reading == null || !reading.isFresh) return null;
      final now = reading.effectiveNowUtc;
      return now.isUtc && now.microsecondsSinceEpoch >= 0 ? now : null;
    } on Object {
      return null;
    }
  }

  Never _conflict(String ownerId) => throw ExperimentAssignmentConflict(
    ownerId: ownerId,
    experimentId: binding.study.experimentId,
    experimentVersion: binding.study.experimentVersion,
  );

  static bool _sameSignedDocument(
    ResearchParticipationPermit a,
    ResearchParticipationPermit b,
  ) =>
      a.canonicalPayload() == b.canonicalPayload() &&
      a.payloadSha256 == b.payloadSha256 &&
      a.signature == b.signature;

  static DateTime _milliseconds(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value.millisecondsSinceEpoch,
        isUtc: true,
      );

  static bool _canonicalTime(DateTime value) =>
      value.isUtc &&
      value.microsecondsSinceEpoch >= 0 &&
      value.microsecondsSinceEpoch % 1000 == 0;
}

/// This admission's checked result, not authority for a later operation.
final class AuthorizedExperimentAssignment {
  const AuthorizedExperimentAssignment._({
    required this.assignment,
    required this.operation,
  });

  final ExperimentAssignment assignment;
  final AuthorizedResearchOperation operation;
}

final class _AdmissionProof {
  const _AdmissionProof({required this.participation, required this.operation});
  final ResearchParticipationPermit participation;
  final AuthorizedResearchOperation operation;
}
