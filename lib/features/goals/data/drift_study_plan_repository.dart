import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../motivation/domain/timezone_policy.dart';
import '../domain/study_plan.dart';

final class DriftStudyPlanRepository {
  DriftStudyPlanRepository(this.database, {required this.nowUtc});
  final AppDatabase database;
  final DateTime Function() nowUtc;

  Future<Map<String, Object?>> exportArchive({
    required String ownerId,
    required String leaseToken,
  }) => database.transaction(() async {
    await _authority(ownerId, leaseToken);
    final content = <String, Object?>{
      'archiveSchemaVersion': 1,
      'databaseSchemaVersion': AppDatabase.currentSchemaVersion,
      'kind': 'study-plan-history',
      'ownerId': ownerId,
      'activeOperationId': (await active(ownerId))?.operationId,
      'revisions': (await history(ownerId)).map((p) => p.toJson()).toList(),
    };
    await _authority(ownerId, leaseToken);
    return {...content, 'contentHash': studyPlanHash(content)};
  });

  Future<void> restoreArchive({
    required String ownerId,
    required String leaseToken,
    required Map<String, Object?> envelope,
    required Future<void> Function() requireCurrent,
  }) async {
    // Copy and validate before waiting; caller mutation cannot change the import.
    final content = Map<String, Object?>.from(
      jsonDecode(jsonEncode(envelope)) as Map,
    )..remove('contentHash');
    final version = content['databaseSchemaVersion'];
    if (envelope['contentHash'] != studyPlanHash(content) ||
        content.length != 6 ||
        content['archiveSchemaVersion'] != 1 ||
        content['kind'] != 'study-plan-history' ||
        version is! int ||
        version < 30 ||
        version > AppDatabase.currentSchemaVersion ||
        content['revisions'] is! List ||
        (content['revisions'] as List).length > 10000) {
      throw const FormatException('Unsupported study plan archive');
    }
    if (content['ownerId'] != ownerId) {
      throw StateError('Study plan archive owner mismatch');
    }
    final revisions = (content['revisions'] as List)
        .map(
          (p) =>
              StudyPlanRevision.fromJson(Map<String, Object?>.from(p as Map)),
        )
        .toList();
    if (revisions.map((p) => p.operationId).toSet().length !=
        revisions.length) {
      throw const FormatException('Duplicate study plan archive identity');
    }
    final activeId = content['activeOperationId'];
    if (activeId != null && !revisions.any((p) => p.operationId == activeId)) {
      throw const FormatException('Missing active study plan revision');
    }
    await database.transaction(() async {
      await _authority(ownerId, leaseToken);
      await requireCurrent();
      final priorHistory = await history(ownerId);
      for (final p in revisions) {
        final prior = await exact(ownerId, p.operationId);
        if (prior != null) {
          if (prior.payloadHash != p.payloadHash) {
            throw StateError('Study plan restore collision');
          }
          continue;
        }
        await database
            .into(database.studyPlanRevisions)
            .insert(
              StudyPlanRevisionsCompanion.insert(
                ownerId: ownerId,
                operationId: p.operationId,
                revision: p.revision,
                payloadHash: p.payloadHash,
                payloadJson: jsonEncode(p.toJson()),
              ),
            );
      }
      // A history import never overwrites a live pointer or rewinds an owner
      // with existing history. Restored historical plans do not start lessons.
      if (priorHistory.isEmpty && activeId is String) {
        await database
            .into(database.activePlanPointers)
            .insert(
              ActivePlanPointersCompanion.insert(
                ownerId: ownerId,
                operationId: activeId,
              ),
            );
      }
      await _authority(ownerId, leaseToken);
      await requireCurrent();
    });
  }

  Future<void> _authority(String ownerId, String lease) async {
    await DriftOwnerOperationGate(
      database,
    ).requireOwned(token: lease, nowUtc: nowUtc());
    final owners = await (database.select(
      database.localOwners,
    )..where((r) => r.isActive.equals(true))).get();
    if (owners.length != 1 || owners.single.id != ownerId) {
      throw StateError('Study plan owner changed');
    }
  }

  StudyPlanRevision _decode(StudyPlanRevisionRow row) {
    final p = StudyPlanRevision.fromJson(
      Map<String, Object?>.from(jsonDecode(row.payloadJson) as Map),
    );
    if (p.operationId != row.operationId ||
        p.revision != row.revision ||
        p.payloadHash != row.payloadHash) {
      throw StateError('Study plan envelope mismatch');
    }
    return p;
  }

  Future<StudyPlanRevision?> exact(String ownerId, String operationId) async {
    final row =
        await (database.select(database.studyPlanRevisions)..where(
              (r) =>
                  r.ownerId.equals(ownerId) & r.operationId.equals(operationId),
            ))
            .getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  Future<StudyPlanRevision?> active(String ownerId) async {
    final pointer = await (database.select(
      database.activePlanPointers,
    )..where((r) => r.ownerId.equals(ownerId))).getSingleOrNull();
    return pointer == null ? null : exact(ownerId, pointer.operationId);
  }

  Future<List<StudyPlanRevision>> history(String ownerId) async =>
      (await (database.select(database.studyPlanRevisions)
                ..where((r) => r.ownerId.equals(ownerId))
                ..orderBy([
                  (r) => OrderingTerm.asc(r.revision),
                  (r) => OrderingTerm.asc(r.operationId),
                ]))
              .get())
          .map(_decode)
          .toList(growable: false);

  Future<StudyPlanRevision> accept({
    required String ownerId,
    required String leaseToken,
    required StudyPlanRevision proposal,
    required Future<void> Function() requireCurrent,
    required Future<String> Function() readAuthorityHash,
  }) => database.transaction(() async {
    await _authority(ownerId, leaseToken);
    await requireCurrent();
    final existing = await exact(ownerId, proposal.operationId);
    if (existing != null) {
      if (existing.payloadHash != proposal.payloadHash) {
        throw StateError('Study plan operation collision');
      }
      await requireCurrent();
      return existing;
    }
    final prior = await active(ownerId);
    if ((prior?.revision ?? 0) != proposal.expectedPriorRevision) {
      throw StateError('Study plan revision conflict');
    }
    final now = nowUtc();
    if (now.isBefore(proposal.createdAtUtc) ||
        !TimezonePolicy.isSameLearningDay(
          now,
          proposal.createdAtUtc,
          proposal.timezoneId,
        ) ||
        await readAuthorityHash() != proposal.authorityHash) {
      throw StateError('Study plan sources changed; regenerate proposal');
    }
    await database
        .into(database.studyPlanRevisions)
        .insert(
          StudyPlanRevisionsCompanion.insert(
            ownerId: ownerId,
            operationId: proposal.operationId,
            revision: proposal.revision,
            payloadHash: proposal.payloadHash,
            payloadJson: jsonEncode(proposal.toJson()),
          ),
        );
    await database
        .into(database.activePlanPointers)
        .insertOnConflictUpdate(
          ActivePlanPointersCompanion.insert(
            ownerId: ownerId,
            operationId: proposal.operationId,
          ),
        );
    await _authority(ownerId, leaseToken);
    await requireCurrent();
    return proposal;
  });
}
