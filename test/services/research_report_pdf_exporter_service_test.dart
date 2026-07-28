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

  test('calculateAcademicStats rejects a zero pre-test latency baseline', () {
    const zeroPreTestLatency = [
      ResearchObservation(
        preTestScore: 60,
        postTestScore: 80,
        preLatencyMs: 0,
        postLatencyMs: 200,
      ),
      ResearchObservation(
        preTestScore: 70,
        postTestScore: 90,
        preLatencyMs: 0,
        postLatencyMs: 300,
      ),
    ];

    expect(
      () => service.calculateAcademicStats(zeroPreTestLatency),
      throwsA(isA<InsufficientData>()),
    );
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

  test('generateAcademicPdfReport formats a score decline with one sign', () {
    const decliningObservations = [
      ResearchObservation(
        preTestScore: 80,
        postTestScore: 60,
        preLatencyMs: 1000,
        postLatencyMs: 1200,
      ),
      ResearchObservation(
        preTestScore: 60,
        postTestScore: 60,
        preLatencyMs: 1000,
        postLatencyMs: 1200,
      ),
    ];

    final report = service.generateAcademicPdfReport(decliningObservations);

    expect(report, contains('Mean Score Change: -10.0 percentage points'));
    expect(report, isNot(contains('Mean Score Gain')));
    expect(report, isNot(contains('+-10.0')));
  });
}
