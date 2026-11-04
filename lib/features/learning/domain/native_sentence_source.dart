import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../ai/ai_models.dart';
import 'accepted_quiz_plan.dart';

sealed class NativeSentenceSource {
  const NativeSentenceSource();
}

final class GeneratedSentenceSource extends NativeSentenceSource {
  const GeneratedSentenceSource({
    required this.kind,
    required this.cefr,
    required this.language,
    required this.modelVersion,
    required this.cached,
  });
  final ContentKind kind;
  final CefrLevel cefr;
  final String language;
  final String modelVersion;
  final bool cached;
}

final class AuthoredSentenceSource extends NativeSentenceSource {
  AuthoredSentenceSource({
    required this.pack,
    required this.target,
    required this.exampleIndex,
  }) {
    if (exampleIndex < 0 || exampleIndex >= target.entry.examples.length) {
      throw const FormatException('Invalid authored example index');
    }
  }
  final LexicalPackPin pack;
  final LexicalEntryPin target;
  final int exampleIndex;
  String get text => target.entry.examples[exampleIndex].text;
  Map<String, Object?> toJson() => {
    'kind': 'authoredPack',
    'pack': pack.toJson(),
    'target': target.toJson(),
    'exampleIndex': exampleIndex,
  };
  String get provenance =>
      'authored-pack-v1:${sha256.convert(utf8.encode(jsonEncode(toJson())))}';
  factory AuthoredSentenceSource.fromJson(Map<String, dynamic> json) {
    if (json.length != 4 ||
        json['kind'] != 'authoredPack' ||
        json['pack'] is! Map<String, dynamic> ||
        json['target'] is! Map<String, dynamic> ||
        json['exampleIndex'] is! int) {
      throw const FormatException('Invalid authored sentence source');
    }
    return AuthoredSentenceSource(
      pack: LexicalPackPin.fromJson(json['pack'] as Map<String, dynamic>),
      target: LexicalEntryPin.fromJson(json['target'] as Map<String, dynamic>),
      exampleIndex: json['exampleIndex'] as int,
    );
  }
}
