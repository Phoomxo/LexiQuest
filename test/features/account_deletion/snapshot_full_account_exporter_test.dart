import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/snapshot_full_account_exporter.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 10, 26, 8, 30);

  test(
    'saves the exact complete snapshot and returns an opaque receipt',
    () async {
      final owners = _Owners(_owner());
      final store = _Store();
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final exporter = SnapshotFullAccountExporter(
        owners: owners,
        buildSnapshot: ({required ownerId}) async => LocalAccountSnapshot(
          bytes: bytes,
          sha256: 'a' * 64,
          coveredScopes: requiredFullAccountExportScopes,
          generatedAtUtc: generatedAt,
        ),
        store: store,
        schemaVersion: 10,
      );

      final receipt = await exporter.export(ownerId: 'owner-a');

      expect(store.artifact?.bytes, same(bytes));
      expect(store.artifact?.mimeType, 'application/json');
      expect(store.revalidations, 1);
      expect(receipt.ownerId, 'owner-a');
      expect(receipt.artifactId, store.artifact?.suggestedFileName);
      expect(receipt.artifactId, isNot(contains(r'C:\')));
      expect(receipt.artifactSha256, 'a' * 64);
      expect(receipt.bytesWritten, bytes.length);
      expect(receipt.schemaVersion, 10);
      expect(receipt.coveredScopes, requiredFullAccountExportScopes);
      expect(receipt.completedAtUtc, generatedAt);
    },
  );

  test('owner change before write fails without saving a receipt', () async {
    final owners = _Owners(_owner());
    final store = _Store(onSave: () => owners.current = _owner(id: 'owner-b'));
    final exporter = SnapshotFullAccountExporter(
      owners: owners,
      buildSnapshot: ({required ownerId}) async => LocalAccountSnapshot(
        bytes: Uint8List.fromList([1]),
        sha256: 'b' * 64,
        coveredScopes: requiredFullAccountExportScopes,
        generatedAtUtc: generatedAt,
      ),
      store: store,
      schemaVersion: 10,
    );

    await expectLater(
      exporter.export(ownerId: 'owner-a'),
      throwsA(isA<AccountDeletionException>()),
    );
    expect(store.completedWrites, 0);
  });
}

LocalOwner _owner({String id = 'owner-a'}) => LocalOwner(
  id: id,
  firebaseUid: 'firebase-user',
  createdAtUtc: DateTime.utc(2026, 10, 20),
);

final class _Owners implements LocalOwnerRepository {
  _Owners(this.current);
  LocalOwner current;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _Store implements ExportArtifactStore {
  _Store({this.onSave});
  final void Function()? onSave;
  ExportArtifact? artifact;
  int revalidations = 0;
  int completedWrites = 0;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    this.artifact = artifact;
    onSave?.call();
    revalidations++;
    await revalidateBeforeWrite();
    completedWrites++;
    return ExportSaveResult(
      path: r'C:\private\lexiquest-account-export.json',
      bytesWritten: artifact.bytes.length,
    );
  }
}
