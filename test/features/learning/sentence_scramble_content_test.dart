import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/sentence_scramble_content.dart';

ContentResponse response(
  String text, {
  ContentKind kind = ContentKind.sentence,
  CefrLevel cefr = CefrLevel.unknown,
  String language = 'en',
  String modelVersion = 'synthetic-model/r7',
  bool cached = false,
}) => ContentResponse(
  text: text,
  kind: kind,
  cefr: cefr,
  language: language,
  modelVersion: modelVersion,
  cached: cached,
);

SentenceScrambleContent parse(String text, {String target = 'school'}) =>
    SentenceScrambleContent.parse(
      targetSpelling: target,
      response: response(text),
    );

void main() {
  test('real metadata and spaced punctuation remain indexed pieces', () {
    final content = SentenceScrambleContent.parse(
      targetSpelling: 'school',
      response: response(
        'school — a place to learn.',
        cefr: CefrLevel.b1,
        cached: true,
      ),
    );
    expect(content.sentence, 'school — a place to learn.');
    expect(content.targetSpelling, 'school');
    expect(content.tokens, ['school', '—', 'a', 'place', 'to', 'learn.']);
    expect(content.kind, ContentKind.sentence);
    expect(content.cefr, CefrLevel.b1);
    expect(content.language, 'en');
    expect(content.modelVersion, 'synthetic-model/r7');
    expect(content.cached, isTrue);
    expect(content.tokenOrder.toSet(), {0, 1, 2, 3, 4, 5});
    expect(
      content.tokenOrder.map((index) => content.tokens[index]).join(' '),
      isNot(content.sentence),
    );
    expect(() => content.tokens[0] = 'changed', throwsUnsupportedError);
    expect(() => content.tokenOrder.add(6), throwsUnsupportedError);
  });

  for (final separator in [
    0x09,
    0x0a,
    0x0b,
    0x0c,
    0x0d,
    0x20,
    0x85,
    0xa0,
    0x1680,
    for (var rune = 0x2000; rune <= 0x200a; rune++) rune,
    0x2028,
    0x2029,
    0x202f,
    0x205f,
    0x3000,
  ]) {
    test(
      'Unicode White_Space ${separator.toRadixString(16)} normalizes once',
      () {
        final space = String.fromCharCode(separator);
        final content = parse(
          '${space}school$space${space}feels${space}calm.$space',
        );
        expect(content.sentence, 'school feels calm.');
        expect(content.matchesResponse('school${space}feels calm.'), isTrue);
        expect(content.tokens, ['school', 'feels', 'calm.']);
      },
    );
  }

  test('repeated anchor chunks stay distinct and keep a stable bank', () {
    final first = parse('school is school.');
    final second = parse('school is school.');
    expect(first.tokens, ['school', 'is', 'school.']);
    expect(first.tokenOrder.toSet(), {0, 1, 2});
    expect(first.tokenOrder, second.tokenOrder);
    final repeated = parse('school school feels calm.');
    expect(
      repeated.tokenOrder.where((index) => repeated.tokens[index] == 'school'),
      hasLength(2),
    );
    expect(repeated.matchesResponse('school school feels calm.'), isTrue);
  });

  test(
    'case punctuation apostrophes hyphens and combining marks stay exact',
    () {
      final content = parse("school cafe\u0301 isn't closed — well-known.");
      expect(content.tokens, [
        'school',
        'cafe\u0301',
        "isn't",
        'closed',
        '—',
        'well-known.',
      ]);
      expect(
        content.matchesResponse("school cafe\u0301 isn't closed — well-known."),
        isTrue,
      );
      expect(
        content.matchesResponse("School cafe\u0301 isn't closed — well-known."),
        isFalse,
      );
      expect(
        content.matchesResponse("school café isn't closed — well-known."),
        isFalse,
      );
      expect(
        content.matchesResponse("school cafe\u0301 isn't closed well-known."),
        isFalse,
      );
      expect(
        parse("Please don't stop.", target: "don't").targetSpelling,
        "don't",
      );
      expect(
        parse('Please check-in here.', target: 'check-in').targetSpelling,
        'check-in',
      );
    },
  );

  for (final text in [
    '',
    'school',
    'school .',
    'school ☕',
    'school school',
    'preschool feels calm.',
    'schools feel calm.',
    "school's gates open.",
    'éschool feels calm.',
    'schoolé feels calm.',
    'different anchor here.',
  ]) {
    test('unplayable or unbound sentence rejects ${jsonEncode(text)}', () {
      expect(() => parse(text), throwsFormatException);
    });
  }

  test('whole anchor can be quoted and repeated without a gap rule', () {
    expect(parse("'school' is school.").tokens, ["'school'", 'is', 'school.']);
    expect(parse('“school” feels calm.').tokens, [
      '“school”',
      'feels',
      'calm.',
    ]);
  });

  for (final rune in [
    0x00,
    0x08,
    0x7f,
    0x80,
    0xad,
    0x34f,
    0x61c,
    0x180e,
    0x200b,
    0x200c,
    0x200d,
    0x200e,
    0x200f,
    0x202a,
    0x202e,
    0x2060,
    0x206f,
    0xd800,
    0xdfff,
    0xfeff,
    0xfff9,
    0xfffb,
  ]) {
    test(
      'control or format ${rune.toRadixString(16)} fails for content and typed input',
      () {
        final invalid = 'school ${String.fromCharCode(rune)}feels calm.';
        expect(() => parse(invalid), throwsFormatException);
        expect(parse('school feels calm.').matchesResponse(invalid), isFalse);
      },
    );
  }

  test('markup and invalid provider metadata never become a sentence', () {
    for (final text in [
      '<p>school feels calm.</p>',
      'school *feels* calm.',
      'school _feels_ calm.',
      'school [feels] calm.',
      'school {feels} calm.',
      '# school feels calm.',
      'school `feels` calm.',
    ]) {
      expect(() => parse(text), throwsFormatException, reason: text);
    }
    for (final invalid in [
      response('school feels calm.', kind: ContentKind.story),
      response('school feels calm.', language: 'th'),
      response('school feels calm.', modelVersion: ''),
      response('school feels calm.', modelVersion: '<untrusted>'),
      response('school feels calm.', modelVersion: 'model\nversion'),
      response('school feels calm.', modelVersion: 'm' * 257),
      response('school feels calm.', modelVersion: 'ก' * 86),
    ]) {
      expect(
        () => SentenceScrambleContent.parse(
          targetSpelling: 'school',
          response: invalid,
        ),
        throwsFormatException,
      );
    }
    expect(
      SentenceScrambleContent.parse(
        targetSpelling: 'school',
        response: response('school feels calm.', modelVersion: 'm' * 256),
      ).modelVersion,
      'm' * 256,
    );
  });

  test(
    'raw bounds precede whitespace collapse and allow their exact UTF8 boundary',
    () {
      final maxBytes = 'school ${'é' * 1013}${'😀' * 3}漢';
      expect(maxBytes.runes.length, 1024);
      expect(utf8.encode(maxBytes), hasLength(2048));
      expect(parse(maxBytes).matchesResponse(maxBytes), isTrue);
      expect(
        () => parse('school ${'é' * 1013}${'😀' * 4}'),
        throwsFormatException,
      );
      expect(() => parse('school ${'a' * 1018}'), throwsFormatException);
      final collapsible = 'school${' ' * 1024}word';
      expect(() => parse(collapsible), throwsFormatException);
      expect(parse('school word').matchesResponse(collapsible), isFalse);
    },
  );

  test('chunk limits count punctuation but need two lexical chunks', () {
    expect(
      parse('school ${List.filled(63, 'word').join(' ')}').tokens,
      hasLength(64),
    );
    expect(
      () => parse('school ${List.filled(64, 'word').join(' ')}'),
      throwsFormatException,
    );
    expect(parse('school — school').tokens, ['school', '—', 'school']);
  });

  test('seed target keeps conservative lexical support and original case', () {
    for (final seed in ['', 'two words', 'café', 'a' * 121, 'word_']) {
      expect(SentenceScrambleContent.supportsTarget(seed), isFalse);
      expect(
        () => parse('school feels calm.', target: seed),
        throwsFormatException,
      );
    }
    expect(
      parse('School feels calm.', target: 'School').targetSpelling,
      'School',
    );
  });
}
