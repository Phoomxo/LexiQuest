import '../../export/domain/export_contracts.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../domain/account_deletion_contracts.dart';
import 'drift_account_snapshot.dart';

typedef BuildAccountSnapshot =
    Future<LocalAccountSnapshot> Function({required String ownerId});

final class SnapshotFullAccountExporter implements FullAccountExporter {
  const SnapshotFullAccountExporter({
    required this.owners,
    required this.buildSnapshot,
    required this.store,
    required this.schemaVersion,
  });

  final LocalOwnerRepository owners;
  final BuildAccountSnapshot buildSnapshot;
  final ExportArtifactStore store;
  final int schemaVersion;

  @override
  Future<FullAccountExportReceipt> export({required String ownerId}) async {
    final owner = ownerId.trim();
    if (owner.isEmpty || schemaVersion <= 0) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.fullExportFailed,
      );
    }
    await _requireOwner(owner);
    final snapshot = await buildSnapshot(ownerId: owner);
    if (snapshot.bytes.isEmpty ||
        !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(snapshot.sha256) ||
        snapshot.coveredScopes.length !=
            requiredFullAccountExportScopes.length ||
        !snapshot.coveredScopes.containsAll(requiredFullAccountExportScopes) ||
        !snapshot.generatedAtUtc.isUtc) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.fullExportRequired,
      );
    }
    final fileName =
        'lexiquest-account-${snapshot.generatedAtUtc.toIso8601String().replaceAll(':', '').replaceAll('-', '')}.json';
    try {
      final saved = await store.save(
        ExportArtifact(
          format: ExportFormat.researchJson,
          suggestedFileName: fileName,
          mimeType: 'application/json',
          bytes: snapshot.bytes,
          recordCount: 1,
          schemaVersion: schemaVersion,
          algorithmVersion: 1,
          generatedAtUtc: snapshot.generatedAtUtc,
          timeZone: 'UTC',
          exclusions: const [
            'cloud-only records',
            'authentication credentials',
            'API keys and tokens',
          ],
        ),
        cancellation: ExportCancellation(),
        revalidateBeforeWrite: () => _requireOwner(owner),
      );
      if (saved.bytesWritten != snapshot.bytes.length) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.fullExportFailed,
        );
      }
      return FullAccountExportReceipt(
        ownerId: owner,
        artifactId: fileName,
        artifactSha256: snapshot.sha256,
        bytesWritten: saved.bytesWritten,
        schemaVersion: schemaVersion,
        coveredScopes: Set.unmodifiable(snapshot.coveredScopes),
        completedAtUtc: snapshot.generatedAtUtc,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.fullExportFailed,
        cause: error,
      );
    }
  }

  Future<void> _requireOwner(String ownerId) async {
    try {
      if ((await owners.getOrCreateActiveOwner()).id != ownerId) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.ownerChanged,
        );
      }
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.fullExportFailed,
        cause: error,
      );
    }
  }
}
