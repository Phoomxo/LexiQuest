import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';

CefrVocabularyCatalog loadExpandedCatalog() =>
    CefrVocabularyCatalog.fromAssets({
      for (final path in [
        CefrVocabularyCatalog.asset,
        ...CefrVocabularyCatalog.expansionChecksums.keys,
      ])
        path: File(path).readAsBytesSync(),
    });

void main() {
  test(
    'expansion preserves 3000 legacy identities and separates 500 C2 words',
    () {
      final old = CefrVocabularyCatalog.fromBytes(
        File(CefrVocabularyCatalog.asset).readAsBytesSync(),
      );
      final catalog = loadExpandedCatalog();
      expect(catalog.words, hasLength(5500));
      expect(
        catalog.words.map((w) => w.word.toLowerCase()).toSet(),
        hasLength(5500),
      );
      expect(catalog.search(), hasLength(5000));
      expect(catalog.search(level: 'C1'), hasLength(500));
      expect(catalog.search(level: 'C2'), hasLength(500));
      for (final previous in old.words) {
        final current = catalog.words.singleWhere((w) => w.id == previous.id);
        expect(current.word, previous.word);
        expect(current.meanings, previous.meanings);
        expect(current.importNamespace, 'cefr-starter-3000-r1');
        expect(current.cefrLevel, previous.cefrLevel);
      }
      final c2 = catalog.search(level: 'C2').last;
      expect(catalog.search(query: c2.word), isEmpty);
      expect(catalog.search(query: c2.word, level: 'C2'), contains(c2));
      expect(c2.levelSource, 'Octanove 1.0');
      expect(c2.importNamespace, 'cefr-expanded-r1');
    },
  );
  test(
    'any corrupted extension is rejected before returning a partial inventory',
    () {
      for (final corrupt in CefrVocabularyCatalog.expansionChecksums.keys) {
        final assets = {
          for (final path in [
            CefrVocabularyCatalog.asset,
            ...CefrVocabularyCatalog.expansionChecksums.keys,
          ])
            path: File(path).readAsBytesSync(),
        };
        assets[corrupt]![20] ^= 1;
        expect(
          () => CefrVocabularyCatalog.fromAssets(assets),
          throwsFormatException,
        );
      }
    },
  );
}
