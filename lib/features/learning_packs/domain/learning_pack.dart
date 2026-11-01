import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as image;

part 'learning_pack_codec.dart';

enum LearningPackFailureCode {
  invalidFormat,
  unsupportedVersion,
  tooLarge,
  integrityMismatch,
  duplicateIdentity,
  invalidReference,
  invalidMedia,
  unsafeUri,
}

final class LearningPackException implements Exception {
  const LearningPackException(this.code);
  final LearningPackFailureCode code;
}

enum LearningPackQuality { userProvidedUnreviewed }

const maxLearningPackBytes = 8 * 1024 * 1024;
const maxLearningPackEntries = 50;
const maxLearningPackImages = 50;
const maxLearningPackImageBytes = 512 * 1024;
const maxLearningPackImageDimension = 2048;
const maxLearningPackImagePixels = 1024 * 1024;
const maxLearningPackTotalImagePixels = 4 * 1024 * 1024;

final class LearningPackProvenance {
  const LearningPackProvenance({
    required this.author,
    required this.source,
    required this.license,
    required this.attribution,
    this.sourceUri,
  });
  final String author;
  final String source;
  final String license;
  final String attribution;
  final Uri? sourceUri;

  Map<String, Object?> toJson() => {
    'author': author,
    'source': source,
    'sourceUri': sourceUri?.toString(),
    'license': license,
    'attribution': attribution,
  };
}

final class LearningPackMetadata {
  LearningPackMetadata({
    required this.packId,
    required this.version,
    required this.title,
    required List<String> objectives,
    required this.cefrLevel,
    required this.language,
    required this.meaningLanguage,
    required this.provenance,
  }) : objectives = List.unmodifiable(objectives);
  final String packId;
  final String version;
  final String title;
  final List<String> objectives;
  final String cefrLevel;
  final String language;
  final String meaningLanguage;
  final LearningPackProvenance provenance;
  LearningPackQuality get quality => LearningPackQuality.userProvidedUnreviewed;

  Map<String, Object?> toJson() => _metadataJson(this);
}

final class LearningPackManifest extends LearningPackMetadata {
  LearningPackManifest._({
    required LearningPackMetadata metadata,
    required this.entryCount,
    required this.payloadSha256,
    required this.payloadBytes,
  }) : super(
         packId: metadata.packId,
         version: metadata.version,
         title: metadata.title,
         objectives: metadata.objectives,
         cefrLevel: metadata.cefrLevel,
         language: metadata.language,
         meaningLanguage: metadata.meaningLanguage,
         provenance: metadata.provenance,
       );
  final int entryCount;
  final String payloadSha256;
  final int payloadBytes;

  @override
  Map<String, Object?> toJson() => {
    ..._metadataJson(this),
    'entryCount': entryCount,
    'payloadSha256': payloadSha256,
    'payloadBytes': payloadBytes,
  };
  String get canonicalJson => _canonicalJson(toJson());
}

final class LearningPackExample {
  const LearningPackExample({required this.text, this.translation});
  final String text;
  final String? translation;
  Map<String, Object?> toJson() => {'text': text, 'translation': translation};
}

final class LearningPackDefinitionOption {
  const LearningPackDefinitionOption({
    required this.code,
    required this.entryCode,
    this.contrastiveExplanation,
  });
  final String code;
  final String entryCode;
  final String? contrastiveExplanation;
  Map<String, Object?> toJson() => {
    'code': code,
    'entryCode': entryCode,
    'contrastiveExplanation': contrastiveExplanation,
  };
}

final class LearningPackDefinitionQuestion {
  LearningPackDefinitionQuestion({
    required this.correctOptionCode,
    required List<LearningPackDefinitionOption> options,
  }) : options = List.unmodifiable(options);
  final String correctOptionCode;
  final List<LearningPackDefinitionOption> options;
  Map<String, Object?> toJson() => {
    'correctOptionCode': correctOptionCode,
    'options': [for (final option in options) option.toJson()],
  };
}

final class LearningPackLexicalDetails {
  LearningPackLexicalDetails({
    this.ipa,
    List<String> synonyms = const [],
    List<String> antonyms = const [],
  }) : synonyms = List.unmodifiable(synonyms),
       antonyms = List.unmodifiable(antonyms);
  final String? ipa;
  final List<String> synonyms;
  final List<String> antonyms;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'ipa': ipa,
    'synonyms': synonyms,
    'antonyms': antonyms,
  };
}

final class LearningPackEntry {
  LearningPackEntry({
    required this.code,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.definition,
    List<LearningPackExample> examples = const [],
    this.imageId,
    this.memoryCue,
    this.hint,
    this.strategy,
    this.definitionQuestion,
    this.lexicalDetails,
  }) : examples = List.unmodifiable(examples);
  final String code;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? definition;
  final List<LearningPackExample> examples;
  final String? imageId;
  final String? memoryCue;
  final String? hint;
  final String? strategy;
  final LearningPackDefinitionQuestion? definitionQuestion;
  final LearningPackLexicalDetails? lexicalDetails;

  Map<String, Object?> toJson() => {
    'code': code,
    'spelling': spelling,
    'meaning': meaning,
    'partOfSpeech': partOfSpeech,
    'definition': definition,
    'examples': [for (final example in examples) example.toJson()],
    'imageId': imageId,
    'memoryCue': memoryCue,
    'hint': hint,
    'strategy': strategy,
    'definitionQuestion': definitionQuestion?.toJson(),
    if (lexicalDetails != null) 'lexicalDetails': lexicalDetails!.toJson(),
  };
  String get canonicalJson => _canonicalJson(toJson());
  String get contentSha256 => _digest(utf8.encode(canonicalJson));
}

final class LearningPackImage {
  LearningPackImage({
    required this.id,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.altText,
    required Uint8List bytes,
  }) : _bytes = Uint8List.fromList(bytes),
       sha256 = _digest(bytes);
  final String id;
  final String mimeType;
  final int width;
  final int height;
  final String altText;
  final Uint8List _bytes;
  final String sha256;
  int get byteCount => _bytes.length;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  Map<String, Object?> toJson() => {
    'id': id,
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'altText': altText,
    'sha256': sha256,
    'byteCount': byteCount,
    'dataBase64': base64.encode(_bytes),
  };
}

final class LearningPack {
  LearningPack._({
    required this.manifest,
    required List<LearningPackEntry> entries,
    required List<LearningPackImage> images,
    required Uint8List packageBytes,
  }) : entries = List.unmodifiable(entries),
       images = List.unmodifiable(images),
       entriesByCode = Map.unmodifiable({
         for (final entry in entries) entry.code: entry,
       }),
       imagesById = Map.unmodifiable({
         for (final asset in images) asset.id: asset,
       }),
       _bytes = Uint8List.fromList(packageBytes),
       packageSha256 = _digest(packageBytes);
  final LearningPackManifest manifest;
  final List<LearningPackEntry> entries;
  final List<LearningPackImage> images;
  final Map<String, LearningPackEntry> entriesByCode;
  final Map<String, LearningPackImage> imagesById;
  final Uint8List _bytes;
  final String packageSha256;
  int get byteCount => _bytes.length;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

final class LearningPackRetainedMedia {
  LearningPackRetainedMedia._({
    required List<String> entryCodes,
    required List<LearningPackImage> images,
  }) : entryCodes = List.unmodifiable(entryCodes),
       images = List.unmodifiable(images);

  factory LearningPackRetainedMedia.fromPack(LearningPack pack) =>
      LearningPackRetainedMedia._(
        entryCodes: [for (final entry in pack.entries) entry.code],
        images: pack.images,
      );

  final List<String> entryCodes;
  final List<LearningPackImage> images;
  String get canonicalJson => _canonicalJson({
    'schemaVersion': 1,
    'entryCodes': entryCodes,
    'images': [for (final asset in images) asset.toJson()],
  });
}
