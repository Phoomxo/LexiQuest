import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_content.dart';

void main() {
  test(
    'accepts one actual target and preserves sentence and response metadata',
    () {
      final content = ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(
          text: 'The CAT sleeps.',
          cefr: CefrLevel.b1,
          cached: true,
        ),
      );
      expect(content.sentence, 'The CAT sleeps.');
      expect(content.gapStart, 4);
      expect(content.gapEnd, 7);
      expect(content.prefix, 'The ');
      expect(content.gapText, 'CAT');
      expect(content.suffix, ' sleeps.');
      expect(content.kind, ContentKind.sentence);
      expect(content.cefr, CefrLevel.b1);
      expect(content.language, 'en');
      expect(content.modelVersion, 'synthetic-cloze-model-v1');
      expect(content.cached, isTrue);
    },
  );

  test(
    'trims outer spaces while preserving exact inner context and UTF16 offsets',
    () {
      final content = ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(text: '  A 🐾  cat rests.  '),
      );
      expect(content.sentence, 'A 🐾  cat rests.');
      expect(content.prefix, 'A 🐾  ');
      expect(content.gapStart, content.prefix.length);
      expect(content.gapEnd, content.gapStart + 3);
      expect(
        content.prefix + content.gapText + content.suffix,
        content.sentence,
      );
    },
  );

  test('preserves unknown CEFR instead of inventing validated A2 metadata', () {
    final content = ClozeContent.parse(
      targetSpelling: 'cat',
      response: _response(cefr: CefrLevel.unknown),
    );
    expect(content.cefr, CefrLevel.unknown);
  });

  for (final example in <(String, String, String)>[
    ('cat', 'A cat, waits.', 'cat'),
    ('cat', 'A “cat” waits.', 'cat'),
    ('cat', "A 'cat' waits.", 'cat'),
    ("can't", "They can't wait.", "can't"),
    ('well-known', 'A well-known author came.', 'well-known'),
    ('cat', 'The bobcat sees a cat.', 'cat'),
  ]) {
    test('whole lexical target is accepted in ${example.$2}', () {
      final content = ClozeContent.parse(
        targetSpelling: example.$1,
        response: _response(text: example.$2),
      );
      expect(content.gapText, example.$3);
    });
  }

  for (final sentence in [
    'A dog sleeps.',
    'The cat sees another CAT.',
    'A category is useful.',
    'A bobcat sleeps.',
    'A cat2 sleeps.',
    'A cat-like animal sleeps.',
    "A cat's coat shines.",
    'A caté sleeps.',
    'The scat sleeps.',
    'cat',
    '“cat”.',
    '2 cat.',
    '   ',
  ]) {
    test(
      'rejects absent repeated partial or context-free target: $sentence',
      () {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(text: sentence),
          ),
          throwsFormatException,
        );
      },
    );
  }

  for (final target in [
    '',
    ' cat',
    'cat ',
    'ice cream',
    'café',
    'cat2',
    '-cat',
    "cat'",
    'a' * 121,
  ]) {
    test('rejects unsupported original target without guessing ($target)', () {
      expect(
        () => ClozeContent.parse(targetSpelling: target, response: _response()),
        throwsFormatException,
      );
    });
  }

  for (final sentence in [
    '<b>The cat sleeps.</b>',
    '**The cat sleeps.**',
    '_The cat sleeps._',
    '`The cat sleeps.`',
    '[The cat](https://synthetic.invalid) sleeps.',
    '# The cat sleeps.',
    '{"text":"The cat sleeps."}',
    'The cat\nsleeps.',
    'The cat\rsleeps.',
    'The cat\tsleeps.',
    'The cat\u0000 sleeps.',
    'The cat\u007f sleeps.',
    'The cat\u0085 sleeps.',
    'The cat\u2028 sleeps.',
    'The cat\u202e sleeps.',
    'The cat\u2066 sleeps.',
    'The cat\u200b sleeps.',
    'The cat\ufeff sleeps.',
  ]) {
    test(
      'rejects markup or invisible controls (synthetic case ${sentence.codeUnits})',
      () {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(text: sentence),
          ),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'rejects wrong kind and language while accepting only exact response tags',
    () {
      for (final kind in [ContentKind.story, ContentKind.explanation]) {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(kind: kind),
          ),
          throwsFormatException,
        );
      }
      for (final language in ['th', '', 'EN', ' en ']) {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(language: language),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('applies independent sentence rune and UTF8 byte bounds', () {
    final byteHeavy = '${'—' * 700} A cat sleeps.';
    expect(byteHeavy.runes.length, lessThan(ClozeContent.maxSentenceRunes));
    expect(
      utf8.encode(byteHeavy).length,
      greaterThan(ClozeContent.maxSentenceUtf8Bytes),
    );
    expect(
      () => ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(text: byteHeavy),
      ),
      throwsFormatException,
    );
    final runeHeavy = '${'a' * ClozeContent.maxSentenceRunes} cat.';
    expect(
      () => ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(text: runeHeavy),
      ),
      throwsFormatException,
    );
    final atLimit = 'A cat ${'a' * (ClozeContent.maxSentenceRunes - 6)}';
    expect(atLimit.runes.length, ClozeContent.maxSentenceRunes);
    expect(
      ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(text: atLimit),
      ).sentence,
      atLimit,
    );
  });

  test(
    'model version is nonempty bounded metadata with no controls or markup',
    () {
      for (final version in [
        '',
        ' ',
        'm' * (ClozeContent.maxModelVersionRunes + 1),
        '界' * 100,
        'm\nv1',
        '<model>',
        '\u202emodel',
      ]) {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(modelVersion: version),
          ),
          throwsFormatException,
        );
      }
      final content = ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(modelVersion: '  synthetic-v1  '),
      );
      expect(content.modelVersion, 'synthetic-v1');
    },
  );

  test('rejection does not expose source content in the failure message', () {
    const source = 'synthetic-private-invalid-source';
    try {
      ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(text: source),
      );
      fail('An absent target must reject');
    } on FormatException catch (error) {
      expect(error.message, isNot(contains(source)));
      expect(error.source, isNull);
    }
  });
}

ContentResponse _response({
  String text = 'The cat sleeps.',
  ContentKind kind = ContentKind.sentence,
  CefrLevel cefr = CefrLevel.a2,
  String language = 'en',
  String modelVersion = 'synthetic-cloze-model-v1',
  bool cached = false,
}) => ContentResponse(
  text: text,
  kind: kind,
  cefr: cefr,
  language: language,
  modelVersion: modelVersion,
  cached: cached,
);
