import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../learning_packs/domain/content_manifest.dart';

/// Optional, verified presentation metadata for a pinned vocabulary revision.
///
/// This is deliberately separate from the vocabulary table. It may only be
/// constructed from a verified f04 lexical-metadata artifact.
final class RichLexicalMetadata {
  static const int maxArtifactBytes = 8 * 1024;
  static const int maxJsonStructuralDepth = 4;

  RichLexicalMetadata({
    this.englishDefinition,
    this.verifiedArtifactChecksumSha256,
    this.ipa,
    Iterable<String> examples = const <String>[],
    Iterable<String> synonyms = const <String>[],
    Iterable<String> antonyms = const <String>[],
    this.audio,
  }) : examples = UnmodifiableListView<String>(
         examples.toList(growable: false),
       ),
       synonyms = UnmodifiableListView<String>(
         synonyms.toList(growable: false),
       ),
       antonyms = UnmodifiableListView<String>(
         antonyms.toList(growable: false),
       );

  final String? englishDefinition;

  /// SHA-256 of the verified lexical-metadata artifact these fields came
  /// from. Presentation-only callers may omit it; evidence-producing modes
  /// must fail closed when it is absent or malformed.
  final String? verifiedArtifactChecksumSha256;
  final String? ipa;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> antonyms;
  final LexicalAudioMetadata? audio;

  /// Strictly decodes the bounded canonical f04 lexical-metadata JSON shape.
  /// The caller must already have obtained [bytes] through `requireVerified`.
  factory RichLexicalMetadata.fromVerifiedArtifact({
    required Uint8List bytes,
    required String wordId,
    required int contentRevision,
    String? verifiedArtifactChecksumSha256,
  }) {
    _preflightArtifact(bytes);
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('lexical metadata must be UTF-8 JSON');
    }
    if (decoded is! Map<Object?, Object?> ||
        decoded.keys.any((key) => key is! String)) {
      throw const FormatException('invalid lexical metadata shape');
    }
    final schemaVersion = decoded['schemaVersion'];
    final expectedKeys = switch (schemaVersion) {
      1 => const <String>{
        'schemaVersion',
        'wordId',
        'contentRevision',
        'ipa',
        'examples',
        'synonyms',
        'antonyms',
        'audio',
      },
      2 => const <String>{
        'schemaVersion',
        'wordId',
        'contentRevision',
        'englishDefinition',
        'ipa',
        'examples',
        'synonyms',
        'antonyms',
        'audio',
      },
      _ => const <String>{},
    };
    if (expectedKeys.isEmpty ||
        decoded.length != expectedKeys.length ||
        decoded.keys.toSet().difference(expectedKeys).isNotEmpty) {
      throw const FormatException('invalid lexical metadata shape');
    }
    if (decoded['wordId'] != wordId ||
        decoded['contentRevision'] != contentRevision) {
      throw const FormatException('lexical metadata identity mismatch');
    }
    final ipa = _optionalText(decoded['ipa'], 'ipa', maxLength: 160);
    return RichLexicalMetadata(
      englishDefinition: schemaVersion == 2
          ? _optionalText(
              decoded['englishDefinition'],
              'englishDefinition',
              maxLength: 600,
            )
          : null,
      verifiedArtifactChecksumSha256: verifiedArtifactChecksumSha256,
      ipa: ipa,
      examples: _textList(decoded['examples'], 'examples'),
      synonyms: _textList(decoded['synonyms'], 'synonyms'),
      antonyms: _textList(decoded['antonyms'], 'antonyms'),
      audio: _audio(decoded['audio']),
    );
  }

  static String? _optionalText(
    Object? value,
    String field, {
    required int maxLength,
  }) {
    if (value == null) return null;
    if (value is! String || !_canonicalText(value, maxLength: maxLength)) {
      throw FormatException('invalid lexical metadata $field');
    }
    return value;
  }

  static void _preflightArtifact(Uint8List bytes) {
    if (bytes.length > maxArtifactBytes) {
      throw const FormatException('lexical metadata exceeds the byte limit');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (final byte in bytes) {
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (byte == 0x5c) {
          escaped = true;
        } else if (byte == 0x22) {
          inString = false;
        }
        continue;
      }
      if (byte == 0x22) {
        inString = true;
      } else if (byte == 0x7b || byte == 0x5b) {
        depth += 1;
        if (depth > maxJsonStructuralDepth) {
          throw const FormatException('lexical metadata is nested too deeply');
        }
      } else if (byte == 0x7d || byte == 0x5d) {
        depth -= 1;
        if (depth < 0) {
          throw const FormatException('lexical metadata has unbalanced JSON');
        }
      }
    }
    if (inString || depth != 0) {
      throw const FormatException('lexical metadata has unbalanced JSON');
    }
  }

  static List<String> _textList(Object? value, String field) {
    if (value is! List<Object?> || value.length > 8) {
      throw FormatException('invalid lexical metadata $field');
    }
    final values = <String>[];
    final seen = <String>{};
    for (final entry in value) {
      if (entry is! String ||
          !_canonicalText(entry, maxLength: 400) ||
          !seen.add(entry)) {
        throw FormatException('invalid lexical metadata $field');
      }
      values.add(entry);
    }
    return values;
  }

  static LexicalAudioMetadata? _audio(Object? value) {
    if (value == null) return null;
    if (value is! Map<Object?, Object?> ||
        value.length != 2 ||
        value.keys.toSet().length != 2 ||
        value['language'] is! String ||
        value['assetId'] is! String) {
      throw const FormatException('invalid lexical metadata audio');
    }
    final language = value['language']! as String;
    final assetId = value['assetId']! as String;
    if ((language != 'en' && language != 'th') ||
        !_canonicalText(assetId, maxLength: 256)) {
      throw const FormatException('invalid lexical metadata audio');
    }
    return LexicalAudioMetadata(language: language, assetId: assetId);
  }

  static bool _canonicalText(String value, {required int maxLength}) =>
      value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= maxLength;
}

final class LexicalAudioMetadata {
  const LexicalAudioMetadata({required this.language, required this.assetId});

  final String language;
  final String assetId;
}

final class VocabularyWord {
  const VocabularyWord({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.spelling,
    required this.normalizedSpelling,
    required this.meaning,
    required this.normalizedMeaning,
    required this.partOfSpeech,
    required this.source,
    required this.isGlobal,
    required this.localRevision,
    required this.isDeleted,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.cefrLevel,
    this.contentRevision = 1,
    this.contentChecksumSha256,
    this.contentProvenance = ContentProvenance.userAuthored,
    this.contentReviewState = ContentReviewState.unreviewed,
    this.contentPublicationState = ContentPublicationState.private,
    this.richMetadata,
  });

  final String id;
  final String ownerId;
  final String categoryId;
  final String spelling;
  final String normalizedSpelling;
  final String meaning;
  final String normalizedMeaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
  final bool isGlobal;
  final int localRevision;
  final bool isDeleted;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int contentRevision;
  final String? contentChecksumSha256;
  final ContentProvenance contentProvenance;
  final ContentReviewState contentReviewState;
  final ContentPublicationState contentPublicationState;
  final RichLexicalMetadata? richMetadata;

  VocabularyWord copyWith({
    String? categoryId,
    String? spelling,
    String? normalizedSpelling,
    String? meaning,
    String? normalizedMeaning,
    String? partOfSpeech,
    String? cefrLevel,
    String? source,
    bool? isGlobal,
    int? localRevision,
    bool? isDeleted,
    DateTime? updatedAtUtc,
    int? contentRevision,
    String? contentChecksumSha256,
    ContentProvenance? contentProvenance,
    ContentReviewState? contentReviewState,
    ContentPublicationState? contentPublicationState,
    RichLexicalMetadata? richMetadata,
  }) {
    return VocabularyWord(
      id: id,
      ownerId: ownerId,
      categoryId: categoryId ?? this.categoryId,
      spelling: spelling ?? this.spelling,
      normalizedSpelling: normalizedSpelling ?? this.normalizedSpelling,
      meaning: meaning ?? this.meaning,
      normalizedMeaning: normalizedMeaning ?? this.normalizedMeaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      source: source ?? this.source,
      isGlobal: isGlobal ?? this.isGlobal,
      localRevision: localRevision ?? this.localRevision,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      contentRevision: contentRevision ?? this.contentRevision,
      contentChecksumSha256:
          contentChecksumSha256 ?? this.contentChecksumSha256,
      contentProvenance: contentProvenance ?? this.contentProvenance,
      contentReviewState: contentReviewState ?? this.contentReviewState,
      contentPublicationState:
          contentPublicationState ?? this.contentPublicationState,
      richMetadata: richMetadata ?? this.richMetadata,
    );
  }
}
