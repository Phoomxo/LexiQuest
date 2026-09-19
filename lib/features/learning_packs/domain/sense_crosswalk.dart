import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../vocabulary/domain/vocabulary_word.dart';
import 'content_manifest.dart';
import 'content_quality_policy.dart';

/// Supplemental sense identity. It never replaces historical word SRS identity.
final class SenseRef {
  const SenseRef._(
    this.corpusManifestHash,
    this.wordId,
    this.senseKey,
    this.senseRevision,
    this.lexicalArtifactHash,
  );

  factory SenseRef.fromJson(Map<String, Object?> json) {
    _fields(json, const {
      'corpusManifestHash',
      'wordId',
      'senseKey',
      'senseRevision',
      'lexicalArtifactHash',
    });
    return SenseRef._(
      _hash(json['corpusManifestHash']),
      _text(json['wordId']),
      _text(json['senseKey']),
      _revision(json['senseRevision']),
      _hash(json['lexicalArtifactHash']),
    );
  }

  final String corpusManifestHash, wordId, senseKey, lexicalArtifactHash;
  final int senseRevision;

  Map<String, Object?> toJson() => {
    'corpusManifestHash': corpusManifestHash,
    'wordId': wordId,
    'senseKey': senseKey,
    'senseRevision': senseRevision,
    'lexicalArtifactHash': lexicalArtifactHash,
  };
  String get stableHash =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  @override
  bool operator ==(Object other) =>
      other is SenseRef &&
      corpusManifestHash == other.corpusManifestHash &&
      wordId == other.wordId &&
      senseKey == other.senseKey &&
      senseRevision == other.senseRevision &&
      lexicalArtifactHash == other.lexicalArtifactHash;
  @override
  int get hashCode => Object.hash(
    corpusManifestHash,
    wordId,
    senseKey,
    senseRevision,
    lexicalArtifactHash,
  );
}

final class SenseCrosswalkEntry {
  const SenseCrosswalkEntry._(
    this.ref,
    this.wordRevision,
    this.wordChecksumSha256,
    this.partOfSpeech,
  );
  final SenseRef ref;
  final int wordRevision;
  final String wordChecksumSha256, partOfSpeech;
}

/// A pinned crosswalk can be used to browse/save drafts without granting
/// scoring permission. Scored admission additionally requires a reviewed
/// crosswalk envelope and current, exact approved word and lexical artifacts.
final class SenseCrosswalk {
  SenseCrosswalk._(
    this.corpusManifestHash,
    this.artifactHash,
    this.isReviewed,
    Map<SenseRef, SenseCrosswalkEntry> entries,
  ) : _entries = Map.unmodifiable(entries);

  factory SenseCrosswalk.fromBytes(
    Uint8List bytes, {
    required String expectedSha256,
    required String corpusManifestHash,
    ContentManifest? reviewManifest,
  }) {
    _hash(corpusManifestHash);
    _hash(expectedSha256);
    if (bytes.length > 8 * 1024 * 1024 ||
        sha256.convert(bytes).toString() != expectedSha256) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.checksumMismatch,
      );
    }
    if (reviewManifest != null) {
      if (reviewManifest.identity.type != ContentType.offlineArtifact ||
          reviewManifest.identity.id != 'sense-crosswalk:$corpusManifestHash') {
        throw const ContentQualityFailure(
          ContentQualityFailureCode.invalidIdentity,
        );
      }
      const ContentQualityPolicy().requireVerified(
        manifest: reviewManifest,
        bytes: bytes,
      );
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid crosswalk');
    }
    _fields(json, const {'schemaVersion', 'corpusManifestHash', 'entries'});
    final values = json['entries'];
    if (json['schemaVersion'] != 1 ||
        json['corpusManifestHash'] != corpusManifestHash ||
        values is! List ||
        values.isEmpty ||
        values.length > 10000) {
      throw const FormatException('Unsupported crosswalk');
    }
    final entries = <SenseRef, SenseCrosswalkEntry>{};
    final semanticIdentities = <(String, String, int)>{};
    for (final value in values) {
      if (value is! Map<String, dynamic> ||
          value['ref'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid crosswalk entry');
      }
      _fields(value, const {
        'ref',
        'wordRevision',
        'wordChecksumSha256',
        'partOfSpeech',
      });
      final ref = SenseRef.fromJson(value['ref'] as Map<String, dynamic>);
      if (ref.corpusManifestHash != corpusManifestHash ||
          !semanticIdentities.add((
            ref.wordId,
            ref.senseKey,
            ref.senseRevision,
          ))) {
        throw const FormatException('Duplicate or foreign sense');
      }
      entries[ref] = SenseCrosswalkEntry._(
        ref,
        _revision(value['wordRevision']),
        _hash(value['wordChecksumSha256']),
        _text(value['partOfSpeech']),
      );
    }
    return SenseCrosswalk._(
      corpusManifestHash,
      expectedSha256,
      reviewManifest != null,
      entries,
    );
  }

  final String corpusManifestHash, artifactHash;
  final bool isReviewed;
  final Map<SenseRef, SenseCrosswalkEntry> _entries;
  List<SenseCrosswalkEntry> get entries => List.unmodifiable(_entries.values);
  SenseCrosswalkEntry resolve(SenseRef ref) =>
      _entries[ref] ??
      (throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      ));

  SenseCrosswalkEntry requireScored(
    SenseRef ref, {
    required VocabularyWord word,
    required bool categoryAvailable,
    required VerifiedContentManifest lexicalArtifact,
  }) {
    final entry = resolve(ref);
    if (!isReviewed) {
      throw const ContentQualityFailure(ContentQualityFailureCode.unreviewed);
    }
    if (word.id != ref.wordId ||
        word.contentRevision != entry.wordRevision ||
        word.contentChecksumSha256 != entry.wordChecksumSha256 ||
        word.partOfSpeech != entry.partOfSpeech ||
        word.contentProvenance != ContentProvenance.packaged ||
        word.contentReviewState != ContentReviewState.approved ||
        word.contentPublicationState != ContentPublicationState.published ||
        !ContentQualityPolicy.isAvailableVocabulary(
          categoryAvailable: categoryAvailable,
          id: word.id,
          categoryId: word.categoryId,
          spelling: word.spelling,
          normalizedSpelling: word.normalizedSpelling,
          meaning: word.meaning,
          normalizedMeaning: word.normalizedMeaning,
          partOfSpeech: word.partOfSpeech,
          cefrLevel: word.cefrLevel,
          source: word.source,
          isGlobal: word.isGlobal,
          contentRevision: word.contentRevision,
          contentChecksumSha256: word.contentChecksumSha256,
          contentProvenance: word.contentProvenance.name,
          contentReviewState: word.contentReviewState.name,
          contentPublicationState: word.contentPublicationState.name,
          isDeleted: word.isDeleted,
        )) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    final manifest = lexicalArtifact.manifest;
    if (manifest.identity !=
            ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: ref.wordId,
              revision: entry.wordRevision,
            ) ||
        manifest.checksumSha256 != ref.lexicalArtifactHash) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    // VerifiedContentManifest is publicly constructible; recheck its bytes.
    const ContentQualityPolicy().requireVerified(
      manifest: manifest,
      bytes: lexicalArtifact.bytes,
    );
    RichLexicalMetadata.fromVerifiedArtifact(
      bytes: lexicalArtifact.bytes,
      wordId: ref.wordId,
      contentRevision: entry.wordRevision,
      verifiedArtifactChecksumSha256: ref.lexicalArtifactHash,
    );
    return entry;
  }
}

void _fields(Map<String, Object?> value, Set<String> expected) {
  if (value.length != expected.length || !expected.every(value.containsKey)) {
    throw const FormatException('Unexpected sense fields');
  }
}

String _text(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.runes.length > 256 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Noncanonical sense text');
  }
  return value;
}

String _hash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid sense hash');
  }
  return value;
}

int _revision(Object? value) {
  if (value is! int || value <= 0 || value > 0x7fffffff) {
    throw const FormatException('Invalid sense revision');
  }
  return value;
}
