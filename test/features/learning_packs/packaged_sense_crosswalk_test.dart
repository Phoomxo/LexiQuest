import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';

Future<Uint8List?> load(ContentIdentity identity) async {
  if (identity == PackagedSenseCrosswalk.identity) {
    return File(PackagedSenseCrosswalk.assetPath).readAsBytes();
  }
  if (identity.type != ContentType.lexicalMetadata) return null;
  return File(
    'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
  ).readAsBytes();
}

void main() {
  Map<String, Object?> pinJson() => {
    'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
    'revision': 1,
    'artifactHash': PackagedSenseCrosswalk.artifactHash,
  };

  test(
    'saved pin round trips strictly and does not select latest content',
    () async {
      final artifact = PackagedSenseCrosswalk.verify(
        (await load(PackagedSenseCrosswalk.identity))!,
      );
      final manifests = _Manifests(artifact);
      final repository = SenseCrosswalkRepository(manifests);
      final pin = SenseCrosswalkPin.fromJson(pinJson());
      expect(pin.toJson(), pinJson());
      expect(
        (await repository.requirePinned(pin)).artifactHash,
        PackagedSenseCrosswalk.artifactHash,
      );
      expect(manifests.requested, PackagedSenseCrosswalk.identity);
      for (final change in [
        {'revision': 2},
        {'artifactHash': '0' * 64},
        {'corpusManifestHash': '1' * 64},
      ]) {
        await expectLater(
          repository.requirePinned(
            SenseCrosswalkPin.fromJson({...pinJson(), ...change}),
          ),
          throwsA(isA<ContentQualityFailure>()),
        );
      }
    },
  );

  test('saved pin rejects malformed or unversioned archive fields', () {
    for (final change in <Map<String, Object?>>[
      {'revision': 0},
      {'revision': 1.0},
      {'revision': 2147483648},
      {'artifactHash': 'bad'},
      {'corpusManifestHash': 'A' * 64},
      {'extra': true},
    ]) {
      expect(
        () => SenseCrosswalkPin.fromJson({...pinJson(), ...change}),
        throwsFormatException,
      );
    }
    final missing = pinJson()..remove('revision');
    expect(() => SenseCrosswalkPin.fromJson(missing), throwsFormatException);
  });

  test(
    'pinned reader rechecks bytes even when a repository claims verification',
    () async {
      final bytes = (await load(PackagedSenseCrosswalk.identity))!;
      final forged = VerifiedContentManifest(
        manifest: PackagedSenseCrosswalk.manifest,
        bytes: Uint8List.fromList(bytes)..[20] ^= 1,
      );
      await expectLater(
        SenseCrosswalkRepository(
          _Manifests(forged),
        ).requirePinned(SenseCrosswalkPin.fromJson(pinJson())),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.checksumMismatch,
          ),
        ),
      );
    },
  );

  test(
    'disk reopen retains exact mapping and rejects manifest replacement',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crosswalk-reopen-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/content.sqlite');
      var database = db.AppDatabase(NativeDatabase(file));
      final bytes = (await load(PackagedSenseCrosswalk.identity))!;
      try {
        await DriftContentManifestRepository(
          database,
          loadArtifactBytes: load,
        ).provisionPackagedArtifact(PackagedSenseCrosswalk.verify(bytes));
      } finally {
        await database.close();
      }
      database = db.AppDatabase(NativeDatabase(file));
      addTearDown(database.close);
      final manifests = DriftContentManifestRepository(
        database,
        loadArtifactBytes: load,
      );
      final repository = SenseCrosswalkRepository(manifests);
      final pin = SenseCrosswalkPin.fromJson(pinJson());
      final before = (await repository.requirePinned(
        pin,
      )).entries.map((e) => e.ref.stableHash).toList();
      await manifests.provisionPackagedArtifact(
        PackagedSenseCrosswalk.verify(bytes),
      );
      expect(
        (await repository.requirePinned(
          pin,
        )).entries.map((e) => e.ref.stableHash),
        before,
      );
      await expectLater(
        database.customStatement(
          "UPDATE content_manifests SET publication_state = 'retired' WHERE id = ?",
          [PackagedSenseCrosswalk.manifest.storageId],
        ),
        throwsA(
          predicate<Object>(
            (e) =>
                e.toString().contains('content_manifest_revision_is_immutable'),
          ),
        ),
      );
      await expectLater(
        manifests.provisionPackagedArtifact(
          VerifiedContentManifest(
            manifest: _manifest(sourceUri: 'asset://changed-source'),
            bytes: bytes,
          ),
        ),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.immutableRevisionConflict,
          ),
        ),
      );
      expect(
        (await database.select(database.contentManifests).get())
            .single
            .publicationState,
        'published',
      );
    },
  );

  test(
    'pinned reader rejects retired authority despite a verified wrapper',
    () async {
      final artifact = VerifiedContentManifest(
        manifest: _manifest(publicationState: ContentPublicationState.retired),
        bytes: (await load(PackagedSenseCrosswalk.identity))!,
      );
      await expectLater(
        SenseCrosswalkRepository(
          _Manifests(artifact),
        ).requirePinned(SenseCrosswalkPin.fromJson(pinJson())),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.unpublished,
          ),
        ),
      );
    },
  );

  test(
    'missing pinned artifact cannot fall back to another installed source',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final manifests = DriftContentManifestRepository(
        database,
        loadArtifactBytes: (_) async => null,
      );
      await manifests.provisionPackagedArtifact(
        PackagedSenseCrosswalk.verify(
          (await load(PackagedSenseCrosswalk.identity))!,
        ),
      );
      await expectLater(
        SenseCrosswalkRepository(
          manifests,
        ).requirePinned(SenseCrosswalkPin.fromJson(pinJson())),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.missingReference,
          ),
        ),
      );
    },
  );

  test(
    'shipped mapping admits exactly twelve existing reviewed starter senses',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.localOwners)
          .insert(
            db.LocalOwnersCompanion.insert(id: 'learner', createdAtUtcMs: 1),
          );
      final manifests = DriftContentManifestRepository(
        database,
        loadArtifactBytes: load,
      );
      await PackagedStarterCatalog.provision(database, manifests, load);
      final bytes = (await load(PackagedSenseCrosswalk.identity))!;
      await manifests.provisionPackagedArtifact(
        PackagedSenseCrosswalk.verify(bytes),
      );
      final artifact = await manifests.requireVerified(
        PackagedSenseCrosswalk.identity,
      );
      final crosswalk = PackagedSenseCrosswalk.decode(artifact.bytes);
      expect(crosswalk.isReviewed, isTrue);
      expect(crosswalk.entries.length, 12);
      expect(
        crosswalk.corpusManifestHash,
        isNot(
          '0b5e5e4d22e7ea8cd33ed2001e89dfafe2b50580346680e4d33fcd45414b0bfa',
        ),
      );
      final vocabulary = DriftVocabularyRepository(
        database,
        contentManifests: manifests,
      );
      for (final entry in crosswalk.entries) {
        final word = (await vocabulary.readPinnedByIds([
          entry.ref.wordId,
        ])).single;
        expect(
          crosswalk.requireScored(
            entry.ref,
            word: word,
            categoryAvailable: true,
            lexicalArtifact: await manifests.requireVerified(
              ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: word.id,
                revision: 1,
              ),
            ),
          ),
          same(entry),
        );
        expect(entry.ref.senseKey, 'starter-object-v1');
        expect(entry.ref.wordId, startsWith('word:starter-'));
      }
      await manifests.provisionPackagedArtifact(
        PackagedSenseCrosswalk.verify(bytes),
      );
      expect(
        (await database.select(database.contentManifests).get()).length,
        13,
      );
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'changed packaged crosswalk bytes cannot borrow reviewed authority',
    () async {
      final bytes = (await load(PackagedSenseCrosswalk.identity))!;
      final changed = Uint8List.fromList(bytes)..[20] ^= 1;
      expect(
        () => PackagedSenseCrosswalk.decode(changed),
        throwsA(isA<ContentQualityFailure>()),
      );
    },
  );
}

ContentManifest _manifest({
  String? sourceUri,
  ContentPublicationState? publicationState,
}) {
  final original = PackagedSenseCrosswalk.manifest;
  return ContentManifest(
    storageId: original.storageId,
    identity: original.identity,
    checksumSha256: original.checksumSha256,
    byteLength: original.byteLength,
    provenance: original.provenance,
    sourceUri: sourceUri ?? original.sourceUri,
    reviewState: original.reviewState,
    publicationState: publicationState ?? original.publicationState,
    createdAtUtc: original.createdAtUtc,
    reviewedAtUtc: original.reviewedAtUtc,
    publishedAtUtc: original.publishedAtUtc,
  );
}

final class _Manifests implements ContentManifestRepository {
  _Manifests(this.artifact);
  final VerifiedContentManifest artifact;
  ContentIdentity? requested;
  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async {
    requested = identity;
    return artifact;
  }
}
