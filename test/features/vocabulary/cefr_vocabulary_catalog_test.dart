import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';

void main() {
  test(
    'pinned offline corpus has 3000 distinct sourced words across A1-B2',
    () {
      final bytes = File(
        'assets/content/cefr_starter/catalog.json',
      ).readAsBytesSync();
      final catalog = CefrVocabularyCatalog.fromBytes(bytes);
      expect(catalog.words, hasLength(3000));
      expect(catalog.words.map((word) => word.word).toSet(), hasLength(3000));
      for (final level in ['A1', 'A2', 'B1', 'B2']) {
        expect(catalog.search(level: level), isNotEmpty);
      }
      expect(catalog.search(level: 'C2'), isEmpty);
      final last = catalog.words.last;
      expect(catalog.search(query: last.word), contains(last));
      expect(
        catalog.search(query: '  BOOK  ').map((word) => word.word),
        contains('book'),
      );
      expect(catalog.search(query: 'หนังสือ'), isNotEmpty);
      expect(
        catalog.search(query: 'april').map((word) => word.word),
        contains('April'),
      );
      expect(catalog.search(query: 'no-such-word-12345'), isEmpty);
      expect(
        catalog.words.every(
          (word) =>
              word.meanings.isNotEmpty &&
              word.cefrjRow > 1 &&
              word.lexitronIds.isNotEmpty,
        ),
        isTrue,
      );
      expect(() => catalog.words.clear(), throwsUnsupportedError);
      bytes[20] ^= 1;
      expect(
        () => CefrVocabularyCatalog.fromBytes(bytes),
        throwsFormatException,
      );
    },
  );
}
