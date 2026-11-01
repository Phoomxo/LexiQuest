import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/rich_lexical_card.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';

import '../screens/learning_pack_test_support.dart';
import '../support/authored_lexical_pack.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'authored rich details fit 320px 200 percent ${dark ? 'dark' : 'light'} and label image and IPA',
      (tester) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LexicalEntryDetails(
                        entry: _entry(),
                        packCefrLevel: 'A1',
                        image: LearningPackImage(
                          id: 'synthetic-cat',
                          mimeType: 'image/png',
                          width: 2,
                          height: 2,
                          altText: 'Synthetic authored cat illustration',
                          bytes: Uint8List.fromList(
                            image.encodePng(image.Image(width: 2, height: 2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('/kæt/'), findsOneWidget);
          expect(find.text('ระดับแพ็ก A1'), findsOneWidget);
          expect(find.text('feline'), findsOneWidget);
          expect(find.text('dog'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Synthetic authored cat illustration'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('การออกเสียง IPA /kæt/'),
            findsOneWidget,
          );
          expect(find.text('A synthetic memory cue.'), findsNothing);
          expect(find.text('An authored hint.'), findsNothing);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'owned detail reads every table purely and retires after real owner ABA',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'rich/open',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(tester, () => h.seed(_pack()));
        final word = await motivationPresentationIo(
          tester,
          () => h.database.select(h.database.vocabularyWords).getSingle(),
        );
        final before = await motivationPresentationIo(
          tester,
          () => _rows(h.database),
        );
        await tester.pumpWidget(_owned(h, word));
        await _until(tester, () => find.text('/kæt/').evaluate().isNotEmpty);
        expect(
          await motivationPresentationIo(tester, () => _rows(h.database)),
          before,
        );
        await motivationPresentationIo(
          tester,
          () => h.switchOwner('synthetic-actions-other'),
        );
        await _until(tester, () => find.text('/kæt/').evaluate().isEmpty);
        await motivationPresentationIo(
          tester,
          () => h.switchOwner('synthetic-actions-owner'),
        );
        await tester.pump();
        expect(find.text('/kæt/'), findsNothing);
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );

  testWidgets(
    'a changed actual vocabulary revision removes stale rich details',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'rich/revision-open',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(tester, () => h.seed(_pack()));
        final word = await motivationPresentationIo(
          tester,
          () => h.database.select(h.database.vocabularyWords).getSingle(),
        );
        await tester.pumpWidget(_owned(h, word));
        await _until(tester, () => find.text('/kæt/').evaluate().isNotEmpty);
        await motivationPresentationIo(
          tester,
          () =>
              (h.database.update(
                h.database.vocabularyWords,
              )..where((row) => row.id.equals(word.id))).write(
                const VocabularyWordsCompanion(
                  localRevision: Value(2),
                  meaning: Value('updated synthetic meaning'),
                ),
              ),
        );
        await _until(tester, () => find.text('/kæt/').evaluate().isEmpty);
        expect(find.text('A synthetic memory cue.'), findsNothing);
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );
}

LearningPackEntry _entry() => LearningPackEntry(
  code: 'cat',
  spelling: 'cat',
  meaning: 'แมว',
  partOfSpeech: 'noun',
  definition: 'A small animal that meows.',
  examples: const [
    LearningPackExample(text: 'The cat rests.', translation: 'แมวพักผ่อน'),
  ],
  hint: 'An authored hint.',
  memoryCue: 'A synthetic memory cue.',
  lexicalDetails: LearningPackLexicalDetails(
    ipa: '/kæt/',
    synonyms: ['feline'],
    antonyms: ['dog'],
  ),
);

LearningPack _pack() => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: authoredLexicalPack().manifest,
    entries: [_entry()],
  ),
);

Widget _owned(LearningPackUiHarness h, VocabularyWord word) {
  final scope = h.app() as AppDependenciesScope;
  return AppDependenciesScope(
    dependencies: scope.dependencies,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OwnedLexicalDetails(
            expectedOwnerId: word.ownerId,
            word: QuizWord(
              id: word.id,
              categoryId: word.categoryId,
              spelling: word.spelling,
              meaning: word.meaning,
              partOfSpeech: word.partOfSpeech,
              contentRevision: 'local-vocabulary-v1:${word.localRevision}',
            ),
            visible: () => true,
          ),
        ),
      ),
    ),
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 100; frame++) {
    await motivationPresentationDeadline(
      tester,
      'rich/frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (done()) return;
  }
  fail('Authored lexical details did not reach the expected visible state');
}

Future<Map<String, Object?>> _rows(AppDatabase db) async => {
  for (final table in db.allTables)
    table.actualTableName:
        (await db
                .customSelect(
                  'SELECT * FROM ${table.actualTableName} ORDER BY rowid',
                )
                .get())
            .map((row) => row.data)
            .toList(),
};
