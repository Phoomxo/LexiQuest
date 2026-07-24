class ResearchDataExporterService {
  const ResearchDataExporterService();

  /// Converts learning telemetry and SRS performance records into CSV format for SPSS/Python analysis in Chapter 4.
  String generateCsvReport(List<Map<String, dynamic>> records) {
    final buffer = StringBuffer();
    buffer.writeln(
      'word,cefr_level,latency_ms,accuracy_percent,srs_box,reviewed_at',
    );

    for (final rec in records) {
      final word = rec['word']?.toString() ?? '';
      final level = rec['cefr_level']?.toString() ?? 'A1';
      final latency = rec['latency_ms']?.toString() ?? '0';
      final accuracy = rec['accuracy_percent']?.toString() ?? '0.0';
      final box = rec['srs_box']?.toString() ?? '1';
      final time =
          rec['reviewed_at']?.toString() ?? DateTime.now().toIso8601String();

      buffer.writeln('$word,$level,$latency,$accuracy,$box,$time');
    }

    return buffer.toString();
  }
}
