import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/research_report_pdf_exporter_service.dart';

void main() {
  const service = ResearchReportPdfExporterService();

  const observations = [
    ResearchObservation(
      preTestScore: 60,
      postTestScore: 80,
      preLatencyMs: 3000,
      postLatencyMs: 1500,
    ),
    ResearchObservation(
      preTestScore: 70,
      postTestScore: 90,
      preLatencyMs: 1000,
      postLatencyMs: 500,
    ),
  ];

  test(
    'calculateAcademicStats rejects empty research observations explicitly',
    () {
      expect(
        () => service.calculateAcademicStats(const []),
        throwsA(isA<InsufficientData>()),
      );
    },
  );

  test('calculateAcademicStats derives statistics from typed observations', () {
    final stats = service.calculateAcademicStats(observations);

    expect(stats.sampleSize, 2);
    expect(stats.preTestMean, 65.0);
    expect(stats.postTestMean, 85.0);
    expect(stats.preLatencyMs, 2000.0);
    expect(stats.postLatencyMs, 1000.0);
    expect(stats.latencyReductionPercentage, 50.0);
  });

  test('generateAcademicPdfReport contains only derived statistics', () {
    final report = service.generateAcademicPdfReport(observations);

    expect(report, contains('Sample Size (N): 2 participants'));
    expect(report, contains('65.0%'));
    expect(report, contains('85.0%'));
    expect(report, contains('2000 ms'));
    expect(report, contains('1000 ms'));
    expect(report, isNot(contains('Expected Significance')));
    expect(report, isNot(contains('p <')));
    expect(report, isNot(contains('Paired-Samples t-Test')));
  });
}
