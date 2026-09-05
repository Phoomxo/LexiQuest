import 'dart:convert';

import 'package:crypto/crypto.dart';

enum MotivationTimepoint { baseline, post }

/// A coded response with immutable Thai and English labels.
final class MotivationResponseOption {
  MotivationResponseOption({
    required this.code,
    required this.ordinalValue,
    required Map<String, String> labels,
  }) : labels = _localizedText(labels, 'labels') {
    _identifier(code, 'code');
    if (ordinalValue < 0 || ordinalValue > 100) {
      throw const FormatException('ordinalValue must be in 0..100');
    }
  }

  final String code;
  final int ordinalValue;
  final Map<String, String> labels;
}

/// One immutable item; option order must follow strictly increasing ordinals.
final class MotivationItem {
  MotivationItem({
    required this.id,
    required this.timepoint,
    required Map<String, String> prompts,
    required List<MotivationResponseOption> options,
    this.reverseScored = false,
  }) : prompts = _localizedText(prompts, 'prompts'),
       options = List.unmodifiable(options) {
    _identifier(id, 'id');
    if (this.options.length < 2 || this.options.length > 10) {
      throw const FormatException('Each item requires 2..10 options');
    }
    final codes = <String>{};
    var previous = -1;
    for (final option in this.options) {
      if (!codes.add(option.code) || option.ordinalValue <= previous) {
        throw const FormatException(
          'Options require unique codes and strictly increasing ordinals',
        );
      }
      previous = option.ordinalValue;
    }
  }

  final String id;
  final MotivationTimepoint timepoint;
  final Map<String, String> prompts;
  final List<MotivationResponseOption> options;
  final bool reverseScored;
}

/// A versioned, immutable instrument definition, without built-in item wording.
///
/// This contract does not establish an instrument's psychometric validity.
final class MotivationInstrument {
  MotivationInstrument({
    required this.instrumentId,
    required this.instrumentVersion,
    required this.formId,
    required this.formVersion,
    required this.itemCatalogVersion,
    required List<MotivationItem> items,
  }) : items = List.unmodifiable(items) {
    _identifier(instrumentId, 'instrumentId');
    _identifier(instrumentVersion, 'instrumentVersion');
    _identifier(formId, 'formId');
    _identifier(formVersion, 'formVersion');
    _identifier(itemCatalogVersion, 'itemCatalogVersion');
    final ids = <String>{};
    final counts = {for (final point in MotivationTimepoint.values) point: 0};
    for (final item in this.items) {
      if (!ids.add(item.id)) {
        throw FormatException('Duplicate item ID: ${item.id}');
      }
      counts[item.timepoint] = counts[item.timepoint]! + 1;
    }
    if (counts.values.any((count) => count < 1 || count > 32)) {
      throw const FormatException('Each timepoint requires 1..32 items');
    }
  }

  final String instrumentId;
  final String instrumentVersion;
  final String formId;
  final String formVersion;
  final String itemCatalogVersion;
  final List<MotivationItem> items;

  late final String _checksumSha256 = sha256
      .convert(utf8.encode(jsonEncode(toJson())))
      .toString();

  /// SHA-256 of UTF-8 canonical JSON, as 64 lowercase hexadecimal characters.
  String get checksumSha256 => _checksumSha256;

  /// Returns a detached graph in fixed key order, with no checksum field.
  ///
  /// Locale keys are always th then en. Item and option list order is retained.
  /// The checksum is transported separately via [expectedChecksumSha256] in
  /// [MotivationInstrument.fromJson].
  Map<String, Object?> toJson() => {
    'instrumentId': instrumentId,
    'instrumentVersion': instrumentVersion,
    'formId': formId,
    'formVersion': formVersion,
    'itemCatalogVersion': itemCatalogVersion,
    'items': [
      for (final item in items)
        <String, Object?>{
          'id': item.id,
          'timepoint': item.timepoint.name,
          'prompts': <String, Object?>{
            'th': item.prompts['th']!,
            'en': item.prompts['en']!,
          },
          'options': [
            for (final option in item.options)
              <String, Object?>{
                'code': option.code,
                'ordinalValue': option.ordinalValue,
                'labels': <String, Object?>{
                  'th': option.labels['th']!,
                  'en': option.labels['en']!,
                },
              },
          ],
          'reverseScored': item.reverseScored,
        },
    ],
  };

  /// Strictly decodes every field, then validates and freezes the entire graph.
  ///
  /// All emitted JSON fields are required, including reverseScored. Unknown
  /// fields and checksum mismatches throw [FormatException].
  factory MotivationInstrument.fromJson(
    Map<String, Object?> json, {
    String? expectedChecksumSha256,
  }) {
    final data = _jsonObject(json, const {
      'instrumentId',
      'instrumentVersion',
      'formId',
      'formVersion',
      'itemCatalogVersion',
      'items',
    }, 'instrument');
    final instrument = MotivationInstrument(
      instrumentId: _jsonValue<String>(data['instrumentId'], 'instrumentId'),
      instrumentVersion: _jsonValue<String>(
        data['instrumentVersion'],
        'instrumentVersion',
      ),
      formId: _jsonValue<String>(data['formId'], 'formId'),
      formVersion: _jsonValue<String>(data['formVersion'], 'formVersion'),
      itemCatalogVersion: _jsonValue<String>(
        data['itemCatalogVersion'],
        'itemCatalogVersion',
      ),
      items: _jsonList(
        data['items'],
        'items',
        2,
        64,
      ).map(_itemFromJson).toList(),
    );
    if (expectedChecksumSha256 != null &&
        instrument.checksumSha256 != expectedChecksumSha256) {
      throw const FormatException('Instrument checksum mismatch');
    }
    return instrument;
  }

  MotivationItem item(String itemId) => items.firstWhere(
    (item) => item.id == itemId,
    orElse: () => throw FormatException('Unknown item ID: $itemId'),
  );
  MotivationResponseOption response(String itemId, String responseCode) =>
      item(itemId).options.firstWhere(
        (option) => option.code == responseCode,
        orElse: () =>
            throw FormatException('Unknown response code: $responseCode'),
      );
  List<MotivationItem> itemsAt(MotivationTimepoint timepoint) =>
      List.unmodifiable(items.where((item) => item.timepoint == timepoint));

  /// Returns a 0..100 score, or null when a selected-timepoint item is missing.
  ///
  /// Every supplied key/code is validated first. Valid responses belonging to
  /// the other timepoint are permitted and do not contribute to this score.
  double? normalizedScore(
    MotivationTimepoint timepoint,
    Map<String, String> responseCodes,
  ) {
    // Validate even opposite-timepoint entries before checking completeness.
    final responses = <String, MotivationResponseOption>{
      for (final entry in responseCodes.entries)
        entry.key: response(entry.key, entry.value),
    };
    final selected = itemsAt(timepoint);
    var total = 0.0;
    for (final item in selected) {
      final answer = responses[item.id];
      if (answer == null) return null;
      final minimum = item.options.first.ordinalValue;
      final maximum = item.options.last.ordinalValue;
      final normalized = (answer.ordinalValue - minimum) / (maximum - minimum);
      total += item.reverseScored ? 1.0 - normalized : normalized;
    }
    return total / selected.length * 100.0;
  }
}

MotivationItem _itemFromJson(Object? value) {
  final data = _jsonObject(value, const {
    'id',
    'timepoint',
    'prompts',
    'options',
    'reverseScored',
  }, 'item');
  return MotivationItem(
    id: _jsonValue<String>(data['id'], 'id'),
    timepoint: switch (data['timepoint']) {
      'baseline' => MotivationTimepoint.baseline,
      'post' => MotivationTimepoint.post,
      _ => throw const FormatException('Unknown or malformed timepoint'),
    },
    prompts: _localizedFromJson(data['prompts'], 'prompts'),
    options: _jsonList(
      data['options'],
      'options',
      2,
      10,
    ).map(_optionFromJson).toList(),
    reverseScored: _jsonValue<bool>(data['reverseScored'], 'reverseScored'),
  );
}

MotivationResponseOption _optionFromJson(Object? value) {
  final data = _jsonObject(value, const {
    'code',
    'ordinalValue',
    'labels',
  }, 'option');
  return MotivationResponseOption(
    code: _jsonValue<String>(data['code'], 'code'),
    ordinalValue: _jsonValue<int>(data['ordinalValue'], 'ordinalValue'),
    labels: _localizedFromJson(data['labels'], 'labels'),
  );
}

Map<String, Object?> _jsonObject(
  Object? value,
  Set<String> keys,
  String field,
) {
  if (value is! Map<Object?, Object?> ||
      value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    throw FormatException(
      '$field must be an object with exactly ${keys.join(', ')}',
    );
  }
  return Map<String, Object?>.from(value);
}

T _jsonValue<T>(Object? value, String field) {
  if (value is! T) throw FormatException('$field must be a $T');
  return value;
}

List<Object?> _jsonList(Object? value, String field, int minimum, int maximum) {
  if (value is! List<Object?> ||
      value.length < minimum ||
      value.length > maximum) {
    throw FormatException(
      '$field must be a list of $minimum..$maximum entries',
    );
  }
  return value;
}

Map<String, String> _localizedFromJson(Object? value, String field) {
  final data = _jsonObject(value, const {'th', 'en'}, field);
  return {
    'th': _jsonValue<String>(data['th'], '$field.th'),
    'en': _jsonValue<String>(data['en'], '$field.en'),
  };
}

final _nonIdentifier = RegExp(r'[^A-Za-z0-9_.:\-]');

void _identifier(String value, String field) {
  if (value.isEmpty || value.length > 128 || _nonIdentifier.hasMatch(value)) {
    throw FormatException('$field must be a canonical 1..128 character ID');
  }
}

Map<String, String> _localizedText(Map<String, String> input, String field) {
  if (input.length != 2 ||
      !input.containsKey('th') ||
      !input.containsKey('en')) {
    throw FormatException('$field must contain exactly th and en');
  }
  for (final value in input.values) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.runes.length > 1000 ||
        value.runes.any(
          (rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f),
        )) {
      throw FormatException('$field contains invalid localized text');
    }
  }
  return Map.unmodifiable({'th': input['th']!, 'en': input['en']!});
}
