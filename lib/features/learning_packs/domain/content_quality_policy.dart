import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'content_manifest.dart';

enum ContentQualityFailureCode {
  invalidIdentity,
  invalidChecksum,
  checksumMismatch,
  invalidByteLength,
  missingProvenance,
  unreviewed,
  unpublished,
  invalidLifecycle,
  immutableRevisionConflict,
  missingReference,
}

final class ContentQualityFailure implements Exception {
  const ContentQualityFailure(this.code);

  final ContentQualityFailureCode code;

  @override
  String toString() => 'ContentQualityFailure(${code.name})';
}

final class ContentQualityPolicy {
  const ContentQualityPolicy();

  static Uint8List canonicalLearningPackBytes({
    required String packId,
    required int revision,
    required String title,
    required String cefrLevel,
    required String topic,
    required String skill,
    required String goal,
    required Iterable<ContentVocabularyReference> vocabularyReferences,
  }) {
    final references = vocabularyReferences.toList(growable: false);
    if (references.any(
      (reference) =>
          !_canonicalText(reference.id) ||
          reference.revision <= 0 ||
          !_sha256.hasMatch(reference.checksumSha256),
    )) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'packId': packId,
          'revision': revision,
          'title': title,
          'cefrLevel': cefrLevel,
          'topic': topic,
          'skill': skill,
          'goal': goal,
          'vocabularyReferences': references
              .map(
                (reference) => <String, Object?>{
                  'id': reference.id,
                  'revision': reference.revision,
                  'checksumSha256': reference.checksumSha256,
                },
              )
              .toList(growable: false),
        }),
      ),
    );
  }

  static String vocabularyChecksumSha256({
    required String categoryId,
    required String spelling,
    required String normalizedSpelling,
    required String meaning,
    required String normalizedMeaning,
    required String partOfSpeech,
    required String? cefrLevel,
    required String source,
    required bool isGlobal,
  }) => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'categoryId': categoryId,
            'spelling': spelling,
            'normalizedSpelling': normalizedSpelling,
            'meaning': meaning,
            'normalizedMeaning': normalizedMeaning,
            'partOfSpeech': partOfSpeech,
            'cefrLevel': cefrLevel,
            'source': source,
            'isGlobal': isGlobal,
          }),
        ),
      )
      .toString();

  VerifiedContentManifest requireVerified({
    required ContentManifest manifest,
    required Uint8List bytes,
    Iterable<String> referencedVocabularyIds = const <String>[],
    Set<String> knownVocabularyIds = const <String>{},
  }) {
    _requireCanonicalIdentity(manifest);
    if (!_sha256.hasMatch(manifest.checksumSha256)) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.invalidChecksum,
      );
    }
    if (manifest.byteLength < 0 || manifest.byteLength != bytes.length) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.invalidByteLength,
      );
    }
    if (sha256.convert(bytes).toString() != manifest.checksumSha256) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.checksumMismatch,
      );
    }
    if (manifest.provenance != ContentProvenance.packaged ||
        !_canonicalText(manifest.sourceUri, maxLength: 2048)) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingProvenance,
      );
    }
    if (manifest.reviewState != ContentReviewState.approved) {
      throw const ContentQualityFailure(ContentQualityFailureCode.unreviewed);
    }
    if (manifest.publicationState != ContentPublicationState.published) {
      throw const ContentQualityFailure(ContentQualityFailureCode.unpublished);
    }
    final reviewedAtUtc = manifest.reviewedAtUtc;
    final publishedAtUtc = manifest.publishedAtUtc;
    if (!_validUtc(manifest.createdAtUtc) ||
        reviewedAtUtc == null ||
        !_validUtc(reviewedAtUtc) ||
        reviewedAtUtc.isBefore(manifest.createdAtUtc) ||
        publishedAtUtc == null ||
        !_validUtc(publishedAtUtc) ||
        publishedAtUtc.isBefore(reviewedAtUtc)) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.invalidLifecycle,
      );
    }
    final seen = <String>{};
    for (final wordId in referencedVocabularyIds) {
      if (!_canonicalText(wordId) ||
          !seen.add(wordId) ||
          !knownVocabularyIds.contains(wordId)) {
        throw const ContentQualityFailure(
          ContentQualityFailureCode.missingReference,
        );
      }
    }
    return VerifiedContentManifest(manifest: manifest, bytes: bytes);
  }

  void requireImmutableRevision({
    required ContentManifest existing,
    required ContentManifest candidate,
  }) {
    if (existing.identity != candidate.identity) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.invalidIdentity,
      );
    }
    if (existing.storageId != candidate.storageId ||
        existing.checksumSha256 != candidate.checksumSha256 ||
        existing.byteLength != candidate.byteLength ||
        existing.provenance != candidate.provenance ||
        existing.sourceUri != candidate.sourceUri ||
        existing.reviewState != candidate.reviewState ||
        existing.publicationState != candidate.publicationState ||
        existing.createdAtUtc != candidate.createdAtUtc ||
        existing.reviewedAtUtc != candidate.reviewedAtUtc ||
        existing.publishedAtUtc != candidate.publishedAtUtc) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.immutableRevisionConflict,
      );
    }
  }

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  static void _requireCanonicalIdentity(ContentManifest manifest) {
    if (!_canonicalText(manifest.storageId) ||
        !_canonicalText(manifest.identity.id) ||
        manifest.identity.revision <= 0) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.invalidIdentity,
      );
    }
  }

  static bool _canonicalText(String value, {int maxLength = 256}) =>
      value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= maxLength;

  static bool _validUtc(DateTime value) =>
      value.isUtc && value.millisecondsSinceEpoch >= 0;
}
