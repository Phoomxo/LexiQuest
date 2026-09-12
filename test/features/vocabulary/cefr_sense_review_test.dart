import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/screens/cefr_vocabulary_detail_screen.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_vocabulary_catalog.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_sense_review.dart';
import 'package:vocab_learning_app/features/vocabulary/data/cefr_editorial_catalog.dart';

void main() {
  final base = CefrVocabularyCatalog.fromBytes(
    File(CefrVocabularyCatalog.asset).readAsBytesSync(),
  );
  Map<String, dynamic> row() => {
    'id': 'cefrj15:address',
    'acceptedSourceMeaningIndices': [0],
    'excludedSourceMeanings': [
      {'index': 1, 'reason': 'Synthetic exclusion for test.'},
    ],
    'status': 'ai-reviewed',
    'reviewNote': 'Every original meaning checked.',
  };
  testWidgets(
    'severe slur remains available for recognition without an import action',
    (tester) async {
      final full = CefrVocabularyCatalog.fromAssets({
        for (final path in [
          CefrVocabularyCatalog.asset,
          ...CefrVocabularyCatalog.expansionChecksums.keys,
        ])
          path: File(path).readAsBytesSync(),
      });
      final bytes = utf8.encode(jsonEncode({'schemaVersion': 1, 'entries': [
        {'id': 'cefrj15:gook', 'senseKey': 'primary-v1', 'sourceMeaningIndex': null,
          'meaning': 'คำเหยียดเชื้อชาติรุนแรง',
          'example': 'The dictionary labels gook as a severe racial slur.',
          'translation': 'พจนานุกรมระบุว่าคำนี้เป็นคำเหยียดเชื้อชาติรุนแรง',
          'reviewNote': 'Synthetic recognition-only fixture.', 'status': 'ai-reviewed'}
      ]}));
      final word = full.withEditorial(CefrEditorialCatalog.fromBytes(bytes,
          expectedSha256: sha256.convert(bytes).toString())).words.singleWhere((w) => w.word == 'gook');
      expect(word.practiceUsageNotice, isNotNull);
      await tester.pumpWidget(
        MaterialApp(home: CefrVocabularyDetailScreen(word: word, canAdd: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text(word.practiceUsageNotice!), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.byKey(const ValueKey('add-curated-meaning')), findsNothing);
    },
  );
  List<CefrSenseReviewEntry> decode(Map<String, dynamic> item) {
    final raw = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'entries': [item],
      }),
    );
    return CefrSenseReview.fromBytes(
      raw,
      expectedSha256: sha256.convert(raw).toString(),
    );
  }

  test(
    'review filters selectable indices without changing original meanings',
    () {
      final revised = base.withSenseReviews(decode(row()));
      final word = revised.words.singleWhere((w) => w.id == 'cefrj15:address');
      expect(word.meanings, ['คำปราศรัย', 'หลักแหล่ง']);
      expect(word.selectableMeaningIndices, [0]);
      expect(revised.search(query: 'หลักแหล่ง'), isNot(contains(word)));
      expect(revised.search(query: 'คำปราศรัย'), contains(word));
      expect(
        word.senseReview!.excludedSourceMeanings[1],
        contains('Synthetic'),
      );
    },
  );
  test('rejects incomplete, overlapping, invalid or unpinned review data', () {
    for (final changed in [
      {...row(), 'acceptedSourceMeaningIndices': <int>[]},
      {
        ...row(),
        'acceptedSourceMeaningIndices': [0, 1],
      },
      {...row(), 'id': 'unknown'},
    ]) {
      expect(
        () => base.withSenseReviews(decode(changed)),
        throwsFormatException,
      );
    }
    expect(
      () => decode({...row(), 'status': 'certified'}),
      throwsFormatException,
    );
    expect(
      () =>
          CefrSenseReview.fromBytes(utf8.encode('{}'), expectedSha256: 'wrong'),
      throwsFormatException,
    );
  });
  testWidgets('excluded source meaning is absent from learner selection', (
    tester,
  ) async {
    final word = base
        .withSenseReviews(decode(row()))
        .words
        .singleWhere((w) => w.id == 'cefrj15:address');
    await tester.pumpWidget(
      MaterialApp(home: CefrVocabularyDetailScreen(word: word, canAdd: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('คำปราศรัย'), findsOneWidget);
    expect(find.text('หลักแหล่ง'), findsNothing);
    expect(word.meanings, ['คำปราศรัย', 'หลักแหล่ง']);
  });
}
