import 'dart:convert';

import '../../../ai/ai_models.dart';

/// Admitted sentence text and provider metadata, without a grammar or level claim.
final class SentenceScrambleContent {
  const SentenceScrambleContent._({
    required this.targetSpelling,
    required this.sentence,
    required this.tokens,
    required this.tokenOrder,
    required this.kind,
    required this.cefr,
    required this.language,
    required this.modelVersion,
    required this.cached,
  });

  static const maxSentenceRunes = 1024;
  static const maxSentenceUtf8Bytes = 2048;
  static const maxTargetLength = 120;
  static const maxModelVersionRunes = 256;
  static const maxModelVersionUtf8Bytes = 256;
  static const maxTokens = 64;

  static bool supportsTarget(String spelling) {
    if (spelling.length > maxTargetLength) return false;
    final match = _lexicalTarget.matchAsPrefix(spelling);
    return match != null && match.end == spelling.length;
  }

  factory SentenceScrambleContent.parse({
    required String targetSpelling,
    required ContentResponse response,
  }) {
    final sentence = _canonicalSentence(response.text);
    if (!supportsTarget(targetSpelling) ||
        response.kind != ContentKind.sentence ||
        response.language != 'en' ||
        sentence == null ||
        !_boundedModelVersion(response.modelVersion) ||
        !_containsWholeAnchor(sentence, targetSpelling)) {
      _invalidContent();
    }
    final tokens = sentence.split(' ');
    if (tokens.length < 2 ||
        tokens.length > maxTokens ||
        tokens.where((token) => _wordChunk.hasMatch(token)).length < 2) {
      _invalidContent();
    }
    final order = [for (var i = 1; i < tokens.length; i++) i, 0];
    if (order.map((index) => tokens[index]).join(' ') == sentence) {
      _invalidContent();
    }
    return SentenceScrambleContent._(
      targetSpelling: targetSpelling,
      sentence: sentence,
      tokens: List<String>.unmodifiable(tokens),
      tokenOrder: List<int>.unmodifiable(order),
      kind: response.kind,
      cefr: response.cefr,
      language: response.language,
      modelVersion: response.modelVersion.trim(),
      cached: response.cached,
    );
  }

  final String targetSpelling;
  final String sentence;

  /// Canonical answer order. Equal-text chunks keep distinct positions.
  final List<String> tokens;

  /// Stable bank order expressed as indices into [tokens].
  final List<int> tokenOrder;
  final ContentKind kind;
  final CefrLevel cefr;
  final String language;
  final String modelVersion;
  final bool cached;

  bool matchesResponse(String response) =>
      _canonicalSentence(response) == sentence;
}

final _lexicalTarget = RegExp(r"^[A-Za-z]+(?:['-][A-Za-z]+)*$");
final _wordChunk = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _markup = RegExp(r'[<>`*_\[\]{}#]');
const _delimiters = ' \u00a0.,!?;:()"“”«»—–…';

String? _canonicalSentence(String value) {
  if (value.runes.length > SentenceScrambleContent.maxSentenceRunes ||
      utf8.encode(value).length >
          SentenceScrambleContent.maxSentenceUtf8Bytes) {
    return null;
  }
  final buffer = StringBuffer();
  var separator = false;
  for (final rune in value.runes) {
    if (_whiteSpace(rune)) {
      if (buffer.isNotEmpty) separator = true;
      continue;
    }
    if (_excludedRune(rune)) return null;
    if (separator) {
      buffer.write(' ');
      separator = false;
    }
    buffer.writeCharCode(rune);
  }
  final result = buffer.toString();
  return result.isEmpty || _markup.hasMatch(result) ? null : result;
}

// Unicode White_Space, handled before Cloze's conservative control exclusions.
bool _whiteSpace(int rune) =>
    (rune >= 0x09 && rune <= 0x0d) ||
    rune == 0x20 ||
    rune == 0x85 ||
    rune == 0xa0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200a) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202f ||
    rune == 0x205f ||
    rune == 0x3000;

bool _excludedRune(int rune) =>
    rune < 0x20 ||
    (rune >= 0x7f && rune <= 0x9f) ||
    rune == 0xad ||
    rune == 0x34f ||
    rune == 0x61c ||
    rune == 0x180e ||
    (rune >= 0x200b && rune <= 0x200f) ||
    (rune >= 0x2028 && rune <= 0x202e) ||
    (rune >= 0x2060 && rune <= 0x206f) ||
    (rune >= 0xd800 && rune <= 0xdfff) ||
    rune == 0xfeff ||
    (rune >= 0xfff9 && rune <= 0xfffb);

bool _boundedModelVersion(String value) =>
    value.trim().isNotEmpty &&
    value.runes.length <= SentenceScrambleContent.maxModelVersionRunes &&
    utf8.encode(value).length <=
        SentenceScrambleContent.maxModelVersionUtf8Bytes &&
    !value.runes.any(_excludedRune) &&
    !RegExp(r'[<>]').hasMatch(value);

bool _containsWholeAnchor(String sentence, String target) {
  final folded = _asciiLower(sentence);
  final foldedTarget = _asciiLower(target);
  var candidate = folded.indexOf(foldedTarget);
  while (candidate != -1) {
    final end = candidate + target.length;
    if (_leftBoundary(sentence, candidate) && _rightBoundary(sentence, end)) {
      return true;
    }
    candidate = folded.indexOf(foldedTarget, candidate + 1);
  }
  return false;
}

bool _leftBoundary(String value, int start) {
  if (start == 0) return true;
  final previous = start - 1;
  if (_delimiter(value.codeUnitAt(previous))) return true;
  return _singleQuote(value.codeUnitAt(previous)) &&
      (previous == 0 || _delimiter(value.codeUnitAt(previous - 1)));
}

bool _rightBoundary(String value, int end) {
  if (end == value.length) return true;
  if (_delimiter(value.codeUnitAt(end))) return true;
  return _singleQuote(value.codeUnitAt(end)) &&
      (end + 1 == value.length || _delimiter(value.codeUnitAt(end + 1)));
}

bool _delimiter(int unit) => _delimiters.contains(String.fromCharCode(unit));
bool _singleQuote(int unit) => unit == 0x27 || unit == 0x2018 || unit == 0x2019;
String _asciiLower(String value) => String.fromCharCodes(
  value.codeUnits.map(
    (unit) => unit >= 0x41 && unit <= 0x5a ? unit + 0x20 : unit,
  ),
);
Never _invalidContent() =>
    throw const FormatException('Invalid Sentence Scramble content.');
