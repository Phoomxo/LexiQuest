import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../../runtime/registries/consent_registry.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../sync/domain/sync_entity.dart';
import '../domain/content_quality_report.dart';
import '../domain/content_quality_report_repository.dart';

typedef ContentReportMutationNotifier = Future<void> Function();

final class ContentReportUploadPolicy {
  const ContentReportUploadPolicy.off()
    : enabled = false,
      deployedRulesRevision = '',
      consentVersion = 0;

  const ContentReportUploadPolicy.v1({
    required this.deployedRulesRevision,
    required this.consentVersion,
  }) : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;
  final int consentVersion;

  bool get allowsQueue =>
      enabled &&
      deployedRulesRevision == contentQualityReportV1RulesRevision &&
      consentVersion > 0;
}

final class DriftContentQualityReportRepository
    implements ContentQualityReportRepository {
  DriftContentQualityReportRepository(
    this.database, {
    required this.owners,
    this.consentRegistry = const NoOpConsentRegistry(),
    this.uploadPolicy = const ContentReportUploadPolicy.off(),
    this.onLocalMutation,
  });

  final db.AppDatabase database;
  final LocalOwnerRepository owners;
  final ConsentRegistry consentRegistry;
  final ContentReportUploadPolicy uploadPolicy;
  final ContentReportMutationNotifier? onLocalMutation;

  @override
  Future<void> submit(ContentQualityReport report) async {
    _revalidate(report);
    await owners.getOrCreateActiveOwner();

    final queued = await database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final existingById = await (database.select(
        database.contentQualityReports,
      )..where((row) => row.id.equals(report.id))).getSingleOrNull();
      if (existingById != null &&
          !_sameSemantic(existingById, ownerId, report)) {
        throw StateError('content report id is already bound to other data');
      }
      final semanticReplay = await _findSemanticReplay(ownerId, report);
      final existing = existingById ?? semanticReplay;

      final uploadAllowed = await _uploadAllowed(ownerId);
      if (existing == null) {
        await database
            .into(database.contentQualityReports)
            .insert(
              db.ContentQualityReportsCompanion.insert(
                id: report.id,
                ownerId: ownerId,
                contentType: report.contentIdentity.type.name,
                contentId: report.contentIdentity.id,
                contentRevision: report.contentIdentity.revision,
                reasonCode: report.reason.name,
                comment: Value(report.comment),
                submittedAtUtcMs: report.submittedAtUtc.millisecondsSinceEpoch,
              ),
            );
      }

      if (!uploadAllowed) return false;
      return _ensureOutbox(
        ownerId: ownerId,
        reportId: existing?.id ?? report.id,
        submittedAtUtcMs:
            existing?.submittedAtUtcMs ??
            report.submittedAtUtc.millisecondsSinceEpoch,
      );
    });
    if (queued) await onLocalMutation?.call();
  }

  Future<bool> _uploadAllowed(String ownerId) async {
    if (!uploadPolicy.allowsQueue) return false;
    final snapshot = await consentRegistry.snapshot(
      purpose: ConsentPurpose.researchDataUpload,
      ownerId: ownerId,
      consentVersion: uploadPolicy.consentVersion,
    );
    return snapshot.state == ConsentState.granted &&
        snapshot.withdrawalUtc == null;
  }

  Future<bool> _ensureOutbox({
    required String ownerId,
    required String reportId,
    required int submittedAtUtcMs,
  }) async {
    final operationId = 'contentQualityReport:$reportId:1';
    final existing = await (database.select(
      database.outboxOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
    if (existing != null) {
      if (existing.ownerId != ownerId ||
          existing.entityType !=
              SyncCollection.contentQualityReports.entityType ||
          existing.entityId != reportId ||
          existing.operationKind != SyncOperationKind.upsert.name ||
          existing.payloadVersion != 1 ||
          existing.baseRevision != 0 ||
          existing.createdAtUtcMs != submittedAtUtcMs) {
        throw StateError('content report outbox identity is already in use');
      }
      return false;
    }
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: operationId,
            ownerId: ownerId,
            entityType: SyncCollection.contentQualityReports.entityType,
            entityId: reportId,
            operationKind: SyncOperationKind.upsert.name,
            payloadVersion: const Value(1),
            baseRevision: const Value(0),
            createdAtUtcMs: submittedAtUtcMs,
          ),
        );
    return true;
  }

  Future<String> _requireSingleActiveOwnerId() async {
    final active =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (active.length != 1) {
      throw StateError('exactly one active local owner is required');
    }
    return active.single.id;
  }

  Future<db.ContentQualityReportRow?> _findSemanticReplay(
    String ownerId,
    ContentQualityReport report,
  ) {
    final query = database.select(database.contentQualityReports)
      ..where(
        (row) =>
            row.ownerId.equals(ownerId) &
            row.contentType.equals(report.contentIdentity.type.name) &
            row.contentId.equals(report.contentIdentity.id) &
            row.contentRevision.equals(report.contentIdentity.revision) &
            row.reasonCode.equals(report.reason.name) &
            (report.comment == null
                ? row.comment.isNull()
                : row.comment.equals(report.comment!)),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.submittedAtUtcMs),
        (row) => OrderingTerm.asc(row.id),
      ])
      ..limit(1);
    return query.getSingleOrNull();
  }

  bool _sameSemantic(
    db.ContentQualityReportRow existing,
    String ownerId,
    ContentQualityReport report,
  ) {
    return existing.ownerId == ownerId &&
        existing.contentType == report.contentIdentity.type.name &&
        existing.contentId == report.contentIdentity.id &&
        existing.contentRevision == report.contentIdentity.revision &&
        existing.reasonCode == report.reason.name &&
        existing.comment == report.comment;
  }

  void _revalidate(ContentQualityReport report) {
    ContentQualityReport(
      id: report.id,
      contentIdentity: report.contentIdentity,
      reason: report.reason,
      comment: report.comment,
      submittedAtUtc: report.submittedAtUtc,
    );
  }
}
