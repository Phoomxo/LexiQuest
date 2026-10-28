import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';

// Synthetic contract fixtures only; these are not a validated instrument.
const canonicalFixtureJson =
    '{"instrumentId":"fixture","instrumentVersion":"1","formId":"form",'
    '"formVersion":"1","itemCatalogVersion":"1","items":['
    '{"id":"b","timepoint":"baseline",'
    '"prompts":{"th":"TH baseline","en":"EN baseline"},"options":['
    '{"code":"low","ordinalValue":0,"labels":{"th":"TH low","en":"EN low"}},'
    '{"code":"high","ordinalValue":100,"labels":{"th":"TH high","en":"EN high"}}],'
    '"reverseScored":false},'
    '{"id":"p","timepoint":"post",'
    '"prompts":{"th":"TH post","en":"EN post"},"options":['
    '{"code":"low","ordinalValue":0,"labels":{"th":"TH low","en":"EN low"}},'
    '{"code":"high","ordinalValue":100,"labels":{"th":"TH high","en":"EN high"}}],'
    '"reverseScored":true}]}';

// Independently calculated with .NET SHA256 over the UTF-8 literal above.
const canonicalFixtureChecksum =
    'b173460cb4300e2abee01bda39ce5cb8c8e911153e8f611b25517cafff0f72cb';

Map<String, Object?> jsonFixture() =>
    jsonDecode(canonicalFixtureJson) as Map<String, Object?>;

List<Object?> jsonItems(Map<String, Object?> json) =>
    json['items'] as List<Object?>;
Map<String, Object?> jsonItem(Map<String, Object?> json, [int index = 0]) =>
    jsonItems(json)[index] as Map<String, Object?>;
List<Object?> jsonOptions(Map<String, Object?> json) =>
    jsonItem(json)['options'] as List<Object?>;
Map<String, Object?> jsonOption(Map<String, Object?> json, [int index = 0]) =>
    jsonOptions(json)[index] as Map<String, Object?>;

Object? reverseMapKeys(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final key in value.keys.toList().reversed)
        key: reverseMapKeys(value[key]),
    };
  }
  if (value is List<Object?>) return value.map(reverseMapKeys).toList();
  return value;
}

MotivationResponseOption option(
  String code,
  int ordinal, {
  Map<String, String>? labels,
}) => MotivationResponseOption(
  code: code,
  ordinalValue: ordinal,
  labels: labels ?? {'th': 'ตัวเลือก $code', 'en': 'Fixture $code'},
);

MotivationItem fixtureItem(
  String id,
  MotivationTimepoint timepoint, {
  List<MotivationResponseOption>? options,
  Map<String, String>? prompts,
  bool reverseScored = false,
}) => MotivationItem(
  id: id,
  timepoint: timepoint,
  prompts: prompts ?? {'th': 'คำถามทดสอบ $id', 'en': 'Fixture prompt $id'},
  options:
      options ?? [option('low', 10), option('mid', 30), option('high', 50)],
  reverseScored: reverseScored,
);

MotivationInstrument fixture({
  String instrumentId = 'motivation.fixture',
  String instrumentVersion = '1.0',
  String formId = 'form:fixture',
  String formVersion = '1',
  String itemCatalogVersion = 'catalog-1',
  List<MotivationItem>? items,
}) => MotivationInstrument(
  instrumentId: instrumentId,
  instrumentVersion: instrumentVersion,
  formId: formId,
  formVersion: formVersion,
  itemCatalogVersion: itemCatalogVersion,
  items:
      items ??
      [
        fixtureItem('b1', MotivationTimepoint.baseline),
        fixtureItem('p1', MotivationTimepoint.post),
      ],
);

void main() {
  group('immutable value objects', () {
    test('response option freezes labels immediately', () {
      final labels = {'th': 'น้อย', 'en': 'Low'};
      final value = option('low', 0, labels: labels);
      labels['en'] = 'Changed';
      expect(value.labels['en'], 'Low');
      expect(() => value.labels['en'] = 'Changed', throwsUnsupportedError);
      expect(value.code, 'low');
      expect(value.ordinalValue, 0);
    });

    test('item freezes prompts and options immediately', () {
      final prompts = {'th': 'คำถามทดสอบ', 'en': 'Fixture prompt'};
      final options = [option('low', 0), option('high', 100)];
      final value = fixtureItem(
        'b1',
        MotivationTimepoint.baseline,
        prompts: prompts,
        options: options,
      );
      prompts['en'] = 'Changed';
      options.clear();
      expect(value.prompts['en'], 'Fixture prompt');
      expect(value.options, hasLength(2));
      expect(value.reverseScored, isFalse);
      expect(() => value.prompts.clear(), throwsUnsupportedError);
      expect(() => value.options.clear(), throwsUnsupportedError);
    });

    test('instrument freezes items and exposes immutable selections', () {
      final items = [
        fixtureItem('b1', MotivationTimepoint.baseline),
        fixtureItem('p1', MotivationTimepoint.post),
      ];
      final value = fixture(items: items);
      items.clear();
      expect(value.items, hasLength(2));
      expect(() => value.items.clear(), throwsUnsupportedError);
      final selected = value.itemsAt(MotivationTimepoint.baseline);
      expect(selected.map((item) => item.id), ['b1']);
      expect(() => selected.clear(), throwsUnsupportedError);
      expect(value.item('p1').timepoint, MotivationTimepoint.post);
      expect(value.response('b1', 'mid').ordinalValue, 30);
    });
  });

  group('constructor validation', () {
    final invalidIds = [
      '',
      ' ',
      ' leading',
      'trailing ',
      'has space',
      'slash/id',
      'ไทย',
      'é',
      'line\n',
      'nul\u0000',
      'x' * 129,
    ];
    for (final id in invalidIds) {
      test('rejects noncanonical identifiers ${invalidIds.indexOf(id)}', () {
        expect(() => option(id, 0), throwsFormatException);
        expect(
          () => fixtureItem(id, MotivationTimepoint.baseline),
          throwsFormatException,
        );
        expect(() => fixture(instrumentId: id), throwsFormatException);
        expect(() => fixture(instrumentVersion: id), throwsFormatException);
        expect(() => fixture(formId: id), throwsFormatException);
        expect(() => fixture(formVersion: id), throwsFormatException);
        expect(() => fixture(itemCatalogVersion: id), throwsFormatException);
      });
    }

    test('accepts the identifier alphabet and 128-character boundary', () {
      final id = 'Az09_.:-${'x' * 120}';
      expect(fixture(instrumentId: id).instrumentId, id);
      expect(option(id, 100).code, id);
      expect(fixtureItem(id, MotivationTimepoint.baseline).id, id);
    });

    final invalidLocales = <Map<String, String>>[
      {},
      {'en': 'Fixture'},
      {'th': 'ทดสอบ'},
      {'th': 'ทดสอบ', 'en': 'Fixture', 'fr': 'Fixture'},
      {'TH': 'ทดสอบ', 'en': 'Fixture'},
      for (final value in [
        '',
        ' ',
        ' leading',
        'trailing ',
        '\u00a0text',
        'text\u00a0',
        'a\u0000b',
        'a\nb',
        'a\rb',
        'a\tb',
        'a\u007fb',
        'a\u0085b',
        'a\u009fb',
        'x' * 1001,
        '😀' * 1001,
      ]) ...[
        {'th': 'ทดสอบ', 'en': value},
        {'th': value, 'en': 'Fixture'},
      ],
    ];
    for (var index = 0; index < invalidLocales.length; index++) {
      test('rejects invalid localized text $index', () {
        expect(
          () => option('low', 0, labels: invalidLocales[index]),
          throwsFormatException,
        );
        expect(
          () => fixtureItem(
            'b1',
            MotivationTimepoint.baseline,
            prompts: invalidLocales[index],
          ),
          throwsFormatException,
        );
      });
    }

    test('localized text counts Unicode runes, not UTF-16 code units', () {
      final labels = {'th': '😀' * 1000, 'en': 'x' * 1000};
      expect(option('low', 0, labels: labels).labels, labels);
      expect(
        fixtureItem(
          'b1',
          MotivationTimepoint.baseline,
          prompts: labels,
        ).prompts,
        labels,
      );
    });

    test('rejects ordinals outside 0..100', () {
      for (final ordinal in [-1, 101]) {
        expect(() => option('low', ordinal), throwsFormatException);
      }
    });

    test(
      'requires 2..10 options with unique codes and increasing ordinals',
      () {
        final invalid = <List<MotivationResponseOption>>[
          [],
          [option('only', 0)],
          List.generate(11, (i) => option('o$i', i)),
          [option('same', 0), option('same', 100)],
          [option('first', 10), option('second', 10)],
          [option('first', 100), option('second', 0)],
          [option('a', 0), option('b', 60), option('c', 50)],
        ];
        for (final options in invalid) {
          expect(
            () => fixtureItem(
              'b1',
              MotivationTimepoint.baseline,
              options: options,
            ),
            throwsFormatException,
          );
        }
        expect(
          fixtureItem(
            'b1',
            MotivationTimepoint.baseline,
            options: List.generate(10, (i) => option('o$i', i)),
          ).options,
          hasLength(10),
        );
      },
    );

    test('requires 1..32 items independently for both timepoints', () {
      for (final items in <List<MotivationItem>>[
        [],
        [fixtureItem('b1', MotivationTimepoint.baseline)],
        [fixtureItem('p1', MotivationTimepoint.post)],
        for (final point in MotivationTimepoint.values)
          [
            ...List.generate(33, (i) => fixtureItem('i$i', point)),
            fixtureItem(
              'other',
              point == MotivationTimepoint.baseline
                  ? MotivationTimepoint.post
                  : MotivationTimepoint.baseline,
            ),
          ],
      ]) {
        expect(() => fixture(items: items), throwsFormatException);
      }
      final maximum = fixture(
        items: [
          for (final point in MotivationTimepoint.values)
            ...List.generate(32, (i) => fixtureItem('${point.name}$i', point)),
        ],
      );
      expect(maximum.items, hasLength(64));
      expect(maximum.itemsAt(MotivationTimepoint.post), hasLength(32));
    });

    test('item IDs are globally unique, including across timepoints', () {
      expect(
        () => fixture(
          items: [
            fixtureItem('same', MotivationTimepoint.baseline),
            fixtureItem('same', MotivationTimepoint.post),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => fixture(
          items: [
            fixtureItem('b1', MotivationTimepoint.baseline),
            fixtureItem('b1', MotivationTimepoint.baseline),
            fixtureItem('p1', MotivationTimepoint.post),
          ],
        ),
        throwsFormatException,
      );
    });

    test('lookups reject unknown or malformed IDs and codes', () {
      final value = fixture();
      for (final id in ['unknown', '', ' b1']) {
        expect(() => value.item(id), throwsFormatException);
        expect(() => value.response(id, 'low'), throwsFormatException);
      }
      for (final code in ['unknown', '', ' low']) {
        expect(() => value.response('b1', code), throwsFormatException);
      }
    });
  });

  group('normalized scoring', () {
    MotivationInstrument scoringFixture() => fixture(
      items: [
        fixtureItem(
          'b1',
          MotivationTimepoint.baseline,
          options: [option('low', 5), option('mid', 15), option('high', 45)],
        ),
        fixtureItem(
          'b2',
          MotivationTimepoint.baseline,
          reverseScored: true,
          options: [option('low', 40), option('mid', 70), option('high', 100)],
        ),
        fixtureItem('p1', MotivationTimepoint.post),
      ],
    );

    test('missing any selected item returns null, including an empty form', () {
      final value = scoringFixture();
      for (final codes in <Map<String, String>>[
        {},
        {'b1': 'low'},
        {'b2': 'high'},
        {'p1': 'high'},
      ]) {
        expect(
          value.normalizedScore(MotivationTimepoint.baseline, codes),
          isNull,
        );
      }
      expect(
        value.normalizedScore(MotivationTimepoint.post, {'b1': 'low'}),
        isNull,
      );
    });

    test(
      'complete extremes are exactly zero and one hundred with reversal',
      () {
        final value = scoringFixture();
        expect(
          value.normalizedScore(MotivationTimepoint.baseline, {
            'b1': 'low',
            'b2': 'high',
          }),
          0.0,
        );
        expect(
          value.normalizedScore(MotivationTimepoint.baseline, {
            'b1': 'high',
            'b2': 'low',
          }),
          100.0,
        );
        expect(
          value.normalizedScore(MotivationTimepoint.post, {'p1': 'low'}),
          0.0,
        );
        expect(
          value.normalizedScore(MotivationTimepoint.post, {'p1': 'high'}),
          100.0,
        );
      },
    );

    test('midpoint is fifty for a complete single-item form', () {
      expect(
        fixture().normalizedScore(MotivationTimepoint.post, {'p1': 'mid'}),
        50.0,
      );
    });

    test('normalizes each unequal range before averaging and reversing', () {
      final value = scoringFixture();
      expect(
        value.normalizedScore(MotivationTimepoint.baseline, {
          'b1': 'mid',
          'b2': 'mid',
        }),
        37.5,
      );
      expect(
        value.normalizedScore(MotivationTimepoint.baseline, {
          'b1': 'mid',
          'b2': 'low',
        }),
        62.5,
      );
    });

    test('valid opposite-timepoint responses are ignored', () {
      final value = scoringFixture();
      final codes = {'p1': 'low', 'b2': 'low', 'b1': 'high'};
      expect(value.normalizedScore(MotivationTimepoint.baseline, codes), 100.0);
      expect(value.normalizedScore(MotivationTimepoint.post, codes), 0.0);
      expect(codes, {'p1': 'low', 'b2': 'low', 'b1': 'high'});
    });

    test('validates every response before returning null or a score', () {
      final value = scoringFixture();
      for (final codes in <Map<String, String>>[
        {'unknown': 'low'},
        {'': 'low'},
        {' b1': 'low'},
        {'b1': 'unknown'},
        {'b1': ''},
        {'b1': ' low'},
        {'p1': 'unknown'},
        {'b1': 'high', 'b2': 'low', 'p1': 'unknown'},
        {'b1': 'high', 'b2': 'low', 'unknown': 'low'},
      ]) {
        for (final point in MotivationTimepoint.values) {
          expect(
            () => value.normalizedScore(point, codes),
            throwsFormatException,
          );
        }
      }
    });

    test('a response code belongs to its own item', () {
      final value = fixture(
        items: [
          fixtureItem('b1', MotivationTimepoint.baseline),
          fixtureItem(
            'p1',
            MotivationTimepoint.post,
            options: [option('no', 0), option('yes', 100)],
          ),
        ],
      );
      expect(
        () => value.normalizedScore(MotivationTimepoint.post, {'p1': 'high'}),
        throwsFormatException,
      );
      expect(
        () => value.normalizedScore(MotivationTimepoint.post, {
          'p1': 'yes',
          'b1': 'yes',
        }),
        throwsFormatException,
      );
    });
  });

  group('strict JSON decoding', () {
    final objects =
        <String, Map<String, Object?> Function(Map<String, Object?>)>{
          'instrument': (json) => json,
          'item': jsonItem,
          'option': jsonOption,
          'prompts': (json) =>
              jsonItem(json)['prompts'] as Map<String, Object?>,
          'labels': (json) =>
              jsonOption(json)['labels'] as Map<String, Object?>,
        };
    for (final entry in objects.entries) {
      test(
        '${entry.key} rejects every missing key and unknown/free-text keys',
        () {
          for (final key in entry.value(jsonFixture()).keys) {
            final json = jsonFixture();
            entry.value(json).remove(key);
            expect(
              () => MotivationInstrument.fromJson(json),
              throwsFormatException,
              reason: 'Missing ${entry.key}.$key',
            );
          }
          for (final key in ['unknown', 'freeText', '', ' en']) {
            final json = jsonFixture();
            entry.value(json)[key] = 'unstructured response';
            expect(
              () => MotivationInstrument.fromJson(json),
              throwsFormatException,
              reason: 'Unknown ${entry.key}.$key',
            );
          }
        },
      );
    }

    test('all string fields reject non-strings and noncanonical values', () {
      for (final field in [
        'instrumentId',
        'instrumentVersion',
        'formId',
        'formVersion',
        'itemCatalogVersion',
        'id',
        'code',
      ]) {
        for (final invalid in <Object?>[
          null,
          1,
          true,
          [],
          {},
          '',
          'bad value',
        ]) {
          final json = jsonFixture();
          final target = field == 'id'
              ? jsonItem(json)
              : field == 'code'
              ? jsonOption(json)
              : json;
          target[field] = invalid;
          expect(
            () => MotivationInstrument.fromJson(json),
            throwsFormatException,
            reason: '$field = $invalid',
          );
        }
      }
    });

    test('timepoint must be an exact known string', () {
      for (final invalid in <Object?>[
        null,
        0,
        false,
        {},
        [],
        'Baseline',
        'pre',
        'POST',
        'post ',
        '',
      ]) {
        final json = jsonFixture();
        jsonItem(json)['timepoint'] = invalid;
        expect(
          () => MotivationInstrument.fromJson(json),
          throwsFormatException,
        );
      }
    });

    test('ordinalValue requires an integer in range, never a coercion', () {
      for (final invalid in <Object?>[
        null,
        true,
        '0',
        0.0,
        double.nan,
        double.infinity,
        [],
        {},
        -1,
        101,
      ]) {
        final json = jsonFixture();
        jsonOption(json)['ordinalValue'] = invalid;
        expect(
          () => MotivationInstrument.fromJson(json),
          throwsFormatException,
        );
      }
    });

    test('reverseScored requires a boolean', () {
      for (final invalid in <Object?>[null, 0, 1, 'false', [], {}]) {
        final json = jsonFixture();
        jsonItem(json)['reverseScored'] = invalid;
        expect(
          () => MotivationInstrument.fromJson(json),
          throwsFormatException,
        );
      }
    });

    test('arrays require bounded lists of objects with string keys', () {
      for (final field in ['items', 'options']) {
        for (final invalid in <Object?>[
          null,
          0,
          true,
          '[]',
          {},
          <Object?>{},
          [],
          [null],
          [1],
          ['value'],
          [[]],
          [
            {1: 'value'},
          ],
        ]) {
          final json = jsonFixture();
          (field == 'items' ? json : jsonItem(json))[field] = invalid;
          expect(
            () => MotivationInstrument.fromJson(json),
            throwsFormatException,
          );
        }
      }
    });

    test('localized maps reject malformed keys, types, locales, and text', () {
      for (final field in ['prompts', 'labels']) {
        for (final invalid in <Object?>[
          null,
          1,
          true,
          'text',
          [],
          {1: 'text', 'en': 'English'},
          {'th': 'TH', 'en': null},
          {'th': 1, 'en': 'English'},
          {'th': 'TH', 'en': false},
          {'th': 'TH', 'en': []},
          {'th': {}, 'en': 'English'},
          {'th': 'TH', 'en': ' leading'},
          {'th': 'TH', 'en': 'a\nb'},
          {'th': 'TH', 'en': 'x' * 1001},
        ]) {
          final json = jsonFixture();
          (field == 'prompts' ? jsonItem(json) : jsonOption(json))[field] =
              invalid;
          expect(
            () => MotivationInstrument.fromJson(json),
            throwsFormatException,
          );
        }
      }
    });

    test('malformed array elements are rejected after valid length checks', () {
      for (final field in ['items', 'options']) {
        for (final invalid in <Object?>[
          null,
          1,
          'value',
          [],
          {1: 'value'},
        ]) {
          final json = jsonFixture();
          final target = field == 'items' ? json : jsonItem(json);
          final values = List<Object?>.from(target[field] as List);
          values[0] = invalid;
          target[field] = values;
          expect(
            () => MotivationInstrument.fromJson(json),
            throwsFormatException,
          );
        }
      }
    });

    test('JSON cannot bypass duplicate, order, or timepoint bounds', () {
      final changes = <void Function(Map<String, Object?>)>[
        (json) => jsonItem(json, 1)['id'] = 'b',
        (json) => jsonOption(json, 1)['code'] = 'low',
        (json) => jsonOption(json, 1)['ordinalValue'] = 0,
        (json) =>
            jsonItem(json)['options'] = jsonOptions(json).reversed.toList(),
        (json) => jsonItem(json, 1)['timepoint'] = 'baseline',
        (json) => jsonItem(json)['options'] = [jsonOption(json)],
        (json) => json['items'] = [jsonItem(json)],
        (json) => jsonItem(json)['options'] = List.generate(
          11,
          (i) => {
            'code': 'o$i',
            'ordinalValue': i,
            'labels': {'th': 'TH', 'en': 'EN'},
          },
        ),
        (json) => json['items'] = [
          for (var i = 0; i < 33; i++) {...jsonItem(json), 'id': 'b$i'},
          jsonItem(json, 1),
        ],
      ];
      for (final change in changes) {
        final json = jsonFixture();
        change(json);
        expect(
          () => MotivationInstrument.fromJson(json),
          throwsFormatException,
        );
      }
    });
  });

  group('canonical serialization', () {
    test('canonical JSON and SHA-256 match an independent fixed vector', () {
      final value = MotivationInstrument.fromJson(jsonFixture());
      expect(jsonEncode(value.toJson()), canonicalFixtureJson);
      expect(value.checksumSha256, canonicalFixtureChecksum);
      expect(
        value.normalizedScore(MotivationTimepoint.post, {'p': 'low'}),
        100.0,
      );
    });

    test(
      'all nested map insertion orders produce identical bytes and hashes',
      () {
        final reordered = reverseMapKeys(jsonFixture()) as Map<String, Object?>;
        final value = MotivationInstrument.fromJson(
          reordered,
          expectedChecksumSha256: canonicalFixtureChecksum,
        );
        expect(jsonEncode(value.toJson()), canonicalFixtureJson);
        expect(value.checksumSha256, canonicalFixtureChecksum);
      },
    );

    test(
      'constructor inputs and JSON round-trip to the same complete graph',
      () {
        final original = fixture();
        final encoded = original.toJson();
        final restored = MotivationInstrument.fromJson(
          jsonDecode(jsonEncode(encoded)) as Map<String, Object?>,
          expectedChecksumSha256: original.checksumSha256,
        );
        expect(restored.toJson(), encoded);
        expect(restored.checksumSha256, original.checksumSha256);
        expect(restored.response('b1', 'mid').labels['th'], 'ตัวเลือก mid');
      },
    );

    test('JSON input is detached at every nested level', () {
      final json = jsonFixture();
      final value = MotivationInstrument.fromJson(json);
      final item = jsonItem(json);
      final option = jsonOption(json);
      (item['prompts'] as Map<String, Object?>)['en'] = 'Changed';
      (option['labels'] as Map<String, Object?>)['en'] = 'Changed';
      option['ordinalValue'] = 25;
      jsonOptions(json).clear();
      item['id'] = 'changed';
      jsonItems(json).clear();
      json.clear();
      expect(jsonEncode(value.toJson()), canonicalFixtureJson);
      expect(value.checksumSha256, canonicalFixtureChecksum);
    });

    test('mutating exported JSON never changes the instrument or checksum', () {
      final value = MotivationInstrument.fromJson(jsonFixture());
      final json = value.toJson();
      (jsonItem(json)['prompts'] as Map<String, Object?>)['th'] = 'Changed';
      (jsonOption(json)['labels'] as Map<String, Object?>)['en'] = 'Changed';
      jsonOption(json)['code'] = 'changed';
      jsonOptions(json).clear();
      jsonItems(json).clear();
      json['instrumentVersion'] = 'changed';
      expect(jsonEncode(value.toJson()), canonicalFixtureJson);
      expect(value.checksumSha256, canonicalFixtureChecksum);
    });

    test('item and option order are preserved without sorting', () {
      final json = jsonFixture();
      json['items'] = jsonItems(json).reversed.toList();
      final value = MotivationInstrument.fromJson(json);
      expect(value.items.map((item) => item.id), ['p', 'b']);
      expect(
        jsonItems(
          value.toJson(),
        ).map((item) => (item as Map<String, Object?>)['id']),
        ['p', 'b'],
      );
      expect(value.item('b').options.map((option) => option.code), [
        'low',
        'high',
      ]);
      expect(value.checksumSha256, isNot(canonicalFixtureChecksum));
      final reversedOptions = jsonFixture();
      jsonItem(reversedOptions)['options'] = jsonOptions(
        reversedOptions,
      ).reversed.toList();
      expect(
        () => MotivationInstrument.fromJson(reversedOptions),
        throwsFormatException,
      );
    });

    final changes = <String, void Function(Map<String, Object?>)>{
      for (final field in [
        'instrumentId',
        'instrumentVersion',
        'formId',
        'formVersion',
        'itemCatalogVersion',
      ])
        field: (json) => json[field] = 'changed',
      'item ID': (json) => jsonItem(json)['id'] = 'changed',
      'timepoints': (json) {
        jsonItem(json)['timepoint'] = 'post';
        jsonItem(json, 1)['timepoint'] = 'baseline';
      },
      'reverse scoring': (json) => jsonItem(json)['reverseScored'] = true,
      'option code': (json) => jsonOption(json)['code'] = 'changed',
      'option ordinal': (json) => jsonOption(json)['ordinalValue'] = 1,
      for (final locale in ['th', 'en']) ...{
        'prompt $locale': (json) =>
            (jsonItem(json)['prompts'] as Map<String, Object?>)[locale] =
                'Changed',
        'label $locale': (json) =>
            (jsonOption(json)['labels'] as Map<String, Object?>)[locale] =
                'Changed',
      },
    };
    for (final entry in changes.entries) {
      test('checksum includes ${entry.key} and rejects content mismatch', () {
        final json = jsonFixture();
        entry.value(json);
        expect(
          MotivationInstrument.fromJson(json).checksumSha256,
          isNot(canonicalFixtureChecksum),
        );
        expect(
          () => MotivationInstrument.fromJson(
            json,
            expectedChecksumSha256: canonicalFixtureChecksum,
          ),
          throwsFormatException,
        );
      });
    }

    test('malformed or incorrect expected checksums are rejected', () {
      for (final checksum in [
        '',
        'x' * 64,
        '0' * 64,
        canonicalFixtureChecksum.toUpperCase(),
        ' $canonicalFixtureChecksum',
      ]) {
        expect(
          () => MotivationInstrument.fromJson(
            jsonFixture(),
            expectedChecksumSha256: checksum,
          ),
          throwsFormatException,
        );
      }
    });
  });
}
