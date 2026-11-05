import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

import '../support/authored_lexical_pack.dart';
import '../support/motivation_presentation_io.dart';
import 'learning_pack_test_support.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  testWidgets(
    'actual vocabulary detail reuses authored rich content without learning writes',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'vocab-rich/open',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(
          tester,
          () => h.seed(authoredLexicalPack()),
        );
        final scope = (await motivationPresentationIo(
          tester,
          () => h.packs.captureOwner(stillCurrent: () => true),
        ))!;
        final pack = (await motivationPresentationIo(
          tester,
          () => h.packs.list(scope),
        )).single;
        final detail = await motivationPresentationIo(
          tester,
          () => h.packs.detail(scope, pack.id),
        );
        final cat = detail.bindings.singleWhere(
          (row) => row.entry.code == 'cat',
        );
        final vocabulary = VocabularyUseCases(
          owners: h.learning.owners,
          vocabulary: DriftVocabularyRepository(h.database),
          generateId: () => 'synthetic-rich-unused',
          nowUtc: () => DateTime.utc(2026, 11, 1),
        );
        final before = await motivationPresentationIo(
          tester,
          () => _rows(h.database),
        );
        await tester.pumpWidget(
          _app(
            h,
            VocabListScreen(
              categoryId: pack.categoryId!,
              categoryName: 'Synthetic authored words',
              vocabulary: vocabulary,
              ownerChanges: h.packs.watchActiveOwnerId(),
            ),
          ),
        );
        final toggle = find.byKey(
          ValueKey('vocab-rich:${cat.wordId}:${cat.wordRevision}'),
        );
        await _until(tester, () => toggle.evaluate().isNotEmpty);
        await tester.ensureVisible(toggle);
        await tester.tap(
          find.descendant(of: toggle, matching: find.text('รายละเอียดคำศัพท์')),
        );
        await _until(
          tester,
          () => find.text('A small animal that meows.').evaluate().isNotEmpty,
        );
        expect(find.text('Think of meowing.'), findsOneWidget);
        expect(
          await motivationPresentationIo(tester, () => _rows(h.database)),
          before,
        );
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );

  testWidgets(
    'actual SRS displays authored detail only after flip and keeps hint content hidden',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'srs-rich/open',
        () => tester.runAsync(LearningPackUiHarness.open),
      ))!;
      try {
        await motivationPresentationIo(
          tester,
          () => h.seed(authoredLexicalPack()),
        );
        final scope = (await motivationPresentationIo(
          tester,
          () => h.packs.captureOwner(stillCurrent: () => true),
        ))!;
        final pack = (await motivationPresentationIo(
          tester,
          () => h.packs.list(scope),
        )).single;
        final detail = await motivationPresentationIo(
          tester,
          () => h.packs.detail(scope, pack.id),
        );
        final cat = detail.bindings.singleWhere(
          (row) => row.entry.code == 'cat',
        );
        await tester.pumpWidget(
          _app(
            h,
            SrsFlashcardsScreen(
              sourceWordIds: [cat.wordId],
              expectedOwnerId: scope.ownerId,
              ownerChanges: h.packs.watchActiveOwnerId(),
              learning: h.learning,
            ),
          ),
        );
        final flip = find.byKey(const Key('srs-flip'));
        await _until(tester, () => flip.evaluate().isNotEmpty);
        expect(find.text('A small animal that meows.'), findsNothing);
        final before = await motivationPresentationIo(
          tester,
          () => _rows(h.database),
        );
        await tester.ensureVisible(flip);
        await tester.tap(flip);
        await _until(
          tester,
          () => find.text('A small animal that meows.').evaluate().isNotEmpty,
        );
        expect(find.text('Think of meowing.'), findsNothing);
        expect(find.text('Read the entire authored definition.'), findsNothing);
        final session = before['learning_sessions']!.single;
        final position = jsonDecode(session['checkpoint_json']! as String);
        expect(position['cardIndex'], 0);
        expect(position['revealed'], isFalse);
        position['revealed'] = true;
        session['checkpoint_json'] = jsonEncode(position);
        session['checkpoint_revision'] =
            (session['checkpoint_revision']! as int) + 1;
        expect(
          await motivationPresentationIo(tester, () => _rows(h.database)),
          before,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => h.count('answer_attempts'),
          ),
          0,
        );
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );
}

Widget _app(LearningPackUiHarness h, Widget child) {
  final base = (h.app() as AppDependenciesScope).dependencies;
  return AppDependenciesScope(
    dependencies: AppDependencies(
      runtimeStatus: base.runtimeStatus,
      config: null,
      guestSessionService: base.guestSessionService,
      database: h.database,
      learningPacks: h.packs,
      learning: h.learning,
      localOwners: h.learning.owners,
    ),
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: child,
    ),
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 150; frame++) {
    await motivationPresentationDeadline(
      tester,
      'rich-caller/frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (done()) return;
  }
  fail('Actual rich-card caller did not reach the expected state');
}

Future<Map<String, List<Map<String, Object?>>>> _rows(AppDatabase db) async => {
  for (final table in db.allTables)
    table.actualTableName:
        (await db
                .customSelect(
                  'SELECT * FROM ${table.actualTableName} ORDER BY rowid',
                )
                .get())
            .map((row) => Map<String, Object?>.of(row.data))
            .toList(),
};
