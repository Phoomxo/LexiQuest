import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/vocabulary_word.dart';

const int maxSourcePracticeBytes = 1024 * 1024;

final class SourcePracticeFailure implements Exception {
  const SourcePracticeFailure(this.code);

  final String code;
}

final class SourcePracticeFile {
  const SourcePracticeFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String? mimeType;
  final Uint8List bytes;
}

typedef SourcePracticeFilePicker = Future<SourcePracticeFile?> Function();

final class SourcePracticePreview {
  const SourcePracticePreview({
    required this.sourceName,
    required this.passageText,
    required this.matchedWords,
    required this.unknownWords,
    required this.documentId,
    required this.documentRevision,
  });

  final String sourceName;
  final String passageText;
  final List<VocabularyWord> matchedWords;
  final List<String> unknownWords;
  final String documentId;
  final int documentRevision;
}

SourcePracticePreview parseSourcePracticeFile({
  required String fileName,
  required Uint8List bytes,
  required Iterable<VocabularyWord> words,
  String? mimeType,
}) {
  final extension = _validatedExtension(fileName, mimeType);
  if (bytes.isEmpty) throw const SourcePracticeFailure('emptyFile');
  if (bytes.length > maxSourcePracticeBytes) {
    throw const SourcePracticeFailure('fileTooLarge');
  }

  late final String source;
  try {
    source = utf8.decode(bytes).replaceFirst('\ufeff', '');
  } on FormatException {
    throw const SourcePracticeFailure('invalidEncoding');
  }
  return reviewSourcePracticeText(
    sourceName: fileName,
    text: extension == 'md' ? _markdownToText(source) : source,
    words: words,
  );
}

SourcePracticePreview reviewSourcePracticeText({
  required String sourceName,
  required String text,
  required Iterable<VocabularyWord> words,
}) {
  if (utf8.encode(text).length > maxSourcePracticeBytes) {
    throw const SourcePracticeFailure('fileTooLarge');
  }
  final canonicalName = sourceName.trim();
  if (canonicalName.isEmpty) {
    throw const SourcePracticeFailure('unsupportedType');
  }
  final passage = _canonicalPassage(text);
  if (passage.isEmpty) throw const SourcePracticeFailure('emptyFile');
  _requireEnglish(passage);

  final firstBySpelling = <String, VocabularyWord>{};
  final candidates = words.where((word) => !word.isDeleted).toList()
    ..sort((left, right) => left.id.compareTo(right.id));
  for (final word in candidates) {
    final spelling = _canonicalWord(word.spelling);
    if (spelling.isNotEmpty) firstBySpelling.putIfAbsent(spelling, () => word);
  }

  final found = <({int position, VocabularyWord word})>[];
  for (final entry in firstBySpelling.entries) {
    final pattern = entry.key.split(' ').map(RegExp.escape).join(r'\s+');
    final match = RegExp(
      '(^|[^A-Za-z])($pattern)(?=\$|[^A-Za-z])',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(passage);
    if (match != null) {
      found.add((position: match.start, word: entry.value));
    }
  }
  found.sort((left, right) {
    final byPosition = left.position.compareTo(right.position);
    return byPosition != 0 ? byPosition : left.word.id.compareTo(right.word.id);
  });
  final matched = found.map((item) => item.word).toList(growable: false);
  final knownTokens = <String>{
    for (final word in matched)
      ..._englishTokens(_canonicalWord(word.spelling)),
  };
  final unknown = <String>[];
  final seenUnknown = <String>{};
  for (final token in _englishTokens(passage)) {
    if (!knownTokens.contains(token) && seenUnknown.add(token)) {
      unknown.add(token);
    }
  }

  final nameHash = sha256
      .convert(utf8.encode(canonicalName.toLowerCase()))
      .toString();
  final contentDigest = sha256.convert(utf8.encode(passage)).bytes;
  var revision =
      ((contentDigest[0] & 0x7f) << 24) |
      (contentDigest[1] << 16) |
      (contentDigest[2] << 8) |
      contentDigest[3];
  if (revision == 0) revision = 1;
  return SourcePracticePreview(
    sourceName: canonicalName,
    passageText: passage,
    matchedWords: List.unmodifiable(matched),
    unknownWords: List.unmodifiable(unknown),
    documentId: 'local-source:$nameHash',
    documentRevision: revision,
  );
}

String _validatedExtension(String fileName, String? mimeType) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  if (extension != 'txt' && extension != 'md') {
    throw const SourcePracticeFailure('unsupportedType');
  }
  final mime = mimeType?.split(';').first.trim().toLowerCase();
  if (mime == null ||
      mime.isEmpty ||
      mime == 'application/octet-stream' ||
      mime == 'binary/octet-stream') {
    return extension;
  }
  final allowed = extension == 'txt'
      ? const {'text/plain'}
      : const {'text/plain', 'text/markdown', 'text/x-markdown'};
  if (!allowed.contains(mime)) {
    throw const SourcePracticeFailure('unsupportedType');
  }
  return extension;
}

String _markdownToText(String source) {
  var value = source.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  value = value.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  value = value.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  value = value.replaceAllMapped(
    RegExp(r'`([^`]*)`'),
    (match) => match.group(1) ?? '',
  );
  value = value.replaceAll(
    RegExp(r'^\s{0,3}(?:#{1,6}|>|[-+*])\s+', multiLine: true),
    '',
  );
  return value.replaceAll(RegExp(r'[*_~]'), '');
}

String _canonicalPassage(String value) => value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(r'[ \t]+'), ' '))
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String _canonicalWord(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

List<String> _englishTokens(String value) => RegExp(
  r"[A-Za-z]+(?:['’-][A-Za-z]+)*",
  unicode: true,
).allMatches(value).map((match) => match.group(0)!.toLowerCase()).toList();

void _requireEnglish(String passage) {
  final englishTokens = _englishTokens(passage);
  var englishLetters = 0;
  var nonAsciiCharacters = 0;
  for (final rune in passage.runes) {
    if ((rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122)) {
      englishLetters++;
    } else if (rune > 127 && String.fromCharCode(rune).trim().isNotEmpty) {
      nonAsciiCharacters++;
    }
  }
  final languageCharacters = englishLetters + nonAsciiCharacters;
  if (englishTokens.length < 5 ||
      languageCharacters == 0 ||
      englishLetters / languageCharacters < 0.7) {
    throw const SourcePracticeFailure('notEnglish');
  }
}
