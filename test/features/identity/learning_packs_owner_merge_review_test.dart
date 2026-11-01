import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  test(
    'installed owner collisions retain both lexical histories and canonical receipts',
    () async {
      final h = await PackLifecycleReviewHarness.open();
      addTearDown(h.close);
      final pack = syntheticLifecyclePack();
      final source = await h.install('source', pack);
      final target = await h.install('target', pack);
      final lexicalBefore = await h.rows('lexical_content_snapshots');
      final importsBefore = await h.rows('vocabulary_imports');
      final receiptsBefore = await h.rows('vocabulary_import_rows');
      expect(lexicalBefore.length, 4);
      await h.merge('source', 'target');

      final retained = await h.packRows();
      expect(retained.length, 1);
      expect(retained.single.id, target.id);
      expect(retained.single.ownerId, 'target');
      expect(retained.single.categoryId, target.categoryId);
      expect(retained.single.importId, target.importId);
      expect((await h.rows('vocabulary_categories')).length, 1);
      final words = await h.rows('vocabulary_words');
      expect(words.length, 2);
      expect(words.every((row) => row['owner_id'] == 'target'), isTrue);
      final wordIds = words.map((row) => row['id']).toSet();
      final lexicalAfter = await h.rows('lexical_content_snapshots');
      expect(lexicalAfter.length, 4);
      expect(
        lexicalAfter.every(
          (row) =>
              row['owner_id'] == 'target' &&
              row['pack_version_id'] == target.id &&
              wordIds.contains(row['word_id']),
        ),
        isTrue,
      );
      expect(
        _historicalLexical(lexicalAfter),
        _historicalLexical(lexicalBefore),
      );
      final importsAfter = await h.rows('vocabulary_imports');
      expect(
        importsAfter.map((row) => row['id']).toSet(),
        importsBefore.map((row) => row['id']).toSet(),
      );
      expect(
        importsAfter.every(
          (row) =>
              row['owner_id'] == 'target' &&
              row['category_id'] == target.categoryId &&
              row['accepted_count'] == 2,
        ),
        isTrue,
      );
      final receiptsAfter = await h.rows('vocabulary_import_rows');
      expect(
        receiptsAfter.map((row) => row['id']).toSet(),
        receiptsBefore.map((row) => row['id']).toSet(),
      );
      expect(
        receiptsAfter.every((row) => wordIds.contains(row['word_id'])),
        isTrue,
      );

      final beforeRead = await h.snapshot();
      await h.use('target', (packs, scope) async {
        final detail = await packs.detail(scope, target.id);
        expect(
          detail.content!.manifest.payloadSha256,
          pack.manifest.payloadSha256,
        );
        expect(detail.bindings.length, 4);
        expect(detail.bindings.every((binding) => binding.isCurrent), isTrue);
        for (final word in words) {
          final lexical = await packs.currentLexical(
            scope: scope,
            wordId: word['id']! as String,
          );
          expect(lexical!.word.ownerId, 'target');
          expect(lexical.word.categoryId, target.categoryId);
          expect(lexical.pack.id, target.id);
        }
      });
      expect(await h.snapshot(), beforeRead);
      expect(await h.foreignKeyViolations(), isEmpty);
      expect(
        (await h.rows(
          'learning_pack_versions',
        )).any((row) => row['id'] == source.id),
        isFalse,
      );
    },
  );

  test(
    'installed source promotes a cache-only target without changing original receipt times',
    () async {
      final h = await PackLifecycleReviewHarness.open();
      addTearDown(h.close);
      final pack = syntheticLifecyclePack();
      final source = await h.install('source', pack, pinned: true);
      final target = await h.install('target', pack, install: false);
      final before = await h.rows('lexical_content_snapshots');
      await h.merge('source', 'target');
      final retained = (await h.packRows()).single;
      expect(retained.id, target.id);
      expect(retained.categoryId, source.categoryId);
      expect(retained.importId, source.importId);
      expect(
        retained.installedAtUtcMs,
        source.installedAtUtc!.millisecondsSinceEpoch,
      );
      expect(
        retained.createdAtUtcMs,
        target.createdAtUtc.millisecondsSinceEpoch,
      );
      expect(retained.isPinned, isFalse);
      expect(retained.packageBytes, pack.bytes);
      expect(
        _historicalLexical(await h.rows('lexical_content_snapshots')),
        _historicalLexical(before),
      );
      await h.use('target', (packs, scope) async {
        final detail = await packs.detail(scope, target.id);
        expect(detail.pack.isInstalled, isTrue);
        expect(detail.bindings.length, 2);
        expect(detail.bindings.every((binding) => binding.isCurrent), isTrue);
        for (final binding in detail.bindings) {
          expect(
            (await packs.currentLexical(
              scope: scope,
              wordId: binding.wordId,
            ))!.entry.code,
            binding.entry.code,
          );
        }
      });
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );

  test(
    'canonical target POS edit keeps source pins historical after a word collision',
    () async {
      final h = await PackLifecycleReviewHarness.open();
      addTearDown(h.close);
      final pack = syntheticLifecyclePack();
      await h.install('source', pack);
      final target = await h.install('target', pack);
      final lexicalBefore = await h.rows('lexical_content_snapshots');
      final targetCat =
          await (h.database.select(h.database.vocabularyWords)..where(
                (row) =>
                    row.ownerId.equals('target') & row.spelling.equals('cat'),
              ))
              .getSingle();
      await DriftVocabularyRepository(h.database).updateWord(
        DriftVocabularyRepository.wordToDomain(
          targetCat,
        ).copyWith(partOfSpeech: 'adjective', updatedAtUtc: h.nextTime()),
      );
      await h.merge('source', 'target');
      expect(
        _historicalLexical(await h.rows('lexical_content_snapshots')),
        _historicalLexical(lexicalBefore),
      );
      final beforeRead = await h.snapshot();
      await h.use('target', (packs, scope) async {
        final detail = await packs.detail(scope, target.id);
        final cats = detail.bindings.where(
          (binding) => binding.entry.code == 'cat',
        );
        expect(cats.length, 2);
        expect(cats.every((binding) => !binding.isCurrent), isTrue);
        await expectLater(
          packs.currentLexical(scope: scope, wordId: targetCat.id),
          throwsA(
            isA<PackStorageException>().having(
              (error) => error.code,
              'code',
              PackStorageFailureCode.staleContent,
            ),
          ),
        );
        final dog = detail.bindings.firstWhere(
          (binding) => binding.entry.code == 'dog',
        );
        expect(
          (await packs.currentLexical(
            scope: scope,
            wordId: dog.wordId,
          ))!.entry.code,
          'dog',
        );
      });
      expect(await h.snapshot(), beforeRead);
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );

  test(
    'different package digests retain installed variants and require explicit content selection',
    () async {
      final h = await PackLifecycleReviewHarness.open();
      addTearDown(h.close);
      final source = await h.install(
        'source',
        syntheticLifecyclePack(catMeaning: 'Different synthetic cat'),
      );
      final target = await h.install('target', syntheticLifecyclePack());
      final before = await h.rows('lexical_content_snapshots');
      await h.merge('source', 'target');
      expect((await h.packRows()).length, 2);
      expect(
        _historicalLexical(await h.rows('lexical_content_snapshots')),
        _historicalLexical(before),
      );
      final beforeRead = await h.snapshot();
      await h.use('target', (packs, scope) async {
        final list = await packs.list(scope);
        expect(list.length, 2);
        expect(list.every((pack) => pack.identityConflict), isTrue);
        for (final id in [source.id, target.id]) {
          final detail = await packs.detail(scope, id);
          expect(detail.bindings.every((binding) => binding.isCurrent), isTrue);
          final binding = detail.bindings.first;
          await expectLater(
            packs.currentLexical(scope: scope, wordId: binding.wordId),
            throwsA(
              isA<PackStorageException>().having(
                (error) => error.code,
                'code',
                PackStorageFailureCode.conflict,
              ),
            ),
          );
          expect(
            (await packs.currentLexical(
              scope: scope,
              wordId: binding.wordId,
              packVersionId: id,
            ))!.pack.id,
            id,
          );
        }
      });
      expect(await h.snapshot(), beforeRead);
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );

  test(
    'another owner merge retains all history and content-addressed conflict references',
    () async {
      final h = await PackLifecycleReviewHarness.open();
      addTearDown(h.close);
      final pack = syntheticLifecyclePack();
      await h.install('source', pack);
      await h.install('target', pack);
      final third = await h.install('third', pack);
      final before = await h.rows('lexical_content_snapshots');
      await h.merge('source', 'target');
      await h.merge('target', 'third');
      final retained = (await h.packRows()).single;
      expect(retained.id, third.id);
      expect(retained.ownerId, 'third');
      expect(retained.packageBytes, pack.bytes);
      expect(
        _historicalLexical(await h.rows('lexical_content_snapshots')),
        _historicalLexical(before),
      );
      final conflicts = (await h.rows(
        'sync_conflicts',
      )).where((row) => row['entity_type'] == 'learningPack').toList();
      expect(conflicts.length, 2);
      for (final conflict in conflicts) {
        expect(conflict['owner_id'], 'third');
        for (final field in ['local_snapshot_json', 'cloud_snapshot_json']) {
          final snapshot =
              jsonDecode(conflict[field]! as String) as Map<String, dynamic>;
          final media = snapshot['retainedMediaJson'] as Map;
          expect(media['retainedPackageSha256'], retained.packageSha256);
          expect(media['sha256'], retained.retainedMediaSha256);
          expect(snapshot['packageBytes'], isA<Map>());
          expect(
            (snapshot['packageBytes'] as Map)['retainedPackageSha256'],
            retained.packageSha256,
          );
        }
      }
      await h.use('third', (packs, scope) async {
        final detail = await packs.detail(scope, third.id);
        expect(detail.bindings.length, 6);
        expect(detail.bindings.every((binding) => binding.isCurrent), isTrue);
        for (final word in await h.rows('vocabulary_words')) {
          expect(
            (await packs.currentLexical(
              scope: scope,
              wordId: word['id']! as String,
            ))!.pack.id,
            third.id,
          );
        }
      });
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );

  test(
    'a late colliding-pack integrity rejection rolls back every earlier remap',
    () async {
      final h = await PackLifecycleReviewHarness.open();
      addTearDown(h.close);
      final source = await h.install('source', syntheticLifecyclePack());
      await h.install('target', syntheticLifecyclePack());
      await h.activate('source');
      await (h.database.update(
        h.database.learningPackVersions,
      )..where((row) => row.id.equals(source.id))).write(
        db.LearningPackVersionsCompanion(retainedMediaSha256: Value('0' * 64)),
      );
      final before = await h.snapshot();
      await expectLater(
        h.merge('source', 'target'),
        throwsA(isA<StateError>()),
      );
      expect(await h.snapshot(), before);
      expect(await h.foreignKeyViolations(), isEmpty);
    },
  );
}

Map<String, Map<String, Object?>> _historicalLexical(
  List<Map<String, Object?>> rows,
) => {
  for (final row in rows)
    row['id']! as String: Map<String, Object?>.of(row)
      ..remove('owner_id')
      ..remove('pack_version_id')
      ..remove('word_id'),
};

LearningPack syntheticLifecyclePack({
  String catMeaning = 'Synthetic cat',
  String version = '1',
}) => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'synthetic-lifecycle-animals',
      version: version,
      title: 'Synthetic lifecycle animals',
      objectives: ['Synthetic animal practice'],
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
        code: 'cat',
        spelling: 'cat',
        meaning: catMeaning,
        partOfSpeech: 'noun',
        definition: 'A synthetic cat definition.',
        imageId: 'cat-marker',
      ),
      LearningPackEntry(
        code: 'dog',
        spelling: 'dog',
        meaning: 'Synthetic dog',
        partOfSpeech: 'noun',
        definition: 'A synthetic dog definition.',
      ),
    ],
    images: [
      LearningPackImage(
        id: 'cat-marker',
        mimeType: 'image/png',
        width: 1,
        height: 1,
        altText: 'Synthetic single-pixel fixture marker',
        bytes: Uint8List.fromList(
          image.encodePng(image.Image(width: 1, height: 1)),
        ),
      ),
    ],
  ),
);

final class PackLifecycleReviewHarness {
  PackLifecycleReviewHarness(this.database) {
    ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: nextTime,
      nonceGenerator: () => 'synthetic-review-deletion-nonce',
    );
    ownerUpgrade = DriftOwnerUpgradeRepository(
      database,
      nowUtc: nextTime,
      generateConflictId: () => 'synthetic-review-conflict:${++sequence}',
      generateOwnerId: () => 'synthetic-review-unused-guest',
    );
  }
  final db.AppDatabase database;
  late final DriftOwnerWriteCoordinator ownerWrites;
  late final DriftOwnerUpgradeRepository ownerUpgrade;
  var sequence = 0;
  var clock = 0;

  static Future<PackLifecycleReviewHarness> open({
    bool bindSource = false,
  }) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    for (final owner in ['source', 'target', 'third']) {
      final bound = owner != 'source' || bindSource;
      await database
          .into(database.localOwners)
          .insert(
            db.LocalOwnersCompanion.insert(
              id: owner,
              createdAtUtcMs: 1,
              isActive: const Value(false),
              firebaseUid: Value(bound ? 'synthetic-review-uid-$owner' : null),
              accountState: Value(bound ? 'firebaseBound' : 'localGuest'),
            ),
          );
    }
    return PackLifecycleReviewHarness(database);
  }

  DateTime nextTime() =>
      DateTime.utc(2026, 11, 1).add(Duration(milliseconds: ++clock));

  Future<void> activate(String owner) async {
    final active = await database
        .select(database.localOwners)
        .get()
        .then((rows) => rows.where((row) => row.isActive).toList());
    if (active.length == 1 && active.single.id == owner) return;
    await database.transaction(() async {
      await database
          .update(database.localOwners)
          .write(const db.LocalOwnersCompanion(isActive: Value(false)));
      final changed =
          await (database.update(database.localOwners)
                ..where((row) => row.id.equals(owner)))
              .write(const db.LocalOwnersCompanion(isActive: Value(true)));
      expect(changed, 1);
    });
  }

  Future<T> use<T>(
    String owner,
    Future<T> Function(LearningPackUseCases packs, PackOwnerScope scope) read,
  ) async {
    await activate(owner);
    final packs = LearningPackUseCases(
      repository: DriftLearningPackRepository(
        database: database,
        ownerWrites: ownerWrites,
      ),
      nowUtc: nextTime,
      generateId: () => 'synthetic-review-operation:${++sequence}',
    );
    try {
      final scope = (await packs.captureOwner(stillCurrent: () => true))!;
      expect(scope.ownerId, owner);
      return await read(packs, scope);
    } finally {
      await packs.dispose();
    }
  }

  Future<StoredLearningPack> install(
    String owner,
    LearningPack pack, {
    bool install = true,
    bool pinned = false,
  }) => use(
    owner,
    (packs, scope) => packs.importPack(
      packs.prepareImport(
        scope: scope,
        pack: pack,
        install: install,
        pinned: pinned,
      ),
    ),
  );

  Future<void> merge(String source, String target) async {
    await activate(source);
    await ownerUpgrade.upgrade(
      activeOwnerId: source,
      firebaseUid: 'synthetic-review-uid-$target',
    );
  }

  Future<List<db.LearningPackVersion>> packRows() =>
      database.select(database.learningPackVersions).get();

  Future<List<Map<String, Object?>>> rows(String table) async =>
      (await database
              .customSelect('SELECT * FROM "$table" ORDER BY rowid')
              .get())
          .map((row) => Map<String, Object?>.of(row.data))
          .toList();

  Future<Map<String, List<String>>> snapshot() async => {
    for (final table in database.allTables)
      table.actualTableName: [
        for (final row in await rows(table.actualTableName)) jsonEncode(row),
      ],
  };

  Future<List<Object?>> foreignKeyViolations() =>
      database.customSelect('PRAGMA foreign_key_check').get();
  Future<void> close() => database.close();
}
