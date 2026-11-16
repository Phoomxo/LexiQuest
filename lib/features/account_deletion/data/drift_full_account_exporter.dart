import '../../export/domain/export_contracts.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../domain/account_deletion_contracts.dart';
import 'drift_account_snapshot.dart';

final class DriftFullAccountExporter implements FullAccountExporter {
  const DriftFullAccountExporter({
    required this.owners,
    required this.snapshots,
    required this.store,
    required this.nowUtc,
  });

  final LocalOwnerRepository owners;
  final DriftAccountSnapshotBuilder snapshots;
  final ExportArtifactStore store;
  final DateTime Function() nowUtc;

  @override
  Future<FullAccountExportReceipt> export({required String ownerId}) async {
    final owner = ownerId.trim();
    if (owner.isEmpty) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.invalidRequest,
      );
    }
    final cancellation = ExportCancellation();
    var ownerChanged = false;
    Future<void> requireOwner() async {
      final current = await owners.getOrCreateActiveOwner();
      if (current.id != owner) {
        ownerChanged = true;
        cancellation.cancel();
        throw const AccountDeletionException(
          AccountDeletionFailureCode.ownerChanged,
        );
      }
    }

    try {
      await requireOwner();
      final snapshot = await snapshots.build(ownerId: owner);
      await requireOwner();
      final stamp = snapshot.generatedAtUtc
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '');
      final artifact = ExportArtifact(
        format: ExportFormat.fullAccountJson,
        suggestedFileName: 'lexiquest-full-account-$stamp.json',
        mimeType: 'application/json',
        bytes: snapshot.bytes,
        recordCount: snapshot.recordCount,
        schemaVersion: snapshot.schemaVersion,
        algorithmVersion: 1,
        generatedAtUtc: snapshot.generatedAtUtc,
        timeZone: 'UTC',
        exclusions: LocalAccountSnapshot.exclusions,
      );
      final saved = await store.save(
        artifact,
        cancellation: cancellation,
        revalidateBeforeWrite: requireOwner,
      );
      await requireOwner();
      if (saved.path.trim().isEmpty ||
          saved.bytesWritten <= 0 ||
          saved.bytesWritten != snapshot.bytes.length) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.fullExportFailed,
        );
      }
      final completedAt = nowUtc();
      if (!completedAt.isUtc) {
        throw ArgumentError.value(completedAt, 'nowUtc', 'must be UTC');
      }
      return FullAccountExportReceipt(
        ownerId: owner,
        artifactId: saved.path,
        artifactSha256: snapshot.sha256,
        bytesWritten: saved.bytesWritten,
        schemaVersion: snapshot.schemaVersion,
        coveredScopes: snapshot.coveredScopes,
        completedAtUtc: completedAt,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        ownerChanged
            ? AccountDeletionFailureCode.ownerChanged
            : AccountDeletionFailureCode.fullExportFailed,
        cause: error,
      );
    }
  }
}
