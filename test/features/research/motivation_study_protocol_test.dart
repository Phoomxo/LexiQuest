import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_study_protocol.dart';

void main() {
  // Synthetic contracts only, without validated questionnaire content.
  final instrument = MotivationInstrument(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: '1',
    formId: 'synthetic-form',
    formVersion: '1',
    itemCatalogVersion: '1',
    items: [
      for (final point in MotivationTimepoint.values)
        MotivationItem(
          id: 'synthetic-${point.name}',
          timepoint: point,
          prompts: {'th': 'ตัวอย่างสำหรับทดสอบ', 'en': 'Synthetic test item'},
          options: [
            MotivationResponseOption(
              code: 'low',
              ordinalValue: 0,
              labels: {'th': 'ตัวอย่างหนึ่ง', 'en': 'Synthetic one'},
            ),
            MotivationResponseOption(
              code: 'high',
              ordinalValue: 100,
              labels: {'th': 'ตัวอย่างสอง', 'en': 'Synthetic two'},
            ),
          ],
        ),
    ],
  );

  MotivationStudyProtocol protocol({
    String? checksum,
    String id = 'synthetic',
  }) => MotivationStudyProtocol(
    protocolId: id,
    protocolVersion: '1',
    consentVersion: 1,
    experimentId: 'synthetic-experiment',
    experimentVersion: 1,
    instrument: instrument,
    approvedInstrumentChecksum: checksum ?? instrument.checksumSha256,
    appVersion: 'test-1',
    buildId: 'synthetic-build',
    contentRevision: 'synthetic-content',
    evidencePolicyVersion: 'learning-evidence-v1',
    catalogVersion: '1.3.0',
  );

  test('requires the externally supplied exact instrument checksum', () {
    expect(protocol().instrument, same(instrument));
    expect(() => protocol(checksum: '0' * 64), throwsFormatException);
  });

  test('protocol identifiers accept codes and reject free text', () {
    expect(
      protocol(id: 'synthetic:protocol-v1').protocolId,
      'synthetic:protocol-v1',
    );
    for (final id in ['', 'contains spaces', 'person@example.test']) {
      expect(() => protocol(id: id), throwsFormatException);
    }
  });

  test('trusted record timestamps require UTC millisecond precision', () {
    expect(
      () => requireResearchUtc(DateTime.utc(2026, 10, 28)),
      returnsNormally,
    );
    expect(
      () => requireResearchUtc(DateTime(2026, 10, 28)),
      throwsFormatException,
    );
    expect(
      () => requireResearchUtc(
        DateTime.fromMicrosecondsSinceEpoch(1001, isUtc: true),
      ),
      throwsFormatException,
    );
  });
}
