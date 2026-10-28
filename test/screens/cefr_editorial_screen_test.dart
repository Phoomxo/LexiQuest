import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_catalog_screen.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  testWidgets(
    'choosing curated sense through UI retains an edited legacy row',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var sequence = 0;
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'ui-editorial-owner',
        nowUtc: () => DateTime.utc(2026, 9, 12),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(db),
        generateId: () => 'ui-editorial-${sequence++}',
        nowUtc: () => DateTime.utc(2026, 9, 12),
      );
      final category = await vocabulary.createCategory('คำที่เลือก');
      final previous = await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'address',
          meaning: 'ที่อยู่เดิมของฉัน',
          partOfSpeech: 'noun',
          cefrLevel: 'A1',
          source: 'cefr-starter-3000-r1/address/1',
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
          ],
        }),
      );
      final catalog =
          CefrVocabularyCatalog.fromBytes(
            File(CefrVocabularyCatalog.asset).readAsBytesSync(),
          ).withEditorial(
            CefrEditorialCatalog.fromBytes(
              bytes,
              expectedSha256: sha256.convert(bytes).toString(),
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: CefrVocabularyCatalogScreen(
            catalog: Future.value(catalog),
            vocabulary: vocabulary,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cefr-catalog-search')),
        'address',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cefr-word-cefrj15:address')));
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('add-curated-meaning'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      // The import progress indicator intentionally animates while category
      // selection is open, so wait for the dialog instead of global settling.
      for (
        var attempt = 0;
        attempt < 20 && find.text('คำที่เลือก').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('คำที่เลือก'), findsOneWidget);
      await tester.tap(find.text('คำที่เลือก'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final owner = await owners.getOrCreateActiveOwner();
      final rows = await vocabulary.vocabulary.listAllWords(owner.id);
      expect(rows, hasLength(1));
      expect(rows.single.id, previous.id);
      expect(rows.single.meaning, 'ที่อยู่เดิมของฉัน');
      expect(
        find.text('คำนี้อยู่ในคลังของคุณแล้ว ใช้ฝึกและทบทวนได้'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'curated meaning and bilingual example appear first at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          ],
        }),
      );
      final catalog =
          CefrVocabularyCatalog.fromBytes(
            File(CefrVocabularyCatalog.asset).readAsBytesSync(),
          ).withEditorial(
            CefrEditorialCatalog.fromBytes(
              bytes,
              expectedSha256: sha256.convert(bytes).toString(),
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CefrVocabularyCatalogScreen(catalog: Future.value(catalog)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cefr-catalog-search')),
        'address',
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('cefr-word-cefrj15:address'));
      await tester.scrollUntilVisible(
        entry,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('คำนาม · ที่อยู่'), findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('Please write your address here.'), findsOneWidget);
      expect(find.text('กรุณาเขียนที่อยู่ของคุณที่นี่'), findsOneWidget);
      expect(find.text('ตัวอย่างนี้ตรวจภาษาเบื้องต้นด้วย AI'), findsOneWidget);
      expect(find.text('ความหมายอื่นจากพจนานุกรม · ยังรอตรวจ'), findsOneWidget);
      expect(find.text('คำปราศรัย'), findsNothing);
      final alternatives = find.text('ความหมายอื่นจากพจนานุกรม · ยังรอตรวจ');
      await tester.ensureVisible(alternatives);
      await tester.pumpAndSettle();
      await tester.tap(alternatives);
      await tester.pumpAndSettle();
      expect(find.text('คำปราศรัย'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
