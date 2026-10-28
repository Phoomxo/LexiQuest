import 'research_export_errors.dart';

export 'research_export_errors.dart';

class ResearchExportRow {
  const ResearchExportRow({
    required this.word,
    required this.cefrLevel,
    required this.latencyMs,
    required this.accuracyPercent,
    required this.srsBox,
    required this.reviewedAtUtc,
  });

  final String word;
  final String cefrLevel;
  final double latencyMs;
  final double accuracyPercent;
  final int srsBox;
  final DateTime reviewedAtUtc;
}

class InvalidResearchExportData implements Exception {
  const InvalidResearchExportData(this.message);

  final String message;

  @override
  String toString() => 'InvalidResearchExportData: $message';
}

class ResearchDataExporterService {
  const ResearchDataExporterService();

  static const int maxWordLength = 100;
  static const Set<String> supportedCefrLevels = {
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  };

  /// Converts learning telemetry and SRS performance records into CSV format for SPSS/Python analysis in Chapter 4.
  String generateCsvReport(List<ResearchExportRow> records) {
    if (records.isEmpty) {
      throw const InsufficientData();
    }

    final buffer = StringBuffer();
    buffer.write(
      'word,cefr_level,latency_ms,accuracy_percent,srs_box,reviewed_at\r\n',
    );

    for (final record in records) {
      _validate(record);
      buffer.write(
        '${_safeTextField(record.word)},${record.cefrLevel},'
        '${record.latencyMs},'
        '${record.accuracyPercent},${record.srsBox},'
        '${record.reviewedAtUtc.toIso8601String()}\r\n',
      );
    }

    return buffer.toString();
  }

  static String _safeTextField(String value) {
    var safe = value
        .trim()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '\r\n');
    if ('=+-@'.contains(safe[0])) {
      safe = "'$safe";
    }
    if (safe.contains(',') ||
        safe.contains('"') ||
        safe.contains('\r') ||
        safe.contains('\n')) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }

  static void _validate(ResearchExportRow row) {
    final word = row.word.trim();
    if (word.isEmpty || word.length > maxWordLength) {
      throw const InvalidResearchExportData(
        'Word must contain between 1 and 100 characters.',
      );
    }
    if (!supportedCefrLevels.contains(row.cefrLevel)) {
      throw const InvalidResearchExportData(
        'CEFR level must be between A1 and C2.',
      );
    }
    if (!row.latencyMs.isFinite || row.latencyMs <= 0) {
      throw const InvalidResearchExportData(
        'Latency must be finite and strictly positive.',
      );
    }
    if (!row.accuracyPercent.isFinite ||
        row.accuracyPercent < 0 ||
        row.accuracyPercent > 100) {
      throw const InvalidResearchExportData(
        'Accuracy must be finite and between 0 and 100.',
      );
    }
    if (row.srsBox < 1 || row.srsBox > 5) {
      throw const InvalidResearchExportData('SRS box must be between 1 and 5.');
    }
    if (!row.reviewedAtUtc.isUtc) {
      throw const InvalidResearchExportData('Review timestamp must be UTC.');
    }
  }
}
