import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/data/bundled_starter_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

void main() {
  test(
    'included starter has immutable original version and honest provenance',
    () {
      final pack = bundledStarterPack;
      expect(bundledStarterCatalogId, 'lexiquest.starter.en-th.1');
      expect(pack.manifest.packId, 'lexiquest.starter.en-th');
      expect(pack.manifest.version, '1.0.0');
      expect(pack.manifest.entryCount, 12);
      expect(pack.manifest.cefrLevel, 'A1');
      expect(pack.manifest.language, 'en');
      expect(pack.manifest.meaningLanguage, 'th');
      expect(pack.manifest.quality, LearningPackQuality.userProvidedUnreviewed);
      expect(pack.manifest.provenance.source, contains('AI-assisted'));
      expect(
        pack.manifest.provenance.attribution,
        contains('Editorial review pending'),
      );
      expect(
        pack.manifest.provenance.attribution,
        contains('not a certified level'),
      );
      expect(pack.manifest.provenance.license, contains('LexiQuest LICENSE'));
      expect(pack.manifest.provenance.sourceUri, isNull);
      expect(
        pack.packageSha256,
        '46203bc4328b66195a989df2471cd16b77e6c4c2f2833b35195956f07961251b',
        reason:
            'Published starter 1.0.0 content changes require a new version and pin.',
      );
      expect(
        pack.manifest.payloadSha256,
        'f582b290b73a274d9121005b0d03e07d2b88904a4284d2f564be75ce948f90f3',
      );
      expect(pack.byteCount, 15408);
    },
  );

  test(
    'actual codec preserves complete original bilingual practice content',
    () {
      final pack = bundledStarterPack;
      final decoded = const LearningPackCodec().decode(
        pack.bytes,
        expectedPackageSha256:
            '46203bc4328b66195a989df2471cd16b77e6c4c2f2833b35195956f07961251b',
      );
      expect(decoded.entries.map((entry) => entry.code), [
        'cat',
        'dog',
        'book',
        'water',
        'bus',
        'home',
        'hot',
        'cold',
        'open',
        'close',
        'day',
        'night',
      ]);
      expect(decoded.entries.map((entry) => entry.meaning), [
        'แมว',
        'สุนัข',
        'หนังสือ',
        'น้ำ',
        'รถโดยสาร',
        'บ้าน',
        'ร้อน',
        'เย็น',
        'เปิด',
        'ปิด',
        'กลางวัน',
        'กลางคืน',
      ]);
      expect(decoded.bytes, pack.bytes);
      expect(
        decoded.entries.map((entry) {
          final question = entry.definitionQuestion!;
          return question.options.indexWhere(
            (option) => option.code == question.correctOptionCode,
          );
        }).toSet(),
        {0, 1, 2},
        reason: 'The authored starter must not reveal answers by position.',
      );
      for (final entry in decoded.entries) {
        expect(entry.definition, isNotEmpty);
        expect(entry.examples.single.translation, isNotEmpty);
        expect(entry.memoryCue, isNotEmpty);
        expect(entry.hint, isNotEmpty);
        expect(entry.strategy, isNotEmpty);
        expect(entry.lexicalDetails!.ipa, isNotEmpty);
        final question = entry.definitionQuestion!;
        expect(question.options, hasLength(3));
        expect(
          question.options
              .singleWhere(
                (option) => option.code == question.correctOptionCode,
              )
              .entryCode,
          entry.code,
        );
        for (final option in question.options.where(
          (option) => option.code != question.correctOptionCode,
        )) {
          expect(option.contrastiveExplanation, isNotEmpty);
        }
      }
    },
  );
}
