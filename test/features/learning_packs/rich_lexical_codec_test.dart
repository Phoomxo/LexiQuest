import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

void main() {
  const legacy =
      '{"code":"harbor","definition":null,"definitionQuestion":null,"examples":[],"hint":null,"imageId":null,"meaning":"ท่าเรือ","memoryCue":null,"partOfSpeech":"noun","spelling":"harbor","strategy":null}';
  const details = <String, Object?>{
    'schemaVersion': 1,
    'ipa': '/ˈhɑːrbər/',
    'synonyms': ['port', 'haven'],
    'antonyms': ['open sea'],
  };
  Map<String, Object?> enriched() => {
    ...jsonDecode(legacy) as Map<String, dynamic>,
    'lexicalDetails': Map<String, Object?>.from(details),
  };

  test('existing lexical bytes and digest do not gain absent enrichment', () {
    final entry = const LearningPackCodec().decodeEntry(legacy);
    expect(entry.canonicalJson, legacy);
    expect(entry.contentSha256, sha256.convert(utf8.encode(legacy)).toString());
    expect(entry.toJson().containsKey('lexicalDetails'), isFalse);
  });

  test(
    'closed versioned IPA and relation data roundtrips from authored bytes',
    () {
      final entry = const LearningPackCodec().decodeEntry(
        jsonEncode(enriched()),
      );
      expect(entry.toJson()['lexicalDetails'], details);
      final restored = const LearningPackCodec().decodeEntry(
        entry.canonicalJson,
      );
      expect(restored.canonicalJson, entry.canonicalJson);
      expect(restored.contentSha256, entry.contentSha256);
      expect(
        entry.contentSha256,
        isNot(sha256.convert(utf8.encode(legacy)).toString()),
      );
    },
  );

  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'unknown field': (map) => map['guessedDefinition'] = 'Not allowed',
    'unknown version': (map) => map['schemaVersion'] = 2,
    'noninteger version': (map) => map['schemaVersion'] = 1.0,
    'blank IPA': (map) => map['ipa'] = ' ',
    'noncanonical relation': (map) => map['synonyms'] = ['  port'],
    'duplicate relation': (map) => map['synonyms'] = ['port', 'PORT'],
    'oversized relation list': (map) =>
        map['antonyms'] = List.generate(13, (i) => 'sea $i'),
    'empty enrichment': (map) {
      map['ipa'] = null;
      map['synonyms'] = [];
      map['antonyms'] = [];
    },
  }.entries) {
    test('authored details reject ${mutation.key}', () {
      final value = enriched();
      mutation.value(value['lexicalDetails'] as Map<String, Object?>);
      expect(
        () => const LearningPackCodec().decodeEntry(jsonEncode(value)),
        throwsA(isA<LearningPackException>()),
      );
    });
  }
}
