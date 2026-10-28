
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import.dart';

Future<Uint8List?> _asset(ContentIdentity identity) async {
  final data = await rootBundle.load(
    'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
  );
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late db.AppDatabase database;
  late DriftContentManifestRepository manifests;
  late DriftVocabularyRepository vocabulary;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    manifests = DriftContentManifestRepository(
      database,
      loadArtifactBytes: _asset,
    );
    vocabulary = DriftVocabularyRepository(
      database,
      contentManifests: manifests,
    );
    for (final owner in ['owner-a', 'owner-b']) {
      await database
          .into(database.localOwners)
          .insert(
            db.LocalOwnersCompanion.insert(
              id: owner,
              createdAtUtcMs: 1,
              isActive: Value(owner == 'owner-a'),
            ),
          );
    }
  });
  tearDown(() => database.close());

  Future<void> install() =>
      PackagedStarterCatalog.provision(database, manifests, _asset);
  Future<void> privateWord({
    String id = 'word:private-b',
    bool spoof = false,
  }) async {
    await database
        .into(database.vocabularyCategories)
        .insert(
          db.VocabularyCategoriesCompanion.insert(
            id: 'category-b',
            ownerId: 'owner-b',
            name: 'Private',
            normalizedName: 'private',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          db.VocabularyWordsCompanion.insert(
            id: id,
            ownerId: 'owner-b',
            categoryId: 'category-b',
            spelling: 'secret',
            normalizedSpelling: 'secret',
            meaning: 'ส่วนตัว',
            normalizedMeaning: 'ส่วนตัว',
            partOfSpeech: 'noun',
            isGlobal: Value(spoof),
            contentProvenance: Value(spoof ? 'packaged' : 'userAuthored'),
            contentReviewState: Value(spoof ? 'approved' : 'unreviewed'),
            contentPublicationState: Value(spoof ? 'published' : 'private'),
            contentChecksumSha256: Value(
              ContentQualityPolicy.vocabularyChecksumSha256(
                categoryId: 'category-b',
                spelling: 'secret',
                normalizedSpelling: 'secret',
                meaning: 'ส่วนตัว',
                normalizedMeaning: 'ส่วนตัว',
                partOfSpeech: 'noun',
                cefrLevel: null,
                source: 'manual',
                isGlobal: spoof,
              ),
            ),
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }

  test(
    'catalog replay preserves exact rows and creates no owner evidence',
    () async {
      await install();
      final firstWords = await database.select(database.vocabularyWords).get();
      final firstManifests = await database
          .select(database.contentManifests)
          .get();
      await install();
      expect(await database.select(database.vocabularyWords).get(), firstWords);
      expect(
        await database.select(database.contentManifests).get(),
        firstManifests,
      );
      expect(firstWords, hasLength(12));
      expect(firstManifests, hasLength(12));
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(await vocabulary.listAllWords('owner-a'), hasLength(12));
      expect(await vocabulary.listAllWords('owner-b'), hasLength(12));
    },
  );

  for (final corrupt in [false, true]) {
    test(
      '${corrupt ? 'corrupt' : 'missing'} final asset leaves no partial catalog',
      () async {
        Future<Uint8List?> damaged(ContentIdentity identity) async {
          if (identity != PackagedStarterCatalog.words.last.identity) {
            return _asset(identity);
          }
          if (!corrupt) return null;
          final copy = Uint8List.fromList((await _asset(identity))!);
          copy[0] ^= 1;
          return copy;
        }

        await privateWord();
        await expectLater(
          PackagedStarterCatalog.provision(database, manifests, damaged),
          throwsA(
            isA<ContentQualityFailure>().having(
              (e) => e.code,
              'code',
              corrupt
                  ? ContentQualityFailureCode.checksumMismatch
                  : ContentQualityFailureCode.missingReference,
            ),
          ),
        );
        expect(await database.select(database.contentManifests).get(), isEmpty);
        expect(await database.select(database.localOwners).get(), hasLength(2));
        expect(
          (await vocabulary.listAllWords('owner-b')).single.id,
          'word:private-b',
        );
        expect(await vocabulary.listAllWords('owner-a'), isEmpty);
      },
    );
  }

  test(
    'known ID collision preserves private word and rolls catalog back',
    () async {
      await privateWord(id: PackagedStarterCatalog.words.first.id);
      final before = await database.select(database.vocabularyWords).get();
      await expectLater(
        install(),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.immutableRevisionConflict,
          ),
        ),
      );
      expect(await database.select(database.vocabularyWords).get(), before);
      expect(await database.select(database.contentManifests).get(), isEmpty);
      expect(await database.select(database.localOwners).get(), hasLength(2));
    },
  );

  test(
    'core revision corruption is hidden and never overwritten by replay',
    () async {
      await install();
      final id = PackagedStarterCatalog.words.first.id;
      await (database.update(database.vocabularyWords)
            ..where((row) => row.id.equals(id)))
          .write(const db.VocabularyWordsCompanion(contentRevision: Value(2)));
      await expectLater(
        vocabulary.readPinnedByIds([id]),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );
      expect(await vocabulary.listAllWords('owner-a'), hasLength(11));
      await expectLater(
        install(),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.immutableRevisionConflict,
          ),
        ),
      );
      final retained = await (database.select(
        database.vocabularyWords,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(retained.contentRevision, 2);
    },
  );

  test(
    'last manifest revision collision rolls back all starter rows',
    () async {
      final expected = PackagedStarterCatalog.words.last.manifest;
      await database
          .into(database.contentManifests)
          .insert(
            db.ContentManifestsCompanion.insert(
              id: expected.storageId,
              contentType: expected.identity.type.name,
              contentId: expected.identity.id,
              revision: 2,
              checksumSha256: expected.checksumSha256,
              byteLength: expected.byteLength,
              provenance: expected.provenance.name,
              sourceUri: expected.sourceUri,
              reviewState: expected.reviewState.name,
              publicationState: expected.publicationState.name,
              createdAtUtcMs: expected.createdAtUtc.millisecondsSinceEpoch,
              reviewedAtUtcMs: Value(
                expected.reviewedAtUtc!.millisecondsSinceEpoch,
              ),
              publishedAtUtcMs: Value(
                expected.publishedAtUtc!.millisecondsSinceEpoch,
              ),
            ),
          );
      final before = await database.select(database.contentManifests).get();
      await expectLater(
        install(),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.immutableRevisionConflict,
          ),
        ),
      );
      expect(await database.select(database.contentManifests).get(), before);
      expect(await database.select(database.vocabularyWords).get(), isEmpty);
      expect(
        await database.select(database.vocabularyCategories).get(),
        isEmpty,
      );
      expect(await database.select(database.localOwners).get(), hasLength(2));
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'another learner cannot expose a private word by spoofing global flags',
    () async {
      await install();
      await privateWord(spoof: true);
      expect(await vocabulary.listAllWords('owner-a'), hasLength(12));
      await expectLater(
        vocabulary.readPinnedByIds(['word:private-b']),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );
      expect(await vocabulary.listAllWords('owner-b'), hasLength(13));
    },
  );

  test(
    'all direct mutation paths reject reserved catalog even with its owner ID',
    () async {
      await install();
      final word = (await vocabulary.readPinnedByIds([
        PackagedStarterCatalog.words.first.id,
      ])).single;
      final category =
          (await vocabulary.watchCategories('owner-a').first).single;
      final now = DateTime.utc(2026, 9, 9);
      final operations = <Future<Object?> Function()>[
        () => vocabulary.createWord(word),
        () => vocabulary.updateWord(
          word.copyWith(meaning: 'changed', normalizedMeaning: 'changed'),
        ),
        () => vocabulary.deleteWord(
          ownerId: word.ownerId,
          wordId: word.id,
          nowUtc: now,
        ),
        () => vocabulary.createCategory(category),
        () => vocabulary.renameCategory(
          ownerId: category.ownerId,
          categoryId: category.id,
          name: 'changed',
          normalizedName: 'changed',
          nowUtc: now,
        ),
        () => vocabulary.deleteCategory(
          ownerId: category.ownerId,
          categoryId: category.id,
          nowUtc: now,
        ),
        () => DriftVocabularyImportRepository(database).persist(
          PreparedVocabularyImport(
            importId: 'import:blocked',
            ownerId: category.ownerId,
            categoryId: category.id,
            sourceName: 'synthetic',
            sourceHash: 'a' * 64,
            rows: const [],
            nowUtc: now,
          ),
          isCancelled: () => false,
        ),
        () => LocalDataDeletion(
          database,
          deleteOwnerSecrets: (_) async {},
        ).eraseAll(ownerId: PackagedStarterCatalog.ownerId),
      ];
      for (final operation in operations) {
        await expectLater(
          Future.sync(operation),
          throwsA(isA<InvalidVocabularyFailure>()),
        );
      }
      expect(await vocabulary.listAllWords('owner-a'), hasLength(12));
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'learner erasure preserves the other learner and immutable catalog',
    () async {
      await install();
      await privateWord();
      final catalogBefore =
          (await database.select(database.vocabularyWords).get())
              .where((row) => row.ownerId == PackagedStarterCatalog.ownerId)
              .toList();
      await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'owner-a');
      expect(await vocabulary.listAllWords('owner-b'), hasLength(13));
      expect(
        (await database.select(database.vocabularyWords).get()).where(
          (row) => row.ownerId == PackagedStarterCatalog.ownerId,
        ),
        catalogBefore,
      );
      expect(
        await database.select(database.contentManifests).get(),
        hasLength(12),
      );
    },
  );
}
