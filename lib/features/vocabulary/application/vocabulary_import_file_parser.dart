import 'dart:convert';
import 'dart:typed_data';

import 'import_vocabulary.dart';
import 'vocabulary_use_cases.dart';

const int maxVocabularyImportBytes = 1024 * 1024;
const int maxVocabularyImportRows = 500;

enum VocabularyImportPreviewStatus { ready, needsEdit, duplicate }

final class VocabularyImportFileFailure implements Exception {
  const VocabularyImportFileFailure(this.code);

  final String code;
}

final class VocabularyImportPreviewRow {
  const VocabularyImportPreviewRow({
    required this.rowNumber,
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.status,
    this.failureCode,
  });

  final int rowNumber;
  final String word;
  final String meaning;
  final String partOfSpeech;
  final VocabularyImportPreviewStatus status;
  final String? failureCode;

  Map<String, String> toMap() => {
    'word': word,
    'meaning': meaning,
    'partOfSpeech': partOfSpeech,
  };
}

final class VocabularyImportPreview {
  const VocabularyImportPreview({required this.sourceName, required this.rows});

  final String sourceName;
  final List<VocabularyImportPreviewRow> rows;

  int get readyCount => _count(VocabularyImportPreviewStatus.ready);
  int get needsEditCount => _count(VocabularyImportPreviewStatus.needsEdit);
  int get duplicateCount => _count(VocabularyImportPreviewStatus.duplicate);

  int _count(VocabularyImportPreviewStatus status) =>
      rows.where((row) => row.status == status).length;
}

VocabularyImportPreview parseVocabularyImportFile({
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
  Iterable<Map<String, String>> existingRows = const [],
}) {
  final extension = _validatedExtension(fileName, mimeType);
  if (bytes.isEmpty) throw const VocabularyImportFileFailure('emptyFile');
  if (bytes.length > maxVocabularyImportBytes) {
    throw const VocabularyImportFileFailure('fileTooLarge');
  }

  late final String text;
  try {
    text = utf8.decode(bytes).replaceFirst('\ufeff', '');
  } on FormatException {
    throw const VocabularyImportFileFailure('invalidEncoding');
  }
  if (text.trim().isEmpty) {
    throw const VocabularyImportFileFailure('emptyFile');
  }

  final rows = extension == 'csv' ? _csvRows(text) : _jsonRows(text);
  if (rows.isEmpty) throw const VocabularyImportFileFailure('emptyFile');
  if (rows.length > maxVocabularyImportRows) {
    throw const VocabularyImportFileFailure('tooManyRows');
  }
  return VocabularyImportPreview(
    sourceName: fileName,
    rows: reviewVocabularyImportRows(rows, existingRows: existingRows),
  );
}

List<VocabularyImportPreviewRow> reviewVocabularyImportRows(
  Iterable<Map<String, String>> rows, {
  Iterable<Map<String, String>> existingRows = const [],
}) {
  final naturalKeys = existingRows.map(_naturalKey).toSet();
  final reviewed = <VocabularyImportPreviewRow>[];
  var rowNumber = 0;
  for (final row in rows) {
    rowNumber++;
    final failureCode = validateVocabularyImportRow(row);
    final duplicate = failureCode == null && !naturalKeys.add(_naturalKey(row));
    reviewed.add(
      VocabularyImportPreviewRow(
        rowNumber: rowNumber,
        word: row['word'] ?? '',
        meaning: row['meaning'] ?? '',
        partOfSpeech: row['partOfSpeech'] ?? '',
        status: failureCode != null
            ? VocabularyImportPreviewStatus.needsEdit
            : duplicate
            ? VocabularyImportPreviewStatus.duplicate
            : VocabularyImportPreviewStatus.ready,
        failureCode: failureCode,
      ),
    );
  }
  return List.unmodifiable(reviewed);
}

String _validatedExtension(String fileName, String? mimeType) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  if (extension != 'csv' && extension != 'json') {
    throw const VocabularyImportFileFailure('unsupportedType');
  }
  final mime = mimeType?.split(';').first.trim().toLowerCase();
  if (mime == null ||
      mime.isEmpty ||
      mime == 'text/plain' ||
      mime == 'application/octet-stream' ||
      mime == 'binary/octet-stream') {
    return extension;
  }
  final allowed = extension == 'csv'
      ? const {'text/csv', 'application/csv'}
      : const {'application/json', 'text/json'};
  if (!allowed.contains(mime)) {
    throw const VocabularyImportFileFailure('unsupportedType');
  }
  return extension;
}

List<Map<String, String>> _csvRows(String text) {
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var closedQuote = false;

  void finishField() {
    record.add(field.toString());
    field.clear();
    closedQuote = false;
  }

  void finishRecord() {
    final isBlankPhysicalLine =
        record.isEmpty && field.toString().trim().isEmpty && !closedQuote;
    finishField();
    if (!isBlankPhysicalLine) records.add(record);
    record = <String>[];
  }

  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
          closedQuote = true;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    if (char == '"') {
      if (field.isNotEmpty || closedQuote) {
        throw const VocabularyImportFileFailure('malformedCsv');
      }
      quoted = true;
    } else if (char == ',') {
      finishField();
    } else if (char == '\r' || char == '\n') {
      finishRecord();
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
    } else {
      if (closedQuote && char.trim().isNotEmpty) {
        throw const VocabularyImportFileFailure('malformedCsv');
      }
      field.write(char);
    }
  }
  if (quoted) throw const VocabularyImportFileFailure('malformedCsv');
  if (field.isNotEmpty || record.isNotEmpty || closedQuote) finishRecord();
  if (records.isNotEmpty && _isHeader(records.first)) records.removeAt(0);
  if (records.any((row) => row.length != 3)) {
    throw const VocabularyImportFileFailure('malformedCsv');
  }
  return [
    for (final row in records)
      {'word': row[0], 'meaning': row[1], 'partOfSpeech': row[2]},
  ];
}

bool _isHeader(List<String> row) =>
    row.length == 3 &&
    row[0].trim().toLowerCase() == 'word' &&
    row[1].trim().toLowerCase() == 'meaning' &&
    row[2].trim().toLowerCase() == 'partofspeech';

List<Map<String, String>> _jsonRows(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw const VocabularyImportFileFailure('malformedJson');
    }
    return [
      for (final value in decoded)
        if (value is Map<String, dynamic>)
          {
            'word': _jsonString(value, 'word'),
            'meaning': _jsonString(value, 'meaning'),
            'partOfSpeech': _jsonString(value, 'partOfSpeech'),
          }
        else
          throw const VocabularyImportFileFailure('malformedJson'),
    ];
  } on VocabularyImportFileFailure {
    rethrow;
  } on FormatException {
    throw const VocabularyImportFileFailure('malformedJson');
  }
}

String _jsonString(Map<String, dynamic> value, String key) {
  final field = value[key];
  if (field == null) return '';
  if (field is! String) {
    throw const VocabularyImportFileFailure('malformedJson');
  }
  return field;
}

String _naturalKey(Map<String, String> row) =>
    '${normalizeVocabularyText(row['word'] ?? '')}\u001f'
    '${normalizeVocabularyText(row['meaning'] ?? '')}';
