import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_content.dart';

void main() {
  for (final target in ['cat', 'CAT', "can't", 'well-known', 'a' * 120]) {
    test(
      'supported target and parser share exact lexical admission ($target)',
      () {
        expect(ClozeContent.supportsTarget(target), isTrue);
        final content = ClozeContent.parse(
          targetSpelling: target,
          response: _response('The $target rests.'),
        );
        expect(content.gapText, target);
      },
    );
  }

  for (final target in [
    '',
    ' cat',
    'cat ',
    'ice cream',
    'café',
    'γάτα',
    'cat2',
    '-cat',
    "cat'",
    'cat--dog',
    'cat\n',
    'cat\r',
    'cat\u2028',
    'cat\u202e',
    'cat\u200b',
    'a' * 121,
  ]) {
    test(
      'unsupported target rejects before generation and in parser (${target.codeUnits})',
      () {
        expect(ClozeContent.supportsTarget(target), isFalse);
        expect(
          () => ClozeContent.parse(
            targetSpelling: target,
            response: _response('The $target rests.'),
          ),
          throwsFormatException,
        );
      },
    );
  }

  for (final sentence in [
    'The catβ rests.',
    'The βcat rests.',
    'The caté rests.',
    'The écat rests.',
  ]) {
    test(
      'supported ASCII target never consumes a nonASCII subword ($sentence)',
      () {
        expect(ClozeContent.supportsTarget('cat'), isTrue);
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(sentence),
          ),
          throwsFormatException,
        );
      },
    );
  }
}

ContentResponse _response(String text) => ContentResponse(
  text: text,
  kind: ContentKind.sentence,
  cefr: CefrLevel.a2,
  language: 'en',
  modelVersion: 'synthetic-model-v1',
  cached: false,
);
