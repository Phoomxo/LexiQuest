import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/research_data_exporter_service.dart';

void main() {
  const service = ResearchDataExporterService();

  test('generateCsvReport rejects empty research observations explicitly', () {
    expect(
      () => service.generateCsvReport(const []),
      throwsA(isA<InsufficientData>()),
    );
  });

  test('generateCsvReport formats learning data into CSV header and rows', () {
    final records = [
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: DateTime.utc(2026, 7, 24, 12),
      ),
    ];

    final csv = service.generateCsvReport(records);
    expect(
      csv.contains(
        'word,cefr_level,latency_ms,accuracy_percent,srs_box,reviewed_at',
      ),
      true,
    );
    expect(
      csv.contains('apple,A1,1200.0,100.0,2,2026-07-24T12:00:00.000Z'),
      true,
    );
  });

  test('generateCsvReport applies RFC 4180 quoting to text fields', () {
    final csv = service.generateCsvReport([
      ResearchExportRow(
        word: 'hello, "world"\nnext',
        cefrLevel: 'B2',
        latencyMs: 500,
        accuracyPercent: 75,
        srsBox: 3,
        reviewedAtUtc: DateTime.utc(2026, 7, 24, 12),
      ),
    ]);

    expect(
      csv,
      contains(
        '"hello, ""world""\r\nnext",B2,500.0,75.0,3,'
        '2026-07-24T12:00:00.000Z',
      ),
    );
  });

  test('generateCsvReport uses RFC 4180 CRLF record terminators', () {
    final csv = service.generateCsvReport([
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: DateTime.utc(2026, 7, 24, 12),
      ),
    ]);

    expect(csv, contains('\r\n'));
    expect(csv.replaceAll('\r\n', ''), isNot(contains('\n')));
  });

  test('generateCsvReport neutralizes spreadsheet formulas in text fields', () {
    for (final prefix in ['=', '+', '-', '@']) {
      final csv = service.generateCsvReport([
        ResearchExportRow(
          word: '${prefix}SUM(A1:A2)',
          cefrLevel: 'C1',
          latencyMs: 500,
          accuracyPercent: 75,
          srsBox: 3,
          reviewedAtUtc: DateTime.utc(2026, 7, 24, 12),
        ),
      ]);

      expect(csv, contains("'${prefix}SUM(A1:A2),C1,"));
      expect(csv, isNot(contains('\n${prefix}SUM(A1:A2),C1,')));
    }
  });

  test(
    'generateCsvReport rejects missing values through required typed rows',
    () {
      expect(
        () => Function.apply(ResearchExportRow.new, const [], const {
          #word: 'apple',
          #cefrLevel: 'A1',
          #latencyMs: 1200.0,
          #accuracyPercent: 100.0,
          #srsBox: 2,
        }),
        throwsA(isA<NoSuchMethodError>()),
      );
    },
  );

  test('generateCsvReport rejects every invalid row value', () {
    final validTime = DateTime.utc(2026, 7, 24, 12);
    final invalidRows = <ResearchExportRow>[
      ResearchExportRow(
        word: ' ',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: List.filled(101, 'a').join(),
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A0',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: double.nan,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 0,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: double.infinity,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: -0.1,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100.1,
        srsBox: 2,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 0,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 6,
        reviewedAtUtc: validTime,
      ),
      ResearchExportRow(
        word: 'apple',
        cefrLevel: 'A1',
        latencyMs: 1200,
        accuracyPercent: 100,
        srsBox: 2,
        reviewedAtUtc: DateTime(2026, 7, 24, 12),
      ),
    ];

    for (final row in invalidRows) {
      expect(
        () => service.generateCsvReport([row]),
        throwsA(isA<InvalidResearchExportData>()),
      );
    }
  });
}
