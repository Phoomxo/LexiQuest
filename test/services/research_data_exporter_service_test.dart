import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/research_data_exporter_service.dart';

void main() {
  const service = ResearchDataExporterService();

  test('generateCsvReport formats learning data into CSV header and rows', () {
    final records = [
      {
        'word': 'apple',
        'cefr_level': 'A1',
        'latency_ms': 1200,
        'accuracy_percent': 100.0,
        'srs_box': 2,
        'reviewed_at': '2026-07-24T12:00:00Z',
      },
    ];

    final csv = service.generateCsvReport(records);
    expect(
      csv.contains(
        'word,cefr_level,latency_ms,accuracy_percent,srs_box,reviewed_at',
      ),
      true,
    );
    expect(csv.contains('apple,A1,1200,100.0,2,2026-07-24T12:00:00Z'), true);
  });
}
