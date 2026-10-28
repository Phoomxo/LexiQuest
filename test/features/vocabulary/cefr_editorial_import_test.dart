import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/cefr_catalog_import.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_sense_review.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  test(
    'curated imports keep equivalent legacy edits and stable independent senses',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var id = 0;
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'editorial-owner',
        nowUtc: () => DateTime.utc(2026, 9, 12),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(db),
        generateId: () => 'editorial-${id++}',
        nowUtc: () => DateTime.utc(2026, 9, 12),
      );
      final owner = await owners.getOrCreateActiveOwner();
      final category = await vocabulary.createCategory('คำที่คัด');
      final base = CefrVocabularyCatalog.fromBytes(
        File(CefrVocabularyCatalog.asset).readAsBytesSync(),
      );
      final legacy =
          await CefrCatalogImport(vocabulary: vocabulary, catalog: base).add(
            wordId: 'cefrj15:address',
            meaningIndex: 1,
            categoryId: category.id,
            expectedOwnerId: owner.id,
          );
      await vocabulary.updateWord(
        UpdateWordCommand(
          id: legacy.id,
          categoryId: category.id,
          spelling: legacy.spelling,
          meaning: 'ที่อยู่ที่ฉันเขียนเอง',
          partOfSpeech: legacy.partOfSpeech,
          cefrLevel: legacy.cefrLevel,
          source: legacy.source,
        ),
      );
      final bytes = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'entries': [
            {
              'id': 'cefrj15:address',
              'senseKey': 'primary-v1',
              'sourceMeaningIndex': 1,
              'meaning': 'ที่อยู่',
              'example': 'Please write your address here.',
              'translation': 'กรุณาเขียนที่อยู่ของคุณที่นี่',
              'reviewNote': 'ที่อยู่ ไม่ใช่คำปราศรัย',
              'status': 'ai-reviewed',
            },
            {
              'id': 'cefrj15:about',
              'senseKey': 'primary-v1',
              'sourceMeaningIndex': null,
              'meaning': 'ประมาณ',
              'example': 'The bag costs about ten dollars.',
              'translation': 'กระเป๋าใบนี้ราคาประมาณสิบดอลลาร์',
              'reviewNote': 'about ขยายจำนวนโดยประมาณ',
              'status': 'ai-reviewed',
            },
          ],
        }),
      );
      final catalog = base.withEditorial(
        CefrEditorialCatalog.fromBytes(
          bytes,
          expectedSha256: sha256.convert(bytes).toString(),
        ),
      );
      final importer = CefrCatalogImport(
        vocabulary: vocabulary,
        catalog: catalog,
      );
      final retained = await importer.add(
        wordId: 'cefrj15:address',
        meaningIndex: 0,
        useEditorial: true,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(retained.id, legacy.id);
      expect(retained.meaning, 'ที่อยู่ที่ฉันเขียนเอง');
      final fresh = await importer.add(
        wordId: 'cefrj15:about',
        meaningIndex: 0,
        useEditorial: true,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      final repeated = await importer.add(
        wordId: 'cefrj15:about',
        meaningIndex: 0,
        useEditorial: true,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(fresh.id, repeated.id);
      expect(fresh.meaning, 'ประมาณ');
      expect(fresh.source, 'cefr-editorial-r1/about/primary-v1');
      final reviewBytes = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'entries': [
            {
              'id': 'cefrj15:address',
              'acceptedSourceMeaningIndices': [0],
              'excludedSourceMeanings': [
                {'index': 1, 'reason': 'Synthetic selection test.'},
              ],
              'status': 'ai-reviewed',
              'reviewNote': 'Synthetic review.',
            },
          ],
        }),
      );
      final reviewedImporter = CefrCatalogImport(
        vocabulary: vocabulary,
        catalog: catalog.withSenseReviews(
          CefrSenseReview.fromBytes(
            reviewBytes,
            expectedSha256: sha256.convert(reviewBytes).toString(),
          ),
        ),
      );
      await expectLater(
        reviewedImporter.add(
          wordId: 'cefrj15:address',
          meaningIndex: 1,
          categoryId: category.id,
          expectedOwnerId: owner.id,
        ),
        throwsStateError,
      );
      final stillRetained = await reviewedImporter.add(
        wordId: 'cefrj15:address',
        meaningIndex: 1,
        useEditorial: true,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      expect(stillRetained.id, legacy.id);
      expect(stillRetained.meaning, 'ที่อยู่ที่ฉันเขียนเอง');
      await expectLater(
        importer.add(
          wordId: 'cefrj15:book',
          meaningIndex: 0,
          useEditorial: true,
          categoryId: category.id,
          expectedOwnerId: owner.id,
        ),
        throwsStateError,
      );
      expect(await db.select(db.vocabularyWords).get(), hasLength(2));
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await db.select(db.learningSessions).get(), isEmpty);
    },
  );
}
