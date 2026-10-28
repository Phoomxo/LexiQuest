/// Research export error types.
///
/// RESEARCH_ONLY: Used by owner-only export tools.
library;

/// A single validation error found during research data export.
class ResearchExportError {
  const ResearchExportError({
    required this.code,
    required this.message,
    this.rowNumber,
    this.entityId,
  });

  final String code;
  final String message;
  final int? rowNumber;
  final String? entityId;

  @override
  String toString() =>
      'ResearchExportError($code: $message'
      '${rowNumber != null ? ' row=$rowNumber' : ''}'
      '${entityId != null ? ' entity=$entityId' : ''})';
}

/// Aggregate result of a research data export validation pass.
class ResearchExportReport {
  const ResearchExportReport({
    this.errors = const [],
    this.totalRecords = 0,
    this.validRecords = 0,
  });

  final List<ResearchExportError> errors;
  final int totalRecords;
  final int validRecords;

  bool get isClean => errors.isEmpty;
  int get errorCount => errors.length;
}
