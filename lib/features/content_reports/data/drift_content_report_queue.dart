import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../domain/content_report.dart';

final class DriftContentReportQueue implements ContentReportQueue {
  DriftContentReportQueue({required this.database, required this.ownerWrites}) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError('Report queue requires the same owner database');
    }
  }

  final AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;

  Future<void> requireOrdinarySession({
    required String expectedOwnerId,
    required String sessionId,
    required bool Function() stillCurrent,
  }) => _scoped(expectedOwnerId, (current) async {
    bool live() => current() && stillCurrent();
    await _requireOrdinarySession(expectedOwnerId, sessionId, live);
  });

  Future<void> _requireOrdinarySession(
    String ownerId,
    String sessionId,
    bool Function() current,
  ) async {
    await _requireOwner(ownerId, current);
    final session =
        await (database.select(database.learningSessions)..where(
              (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (session == null || session.activityType == 'assessment') _deny();
    final controlled = await database
        .customSelect(
          'SELECT 1 AS controlled FROM assessment_runs WHERE learning_session_id = ? '
          'UNION ALL SELECT 1 AS controlled FROM measurement_opportunities '
          'WHERE learning_session_id = ? LIMIT 1',
          variables: [Variable<String>(sessionId), Variable<String>(sessionId)],
        )
        .getSingleOrNull();
    if (controlled != null) _deny();
    final attempts = await (database.select(
      database.answerAttempts,
    )..where((row) => row.sessionId.equals(sessionId))).get();
    if (attempts.any(
      (attempt) =>
          attempt.ownerId != ownerId ||
          !LearningEvidenceContract.validEvidenceMetadata(
            evidenceClass: attempt.evidenceClass,
            evidenceContextJson: attempt.evidenceContextJson,
          ),
    )) {
      _deny();
    }
    await _requireOwner(ownerId, current);
  }

  Future<void> _requirePayloadSession(
    String owner,
    ContentReportPayload payload,
    bool Function() current,
  ) async {
    if (payload.target.kind != 'aiOutput') return;
    final target =
        contentReportDecodeJson(
              payload.target.snapshotJson,
              maximumBytes: 16384,
            )
            as Map<String, dynamic>;
    final source = target['source'] as Map<String, dynamic>;
    await _requireOrdinarySession(
      owner,
      source['sessionId'] as String,
      current,
    );
    final session =
        await (database.select(database.learningSessions)
              ..where((row) => row.id.equals(source['sessionId'] as String)))
            .getSingle();
    if (session.acceptedPlanId != source['acceptedPlanId']) _deny();
  }

  Never _deny() =>
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);

  Future<String?> _requireOwner(String ownerId, bool Function() current) async {
    if (!current()) _deny();
    final owners = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).get();
    if (owners.length != 1 || owners.single.id != ownerId) _deny();
    final fence = await ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(ownerId) ||
            (fence.cloudReceipt != null &&
                accountDeletionReplacementGuestOwnerId(fence.cloudReceipt!) ==
                    ownerId))) {
      _deny();
    }
    if (!current()) _deny();
    final owner = owners.single;
    return owner.accountState == 'firebaseBound' ? owner.firebaseUid : null;
  }

  Future<T> _scoped<T>(
    String ownerId,
    Future<T> Function(bool Function() current) operation,
  ) async {
    var valid = true;
    final updates = Zone.root.run(
      () =>
          database.tableUpdates(TableUpdateQuery.onTable(database.localOwners)),
    );
    final changes = updates.listen(
      (_) => valid = false,
      onError: (Object _) => valid = false,
      onDone: () => valid = false,
    );
    bool current() => valid;
    try {
      await _requireOwner(ownerId, current);
      final value = await operation(current);
      await _requireOwner(ownerId, current);
      return value;
    } finally {
      await changes.cancel();
    }
  }

  Future<ContentReportRecord?> _read(
    String owner,
    String id,
    bool Function() current,
  ) async {
    final uid = await _requireOwner(owner, current);
    final row = await (database.select(
      database.contentReports,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    if (row.ownerId != owner) _deny();
    final result = _decode(row);
    await _requirePayloadSession(owner, result.payload, current);
    if (result.acknowledgedFirebaseUid != null &&
        result.acknowledgedFirebaseUid != uid) {
      _deny();
    }
    return result;
  }

  ContentReportRecord _decode(ContentReportRow row) {
    try {
      final payload = ContentReportPayload.fromStorage(
        reportJson: row.reportJson,
        reportSha256: row.reportSha256,
      );
      final acknowledgement = row.acknowledgementJson == null
          ? null
          : ContentReportAcknowledgement.fromResponseJson(
              row.acknowledgementJson!,
            );
      if (payload.reportId != row.id ||
          payload.queuedAtUtc.millisecondsSinceEpoch != row.queuedAtUtcMs) {
        throw const FormatException('Report storage identity mismatch');
      }
      return ContentReportRecord(
        ownerId: row.ownerId,
        payload: payload,
        delivery: ContentReportDelivery.values.byName(row.deliveryState),
        acknowledgement: acknowledgement,
        acknowledgedFirebaseUid: row.acknowledgedFirebaseUid,
        localRevision: row.localRevision,
      );
    } on Object {
      throw const ContentReportException(ContentReportFailureCode.unavailable);
    }
  }

  @override
  Future<ContentReportRecord?> read({
    required String expectedOwnerId,
    required String reportId,
  }) => _scoped(
    expectedOwnerId,
    (current) => _read(expectedOwnerId, reportId, current),
  );

  @override
  Future<ContentReportRecord> put({
    required String expectedOwnerId,
    required ContentReportPayload payload,
  }) async {
    ContentReportPayload.fromStorage(
      reportJson: payload.reportJson,
      reportSha256: payload.reportSha256,
    );
    return _write(expectedOwnerId, (current) async {
      await _requirePayloadSession(expectedOwnerId, payload, current);
      final existing = await _read(expectedOwnerId, payload.reportId, current);
      if (existing != null) {
        if (existing.payload.reportJson != payload.reportJson ||
            existing.payload.reportSha256 != payload.reportSha256) {
          throw const ContentReportException(
            ContentReportFailureCode.collision,
          );
        }
        return existing;
      }
      await database
          .into(database.contentReports)
          .insert(
            ContentReportsCompanion.insert(
              id: payload.reportId,
              ownerId: expectedOwnerId,
              reportJson: payload.reportJson,
              reportSha256: payload.reportSha256,
              queuedAtUtcMs: payload.queuedAtUtc.millisecondsSinceEpoch,
            ),
          );
      return (await _read(expectedOwnerId, payload.reportId, current))!;
    }, allowAmbient: true);
  }

  Future<ContentReportRecord> _write(
    String owner,
    Future<ContentReportRecord> Function(bool Function() current) operation, {
    bool allowAmbient = false,
  }) async {
    return _scoped(owner, (current) async {
      if (!allowAmbient && await ownerWrites.hasAmbientTransaction()) _deny();
      return ownerWrites.writeForActiveOwner(
        expectedOwnerId: owner,
        write: () async {
          final result = await operation(current);
          await _requirePayloadSession(owner, result.payload, current);
          await _requireOwner(owner, current);
          return result;
        },
      );
    });
  }

  @override
  Future<ContentReportRecord> markUnconfirmed({
    required String expectedOwnerId,
    required String reportId,
    required String expectedReportSha256,
  }) => _write(expectedOwnerId, (current) async {
    final row = await _read(expectedOwnerId, reportId, current);
    if (row == null || row.payload.reportSha256 != expectedReportSha256) {
      _deny();
    }
    if (row.delivery != ContentReportDelivery.queued) return row;
    await (database.update(database.contentReports)..where(
          (value) =>
              value.id.equals(reportId) &
              value.localRevision.equals(row.localRevision),
        ))
        .write(
          ContentReportsCompanion(
            deliveryState: const Value('unconfirmed'),
            localRevision: Value(row.localRevision + 1),
          ),
        );
    return (await _read(expectedOwnerId, reportId, current))!;
  });

  @override
  Future<ContentReportRecord> acknowledge({
    required String expectedOwnerId,
    required String expectedFirebaseUid,
    required String expectedReportSha256,
    required ContentReportAcknowledgement acknowledgement,
  }) => _write(expectedOwnerId, (current) async {
    final uid = await _requireOwner(expectedOwnerId, current);
    if (uid != expectedFirebaseUid) _deny();
    if (acknowledgement.receipt.receiptId !=
        'content-report-receipt:'
            '${contentReportDigest(jsonEncode([expectedFirebaseUid, acknowledgement.receipt.reportId]))}') {
      throw const ContentReportException(
        ContentReportFailureCode.invalidResponse,
      );
    }
    final row = await _read(
      expectedOwnerId,
      acknowledgement.receipt.reportId,
      current,
    );
    if (row == null || row.payload.reportSha256 != expectedReportSha256) {
      _deny();
    }
    acknowledgement.requireMatches(row.payload);
    if (row.acknowledgement case final previous?) {
      acknowledgement.requireSuccessor(previous);
      if (jsonEncode(previous.toJson()) ==
          jsonEncode(acknowledgement.toJson())) {
        return row;
      }
    }
    await (database.update(database.contentReports)..where(
          (value) =>
              value.id.equals(row.payload.reportId) &
              value.localRevision.equals(row.localRevision),
        ))
        .write(
          ContentReportsCompanion(
            deliveryState: const Value('received'),
            acknowledgementJson: Value(jsonEncode(acknowledgement.toJson())),
            acknowledgedFirebaseUid: Value(expectedFirebaseUid),
            localRevision: Value(row.localRevision + 1),
          ),
        );
    return (await _read(expectedOwnerId, row.payload.reportId, current))!;
  });

  @override
  Stream<List<ContentReportRecord>> watchOwner(String expectedOwnerId) async* {
    var valid = true;
    final ownerChanges = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid;
    try {
      await for (final rows
          in database
              .customSelect(
                'SELECT * FROM content_reports WHERE owner_id = ? '
                'ORDER BY queued_at_utc_ms DESC,id',
                variables: [Variable<String>(expectedOwnerId)],
                readsFrom: {
                  database.contentReports,
                  database.localOwners,
                  database.runtimeFlags,
                  database.learningSessions,
                  database.answerAttempts,
                  database.measurementOpportunities,
                  database.assessmentRuns,
                },
              )
              .watch()) {
        final uid = await _requireOwner(expectedOwnerId, current);
        final values = rows
            .map((row) => _decode(database.contentReports.map(row.data)))
            .toList(growable: false);
        for (final row in values) {
          await _requirePayloadSession(expectedOwnerId, row.payload, current);
        }
        if (values.any(
          (row) =>
              row.acknowledgedFirebaseUid != null &&
              row.acknowledgedFirebaseUid != uid,
        )) {
          _deny();
        }
        await _requireOwner(expectedOwnerId, current);
        yield List.unmodifiable(values);
      }
    } finally {
      await ownerChanges.cancel();
    }
  }
}
