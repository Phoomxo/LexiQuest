import 'dart:convert';

import '../../../ai/ai_models.dart';
import 'native_sentence_source.dart';

final class ClozeContent {
  const ClozeContent._({
    required this.sentence,
    required this.gapStart,
    required this.gapEnd,
    required this.source,
  });

  static const maxSentenceRunes = 1024;
  static const maxSentenceUtf8Bytes = 2048;
  static const maxTargetLength = 120;
  static const maxModelVersionRunes = 256;
  static const maxModelVersionUtf8Bytes = 256;

  static bool supportsTarget(String spelling) {
    if (spelling.length > maxTargetLength) {
      return false;
    }
    final match = _lexicalTarget.matchAsPrefix(spelling);
    return match != null && match.end == spelling.length;
  }

  factory ClozeContent.parse({
    required String targetSpelling,
    required ContentResponse response,
  }) {
    final source = GeneratedSentenceSource(
      kind: response.kind,
      cefr: response.cefr,
      language: response.language,
      modelVersion: response.modelVersion.trim(),
      cached: response.cached,
    );
    final originalModelVersion = response.modelVersion;
    if (response.kind != ContentKind.sentence ||
        response.language != 'en' ||
        !_boundedText(
          originalModelVersion,
          maxModelVersionRunes,
          maxModelVersionUtf8Bytes,
        ) ||
        _html.hasMatch(originalModelVersion)) {
      _invalidContent();
    }
    return ClozeContent._admit(targetSpelling, response.text, source);
  }

  factory ClozeContent.authored(AuthoredSentenceSource source) =>
      ClozeContent._admit(source.target.word.spelling, source.text, source);

  factory ClozeContent._admit(
    String targetSpelling,
    String text,
    NativeSentenceSource source,
  ) {
    if (!supportsTarget(targetSpelling) ||
        !_boundedText(text, maxSentenceRunes, maxSentenceUtf8Bytes) ||
        _markup.hasMatch(text)) {
      _invalidContent();
    }

    final sentence = text.trim();
    final foldedSentence = _asciiLower(sentence);
    final foldedTarget = _asciiLower(targetSpelling);
    var gapStart = -1;
    var candidate = foldedSentence.indexOf(foldedTarget);
    while (candidate != -1) {
      final end = candidate + targetSpelling.length;
      if (_leftBoundary(sentence, candidate) && _rightBoundary(sentence, end)) {
        if (gapStart != -1) {
          _invalidContent();
        }
        gapStart = candidate;
      }
      candidate = foldedSentence.indexOf(foldedTarget, candidate + 1);
    }
    if (gapStart == -1) {
      _invalidContent();
    }
    final gapEnd = gapStart + targetSpelling.length;
    final context =
        '${sentence.substring(0, gapStart)} ${sentence.substring(gapEnd)}';
    if (!_lexicalContext
        .allMatches(context)
        .any(
          (match) =>
              _leftBoundary(context, match.start) &&
              _rightBoundary(context, match.end),
        )) {
      _invalidContent();
    }

    return ClozeContent._(
      sentence: sentence,
      gapStart: gapStart,
      gapEnd: gapEnd,
      source: source,
    );
  }

  final String sentence;

  /// Half-open UTF-16 offsets into [sentence], matching String.substring.
  final int gapStart;
  final int gapEnd;
  final NativeSentenceSource source;

  String get prefix => sentence.substring(0, gapStart);
  String get gapText => sentence.substring(gapStart, gapEnd);
  String get suffix => sentence.substring(gapEnd);
}

final _lexicalTarget = RegExp(r"^[A-Za-z]+(?:['-][A-Za-z]+)*$");
final _lexicalContext = RegExp(r"[A-Za-z]+(?:['-][A-Za-z]+)*");
final _markup = RegExp(r'[<>`*_\[\]{}#]');
final _html = RegExp(r'[<>]');
const _delimiters = ' \u00a0.,!?;:()"“”«»—–…';

bool _boundedText(String value, int maxRunes, int maxUtf8Bytes) {
  if (value.trim().isEmpty ||
      value.runes.length > maxRunes ||
      utf8.encode(value).length > maxUtf8Bytes) {
    return false;
  }
  for (final rune in value.runes) {
    if (rune < 0x20 ||
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
        (rune >= 0xfff9 && rune <= 0xfffb)) {
      return false;
    }
  }
  return true;
}

// Explicit delimiters fail closed for non-ASCII letters adjacent to the target.
bool _leftBoundary(String value, int start) {
  if (start == 0) {
    return true;
  }
  final previous = start - 1;
  if (_delimiter(value.codeUnitAt(previous))) {
    return true;
  }
  return _singleQuote(value.codeUnitAt(previous)) &&
      (previous == 0 || _delimiter(value.codeUnitAt(previous - 1)));
}

bool _rightBoundary(String value, int end) {
  if (end == value.length) {
    return true;
  }
  if (_delimiter(value.codeUnitAt(end))) {
    return true;
  }
  return _singleQuote(value.codeUnitAt(end)) &&
      (end + 1 == value.length || _delimiter(value.codeUnitAt(end + 1)));
}

bool _delimiter(int codeUnit) =>
    _delimiters.contains(String.fromCharCode(codeUnit));
bool _singleQuote(int codeUnit) =>
    codeUnit == 0x27 || codeUnit == 0x2018 || codeUnit == 0x2019;

String _asciiLower(String value) => String.fromCharCodes(
  value.codeUnits.map(
    (unit) => unit >= 0x41 && unit <= 0x5a ? unit + 0x20 : unit,
  ),
);

Never _invalidContent() =>
    throw const FormatException('Invalid Cloze content.');
