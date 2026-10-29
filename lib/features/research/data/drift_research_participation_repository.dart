import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../adventure/domain/adventure_entry.dart';
import '../domain/experiment_assignment.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_participant_snapshot.dart';
import '../domain/research_participation_permit.dart';
import '../domain/research_permit_document.dart';
import 'drift_experiment_assignment_repository.dart';

final class AuthorizedResearchParticipant {
  const AuthorizedResearchParticipant._(this.snapshot, this.operation);

  final ResearchParticipantSnapshot snapshot;
  final AuthorizedResearchOperation operation;
}

/// Stores issuer-signed documents. Cached rows never establish current issuer
/// state; eligibility is checked through the independent R1 authorities.
final class DriftResearchParticipationRepository
    implements ActivePresentationPermitReader {
  DriftResearchParticipationRepository(
    this.database, {
    required this.assignments,
  }) {
    if (!identical(assignments.ownerWrites.database, database)) {
      throw ArgumentError('Participation and assignment databases must match');
    }
  }

  final AppDatabase database;
  final DriftExperimentAssignmentRepository assignments;

  Future<bool> importDocument({
    required String ownerId,
    required String document,
  }) async {
    late final ResearchParticipationPermit permit;
    try {
      permit = decodeResearchPermitDocument(document);
      if (!_matchesScope(ownerId, permit)) return false;
    } on Object {
      return false;
    }
    try {
      return await assignments.ownerWrites.writeForActiveOwner(
        expectedOwnerId: ownerId,
        write: () async {
          final previous = await _stored(permit.id);
          _checkTransition(previous, permit);
          final now = await _now();
          if (_narrowsAt(permit, now)) {
            if (previous == null) _deny();
            await _requireNarrowingAuthority(ownerId, permit);
            await _requireUnchanged(previous, permit.id);
            await _store(previous, permit);
            await _requireNarrowingAuthority(ownerId, permit);
            await _requireUnchanged(permit, permit.id);
            return true;
          }

          final firstAssignment = await assignments.admit(
            ownerId: ownerId,
            participationPermit: permit,
          );
          if (firstAssignment == null) _deny();
          await _requireNoOtherEligible(permit);
          await _requireUnchanged(previous, permit.id);
          await _store(previous, permit);
          final admission = await assignments.admitWithReceipt(
            ownerId: ownerId,
            participationPermit: permit,
          );
          if (admission == null || admission.assignment != firstAssignment) {
            _deny();
          }
          await _snapshot(permit, admission);
          return true;
        },
      );
    } on ResearchParticipationConflict {
      rethrow;
    } on ExperimentAssignmentConflict {
      rethrow;
    } on Object {
      // Any post-admission failure reaches here only after the outer rollback.
      return false;
    }
  }

  Future<ResearchParticipantSnapshot?> requireParticipant({
    required String ownerId,
    required String permitId,
  }) async => (await requireParticipantWithReceipt(
    ownerId: ownerId,
    permitId: permitId,
  ))?.snapshot;

  Future<AuthorizedResearchParticipant?> requireParticipantWithReceipt({
    required String ownerId,
    required String permitId,
  }) async {
    try {
      requireResearchCode(ownerId);
      requireResearchCode(permitId);
      return await assignments.ownerWrites.writeForActiveOwner(
        expectedOwnerId: ownerId,
        write: () async {
          final permit = await _stored(permitId);
          if (permit == null || !_matchesScope(ownerId, permit)) _deny();
          final existingAssignment = await _assignment(permit);
          if (existingAssignment == null) _deny();
          final admission = await assignments.admitWithReceipt(
            ownerId: ownerId,
            participationPermit: permit,
          );
          if (admission == null || admission.assignment != existingAssignment) {
            _deny();
          }
          final snapshot = await _snapshot(permit, admission);
          return AuthorizedResearchParticipant._(snapshot, admission.operation);
        },
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    // The interface's caller timestamp never establishes eligibility.
    try {
      final now = await _now();
      final rows = await _ownerPermits(ownerId);
      final candidates = rows
          .where((permit) => _eligibleAt(permit, now))
          .toList();
      if (candidates.length != 1) return null;
      final context = await requireParticipant(
        ownerId: ownerId,
        permitId: candidates.single.id,
      );
      if (context == null) return null;
      final permit = context.permit;
      return ActivePresentationPermit(
        permitId: permit.id,
        ownerId: permit.ownerId,
        assignedPresentation: permit.assignedTreatment,
        protocolId: permit.protocolId,
        protocolVersion: permit.protocolVersion,
        assignmentId: permit.assignmentId,
        expiresAtUtc: permit.expiresAtUtc,
      );
    } on Object {
      return null;
    }
  }

  /// Reads only admitted, current signed state. It never imports or admits.
  Future<ResearchParticipantSnapshot?> inspectParticipant({
    required String ownerId,
  }) async => (await inspectParticipantWithReceipt(ownerId: ownerId))?.snapshot;

  Future<AuthorizedResearchParticipant?> inspectParticipantWithReceipt({
    required String ownerId,
  }) async {
    try {
      requireResearchCode(ownerId);
      final now = await _now();
      final candidates = (await _ownerPermits(
        ownerId,
      )).where((permit) => _eligibleAt(permit, now)).toList();
      if (candidates.length != 1) {
        return null;
      }
      final permit = candidates.single;
      if (!_matchesScope(ownerId, permit)) {
        return null;
      }
      final admission = await assignments.inspectWithReceipt(
        ownerId: ownerId,
        participationPermit: permit,
      );
      if (admission == null) {
        return null;
      }
      return AuthorizedResearchParticipant._(
        await _readSnapshot(permit, admission),
        admission.operation,
      );
    } on Object {
      return null;
    }
  }

  Future<ResearchParticipantSnapshot> _snapshot(
    ResearchParticipationPermit permit,
    AuthorizedExperimentAssignment admission,
  ) => assignments.ownerWrites.writeForActiveOwner(
    expectedOwnerId: permit.ownerId,
    write: () => _readSnapshot(permit, admission),
  );

  Future<ResearchParticipantSnapshot> _readSnapshot(
    ResearchParticipationPermit permit,
    AuthorizedExperimentAssignment admission,
  ) async {
    await _requireUnchanged(permit, permit.id);
    await _requireNoOtherEligible(permit);
    final assignment = await _assignment(permit);
    final consent = await assignments.consent.load(
      ownerId: permit.ownerId,
      version: assignments.binding.study.consentVersion,
    );
    final now = await _now();
    final decision = consent.decidedAtUtc;
    final operation = admission.operation.permit;
    if (assignment == null ||
        assignment != admission.assignment ||
        operation.ownerId != permit.ownerId ||
        operation.assignmentId != assignment.id ||
        operation.operation != ResearchOperation.collect ||
        now.isBefore(operation.issuedAtUtc) ||
        !now.isBefore(operation.expiresAtUtc) ||
        admission.operation.verifiedAtUtc.isAfter(now) ||
        !_eligibleAt(permit, now) ||
        !consent.accepted ||
        consent.ownerId != permit.ownerId ||
        consent.version != assignments.binding.study.consentVersion ||
        consent.withdrawnAtUtc != null ||
        decision == null ||
        !decision.isUtc ||
        decision.microsecondsSinceEpoch < 0 ||
        assignment.assignedAtUtc.isBefore(decision) ||
        assignment.assignedAtUtc.isAfter(now)) {
      _deny();
    }
    return ResearchParticipantSnapshot(permit, assignment, consent);
  }

  Future<void> _requireNarrowingAuthority(
    String ownerId,
    ResearchParticipationPermit permit,
  ) async {
    final before = await _now();
    if (!_narrowsAt(permit, before)) _deny();
    final current = await assignments.participationDocuments.loadCurrent(
      ownerId: ownerId,
      permitId: permit.id,
    );
    if (current == null || !_sameDocument(current, permit)) _deny();
    final validation = assignments.participationValidator.validateAuthenticity(
      permit,
      expectedOwnerId: ownerId,
      expectedAssignmentId: permit.assignmentId,
      evaluatedAtUtc: _milliseconds(before),
    );
    if (validation != ResearchPermitDenialReason.none) _deny();
    final latest = await assignments.participationDocuments.loadCurrent(
      ownerId: ownerId,
      permitId: permit.id,
    );
    if (latest == null ||
        !_sameDocument(latest, permit) ||
        !_narrowsAt(permit, await _now())) {
      _deny();
    }
  }

  Future<void> _requireNoOtherEligible(
    ResearchParticipationPermit permit,
  ) async {
    final rows = await _ownerPermits(permit.ownerId);
    final now = await _now();
    if (rows.any((other) => other.id != permit.id && _eligibleAt(other, now))) {
      _conflict(permit);
    }
  }

  Future<List<ResearchParticipationPermit>> _ownerPermits(
    String ownerId,
  ) async {
    final study = assignments.binding.study;
    final assignmentId = experimentAssignmentId(
      ownerId: ownerId,
      experimentId: study.experimentId,
      experimentVersion: study.experimentVersion,
    );
    final rows = await database
        .customSelect(
          'SELECT * FROM research_participation_permits '
          'WHERE owner_id = ? AND assignment_id = ? AND protocol_id = ? AND protocol_version = ?',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(assignmentId),
            Variable<String>(study.protocolId),
            Variable<String>(study.protocolVersion),
          ],
        )
        .get();
    return [for (final row in rows) _decodeRow(row.data)];
  }

  Future<ResearchParticipationPermit?> _stored(String permitId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM research_participation_permits WHERE id = ?',
          variables: [Variable<String>(permitId)],
        )
        .getSingleOrNull();
    return row == null ? null : _decodeRow(row.data);
  }

  Future<void> _requireUnchanged(
    ResearchParticipationPermit? expected,
    String permitId,
  ) async {
    final current = await _stored(permitId);
    if (expected == null
        ? current != null
        : current == null || !_sameDocument(expected, current)) {
      if (expected != null) _conflict(expected);
      _deny();
    }
  }

  Future<ExperimentAssignment?> _assignment(
    ResearchParticipationPermit permit,
  ) async {
    final row = await database
        .customSelect(
          'SELECT id, owner_id, experiment_id, experiment_version, cohort, protocol_version, '
          'assigned_at_utc_ms FROM experiment_assignments WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(permit.assignmentId),
            Variable<String>(permit.ownerId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final study = assignments.binding.study;
    if (row.read<String>('experiment_id') != study.experimentId ||
        row.read<int>('experiment_version') != study.experimentVersion ||
        row.read<String>('cohort') != permit.assignedTreatment.wireName ||
        row.read<String>('protocol_version') != study.protocolVersion) {
      _deny();
    }
    return ExperimentAssignment(
      id: row.read<String>('id'),
      ownerId: row.read<String>('owner_id'),
      experimentId: row.read<String>('experiment_id'),
      experimentVersion: row.read<int>('experiment_version'),
      cohort: row.read<String>('cohort'),
      protocolVersion: row.read<String>('protocol_version'),
      assignedAtUtc: _utc(row.data['assigned_at_utc_ms']),
    );
  }

  Future<void> _store(
    ResearchParticipationPermit? previous,
    ResearchParticipationPermit permit,
  ) async {
    if (previous != null && previous.localRevision == permit.localRevision) {
      return;
    }
    const columns = [
      'id',
      'owner_id',
      'local_revision',
      'cloud_revision',
      'is_deleted',
      'participant_class',
      'age_band_code',
      'assignment_id',
      'assigned_treatment',
      'consent_receipt_id',
      'guardian_permission_receipt_ref',
      'learner_assent_receipt_ref',
      'protocol_id',
      'protocol_version',
      'issued_at_utc_ms',
      'expires_at_utc_ms',
      'revoked_at_utc_ms',
      'issuer_key_id',
      'payload_sha256',
      'signature',
    ];
    final values = <Object?>[
      permit.id,
      permit.ownerId,
      permit.localRevision,
      permit.cloudRevision,
      permit.isDeleted ? 1 : 0,
      permit.participantClass.name,
      permit.ageBandCode,
      permit.assignmentId,
      permit.assignedTreatment.wireName,
      permit.consentReceiptId,
      permit.guardianPermissionReceiptRef,
      permit.learnerAssentReceiptRef,
      permit.protocolId,
      permit.protocolVersion,
      permit.issuedAtUtc.millisecondsSinceEpoch,
      permit.expiresAtUtc.millisecondsSinceEpoch,
      permit.revokedAtUtc?.millisecondsSinceEpoch,
      permit.issuerKeyId,
      permit.payloadSha256,
      permit.signature,
    ];
    if (previous == null) {
      await database.customStatement(
        'INSERT INTO research_participation_permits (${columns.join(', ')}) '
        'VALUES (${List.filled(columns.length, '?').join(', ')})',
        values,
      );
    } else {
      await database.customStatement(
        'UPDATE research_participation_permits SET '
        '${columns.map((column) => '$column = ?').join(', ')} '
        'WHERE id = ? AND owner_id = ? AND local_revision = ? AND cloud_revision = ? '
        'AND payload_sha256 = ? AND signature = ?',
        [
          ...values,
          previous.id,
          previous.ownerId,
          previous.localRevision,
          previous.cloudRevision,
          previous.payloadSha256,
          previous.signature,
        ],
      );
      final changed = await database
          .customSelect('SELECT changes() AS changed')
          .getSingle();
      if (changed.read<int>('changed') != 1) _conflict(permit);
    }
  }

  void _checkTransition(
    ResearchParticipationPermit? previous,
    ResearchParticipationPermit next,
  ) {
    if (previous == null) return;
    if (!_samePins(previous, next) ||
        previous.localRevision != previous.cloudRevision ||
        next.localRevision < previous.localRevision ||
        (previous.isDeleted && !next.isDeleted) ||
        (previous.revokedAtUtc != null &&
            previous.revokedAtUtc != next.revokedAtUtc) ||
        (next.localRevision == previous.localRevision &&
            !_sameDocument(previous, next))) {
      _conflict(next);
    }
  }

  bool _matchesScope(String ownerId, ResearchParticipationPermit permit) {
    final study = assignments.binding.study;
    final expected = experimentAssignmentId(
      ownerId: ownerId,
      experimentId: study.experimentId,
      experimentVersion: study.experimentVersion,
    );
    return permit.ownerId == ownerId &&
        permit.assignmentId == expected &&
        assignments.authorizer.requirements.assignmentId == expected &&
        permit.protocolId == study.protocolId &&
        permit.protocolVersion == study.protocolVersion;
  }

  Future<DateTime> _now() async {
    final reading = await assignments.trustedTime.read();
    if (reading == null ||
        !reading.isFresh ||
        reading.effectiveNowUtc.microsecondsSinceEpoch < 0) {
      _deny();
    }
    return reading.effectiveNowUtc;
  }

  static bool _eligibleAt(ResearchParticipationPermit permit, DateTime now) =>
      !permit.isDeleted &&
      !now.isBefore(permit.issuedAtUtc) &&
      now.isBefore(permit.expiresAtUtc) &&
      (permit.revokedAtUtc == null || now.isBefore(permit.revokedAtUtc!));

  static bool _narrowsAt(ResearchParticipationPermit permit, DateTime now) =>
      permit.isDeleted ||
      (permit.revokedAtUtc != null && !now.isBefore(permit.revokedAtUtc!));

  static bool _samePins(
    ResearchParticipationPermit a,
    ResearchParticipationPermit b,
  ) =>
      a.id == b.id &&
      a.ownerId == b.ownerId &&
      a.assignmentId == b.assignmentId &&
      a.protocolId == b.protocolId &&
      a.protocolVersion == b.protocolVersion &&
      a.assignedTreatment == b.assignedTreatment &&
      a.participantClass == b.participantClass &&
      a.ageBandCode == b.ageBandCode &&
      a.consentReceiptId == b.consentReceiptId &&
      a.guardianPermissionReceiptRef == b.guardianPermissionReceiptRef &&
      a.learnerAssentReceiptRef == b.learnerAssentReceiptRef &&
      a.issuedAtUtc == b.issuedAtUtc;

  static bool _sameDocument(
    ResearchParticipationPermit a,
    ResearchParticipationPermit b,
  ) =>
      a.canonicalPayload() == b.canonicalPayload() &&
      a.payloadSha256 == b.payloadSha256 &&
      a.signature == b.signature;

  static ResearchParticipationPermit _decodeRow(Map<String, Object?> row) =>
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
          'isDeleted': _bool(row['is_deleted']),
        }),
      );

  static bool _bool(Object? value) => switch (value) {
    true || 1 => true,
    false || 0 => false,
    _ => throw const FormatException('Invalid cached boolean'),
  };

  static DateTime _utc(Object? value) {
    if (value is! int || value < 0 || value > 8640000000000000) {
      throw const FormatException('Invalid cached timestamp');
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static DateTime _milliseconds(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value.millisecondsSinceEpoch,
        isUtc: true,
      );

  static Never _deny() => throw const _ParticipationDenied();

  static Never _conflict(ResearchParticipationPermit permit) =>
      throw ResearchParticipationConflict(
        ownerId: permit.ownerId,
        permitId: permit.id,
      );
}

final class _ParticipationDenied implements Exception {
  const _ParticipationDenied();
}
