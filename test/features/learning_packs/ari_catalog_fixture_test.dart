import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import '../../support/ari_catalog_fixture.dart';

DriftLearningPackRepository repository(AppDatabase db) =>
    DriftLearningPackRepository(
      db,
      contentManifests: DriftContentManifestRepository(db),
    );

void main() {
  test('fixture detail words respect the existing active owner', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) VALUES ('existing-owner', 'localGuest', 1, 1)",
    );
    await insertAriCatalogFixture(db);
    final detail = await repository(db).getVersion('pack:ari-food-117', 2);
    final vocabulary = DriftVocabularyRepository(
      db,
      contentManifests: DriftContentManifestRepository(db),
    );
    final words = await vocabulary.readPinnedByIds(detail.vocabularyWordIds);
    expect(words.length, 2);
    expect(words.map((word) => word.ownerId).toSet(), {'existing-owner'});
    expect((await db.select(db.localOwners).get()).length, 1);
    await db.customStatement("UPDATE local_owners SET is_active = 0");
    await db.customStatement(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) VALUES ('other-owner', 'localGuest', 2, 1)",
    );
    await expectLater(
      vocabulary.readPinnedByIds(detail.vocabularyWordIds),
      throwsA(anything),
    );
  });

  test(
    'canonical fixture preserves distinct filters and exact revisions',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await insertAriCatalogFixture(db);
      final repo = repository(db);
      expect((await repo.list(LearningPackFilter())).length, 3);
      final food = await repo.list(
        LearningPackFilter(cefrLevels: {'A1'}, topics: {'food'}),
      );
      expect(food.map((p) => p.revision).toSet(), {1, 2});
      expect(
        (await repo.getVersion(
          'pack:ari-food-117',
          1,
        )).vocabularyWordIds.length,
        1,
      );
      expect(
        (await repo.getVersion(
          'pack:ari-food-117',
          2,
        )).vocabularyWordIds.length,
        2,
      );
      expect(
        (await repo.list(
          LearningPackFilter(cefrLevels: {'A2'}, topics: {'food'}),
        )),
        isEmpty,
      );
      expect(
        (await db.select(db.localOwners).get()).where((o) => o.isActive),
        isEmpty,
      );
    },
  );

  test('fixture does not bypass canonical checksum validation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await insertAriCatalogFixture(db);
    await db.customStatement(
      "UPDATE learning_packs SET title = 'tampered' WHERE pack_id = 'pack:ari-food-117'",
    );
    await expectLater(
      repository(db).getVersion('pack:ari-food-117', 2),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'duplicate fixture fails atomically without changing existing rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await insertAriCatalogFixture(db);
      await expectLater(insertAriCatalogFixture(db), throwsA(anything));
      expect((await repository(db).list(LearningPackFilter())).length, 3);
      expect((await db.select(db.vocabularyWords).get()).length, 2);
    },
  );

  // Explicit host-only entry operating on a backed-up working clone. No app
  // startup hook, environment-based production behavior or schema changes.
  test(
    'emit canonical fixture into explicitly supplied working clone',
    () async {
      final supplied = Platform.environment['ARI_CATALOG_FIXTURE_DATABASE'];
      final allowed = File(
        'build/ari-catalog-fixture/working/lexiquest.sqlite',
      ).absolute;
      expect(
        path.normalize(File(supplied!).absolute.path),
        path.normalize(allowed.path),
      );
      expect(allowed.existsSync(), isTrue);
      expect(
        path.normalize(allowed.resolveSymbolicLinksSync()),
        path.normalize(allowed.path),
      );
      final db = AppDatabase(NativeDatabase(allowed));
      try {
        await insertAriCatalogFixture(db);
        final repo = repository(db);
        for (final revision in [1, 2]) {
          expect(
            (await repo.getVersion(
              'pack:ari-food-117',
              revision,
            )).summary.revision,
            revision,
          );
        }
        expect(
          (await repo.getVersion('pack:ari-travel-117', 3)).summary.cefrLevel,
          'A2',
        );
      } finally {
        await db.close();
      }
    },
    skip: Platform.environment['ARI_CATALOG_FIXTURE_DATABASE'] == null,
  );
}
