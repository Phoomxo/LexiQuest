import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_document.dart';
import '../../support/motivation_research_fixture.dart';

void main() {
  late MotivationResearchFixture f;
  late Map<String, dynamic> document;
  setUp(() {
    f = MotivationResearchFixture();
    document = {
      ...jsonDecode(f.permit().canonicalPayload()) as Map<String, dynamic>,
      'payloadSha256': f.permit().payloadSha256,
      'signature': f.permit().signature,
    };
  });
  tearDown(() => f.database.close());
  test('round-trips exact external signed pins without granting authority', () {
    final p = decodeResearchPermitDocument(jsonEncode(document));
    expect(p.canonicalPayload(), f.permit().canonicalPayload());
    expect(p.signature, f.permit().signature);
  });
  for (final invalid in <Object?>[null, [], 1, true, 'text']) {
    test('rejects non-object document $invalid', () {
      expect(
        () => decodeResearchPermitDocument(jsonEncode(invalid)),
        throwsFormatException,
      );
    });
  }
  test(
    'unknown fields, oversized document, noncanonical codes and UTC rejected',
    () {
      final changes = <void Function(Map<String, dynamic>)>[
        (d) => d['guardianName'] = 'SYNTHETIC',
        (d) => d.remove('isDeleted'),
        (d) => d['localRevision'] = 1.5,
        (d) => d['ownerId'] = ' owner:a',
        (d) => d['issuedAtUtc'] = '2026-09-05T18:00:00+07:00',
        (d) => d['participantClass'] = 'unknown',
        (d) => d['schema'] = 'v2',
        (d) => d['isDeleted'] = 0,
      ];
      for (final change in changes) {
        final d = Map<String, dynamic>.of(document);
        change(d);
        expect(
          () => decodeResearchPermitDocument(jsonEncode(d)),
          throwsFormatException,
        );
      }
      expect(
        () => decodeResearchPermitDocument(' ' * 16385),
        throwsFormatException,
      );
    },
  );
  test('parse errors never echo signed document content', () {
    try {
      decodeResearchPermitDocument('{"secret":"SYNTHETIC_PRIVATE"');
      fail('expected failure');
    } catch (error) {
      expect(error, isA<FormatException>());
      expect('$error', isNot(contains('SYNTHETIC_PRIVATE')));
    }
  });
}
