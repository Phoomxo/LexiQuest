import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';

void main() {
  test('same semantic sense revision cannot bind two different artifacts', () {
    final fixture = _Fixture();
    final changed = {
      ...fixture.ref.toJson(),
      'lexicalArtifactHash': _hash('different artifact'),
    };
    expect(
      () => fixture.load(
        entries: [
          fixture.entry,
          {...fixture.entry, 'ref': changed},
        ],
      ),
      throwsFormatException,
    );
  });

  test('a checksum-valid but malformed lexical body is not scored content', () {
    final fixture = _Fixture(lexicalJson: '{"wordId":"word:book"}');
    expect(
      () => fixture.load().requireScored(
        fixture.ref,
        word: fixture.word,
        categoryAvailable: true,
        lexicalArtifact: fixture.lexical,
      ),
      throwsFormatException,
    );
  });
  test(
    'draft crosswalk resolves exact identities without scored admission',
    () {
      final fixture = _Fixture();
      final crosswalk = fixture.load(reviewed: false);
      expect(crosswalk.resolve(fixture.ref).wordRevision, 1);
      expect(
        () => crosswalk.requireScored(
          fixture.ref,
          word: fixture.word,
          categoryAvailable: true,
          lexicalArtifact: fixture.lexical,
        ),
        throwsA(isA<ContentQualityFailure>()),
      );
    },
  );

  test(
    'reviewed crosswalk and exact approved lexical content admit a sense',
    () {
      final fixture = _Fixture();
      final entry = fixture.load().requireScored(
        fixture.ref,
        word: fixture.word,
        categoryAvailable: true,
        lexicalArtifact: fixture.lexical,
      );
      expect(entry.ref, fixture.ref);
      expect(entry.wordRevision, 1);
    },
  );

  test('sense identity round trips and is independent of gloss text', () {
    final fixture = _Fixture();
    final copy = SenseRef.fromJson(fixture.ref.toJson());
    expect(copy, fixture.ref);
    expect(copy.hashCode, fixture.ref.hashCode);
    expect(copy.stableHash, fixture.ref.stableHash);
    expect(copy.toJson().keys, isNot(contains('meaning')));
  });

  test(
    'unknown, changed corpus and changed sense revision never fall forward',
    () {
      final fixture = _Fixture();
      final crosswalk = fixture.load();
      for (final change in [
        {'wordId': 'word:other'},
        {'corpusManifestHash': _hash('other corpus')},
        {'senseRevision': 2},
        {'lexicalArtifactHash': _hash('other artifact')},
      ]) {
        final ref = SenseRef.fromJson({...fixture.ref.toJson(), ...change});
        expect(
          () => crosswalk.resolve(ref),
          throwsA(isA<ContentQualityFailure>()),
        );
      }
    },
  );

  test(
    'duplicate sense bindings and invalid fields reject the whole crosswalk',
    () {
      final fixture = _Fixture();
      for (final entries in [
        [fixture.entry, fixture.entry],
        [
          {...fixture.entry, 'wordRevision': 0},
        ],
        [
          {...fixture.entry, 'unknown': true},
        ],
      ]) {
        expect(() => fixture.load(entries: entries), throwsFormatException);
      }
    },
  );

  test(
    'two senses may share a word but retain different immutable identities',
    () {
      final fixture = _Fixture();
      final second = SenseRef.fromJson({
        ...fixture.ref.toJson(),
        'senseKey': 'verb-v1',
      });
      final crosswalk = fixture.load(
        entries: [
          fixture.entry,
          {...fixture.entry, 'ref': second.toJson()},
        ],
      );
      expect(crosswalk.entries.length, 2);
      expect(crosswalk.resolve(second).ref, isNot(fixture.ref));
    },
  );

  test(
    'changed word, withdrawn content and unavailable category deny scoring',
    () {
      final fixture = _Fixture();
      for (final word in [
        fixture.word.copyWith(contentRevision: 2),
        fixture.word.copyWith(meaning: 'changed'),
        fixture.word.copyWith(
          contentReviewState: ContentReviewState.unreviewed,
        ),
        fixture.word.copyWith(
          contentPublicationState: ContentPublicationState.retired,
        ),
        fixture.word.copyWith(isDeleted: true),
        fixture.word.copyWith(
          isGlobal: false,
          contentProvenance: ContentProvenance.userAuthored,
          contentReviewState: ContentReviewState.unreviewed,
          contentPublicationState: ContentPublicationState.private,
        ),
      ]) {
        expect(
          () => fixture.load().requireScored(
            fixture.ref,
            word: word,
            categoryAvailable: true,
            lexicalArtifact: fixture.lexical,
          ),
          throwsA(isA<ContentQualityFailure>()),
        );
      }
      expect(
        () => fixture.load().requireScored(
          fixture.ref,
          word: fixture.word,
          categoryAvailable: false,
          lexicalArtifact: fixture.lexical,
        ),
        throwsA(isA<ContentQualityFailure>()),
      );
    },
  );

  test(
    'caller-constructed verified wrapper cannot bypass byte verification',
    () {
      final fixture = _Fixture();
      final corrupt = VerifiedContentManifest(
        manifest: fixture.lexical.manifest,
        bytes: Uint8List.fromList(utf8.encode('tampered')),
      );
      expect(
        () => fixture.load().requireScored(
          fixture.ref,
          word: fixture.word,
          categoryAvailable: true,
          lexicalArtifact: corrupt,
        ),
        throwsA(isA<ContentQualityFailure>()),
      );
    },
  );

  test('a reviewed artifact for another word cannot certify this sense', () {
    final fixture = _Fixture();
    final wrong = VerifiedContentManifest(
      manifest: _manifest(
        fixture.lexical.bytes,
        ContentType.lexicalMetadata,
        'word:other',
      ),
      bytes: fixture.lexical.bytes,
    );
    expect(
      () => fixture.load().requireScored(
        fixture.ref,
        word: fixture.word,
        categoryAvailable: true,
        lexicalArtifact: wrong,
      ),
      throwsA(isA<ContentQualityFailure>()),
    );
  });

  test('crosswalk checksum and review manifest are independently verified', () {
    final fixture = _Fixture();
    expect(
      () => SenseCrosswalk.fromBytes(
        fixture.bytes,
        expectedSha256: _hash('wrong'),
        corpusManifestHash: fixture.corpus,
      ),
      throwsA(isA<ContentQualityFailure>()),
    );
    expect(
      () => SenseCrosswalk.fromBytes(
        fixture.bytes,
        expectedSha256: _hashBytes(fixture.bytes),
        corpusManifestHash: fixture.corpus,
        reviewManifest: fixture.lexical.manifest,
      ),
      throwsA(isA<ContentQualityFailure>()),
    );
  });

  test('noncanonical references reject instead of normalizing identities', () {
    final fixture = _Fixture();
    for (final change in [
      {'wordId': ' word:book'},
      {'senseKey': ''},
      {'senseRevision': 0},
      {'senseRevision': 1.5},
      {'lexicalArtifactHash': 'ABC'},
      {'extra': 1},
    ]) {
      expect(
        () => SenseRef.fromJson({...fixture.ref.toJson(), ...change}),
        throwsFormatException,
      );
    }
  });
}

String _hash(String value) => _hashBytes(utf8.encode(value));
String _hashBytes(List<int> bytes) => sha256.convert(bytes).toString();
ContentManifest _manifest(List<int> bytes, ContentType type, String id) =>
    ContentManifest(
      storageId: 'manifest:$id:r1',
      identity: ContentIdentity(type: type, id: id, revision: 1),
      checksumSha256: _hashBytes(bytes),
      byteLength: bytes.length,
      provenance: ContentProvenance.packaged,
      sourceUri: 'fixture://$id',
      reviewState: ContentReviewState.approved,
      publicationState: ContentPublicationState.published,
      createdAtUtc: DateTime.utc(2026),
      reviewedAtUtc: DateTime.utc(2026),
      publishedAtUtc: DateTime.utc(2026),
    );

class _Fixture {
  _Fixture({
    this.lexicalJson =
        '{"schemaVersion":2,"wordId":"word:book",'
        '"contentRevision":1,"englishDefinition":"Pages joined for reading.",'
        '"ipa":null,"examples":[],"synonyms":[],"antonyms":[],"audio":null}',
  });
  final String lexicalJson;
  final corpus = _hash('fixture corpus, not production approval');
  late final lexical = VerifiedContentManifest(
    manifest: _manifest(
      utf8.encode(lexicalJson),
      ContentType.lexicalMetadata,
      'word:book',
    ),
    bytes: Uint8List.fromList(utf8.encode(lexicalJson)),
  );
  late final ref = SenseRef.fromJson({
    'corpusManifestHash': corpus,
    'wordId': 'word:book',
    'senseKey': 'noun-v1',
    'senseRevision': 1,
    'lexicalArtifactHash': lexical.manifest.checksumSha256,
  });
  late final word = VocabularyWord(
    id: 'word:book',
    ownerId: 'packaged',
    categoryId: 'books',
    spelling: 'book',
    normalizedSpelling: 'book',
    meaning: 'หนังสือ',
    normalizedMeaning: 'หนังสือ',
    partOfSpeech: 'noun',
    source: 'fixture',
    isGlobal: true,
    localRevision: 1,
    isDeleted: false,
    createdAtUtc: DateTime.utc(2026),
    updatedAtUtc: DateTime.utc(2026),
    contentChecksumSha256: ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'books',
      spelling: 'book',
      normalizedSpelling: 'book',
      meaning: 'หนังสือ',
      normalizedMeaning: 'หนังสือ',
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'fixture',
      isGlobal: true,
    ),
    contentProvenance: ContentProvenance.packaged,
    contentReviewState: ContentReviewState.approved,
    contentPublicationState: ContentPublicationState.published,
  );
  Map<String, Object?> get entry => {
    'ref': ref.toJson(),
    'wordRevision': 1,
    'wordChecksumSha256': word.contentChecksumSha256,
    'partOfSpeech': 'noun',
  };
  Uint8List get bytes => _bytes([entry]);
  Uint8List _bytes(List<Map<String, Object?>> entries) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'corpusManifestHash': corpus,
        'entries': entries,
      }),
    ),
  );
  SenseCrosswalk load({
    bool reviewed = true,
    List<Map<String, Object?>>? entries,
  }) {
    final bytes = _bytes(entries ?? [entry]);
    return SenseCrosswalk.fromBytes(
      bytes,
      expectedSha256: _hashBytes(bytes),
      corpusManifestHash: corpus,
      reviewManifest: reviewed
          ? _manifest(
              bytes,
              ContentType.offlineArtifact,
              'sense-crosswalk:$corpus',
            )
          : null,
    );
  }
}
