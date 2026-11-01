import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';

import '../identity/learning_packs_owner_merge_review_test.dart'
    show PackLifecycleReviewHarness, syntheticLifecyclePack;

final _generatedAt = DateTime.utc(2026, 11, 1, 1);

void main() {
  test(
    'full personal snapshot exports detached pack bytes and media for exactly one owner',
    () async {
      final h = await PackLifecycleReviewHarness.open(bindSource: true);
      addTearDown(h.close);
      final pack = syntheticLifecyclePack();
      final source = await h.install('source', pack, pinned: true);
      final target = await h.install(
        'target',
        syntheticLifecyclePack(catMeaning: 'Other owner cat'),
      );
      final before = await h.snapshot();
      final snapshot = await _snapshot(h, 'source');
      expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
      expect(
        snapshot.coveredScopes,
        containsAll(['learning_pack_versions', 'lexical_content_snapshots']),
      );
      expect(snapshot.sha256, sha256.convert(snapshot.bytes).toString());
      final document =
          jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
      expect(document['ownerId'], 'source');
      expect(document['schemaVersion'], 23);
      final data = document['data'] as Map<String, dynamic>;
      final packs = (data['learning_pack_versions'] as List).cast<Map>();
      expect(packs.length, 1);
      final archived = packs.single;
      expect(archived['id'], source.id);
      expect(archived['owner_id'], 'source');
      expect(archived['id'], isNot(target.id));
      expect(archived['package_bytes'], isA<String>());
      final detached = base64Decode(archived['package_bytes']! as String);
      expect(detached, pack.bytes);
      expect(sha256.convert(detached).toString(), source.packageSha256);
      final media =
          jsonDecode(archived['retained_media_json']! as String) as Map;
      final image = (media['images'] as List).single as Map;
      expect(
        base64Decode(image['dataBase64']! as String),
        pack.images.single.bytes,
      );
      final lexical = (data['lexical_content_snapshots'] as List).cast<Map>();
      expect(lexical.length, 2);
      expect(
        lexical.every(
          (row) =>
              row['owner_id'] == 'source' &&
              row['pack_version_id'] == source.id,
        ),
        isTrue,
      );
      final sourceWordIds = (data['vocabulary_words'] as List)
          .cast<Map>()
          .map((row) => row['id'])
          .toSet();
      expect(sourceWordIds.length, 2);
      expect(
        lexical.every((row) => sourceWordIds.contains(row['word_id'])),
        isTrue,
      );
      expect(
        (data['vocabulary_import_rows'] as List).cast<Map>().every(
          (row) => row['import_id'] == source.importId,
        ),
        isTrue,
      );
      expect(await h.snapshot(), before);
      final originalFirst = pack.bytes.first;
      detached[0] ^= 1;
      expect(pack.bytes.first, originalFirst);
      expect(
        (await h.packRows())
            .singleWhere((row) => row.id == source.id)
            .packageBytes,
        pack.bytes,
      );
    },
  );

  test(
    'deletion fence denies a prepared install before reverse purge and keeps the other owner exact',
    () async {
      final h = await PackLifecycleReviewHarness.open(bindSource: true);
      addTearDown(h.close);
      await h.install('source', syntheticLifecyclePack(), pinned: true);
      await h.install(
        'target',
        syntheticLifecyclePack(catMeaning: 'Other owner cat'),
        pinned: true,
      );
      await h.activate('source');
      final otherBefore = await _snapshot(h, 'target');
      final purgedSecrets = <String>[];
      await h.use('source', (packs, scope) async {
        final prepared = packs.prepareImport(
          scope: scope,
          pack: syntheticLifecyclePack(version: '2'),
        );
        final cloud = _cloud(h.nextTime());
        final token = await h.ownerWrites.beginDeletion(
          ownerId: 'source',
          firebaseUid: cloud.firebaseUid,
          idempotencyKey: cloud.idempotencyKey,
        );
        final fenced = await h.snapshot();
        await expectLater(
          packs.importPack(prepared),
          throwsA(isA<PackStorageException>()),
        );
        expect(await h.snapshot(), fenced);
        expect(
          (await h.rows(
            'learning_pack_versions',
          )).where((row) => row['owner_id'] == 'source').length,
          1,
        );
        await h.ownerWrites.markPending(token);
        await h.ownerWrites.markCloud(token, cloud);
        final local = await DriftLocalAccountDeletionGateway(
          h.database,
          nowUtc: h.nextTime,
          purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
            purgedSecrets.add('$ownerId:$firebaseUid');
          },
        ).deleteAfterCloud(ownerId: 'source', cloudReceipt: cloud);
        await h.ownerWrites.markLocal(token, cloud, local);
        expect(
          (await h.ownerWrites.inspect())!.phase,
          DeletionIntentPhase.localCompleted,
        );
        expect(local.deletedOwnerId, 'source');
        expect(local.newGuestOwnerId, startsWith('local:deleted:'));
        expect(purgedSecrets, ['source:synthetic-review-uid-source']);
      });
      for (final table in ownerUpgradeInventory) {
        final owned = (await h.rows(
          table,
        )).where((row) => row['owner_id'] == 'source');
        expect(owned, isEmpty, reason: table);
      }
      expect(
        (await h.rows('local_owners')).where((row) => row['id'] == 'source'),
        isEmpty,
      );
      final otherAfter = await _snapshot(h, 'target');
      expect(otherAfter.bytes, otherBefore.bytes);
      expect(otherAfter.sha256, otherBefore.sha256);
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );

  test(
    'lost acknowledgement after pack purge replays one guest and the original local receipt',
    () async {
      final h = await PackLifecycleReviewHarness.open(bindSource: true);
      addTearDown(h.close);
      await h.install('source', syntheticLifecyclePack());
      await h.install(
        'target',
        syntheticLifecyclePack(catMeaning: 'Other owner cat'),
      );
      await h.activate('source');
      final otherBefore = await _snapshot(h, 'target');
      final cloud = _cloud(h.nextTime());
      final token = await h.ownerWrites.beginDeletion(
        ownerId: 'source',
        firebaseUid: cloud.firebaseUid,
        idempotencyKey: cloud.idempotencyKey,
      );
      await h.ownerWrites.markPending(token);
      await h.ownerWrites.markCloud(token, cloud);
      var attempts = 0;
      Future<void> purge({
        required String ownerId,
        required String firebaseUid,
      }) async {
        expect(ownerId, 'source');
        expect(firebaseUid, cloud.firebaseUid);
        if (++attempts == 1) {
          throw StateError('Synthetic lost post-commit acknowledgement');
        }
      }

      await expectLater(
        DriftLocalAccountDeletionGateway(
          h.database,
          nowUtc: h.nextTime,
          purgeOwnerSecret: purge,
        ).deleteAfterCloud(ownerId: 'source', cloudReceipt: cloud),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.localDeleteFailed,
          ),
        ),
      );
      final afterCommit = await h.snapshot();
      final guest = (await h.rows('local_owners')).singleWhere(
        (row) => (row['id']! as String).startsWith('local:deleted:'),
      );
      expect(
        (await h.rows(
          'learning_pack_versions',
        )).every((row) => row['owner_id'] != 'source'),
        isTrue,
      );
      final local = await DriftLocalAccountDeletionGateway(
        h.database,
        nowUtc: h.nextTime,
        purgeOwnerSecret: purge,
      ).deleteAfterCloud(ownerId: 'source', cloudReceipt: cloud);
      expect(attempts, 2);
      expect(local.newGuestOwnerId, guest['id']);
      expect(
        local.completedAtUtc.millisecondsSinceEpoch,
        guest['created_at_utc_ms'],
      );
      expect(await h.snapshot(), afterCommit);
      expect((await _snapshot(h, 'target')).bytes, otherBefore.bytes);
      await h.ownerWrites.markLocal(token, cloud, local);
      expect(
        (await h.ownerWrites.inspect())!.phase,
        DeletionIntentPhase.localCompleted,
      );
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );
}

Future<LocalAccountSnapshot> _snapshot(
  PackLifecycleReviewHarness h,
  String owner,
) => DriftAccountSnapshotBuilder(
  h.database,
  nowUtc: () => _generatedAt,
).build(ownerId: owner);

CloudDeletionReceipt _cloud(DateTime now) => CloudDeletionReceipt(
  receiptId: 'synthetic-pack-cloud-receipt',
  ownerId: 'source',
  firebaseUid: 'synthetic-review-uid-source',
  idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
  completedAtUtc: now,
).durableMarker();
