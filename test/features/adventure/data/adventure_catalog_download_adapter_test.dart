import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/data/adventure_catalog_download_adapter.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/data/drift_offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';

void main() {
  test(
    'production catalog adapter repairs then quarantines corrupt bytes',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-adventure-catalog-',
      );
      final diagnostics = AdventureDiagnostics();
      final manifests = DriftContentManifestRepository(database);
      await manifests.provisionPackagedArtifact(
        PackagedAdventureWorldCatalog.contentArtifact,
      );
      final manager = VerifiedOfflineContentManager(
        repository: DriftOfflineContentRepository(database),
        adapters: const <OfflineContentDownloadAdapter>[
          AdventureCatalogDownloadAdapter(),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 9, 4, 10),
      );
      final recovery = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: diagnostics,
        catalogIdentity: PackagedAdventureWorldCatalog.contentIdentity,
        delay: (_) async {},
      );

      try {
        final repaired = await recovery.repair();
        expect(repaired.status, AdventureCatalogRecoveryStatus.repaired);

        final published = await directory
            .list()
            .where(
              (entity) => entity is File && entity.path.endsWith('.content'),
            )
            .cast<File>()
            .single;
        final corrupt = await published.readAsBytes();
        corrupt[0] ^= 0xff;
        await published.writeAsBytes(corrupt, flush: true);

        final verified = await recovery.verify();
        expect(verified.status, AdventureCatalogRecoveryStatus.quarantined);
        expect(
          verified.failureCode,
          OfflineContentFailureCode.checksumMismatch,
        );
        expect(
          diagnostics.snapshot().counters,
          <AdventureDiagnosticReasonCode, int>{
            AdventureDiagnosticReasonCode.assetChecksumMismatch: 1,
          },
        );
      } finally {
        await recovery.dispose();
        await manager.dispose();
        await database.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );
}
