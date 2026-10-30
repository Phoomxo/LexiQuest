import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/saved_words_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';

import '../support/saved_words_ui_harness.dart';

Future<void> _mount(WidgetTester tester, SavedWordsUiHarness h) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: h.dependencies(),
      child: MaterialApp(
        home: VocabListScreen(
          categoryId: configuredCategoryId,
          categoryName: 'Synthetic travel',
          vocabulary: h.vocabulary,
          savedWords: h.savedWords,
          ownerChanges: h.ownerChanges,
        ),
      ),
    ),
  );
  await savedUiUntil(tester, find.text('station'));
}

void main() {
  for (final accepted in [true, false]) {
    testWidgets(
      'bound Vocab delete confirmation accepted=$accepted preserves normal deletion',
      (tester) async {
        final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
        try {
          await _mount(tester, h);
          final before = await tester.runAsync(h.storage.snapshot);
          final remove = find.byKey(
            ValueKey('vocab-delete:${configuredWordIds.first}'),
          );
          await tester.ensureVisible(remove);
          await tester.tap(remove.hitTestable());
          await tester.pumpAndSettle();
          final confirmation = accepted
              ? find.widgetWithText(FilledButton, 'ลบ')
              : find.widgetWithText(TextButton, 'ยกเลิก');
          await tester.tap(confirmation.hitTestable());
          await tester.pump();
          var deleted = false;
          for (var i = 0; i < 30; i++) {
            deleted = (await tester.runAsync(
              () =>
                  (h.storage.database.select(h.storage.database.vocabularyWords)
                        ..where(
                          (word) => word.id.equals(configuredWordIds.first),
                        ))
                      .getSingle(),
            ))!.isDeleted;
            if (deleted == accepted) break;
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(deleted, accepted);
          if (!accepted) {
            expect(await tester.runAsync(h.storage.snapshot), before);
          }
        } finally {
          await closeSavedUi(tester, h);
        }
      },
    );
  }

  testWidgets(
    'owned VocabList bookmark opens the actual saved list without learning effects',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        await _mount(tester, h);
        final before = await tester.runAsync(h.storage.snapshot);
        await tester.tap(
          find.byKey(ValueKey('vocab-save:${configuredWordIds.first}')),
        );
        await tester.pump();
        expect(h.repository.commands, hasLength(1));
        expect(h.repository.commands.single.desiredIsSaved, isTrue);
        expect(h.repository.commands.single.expectedOwnerId, configuredOwnerId);
        expect(await tester.runAsync(h.storage.snapshot), before);
        await tester.tap(find.byKey(const ValueKey('saved-words')));
        await savedUiUntil(tester, find.byType(SavedWordsScreen));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SavedWordsScreen>(find.byType(SavedWordsScreen))
              .expectedOwnerId,
          configuredOwnerId,
        );
        expect(find.text('station'), findsOneWidget);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          0,
        );
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets(
    'unconfirmed save serializes the whole word row and retries the same identity',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.loseNextAck = true;
        await _mount(tester, h);
        await tester.tap(
          find.byKey(ValueKey('vocab-save:${configuredWordIds.first}')),
        );
        await savedUiUntil(
          tester,
          find.byKey(ValueKey('vocab-save-retry:${configuredWordIds.first}')),
        );
        final first = h.repository.commands.single;
        expect(
          tester
              .widget<IconButton>(
                find.byKey(ValueKey('vocab-save:${configuredWordIds.first}')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(ValueKey('vocab-delete:${configuredWordIds.first}')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.byKey(ValueKey('vocab-save-retry:${configuredWordIds.first}')),
        );
        await tester.pump();
        expect(h.repository.commands, hasLength(2));
        expect(h.repository.commands.last, same(first));
        expect(h.repository.states[configuredWordIds.first]!.localRevision, 1);
        expect(find.byTooltip('ลบคำศัพท์ station'), findsOneWidget);
        expect(find.byKey(const ValueKey('add-word')), findsOneWidget);
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets('stale saved-list action cannot navigate after owner ABA', (
    tester,
  ) async {
    final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
    try {
      await _mount(tester, h);
      final open = tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('saved-words')))
          .onPressed!;
      h.changeOwner(configuredOtherOwnerId);
      h.changeOwner(configuredOwnerId);
      await tester.pump();
      open();
      await tester.pumpAndSettle();
      expect(find.byType(SavedWordsScreen), findsNothing);
      expect(find.text('station', skipOffstage: false), findsNothing);
      expect(h.repository.commands, isEmpty);
    } finally {
      await closeSavedUi(tester, h);
    }
  });
}
