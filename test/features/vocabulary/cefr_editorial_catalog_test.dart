import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';

void main() {
  test(
    'packaged editorial covers all 5500 words and partitions all original senses',
    () async {
      final catalog = await CefrVocabularyCatalog.load(
        bundle: _FileCatalogBundle(),
      );
      expect(catalog.editorialLoadFailed, isFalse);
      expect(catalog.editorialCount, 5500);
      expect(
        catalog.words.where((w) => w.cefrLevel == 'A1' && w.editorial != null),
        hasLength(933),
      );
      expect(
        catalog.words.where((w) => w.cefrLevel == 'A2' && w.editorial != null),
        hasLength(1101),
      );
      expect(
        catalog.words.where(
          (w) => !['A1', 'A2'].contains(w.cefrLevel) && w.editorial != null,
        ),
        hasLength(3466),
      );
      expect(
        catalog.words.where((w) => w.senseReview != null),
        hasLength(5500),
      );
      expect(
        catalog.words.fold<int>(0, (sum, word) => sum + word.meanings.length),
        10793,
      );
      for (final word in catalog.words) {
        final review = word.senseReview!;
        expect(
          [
            ...review.acceptedSourceMeaningIndices,
            ...review.excludedSourceMeanings.keys,
          ]..sort(),
          List.generate(word.meanings.length, (index) => index),
          reason: word.id,
        );
      }
    },
  );
  test(
    'corrupt sense-review asset drops the entire optional overlay',
    () async {
      final catalog = await CefrVocabularyCatalog.load(
        bundle: _FileCatalogBundle(corruptSenseReview: true),
      );
      expect(catalog.words, hasLength(5500));
      expect(catalog.editorialLoadFailed, isTrue);
      expect(catalog.editorialCount, 0);
      expect(catalog.words.where((word) => word.senseReview != null), isEmpty);
    },
  );
  test(
    'unavailable editorial overlay leaves the complete base catalog usable',
    () async {
      final catalog = await CefrVocabularyCatalog.load(
        bundle: _FileCatalogBundle(),
        editorialLoader: () async =>
            throw const FormatException('synthetic missing overlay'),
      );
      expect(catalog.words, hasLength(5500));
      expect(catalog.search(), hasLength(5000));
      expect(catalog.editorialCount, 0);
      expect(catalog.editorialLoadFailed, isTrue);
    },
  );
  Map<String, dynamic> entry() => {
    'id': 'cefrj15:address',
    'senseKey': 'primary-v1',
    'sourceMeaningIndex': 1,
    'meaning': 'ที่อยู่',
    'example': 'Please write your address here.',
    'translation': 'กรุณาเขียนที่อยู่ของคุณที่นี่',
    'reviewNote': 'ใช้ address เป็นคำนามหมายถึงที่อยู่ ไม่ใช่คำปราศรัย',
    'status': 'ai-reviewed',
  };
  test(
    'overlay preserves original indices and rejects a mismatched example',
    () {
      final base = CefrVocabularyCatalog.fromBytes(
        File(CefrVocabularyCatalog.asset).readAsBytesSync(),
      );
      List<CefrEditorialEntry> decode(Map<String, dynamic> row) {
        final bytes = utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'entries': [row],
          }),
        );
        return CefrEditorialCatalog.fromBytes(
          bytes,
          expectedSha256: sha256.convert(bytes).toString(),
        );
      }

      final curated = base.withEditorial(decode(entry()));
      final word = curated.words.singleWhere((w) => w.id == 'cefrj15:address');
      expect(word.meanings, ['คำปราศรัย', 'หลักแหล่ง']);
      expect(word.editorial!.meaning, 'ที่อยู่');
      expect(curated.search(query: 'ที่อยู่'), contains(word));
      expect(curated.editorialCount, 1);
      expect(base.editorialCount, 0);
      for (final row in [
        {...entry(), 'sourceMeaningIndex': 99},
        {...entry(), 'id': 'unknown-word'},
        {...entry(), 'example': 'Please write your name here.'},
      ]) {
        expect(() => base.withEditorial(decode(row)), throwsFormatException);
      }
    },
  );
  test(
    'editorial POS correction is explicit and does not mutate the source word',
    () {
      final bytes = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'entries': [
            {
              ...entry(),
              'id': 'cefrj15:its',
              'sourceMeaningIndex': null,
              'partOfSpeechOverride': 'determiner',
              'meaning': 'ของมัน',
              'example': 'The cat moves its tail.',
              'translation': 'แมวขยับหางของมัน',
            },
          ],
        }),
      );
      final entries = CefrEditorialCatalog.fromBytes(
        bytes,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      final base = CefrVocabularyCatalog.fromBytes(
        File(CefrVocabularyCatalog.asset).readAsBytesSync(),
      );
      final word = base
          .withEditorial(entries)
          .words
          .singleWhere((w) => w.id == 'cefrj15:its');
      expect(word.partOfSpeech, 'pronoun');
      expect(word.editorial!.partOfSpeechOverride, 'determiner');
      expect(word.partOfSpeechThai, 'คำกำกับนาม');
    },
  );
  test(
    'editorial parser retains explicit source mapping and bilingual example',
    () {
      final bytes = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'entries': [entry()],
        }),
      );
      final rows = CefrEditorialCatalog.fromBytes(
        bytes,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      expect(rows.single.sourceMeaningIndex, 1);
      expect(rows.single.meaning, 'ที่อยู่');
      expect(rows.single.example, 'Please write your address here.');
      expect(rows.single.status, 'ai-reviewed');
      expect(() => rows.clear(), throwsUnsupportedError);
      expect(
        () => CefrEditorialCatalog.fromBytes(bytes, expectedSha256: '0' * 64),
        throwsFormatException,
      );
    },
  );
  test(
    'rejects duplicate identities and invalid source mappings or review status',
    () {
      for (final rows in [
        [entry(), entry()],
        [
          {...entry(), 'sourceMeaningIndex': -1},
        ],
        [
          {...entry(), 'sourceMeaningIndex': 1.5},
        ],
        [
          {...entry(), 'status': 'human-certified'},
        ],
        [
          {...entry(), 'translation': ''},
        ],
        [
          {...entry(), 'example': 'broken\u0000sentence'},
        ],
        [
          {...entry(), 'unexpected': true},
        ],
      ]) {
        final bytes = utf8.encode(
          jsonEncode({'schemaVersion': 1, 'entries': rows}),
        );
        expect(
          () => CefrEditorialCatalog.fromBytes(
            bytes,
            expectedSha256: sha256.convert(bytes).toString(),
          ),
          throwsFormatException,
        );
      }
    },
  );
}

class _FileCatalogBundle extends CachingAssetBundle {
  _FileCatalogBundle({this.corruptSenseReview = false});
  final bool corruptSenseReview;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    corruptSenseReview && key.contains('/sense-review-')
        ? Uint8List.fromList(utf8.encode('{}'))
        : File(key).readAsBytesSync(),
  );
}
