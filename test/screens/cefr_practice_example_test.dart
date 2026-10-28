import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_manifest.dart';
import 'package:vocab_learning_app/widgets/cefr_practice_example.dart';

void main() {
  final catalog =
      CefrVocabularyCatalog.fromBytes(
        File(CefrVocabularyCatalog.asset).readAsBytesSync(),
      ).withEditorial(
        CefrEditorialCatalog.fromBytes(
          File('assets/content/cefr_editorial/batch-1.json').readAsBytesSync(),
          expectedSha256:
              cefrEditorialChecksums['assets/content/cefr_editorial/batch-1.json']!,
        ),
      );
  testWidgets('example waits for reveal and disappears for a changed sense', (
    tester,
  ) async {
    Future<void> render(bool visible, String meaning) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CefrPracticeExample(
              spelling: 'about',
              meaning: meaning,
              partOfSpeech: 'adverb',
              cefrLevel: 'A1',
              revealed: visible,
              catalog: Future.value(catalog),
              showUnavailable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render(false, 'ประมาณ');
    expect(find.text('The walk takes about ten minutes.'), findsNothing);
    await render(true, 'ประมาณ');
    expect(find.text('The walk takes about ten minutes.'), findsOneWidget);
    expect(find.text('การเดินใช้เวลาประมาณสิบนาที'), findsOneWidget);
    await render(true, 'เกี่ยวกับ');
    expect(find.text('The walk takes about ten minutes.'), findsNothing);
    expect(find.text('ยังไม่มีตัวอย่างที่ตรงกับความหมายนี้'), findsOneWidget);
  });
}
