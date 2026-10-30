import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/saved_words_screen.dart';

import '../support/saved_words_ui_harness.dart';

Future<void> _mount(
  WidgetTester tester,
  SavedWordsUiHarness h, {
  String language = 'th',
  double scale = 1,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: h.dependencies(),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SavedWordsScreen(
          expectedOwnerId: configuredOwnerId,
          savedWords: h.savedWords,
          learning: h.learning,
          ownerChanges: h.ownerChanges,
          languageCode: language,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'loading empty current content and unavailable removal are honest',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.holdWatch = true;
        await _mount(tester, h);
        await savedUiUntil(tester, find.byKey(const ValueKey('saved-loading')));
        h.repository.holdWatch = false;
        h.repository.emit();
        await savedUiUntil(tester, find.byKey(const ValueKey('saved-empty')));
        h.repository.seed(configuredWordIds.first);
        h.repository.seed(configuredWordIds[1], available: false);
        h.repository.emit();
        await savedUiUntil(tester, find.text('station'));
        expect(find.text('ticket'), findsNothing);
        expect(
          find.byKey(ValueKey('saved-unavailable:${configuredWordIds[1]}')),
          findsOneWidget,
        );
        final before = await tester.runAsync(h.storage.snapshot);
        await tester.tap(
          find.byKey(ValueKey('saved-remove:${configuredWordIds[1]}')),
        );
        await savedUiUntil(tester, find.byKey(const ValueKey('saved-list')));
        expect(h.repository.commands.single.desiredIsSaved, isFalse);
        expect(await tester.runAsync(h.storage.snapshot), before);
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets(
    'lost remove acknowledgement retries the identical frozen command',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.seed(configuredWordIds.first);
        h.repository.loseNextAck = true;
        await _mount(tester, h);
        await savedUiUntil(tester, find.text('station'));
        await tester.tap(
          find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
        );
        await savedUiUntil(
          tester,
          find.byKey(ValueKey('saved-retry:${configuredWordIds.first}')),
        );
        final command = h.repository.commands.single;
        await tester.tap(
          find.byKey(ValueKey('saved-retry:${configuredWordIds.first}')),
        );
        await savedUiUntil(tester, find.byKey(const ValueKey('saved-empty')));
        expect(h.repository.commands, hasLength(2));
        expect(h.repository.commands.last, same(command));
        expect(h.repository.states[configuredWordIds.first]!.localRevision, 2);
        expect(
          find.byKey(ValueKey('saved-retry:${configuredWordIds.first}')),
          findsNothing,
        );
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets(
    'conflict refreshes read state and requires another explicit user intent',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.seed(configuredWordIds.first);
        h.repository.conflictNext = true;
        await _mount(tester, h);
        await savedUiUntil(tester, find.text('station'));
        await tester.tap(
          find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
        );
        await savedUiUntil(
          tester,
          find.byKey(
            ValueKey('saved-refresh-conflict:${configuredWordIds.first}'),
          ),
        );
        await tester.pump();
        expect(h.repository.commands, hasLength(1));
        await tester.tap(
          find.byKey(
            ValueKey('saved-refresh-conflict:${configuredWordIds.first}'),
          ),
        );
        await savedUiUntil(
          tester,
          find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
        );
        expect(h.repository.commands, hasLength(1));
        await tester.tap(
          find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
        );
        await savedUiUntil(tester, find.byKey(const ValueKey('saved-empty')));
        expect(h.repository.commands, hasLength(2));
        expect(
          h.repository.commands.last.mutationId,
          isNot(h.repository.commands.first.mutationId),
        );
        expect(h.repository.commands.last.expectedRevision, 2);
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  for (final loss in ['null', 'error', 'done', 'ABA']) {
    testWidgets(
      'owner $loss clears private content and ignores delayed acknowledgement',
      (tester) async {
        final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
        try {
          h.repository.seed(configuredWordIds.first);
          h.repository.seed(configuredWordIds[1]);
          await _mount(tester, h);
          await savedUiUntil(tester, find.text('station'));
          h.repository.acknowledgement = Completer<void>();
          await tester.tap(
            find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
          );
          await tester.pump();
          switch (loss) {
            case 'null':
              h.changeOwner(null);
            case 'error':
              h.owners.addError(StateError('synthetic owner error'));
            case 'done':
              // The forwarded stream closes asynchronously. Wait for its
              // source completion, then render the invalidation frame below.
              await tester.runAsync(h.owners.close);
            case 'ABA':
              h.changeOwner(configuredOtherOwnerId);
              h.changeOwner(configuredOwnerId);
          }
          await tester.pump();
          expect(find.text('ticket', skipOffstage: false), findsNothing);
          h.repository.release();
          await tester.pump();
          expect(find.byType(QuizScreen), findsNothing);
          expect(h.repository.commands, hasLength(1));
          expect(find.byKey(const ValueKey('saved-practice')), findsNothing);
        } finally {
          await closeSavedUi(tester, h);
        }
      },
    );
  }

  testWidgets(
    'read failure retries a new subscription without a bookmark write',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.failedReads = 1;
        await _mount(tester, h);
        await savedUiUntil(
          tester,
          find.byKey(const ValueKey('saved-read-retry')),
        );
        await tester.tap(find.byKey(const ValueKey('saved-read-retry')));
        await savedUiUntil(tester, find.byKey(const ValueKey('saved-empty')));
        expect(h.repository.watchCalls, 2);
        expect(h.repository.commands, isEmpty);
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets(
    'paused form clears private content and cannot acknowledge an older save',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.seed(configuredWordIds.first);
        h.repository.seed(configuredWordIds[1]);
        await _mount(tester, h);
        await savedUiUntil(tester, find.text('station'));
        h.repository.acknowledgement = Completer<void>();
        await tester.tap(
          find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
        );
        await tester.pump();
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        expect(tester.binding.framesEnabled, isFalse);
        tester.binding.scheduleForcedFrame();
        await tester.pump();
        expect(find.text('ticket', skipOffstage: false), findsNothing);
        h.repository.release();
        tester.binding.scheduleForcedFrame();
        await tester.pump();
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await savedUiUntil(tester, find.text('ticket'));
        expect(h.repository.watchCalls, greaterThan(1));
        expect(
          find.byKey(ValueKey('saved-retry:${configuredWordIds.first}')),
          findsOneWidget,
        );
        expect(h.repository.commands, hasLength(1));
      } finally {
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
        }
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets(
    'covered saved route clears its private subtree before delayed ACK',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      try {
        h.repository.seed(configuredWordIds.first);
        h.repository.seed(configuredWordIds[1]);
        await _mount(tester, h);
        await savedUiUntil(tester, find.text('station'));
        h.repository.acknowledgement = Completer<void>();
        await tester.tap(
          find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
        );
        await tester.pump();
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('synthetic cover')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ticket', skipOffstage: false), findsNothing);
        h.repository.release();
        await tester.pump();
        navigator.pop();
        await tester.pumpAndSettle();
        await savedUiUntil(tester, find.text('ticket'));
        expect(
          find.byKey(ValueKey('saved-retry:${configuredWordIds.first}')),
          findsOneWidget,
        );
        expect(h.repository.commands, hasLength(1));
      } finally {
        await closeSavedUi(tester, h);
      }
    },
  );

  testWidgets('dependency replacement denies stale saved ACK and content', (
    tester,
  ) async {
    final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
    final dependencies = ValueNotifier(h.dependencies());
    try {
      h.repository.seed(configuredWordIds.first);
      h.repository.seed(configuredWordIds[1]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        ValueListenableBuilder<AppDependencies>(
          valueListenable: dependencies,
          builder: (_, value, _) => AppDependenciesScope(
            dependencies: value,
            child: MaterialApp(
              home: SavedWordsScreen(
                expectedOwnerId: configuredOwnerId,
                ownerChanges: h.ownerChanges,
              ),
            ),
          ),
        ),
      );
      await savedUiUntil(tester, find.text('station'));
      h.repository.acknowledgement = Completer<void>();
      await tester.tap(
        find.byKey(ValueKey('saved-remove:${configuredWordIds.first}')),
      );
      await tester.pump();
      dependencies.value = h.dependencies();
      await tester.pump();
      expect(find.text('ticket', skipOffstage: false), findsNothing);
      h.repository.release();
      await tester.pump();
      expect(find.byKey(const ValueKey('saved-practice')), findsNothing);
      expect(h.repository.commands, hasLength(1));
    } finally {
      await closeSavedUi(tester, h);
      dependencies.dispose();
    }
  });

  testWidgets(
    'English narrow 200 percent keyboard practice binds at most20 source IDs',
    (tester) async {
      final h = (await tester.runAsync(SavedWordsUiHarness.open))!;
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        for (var index = 0; index < 25; index++) {
          final id = index < configuredWordIds.length
              ? configuredWordIds[index]
              : 'synthetic-extra-saved-$index';
          h.repository.words[id] = uiWord(id, 'saved$index');
          h.repository.seed(id);
        }
        await _mount(tester, h, language: 'en', scale: 2);
        await savedUiUntil(
          tester,
          find.byKey(const ValueKey('saved-practice')),
        );
        expect(find.textContaining('20'), findsWidgets);
        await tester.ensureVisible(
          find.byKey(const ValueKey('saved-practice')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await savedUiUntil(tester, find.byType(QuizScreen));
        final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(quiz.selectionMode, QuizWordSelectionMode.sourcePractice);
        expect(quiz.expectedOwnerId, configuredOwnerId);
        expect(quiz.learning, same(h.learning));
        expect(quiz.wordIds, hasLength(20));
        expect(quiz.wordIds!.toSet(), hasLength(20));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await closeSavedUi(tester, h);
      }
    },
  );
}
