import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_manifest.dart';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_practice_examples.dart';

void main() {
  final base = CefrVocabularyCatalog.fromBytes(
    File(CefrVocabularyCatalog.asset).readAsBytesSync(),
  );
  final catalog = base.withEditorial(
    CefrEditorialCatalog.fromBytes(
      File('assets/content/cefr_editorial/batch-1.json').readAsBytesSync(),
      expectedSha256:
          cefrEditorialChecksums['assets/content/cefr_editorial/batch-1.json']!,
    ),
  );
  test(
    'a corrected distinct primary does not attach to the old compound sense',
    () {
      final corrected = base.withEditorial(
        CefrEditorialCatalog.fromBytes(
          File('assets/content/cefr_editorial/batch-2.json').readAsBytesSync(),
          expectedSha256:
              cefrEditorialChecksums['assets/content/cefr_editorial/batch-2.json']!,
        ),
      );
      expect(
        CefrPracticeExamples.resolve(
          corrected,
          spelling: 'cooker',
          meaning: 'หม้อหุงข้าว',
          partOfSpeech: 'noun',
          cefrLevel: 'A2',
        ),
        isNull,
      );
      expect(
        CefrPracticeExamples.resolve(
          corrected,
          spelling: 'cooker',
          meaning: 'เตาหุงต้ม (อังกฤษแบบบริติช)',
          partOfSpeech: 'noun',
          cefrLevel: 'A2',
        )?.example,
        'Our new cooker has an oven and four rings.',
      );
    },
  );
  test('matches exact sense POS and level, never a headword-only guess', () {
    expect(
      CefrPracticeExamples.resolve(
        catalog,
        spelling: 'about',
        meaning: 'ประมาณ',
        partOfSpeech: 'adverb',
        cefrLevel: 'A1',
      )?.example,
      'The walk takes about ten minutes.',
    );
    for (final input in [
      ('about', 'เกี่ยวกับ', 'adverb', 'A1'),
      ('about', 'ประมาณ', 'preposition', 'A1'),
      ('about', 'ประมาณ', 'adverb', 'B1'),
      ('about', 'คำแปลที่ฉันแก้เอง', 'adverb', 'A1'),
      ('myword', 'ประมาณ', 'adverb', 'A1'),
    ]) {
      expect(
        CefrPracticeExamples.resolve(
          catalog,
          spelling: input.$1,
          meaning: input.$2,
          partOfSpeech: input.$3,
          cefrLevel: input.$4,
        ),
        isNull,
      );
    }
  });
  test(
    'equivalent original sense works and POS override does not leak to legacy POS',
    () {
      final april = catalog.words.singleWhere((w) => w.word == 'April');
      final original = april.meanings[april.editorial!.sourceMeaningIndex!];
      expect(
        CefrPracticeExamples.resolve(
          catalog,
          spelling: ' April ',
          meaning: original,
          partOfSpeech: 'noun',
          cefrLevel: 'A1',
        ),
        isNotNull,
      );
      expect(
        CefrPracticeExamples.resolve(
          catalog,
          spelling: 'its',
          meaning: 'ของมัน',
          partOfSpeech: 'pronoun',
          cefrLevel: 'A1',
        ),
        isNull,
      );
      expect(
        CefrPracticeExamples.resolve(
          catalog,
          spelling: 'its',
          meaning: 'ของมัน',
          partOfSpeech: 'determiner',
          cefrLevel: 'A1',
        ),
        isNotNull,
      );
    },
  );
}
