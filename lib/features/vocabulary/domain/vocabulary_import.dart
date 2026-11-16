import 'vocabulary_word.dart';

final class VocabularyImportRowFailure {
  const VocabularyImportRowFailure({
    required this.rowNumber,
    required this.code,
  });

  final int rowNumber;
  final String code;
}

final class VocabularyImportResult {
  const VocabularyImportResult({
    required this.importId,
    required this.accepted,
    required this.duplicates,
    required this.rejected,
  });

  final String importId;
  final int accepted;
  final int duplicates;
  final List<VocabularyImportRowFailure> rejected;
}

final class PreparedVocabularyImportRow {
  const PreparedVocabularyImportRow({
    required this.rowNumber,
    required this.payloadHash,
    this.word,
    this.failureCode,
  });

  final int rowNumber;
  final String payloadHash;
  final VocabularyWord? word;
  final String? failureCode;
}

final class PreparedVocabularyImport {
  const PreparedVocabularyImport({
    required this.importId,
    required this.ownerId,
    required this.categoryId,
    required this.sourceName,
    required this.sourceHash,
    required this.rows,
    required this.nowUtc,
  });

  final String importId;
  final String ownerId;
  final String categoryId;
  final String sourceName;
  final String sourceHash;
  final List<PreparedVocabularyImportRow> rows;
  final DateTime nowUtc;
}

final class VocabularyImportCancelled implements Exception {
  const VocabularyImportCancelled();
}
