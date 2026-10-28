import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../adventure/domain/adventure_entry.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../application/research_participation_permit_validator.dart';
import '../domain/experiment_assignment.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_participation_permit.dart';
import 'drift_experiment_assignment_repository.dart';

final class ResearchParticipantSnapshot {
  const ResearchParticipantSnapshot(this.permit, this.assignment, this.consent);
  final ResearchParticipationPermit permit;
  final ExperimentAssignment assignment;
  final db.ResearchConsent consent;
}

/// Database-backed, fail-closed participation authority. Call mutations inside
/// a database transaction; the owner write fence serializes concurrent changes.
final class DriftResearchParticipationRepository
    implements ActivePresentationPermitReader {
  DriftResearchParticipationRepository(
    this.database, {
    required this.study,
    required this.validator,
    required this.nowUtc,
  }) {
    if (validator.protocolId != study.protocolId ||
        validator.protocolVersion != study.protocolVersion) {
      throw const FormatException('Validator protocol mismatch');
    }
  }
  final db.AppDatabase database;
  final MotivationStudyProtocol study;
  final ResearchParticipationPermitValidator validator;
  final DateTime Function() nowUtc;

  Future<void> lockOwner(String ownerId) async {
    requireResearchCode(ownerId);
    final now = nowUtc();
    requireResearchUtc(now);
    final changed = await database.customUpdate(
      'UPDATE local_owners SET is_active = is_active WHERE id = ? AND is_active = 1',
      variables: [Variable<String>(ownerId)],
      updates: {database.localOwners},
    );
    final active = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).get();
    if (changed != 1 ||
        active.length != 1 ||
        active.single.id != ownerId ||
        await DriftOwnerOperationGate(
          database,
        ).isOwnerFenced(ownerId: ownerId, nowUtc: now)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.ownerConflict);
    }
  }

  Future<ResearchParticipantSnapshot> _localContext(
    ResearchParticipationPermit permit,
  ) async {
    await lockOwner(permit.ownerId);
    final consent =
        await (database.select(database.researchConsents)..where(
              (row) =>
                  row.ownerId.equals(permit.ownerId) &
                  row.consentVersion.equals(study.consentVersion),
            ))
            .getSingleOrNull();
    if (consent == null ||
        consent.consentState != 'accepted' ||
        consent.withdrawnAtUtcMs != null ||
        consent.decidedAtUtcMs > permit.issuedAtUtc.millisecondsSinceEpoch) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.withdrawn);
    }
    ExperimentAssignment assignment;
    try {
      assignment = await DriftExperimentAssignmentRepository(database)
          .getAssignment(
            experimentId: study.experimentId,
            experimentVersion: study.experimentVersion,
            ownerId: permit.ownerId,
          );
    } on Object {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
    if (assignment.id != permit.assignmentId ||
        assignment.cohort != permit.assignedTreatment.name ||
        assignment.protocolVersion != study.protocolVersion ||
        assignment.assignedAtUtc.millisecondsSinceEpoch <
            consent.decidedAtUtcMs ||
        assignment.assignedAtUtc.isAfter(permit.issuedAtUtc)) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
    return ResearchParticipantSnapshot(permit, assignment, consent);
  }

  Future<void> _validate(ResearchParticipationPermit permit) async {
    try {
      final result = await validator.validate(
        permit,
        expectedOwnerId: permit.ownerId,
        expectedAssignmentId: permit.assignmentId,
        evaluatedAtUtc: nowUtc(),
      );
      if (!result.isActive) {
        throw ResearchCaptureDenied(switch (result.denialReason) {
          ResearchPermitDenialReason.expired =>
            ResearchCaptureReason.expiredPermit,
          ResearchPermitDenialReason.revoked =>
            ResearchCaptureReason.revokedPermit,
          _ => ResearchCaptureReason.invalidPermit,
        });
      }
    } on ResearchCaptureDenied {
      rethrow;
    } on Object {
      throw const ResearchCaptureDenied(ResearchCaptureReason.invalidPermit);
    }
    // An asynchronous receipt lookup may cross an expiry boundary.
    final now = nowUtc();
    requireResearchUtc(now);
    if (now.isBefore(permit.issuedAtUtc) ||
        !now.isBefore(permit.expiresAtUtc) ||
        (permit.revokedAtUtc != null && !now.isBefore(permit.revokedAtUtc!))) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.expiredPermit);
    }
  }

  Future<void> importPermit(
    ResearchParticipationPermit permit,
  ) => database.transaction(() async {
    for (final code in [
      permit.id,
      permit.ownerId,
      permit.ageBandCode,
      permit.assignmentId,
      permit.consentReceiptId,
      permit.issuerKeyId,
      ?permit.guardianPermissionReceiptRef,
      ?permit.learnerAssentReceiptRef,
    ]) {
      requireResearchCode(code);
    }
    await lockOwner(permit.ownerId);
    final existing = await (database.select(
      database.researchParticipationPermits,
    )..where((row) => row.id.equals(permit.id))).getSingleOrNull();
    final authenticity = validator.validateAuthenticity(
      permit,
      expectedOwnerId: existing?.ownerId ?? permit.ownerId,
      expectedAssignmentId: existing?.assignmentId ?? permit.assignmentId,
      evaluatedAtUtc: nowUtc(),
    );
    if (authenticity != ResearchPermitDenialReason.none) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.invalidPermit);
    }
    final inactiveUpdate = permit.revokedAtUtc != null || permit.isDeleted;
    if (existing != null) {
      final previous = permitFromRow(existing);
      if (!_sameImmutablePins(previous, permit) ||
          permit.localRevision < previous.localRevision ||
          (previous.isDeleted && !permit.isDeleted) ||
          (previous.revokedAtUtc != null &&
              permit.revokedAtUtc != previous.revokedAtUtc)) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.identityConflict,
        );
      }
      if (permit.localRevision == previous.localRevision &&
          (previous.canonicalPayload() != permit.canonicalPayload() ||
              previous.payloadSha256 != permit.payloadSha256 ||
              previous.signature != permit.signature)) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.identityConflict,
        );
      }
    } else if (inactiveUpdate) {
      // An issuer's revocation can narrow existing participation, never enroll.
      throw const ResearchCaptureDenied(ResearchCaptureReason.noPermit);
    }
    if (!inactiveUpdate) {
      await _localContext(permit);
      await _validate(permit);
      await _localContext(permit);
    }
    // Reconcile the row after receipt authority awaits, before updating a revision.
    final current = await (database.select(
      database.researchParticipationPermits,
    )..where((row) => row.id.equals(permit.id))).getSingleOrNull();
    if (current != existing) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
    await lockOwner(permit.ownerId);
    if (existing != null && existing.localRevision == permit.localRevision) {
      return;
    }
    final other =
        await (database.select(database.researchParticipationPermits)..where(
              (row) =>
                  row.ownerId.equals(permit.ownerId) &
                  row.id.equals(permit.id).not() &
                  row.protocolId.equals(study.protocolId) &
                  row.protocolVersion.equals(study.protocolVersion) &
                  row.isDeleted.equals(false) &
                  row.expiresAtUtcMs.isBiggerThanValue(
                    nowUtc().millisecondsSinceEpoch,
                  ) &
                  row.revokedAtUtcMs.isNull(),
            ))
            .get();
    if (!inactiveUpdate && other.isNotEmpty) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.identityConflict);
    }
    final imported = db.ResearchParticipationPermitsCompanion.insert(
      id: permit.id,
      ownerId: permit.ownerId,
      participantClass: permit.participantClass.name,
      ageBandCode: permit.ageBandCode,
      assignmentId: permit.assignmentId,
      assignedTreatment: permit.assignedTreatment.name,
      consentReceiptId: permit.consentReceiptId,
      guardianPermissionReceiptRef: Value(permit.guardianPermissionReceiptRef),
      learnerAssentReceiptRef: Value(permit.learnerAssentReceiptRef),
      protocolId: permit.protocolId,
      protocolVersion: permit.protocolVersion,
      issuedAtUtcMs: permit.issuedAtUtc.millisecondsSinceEpoch,
      expiresAtUtcMs: permit.expiresAtUtc.millisecondsSinceEpoch,
      revokedAtUtcMs: Value(permit.revokedAtUtc?.millisecondsSinceEpoch),
      issuerKeyId: permit.issuerKeyId,
      payloadSha256: permit.payloadSha256,
      signature: permit.signature,
      localRevision: Value(permit.localRevision),
      cloudRevision: Value(permit.cloudRevision),
      isDeleted: Value(permit.isDeleted),
    );
    if (existing == null) {
      await database
          .into(database.researchParticipationPermits)
          .insert(imported);
    } else {
      // Revisions are issuer-signed fields, copied verbatim rather than incremented.
      final changed =
          await (database.update(database.researchParticipationPermits)..where(
                (row) =>
                    row.id.equals(permit.id) &
                    row.ownerId.equals(permit.ownerId) &
                    row.localRevision.equals(existing.localRevision),
              ))
              .write(imported);
      if (changed != 1) {
        throw const ResearchCaptureDenied(
          ResearchCaptureReason.identityConflict,
        );
      }
    }
  });

  Future<ResearchParticipantSnapshot> requireParticipant(
    String ownerId,
    String permitId,
  ) async {
    await lockOwner(ownerId);
    final row =
        await (database.select(database.researchParticipationPermits)..where(
              (row) => row.id.equals(permitId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.noPermit);
    }
    final permit = permitFromRow(row);
    await _localContext(permit);
    await _validate(permit);
    final current = await (database.select(
      database.researchParticipationPermits,
    )..where((row) => row.id.equals(permitId))).getSingleOrNull();
    if (current == null || current != row) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.invalidPermit);
    }
    return _localContext(permit);
  }

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    try {
      requireResearchUtc(evaluatedAtUtc);
      return await database.transaction(() async {
        final permits =
            await (database.select(database.researchParticipationPermits)
                  ..where(
                    (row) =>
                        row.ownerId.equals(ownerId) &
                        row.protocolId.equals(study.protocolId) &
                        row.protocolVersion.equals(study.protocolVersion) &
                        row.isDeleted.equals(false) &
                        row.revokedAtUtcMs.isNull() &
                        row.issuedAtUtcMs.isSmallerOrEqualValue(
                          evaluatedAtUtc.millisecondsSinceEpoch,
                        ) &
                        row.expiresAtUtcMs.isBiggerThanValue(
                          evaluatedAtUtc.millisecondsSinceEpoch,
                        ),
                  ))
                .get();
        if (permits.length != 1) return null;
        final context = await requireParticipant(ownerId, permits.single.id);
        final p = context.permit;
        return ActivePresentationPermit(
          permitId: p.id,
          ownerId: p.ownerId,
          assignedPresentation: p.assignedTreatment,
          protocolId: p.protocolId,
          protocolVersion: p.protocolVersion,
          assignmentId: p.assignmentId,
          expiresAtUtc: p.expiresAtUtc,
        );
      });
    } on Object {
      return null;
    }
  }
}

bool _sameImmutablePins(
  ResearchParticipationPermit previous,
  ResearchParticipationPermit next,
) =>
    previous.id == next.id &&
    previous.ownerId == next.ownerId &&
    previous.assignmentId == next.assignmentId &&
    previous.protocolId == next.protocolId &&
    previous.protocolVersion == next.protocolVersion &&
    previous.assignedTreatment == next.assignedTreatment &&
    previous.participantClass == next.participantClass &&
    previous.ageBandCode == next.ageBandCode &&
    previous.consentReceiptId == next.consentReceiptId &&
    previous.guardianPermissionReceiptRef ==
        next.guardianPermissionReceiptRef &&
    previous.learnerAssentReceiptRef == next.learnerAssentReceiptRef &&
    previous.issuedAtUtc == next.issuedAtUtc;

ResearchParticipationPermit permitFromRow(
  db.ResearchParticipationPermitRow row,
) => ResearchParticipationPermit(
  id: row.id,
  ownerId: row.ownerId,
  participantClass: ResearchParticipantClass.values.byName(
    row.participantClass,
  ),
  ageBandCode: row.ageBandCode,
  assignmentId: row.assignmentId,
  assignedTreatment: TodayExperiencePresentationCodec.decode(
    row.assignedTreatment,
  ),
  consentReceiptId: row.consentReceiptId,
  guardianPermissionReceiptRef: row.guardianPermissionReceiptRef,
  learnerAssentReceiptRef: row.learnerAssentReceiptRef,
  protocolId: row.protocolId,
  protocolVersion: row.protocolVersion,
  issuedAtUtc: researchUtc(row.issuedAtUtcMs),
  expiresAtUtc: researchUtc(row.expiresAtUtcMs),
  revokedAtUtc: row.revokedAtUtcMs == null
      ? null
      : researchUtc(row.revokedAtUtcMs!),
  issuerKeyId: row.issuerKeyId,
  payloadSha256: row.payloadSha256,
  signature: row.signature,
  localRevision: row.localRevision,
  cloudRevision: row.cloudRevision,
  isDeleted: row.isDeleted,
);

DateTime researchUtc(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
