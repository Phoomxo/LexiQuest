import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_catalog_import.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';
import 'expanded_cefr_catalog_test.dart' show loadExpandedCatalog;

void main() {
  test(
    'catalog import is owner-scoped, idempotent and leaves prior learning untouched',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var id = 0;
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'synthetic-owner',
        nowUtc: () => DateTime.utc(2026, 9, 12),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(db),
        generateId: () => 'synthetic-${id++}',
        nowUtc: () => DateTime.utc(2026, 9, 12),
      );
      final category = await vocabulary.createCategory('คำที่เลือก');
      final owner = await owners.getOrCreateActiveOwner();
      final catalog = CefrVocabularyCatalog.fromBytes(
        File('assets/content/cefr_starter/catalog.json').readAsBytesSync(),
      );
      final importer = CefrCatalogImport(
        vocabulary: vocabulary,
        catalog: catalog,
      );
      final word = catalog.words.firstWhere((word) => word.word == 'book');
      final first = await importer.add(
        wordId: word.id,
        meaningIndex: 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      final second = await importer.add(
        wordId: word.id,
        meaningIndex: 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(first.id, second.id);
      expect(first.cefrLevel, word.cefrLevel);
      expect(first.source, contains('cefr-starter-3000-r1'));
      await vocabulary.updateWord(
        UpdateWordCommand(
          id: first.id,
          categoryId: category.id,
          spelling: first.spelling,
          meaning: 'หนังสือที่ฉันเลือกเอง',
          partOfSpeech: first.partOfSpeech,
          cefrLevel: first.cefrLevel,
          source: first.source,
        ),
      );
      final afterEdit = await importer.add(
        wordId: word.id,
        meaningIndex: 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(afterEdit.id, first.id);
      expect(afterEdit.meaning, 'หนังสือที่ฉันเลือกเอง');
      expect(await db.select(db.vocabularyWords).get(), hasLength(1));
      for (var i = 0; i < 49; i++) {
        await vocabulary.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'synthetic$i',
            meaning: 'คำสังเคราะห์ $i',
            partOfSpeech: 'noun',
          ),
        );
      }
      final another = catalog.words.firstWhere(
        (entry) => entry.word != word.word,
      );
      await expectLater(
        importer.add(
          wordId: another.id,
          meaningIndex: 0,
          categoryId: category.id,
          expectedOwnerId: owner.id,
        ),
        throwsA(isA<CategoryWordLimitFailure>()),
      );
      final retainedAtCapacity = await importer.add(
        wordId: word.id,
        meaningIndex: 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(retainedAtCapacity.id, first.id);
      expect(await db.select(db.vocabularyWords).get(), hasLength(50));
      final expanded = loadExpandedCatalog();
      final upgradedImporter = CefrCatalogImport(
        vocabulary: vocabulary,
        catalog: expanded,
      );
      final legacyAgain = await upgradedImporter.add(
        wordId: word.id,
        meaningIndex: 0,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(legacyAgain.id, first.id);
      expect(legacyAgain.meaning, 'หนังสือที่ฉันเลือกเอง');
      final supplementCategory = await vocabulary.createCategory(
        'ชุดเสริมที่เลือก',
      );
      final c2 = expanded.search(level: 'C2').first;
      final importedC2 = await upgradedImporter.add(
        wordId: c2.id,
        meaningIndex: 0,
        categoryId: supplementCategory.id,
        expectedOwnerId: owner.id,
      );
      final repeatedC2 = await upgradedImporter.add(
        wordId: c2.id,
        meaningIndex: 0,
        categoryId: supplementCategory.id,
        expectedOwnerId: owner.id,
      );
      expect(importedC2.id, repeatedC2.id);
      expect(importedC2.cefrLevel, 'C2');
      expect(importedC2.source, startsWith('cefr-expanded-r1/'));
      await expectLater(upgradedImporter.add(wordId: 'cefrj15:gook', meaningIndex: 0,
        categoryId: supplementCategory.id, expectedOwnerId: owner.id), throwsStateError);
      expect(await db.select(db.vocabularyWords).get(), hasLength(51));
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await db.select(db.learningSessions).get(), isEmpty);
      await expectLater(
        importer.add(
          wordId: word.id,
          meaningIndex: 0,
          categoryId: category.id,
          expectedOwnerId: 'another-owner',
        ),
        throwsStateError,
      );
      await expectLater(
        importer.add(
          wordId: word.id,
          meaningIndex: 0,
          categoryId: 'missing-category',
          expectedOwnerId: owner.id,
        ),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );
      await expectLater(
        importer.add(
          wordId: word.id,
          meaningIndex: 9999,
          categoryId: category.id,
          expectedOwnerId: owner.id,
        ),
        throwsRangeError,
      );
      expect(await db.select(db.vocabularyWords).get(), hasLength(51));
    },
  );
}
