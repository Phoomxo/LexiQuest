import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/research_report_pdf_exporter_service.dart';

void main() {
  const service = ResearchReportPdfExporterService();

  test('calculateAcademicStats calculates mean and SD correctly', () {
    final records = [
      {'latencyMs': 2000},
      {'latencyMs': 1000},
    ];

    final stats = service.calculateAcademicStats(records);
    expect(stats.sampleSize, 2);
    expect(stats.postLatencyMs, 1500.0);
  });

  test('generateAcademicPdfReport formats research report text', () {
    final report = service.generateAcademicPdfReport([]);
    expect(report.contains('LEXIQUEST RESEARCH SUMMARY REPORT'), true);
    expect(report.contains('Sample Size (N)'), true);
    expect(report.contains('Paired-Samples t-Test'), true);
  });
}
