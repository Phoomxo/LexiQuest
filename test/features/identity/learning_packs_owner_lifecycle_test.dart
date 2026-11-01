import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

void main() {
  test(
    'owner merge retains cached bytes and distinct immutable pack variants',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      for (final owner in ['source', 'target']) {
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: owner,
                createdAtUtcMs: 1,
                isActive: Value(owner == 'source'),
          accountState: Value(owner == 'target' ? 'firebaseBound' : 'localGuest'),
                firebaseUid: Value(
                  owner == 'target' ? 'synthetic-pack-uid' : null,
                ),
              ),
            );
      }
      final original = _pack('Synthetic meaning');
      final variant = _pack('Different synthetic meaning');
      await _cache(database, 'source-same', 'source', original, cached: true);
      await _cache(database, 'target-same', 'target', original, cached: false);
      await _cache(database, 'source-variant', 'source', variant, cached: true);
      var conflict = 0;
      final repository = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => DateTime.utc(2026, 11, 1),
        generateConflictId: () => 'synthetic-pack-conflict:${++conflict}',
        generateOwnerId: () => 'unused',
      );
      await repository.upgrade(
        activeOwnerId: 'source',
        firebaseUid: 'synthetic-pack-uid',
      );
      final packs = await database.select(database.learningPackVersions).get();
      expect(packs.length, 2);
      expect(packs.every((row) => row.ownerId == 'target'), isTrue);
      final retained = packs.singleWhere((row) => row.id == 'target-same');
      expect(retained.packageBytes, original.bytes);
      expect(retained.isPinned, isFalse);
      expect(retained.revision, 2);
      expect(retained.lastMutationId, startsWith('pack-merge:'));
      expect(packs.map((row) => row.packageSha256).toSet(), {
        original.packageSha256,
        variant.packageSha256,
      });
      final beforeReplay = packs.map((row) => row.toJson()).toList();
      await repository.upgrade(
        activeOwnerId: 'target',
        firebaseUid: 'synthetic-pack-uid',
      );
      expect(
        (await database.select(database.learningPackVersions).get())
            .map((row) => row.toJson())
            .toList(),
        beforeReplay,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

LearningPack _pack(String meaning) => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'synthetic-owner-pack',
      version: '1',
      title: 'Synthetic owner lifecycle',
      objectives: ['Synthetic objective'],
      cefrLevel: 'A1',
      language: 'en',
      meaningLanguage: 'en',
      provenance: const LearningPackProvenance(
        author: 'Synthetic fixture',
        source: 'Synthetic fixture',
        license: 'Synthetic test only',
        attribution: 'No real publisher',
      ),
    ),
    entries: [
      LearningPackEntry(
        code: 'word',
        spelling: 'cat',
        meaning: meaning,
        partOfSpeech: 'noun',
      ),
    ],
  ),
);

Future<void> _cache(
  AppDatabase database,
  String id,
  String owner,
  LearningPack pack, {
  required bool cached,
}) async {
  final media = LearningPackRetainedMedia.fromPack(pack).canonicalJson;
  await database
      .into(database.learningPackVersions)
      .insert(
        LearningPackVersionsCompanion.insert(
          id: id,
          ownerId: owner,
          packId: pack.manifest.packId,
          packVersion: pack.manifest.version,
          manifestJson: pack.manifest.canonicalJson,
          manifestSha256: sha256
              .convert(utf8.encode(pack.manifest.canonicalJson))
              .toString(),
          packageSha256: pack.packageSha256,
          packageByteCount: pack.byteCount,
          packageBytes: Value(cached ? pack.bytes : null),
          retainedMediaJson: media,
          retainedMediaSha256: sha256.convert(utf8.encode(media)).toString(),
          sourceDescriptorJson:
              '{"schemaVersion":1,"kind":"userFile","catalogId":null}',
          isPinned: Value(cached),
          revision: 1,
          lastMutationId: 'synthetic-install:$id',
          lastMutationSha256: 'a' * 64,
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}
