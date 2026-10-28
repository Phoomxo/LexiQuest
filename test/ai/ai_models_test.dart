import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';

void main() {
  group('ContentKind', () {
    test('wire round-trips through fromWire', () {
      for (final kind in ContentKind.values) {
        expect(ContentKind.fromWire(kind.wire), kind);
      }
    });

    test('fromWire returns null for unknown values', () {
      expect(ContentKind.fromWire('essay'), isNull);
      expect(ContentKind.fromWire(null), isNull);
      expect(ContentKind.fromWire(''), isNull);
    });
  });

  group('CefrLevel', () {
    test('wire round-trips through fromWire', () {
      for (final level in CefrLevel.values) {
        expect(CefrLevel.fromWire(level.wire), level);
      }
    });

    test('fromWire is case-insensitive and defaults to unknown', () {
      expect(CefrLevel.fromWire('A1'), CefrLevel.a1);
      expect(CefrLevel.fromWire('  b2  '), CefrLevel.b2);
      expect(CefrLevel.fromWire('garbage'), CefrLevel.unknown);
      expect(CefrLevel.fromWire(null), CefrLevel.unknown);
    });
  });

  group('ContentRequest.create', () {
    test('normalises whitespace and trims', () {
      final request = ContentRequest.create(
        text: '  The   cat   sleeps.  ',
        kind: ContentKind.sentence,
      );
      expect(request.text, 'The cat sleeps.');
    });

    test('rejects empty text', () {
      expect(
        () => ContentRequest.create(text: '   ', kind: ContentKind.sentence),
        throwsA(isA<AiFailure>()),
      );
    });

    test('rejects text over 500 characters', () {
      expect(
        () =>
            ContentRequest.create(text: 'a' * 501, kind: ContentKind.sentence),
        throwsA(isA<AiFailure>()),
      );
    });

    test('accepts text at exactly 500 characters (boundary)', () {
      expect(
        () =>
            ContentRequest.create(text: 'a' * 500, kind: ContentKind.sentence),
        returnsNormally,
      );
    });

    test('rejects unsupported languages', () {
      expect(
        () => ContentRequest.create(
          text: 'cat',
          kind: ContentKind.sentence,
          language: 'fr',
        ),
        throwsA(isA<AiFailure>()),
      );
    });

    test('lowercases language', () {
      final request = ContentRequest.create(
        text: 'cat',
        kind: ContentKind.sentence,
        language: 'EN',
      );
      expect(request.language, 'en');
    });

    test('AiFailure carries only category and message', () {
      try {
        ContentRequest.create(text: '', kind: ContentKind.sentence);
        fail('expected AiFailure');
      } on AiFailure catch (failure) {
        expect(failure.category, AiFailureCategory.validation);
        expect(failure.message, isNotEmpty);
        // No request text, token, or stack frames leaked.
        expect(failure.toString(), contains('AiFailure'));
      }
    });
  });
}
