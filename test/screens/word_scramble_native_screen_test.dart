import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';

import '../support/configured_quiz_harness.dart';

void main() {
  testWidgets(
    'accepted letters stay fixed; feedback waits for saved ACK and finish returns stored summary',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        final original = f.session.letters.toList();
        expect(find.byKey(const ValueKey('scramble-feedback')), findsNothing);
        expect(await f.count(tester, 'learning_sessions'), 1);
        f.repository.answerGate = Completer<void>();
        await _type(tester, f.session.word.spelling);
        await _save(tester);
        await _until(tester, () => f.repository.answers.isNotEmpty);
        expect(find.byKey(const ValueKey('scramble-feedback')), findsNothing);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('scramble-response')),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('scramble-clear')),
              )
              .onPressed,
          isNull,
        );
        expect(await f.count(tester, 'answer_attempts'), 0);
        expect(f.session.letters, original);
        f.repository.answerGate!.complete();
        await tester.runAsync(f.repository.settle);
        await _finishReady(tester, f);
        expect(find.textContaining(f.session.word.spelling), findsWidgets);
        expect(
          f.repository.answers.single.evidenceContext.evidenceClass.name,
          'recreational',
        );
        expect(f.repository.answers.single.evidenceContext.hintLevel, 0);
        await _tap(tester, const ValueKey('scramble-finish'));
        await _until(tester, () => f.summary != null);
        expect(f.summary!.state, 'completed');
        expect(f.summary!.correctCount, 1);
        expect(f.summary!.wrongCount, 0);
        expect(await f.count(tester, 'answer_attempts'), 1);
        for (final table in [
          'srs_states',
          'points_ledger_entries',
          'events_v2',
        ]) {
          expect(await f.count(tester, table), 0);
        }
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'start, answer and finish lost ACK retries reuse exact frozen native identities',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        f.repository.loseStart = true;
        await _mount(tester, f, ready: false);
        await _retryReady(tester, f);
        await _tap(tester, const ValueKey('scramble-retry'));
        await _ready(tester, f);
        expect(
          identical(f.repository.starts.first, f.repository.starts.last),
          isTrue,
        );
        f.repository.loseAnswer = true;
        await _type(tester, 'wrong');
        await _save(tester);
        await _retryReady(tester, f);
        final first = f.repository.answers.single;
        await _tap(tester, const ValueKey('scramble-retry'));
        await _finishReady(tester, f);
        expect(
          identical(f.repository.answers.first, f.repository.answers.last),
          isTrue,
        );
        expect(f.repository.answers.last.occurredAtUtc, first.occurredAtUtc);
        expect(await f.count(tester, 'answer_attempts'), 1);
        f.repository.loseFinish = true;
        await _tap(tester, const ValueKey('scramble-finish'));
        await _retryReady(tester, f);
        await _tap(tester, const ValueKey('scramble-retry'));
        await _until(tester, () => f.summary != null);
        expect(
          identical(f.repository.finishes.first, f.repository.finishes.last),
          isTrue,
        );
        expect(f.summary!.wrongCount, 1);
        expect(await f.count(tester, 'learning_sessions'), 1);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'whole target in meaning is masked in visible text and semantics until ACK',
    (tester) async {
      final f = await _Fixture.open(tester);
      final semantics = tester.ensureSemantics();
      try {
        await _mount(tester, f);
        final cue = find.byKey(const ValueKey('scramble-meaning-cue'));
        await _reveal(tester, cue);
        final text = tester.widget<Text>(cue).data!;
        expect(text, contains('_____ / _____ / letterary'));
        expect(
          RegExp(r'\bletter\b', caseSensitive: false).hasMatch(text),
          isFalse,
        );
        expect(tester.getSemantics(cue).label, text);
        expect(find.byKey(const ValueKey('scramble-feedback')), findsNothing);
      } finally {
        semantics.dispose();
        await f.close(tester);
      }
    },
  );

  for (final spelling in ['กขก', '👩‍💻a']) {
    testWidgets(
      'whole Unicode target $spelling is masked in text and semantics',
      (tester) async {
        final f = await _Fixture.open(tester, spelling: spelling);
        final semantics = tester.ensureSemantics();
        try {
          await _mount(tester, f);
          final cue = find.byKey(const ValueKey('scramble-meaning-cue'));
          await _reveal(tester, cue);
          final text = tester.widget<Text>(cue).data!;
          expect(text, contains('_____ / _____ / ${spelling}ary'));
          expect(tester.getSemantics(cue).label, text);
          expect(find.byKey(const ValueKey('scramble-feedback')), findsNothing);
        } finally {
          semantics.dispose();
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'duplicate graphemes use distinct source indices; Undo and Clear preserve letter order',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        final before = f.session.letters.toList();
        for (var i = 0; i < before.length; i++) {
          await _tap(tester, ValueKey('scramble-letter-$i'));
          await _tap(tester, ValueKey('scramble-letter-$i'));
        }
        final answer = tester.widget<Text>(
          find.byKey(const ValueKey('scramble-arranged')),
        );
        expect(answer.data, before.join());
        await _tap(tester, const ValueKey('scramble-undo'));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('scramble-arranged')))
              .data,
          before.take(before.length - 1).join(),
        );
        await _tap(tester, const ValueKey('scramble-clear'));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('scramble-arranged')))
              .data,
          '',
        );
        expect(f.session.letters, before);
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'stale, reused and out-of-range drop payloads cannot alter an accepted arrangement',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        final target = tester.widget<DragTarget<int>>(
          find.byKey(const ValueKey('scramble-slot-0')),
        );
        expect(
          target.onWillAcceptWithDetails!(
            DragTargetDetails(data: -1, offset: Offset.zero),
          ),
          isFalse,
        );
        expect(
          target.onWillAcceptWithDetails!(
            DragTargetDetails(
              data: f.session.letters.length,
              offset: Offset.zero,
            ),
          ),
          isFalse,
        );
        target.onAcceptWithDetails!(
          DragTargetDetails(data: 0, offset: Offset.zero),
        );
        await tester.pump();
        target.onAcceptWithDetails!(
          DragTargetDetails(data: 0, offset: Offset.zero),
        );
        target.onAcceptWithDetails!(
          DragTargetDetails(data: 999, offset: Offset.zero),
        );
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('scramble-arranged')))
              .data,
          f.session.letters.first,
        );
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'tiles support focused keyboard activation and typed alternative',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _tap(tester, const ValueKey('scramble-letter-0'));
        await _tap(tester, const ValueKey('scramble-undo'));
        final tile = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('scramble-letter-0')),
        );
        tile.focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('scramble-arranged')))
              .data,
          f.session.letters.first,
        );
        await _type(tester, f.session.word.spelling);
        await _save(tester);
        await _finishReady(tester, f);
        expect(f.repository.answers.single.isCorrect, isTrue);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets('reduced motion shows actual drag drop colour immediately', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      await _mount(tester, f, reducedMotion: true);
      final source = find.byType(Draggable<int>).first;
      final target = find.byKey(const ValueKey('scramble-slot-0'));
      await tester.ensureVisible(source);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(source));
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: target, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        Theme.of(tester.element(target)).colorScheme.primaryContainer,
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: target,
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
    } finally {
      await f.close(tester);
    }
  });

  for (final invalidation in [
    'null',
    'other',
    'aba',
    'error',
    'done',
    'lifecycle',
    'route',
    'dependencies',
    'dispose',
  ]) {
    testWidgets(
      '$invalidation invalidates pending save without recording a new answer or feedback',
      (tester) async {
        final f = await _Fixture.open(tester);
        try {
          await _mount(tester, f);
          f.repository.answerGate = Completer<void>();
          await _type(tester, f.session.word.spelling);
          await _save(tester);
          await _until(tester, () => f.repository.answers.isNotEmpty);
          switch (invalidation) {
            case 'null':
              f.owners.add(null);
            case 'other':
              f.owners.add(configuredOtherOwnerId);
            case 'aba':
              f.owners.add(configuredOtherOwnerId);
              f.owners.add(configuredOwnerId);
            case 'error':
              f.owners.addError(StateError('SYNTHETIC_PRIVATE_CANARY'));
            case 'done':
              await tester.runAsync(f.owners.close);
            case 'lifecycle':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
            case 'route':
              unawaited(
                f.navigator.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Overlay')),
                  ),
                ),
              );
            case 'dependencies':
              f.language.value = 'en';
            case 'dispose':
              await tester.pumpWidget(const SizedBox.shrink());
          }
          await tester.pump();
          f.repository.answerGate!.complete();
          await tester.runAsync(f.repository.settle);
          await tester.pump();
          expect(await f.count(tester, 'answer_attempts'), 0);
          expect(find.byKey(const ValueKey('scramble-feedback')), findsNothing);
          expect(find.textContaining('SYNTHETIC_PRIVATE_CANARY'), findsNothing);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets('missing owner observation cannot start an accepted round', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: WordScrambleScreen(session: f.session, learning: f.learning),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scramble-response')), findsNothing);
      expect(await f.count(tester, 'learning_sessions'), 0);
      expect(await f.count(tester, 'answer_attempts'), 0);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'back leaves accepted session unfinished without synthesizing answer or finish',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _tap(tester, const ValueKey('scramble-back'));
        await tester.pumpAndSettle();
        expect(find.byType(WordScrambleScreen), findsNothing);
        final row = (await tester.runAsync(() => f.h.session(f.session.id)))!;
        expect(row['state'], 'active');
        expect(row['ended_at_utc_ms'], isNull);
        expect(await f.count(tester, 'answer_attempts'), 0);
        expect(f.repository.finishes, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language 320px at 200 percent has visible tappable tiles and controls',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = await _Fixture.open(tester);
        try {
          await _mount(tester, f, language: language, scale: 2);
          final tile = find.byKey(const ValueKey('scramble-letter-0'));
          await tester.ensureVisible(tile);
          await tester.pump();
          expect(tile.hitTestable(), findsOneWidget);
          await tester.tap(tile.hitTestable());
          expect(tester.takeException(), isNull);
          await _type(tester, f.session.word.spelling);
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await _save(tester);
          await _finishReady(tester, f);
          expect(
            find.byKey(const ValueKey('scramble-finish')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetViewInsets();
          await f.close(tester);
        }
      },
    );
  }
}

final class _Fixture {
  _Fixture(this.h, this.repository, this.learning, this.session);
  final ConfiguredQuizHarness h;
  final _AckRepository repository;
  final LearningUseCases learning;
  final WordScrambleSession session;
  final owners = StreamController<String?>.broadcast(sync: true);
  final navigator = GlobalKey<NavigatorState>();
  final language = ValueNotifier<String>('th');
  LearningSessionSummary? summary;

  static Future<_Fixture> open(
    WidgetTester tester, {
    String spelling = 'letter',
  }) async {
    final h = (await tester.runAsync(ConfiguredQuizHarness.open))!;
    await tester.runAsync(() async {
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1 WHERE owner_id = ? AND id != ?',
        [configuredOwnerId, configuredWordIds.first],
      );
      await h.database.customStatement(
        'UPDATE vocabulary_words SET spelling = ?, normalized_spelling = ?, meaning = ? WHERE id = ?',
        [
          spelling,
          spelling.toLowerCase(),
          'synthetic gloss $spelling / ${spelling.toUpperCase()} / ${spelling}ary',
          configuredWordIds.first,
        ],
      );
    });
    final repository = _AckRepository(
      DriftLearningRepository(h.database, ownerWrites: h.ownerWrites),
    );
    var id = 0;
    final learning = LearningUseCases(
      owners: h.owners,
      repository: repository,
      generateId: () => 'scramble-ui-${++id}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'synthetic-ui'),
    );
    final session = await tester.runAsync(
      () => learning.prepareWordScramble(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ),
    );
    return _Fixture(h, repository, learning, session!);
  }

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => h.count(table)))!;
  Future<void> close(WidgetTester tester) async {
    if (repository.answerGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    _resume(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(repository.settle);
    if (!owners.isClosed) {
      await tester.runAsync(owners.close);
    }
    language.dispose();
    await tester.runAsync(h.close);
  }
}

final class _AckRepository extends Fake
    implements LearningRepository, NativeExerciseRepository {
  _AckRepository(this.delegate);
  final NativeExerciseRepository delegate;
  final starts = <AcceptedNativeExercise>[];
  final answers = <RecordAnswerCommand>[];
  final finishes = <NativeFinishIntent>[];
  final pending = <Future<void>>{};
  bool loseStart = false;
  bool loseAnswer = false;
  bool loseFinish = false;
  Completer<void>? answerGate;

  Future<T> _track<T>(Future<T> Function() operation) async {
    final done = Completer<void>();
    pending.add(done.future);
    try {
      return await operation();
    } finally {
      pending.remove(done.future);
      done.complete();
    }
  }

  Future<void> settle() async {
    await Future.wait(pending.toList());
  }

  @override
  Future<bool> hasAmbientTransaction() => delegate.hasAmbientTransaction();

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => (delegate as LearningRepository).listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );
  @override
  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T exercise, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    starts.add(exercise);
    final result = await delegate.startNativeExercise(
      exercise,
      stillCurrent: stillCurrent,
    );
    if (loseStart) {
      loseStart = false;
      throw StateError('synthetic lost start ACK');
    }
    return result;
  });
  @override
  Future<AnswerRecordResult> commitNativeAnswer(
    AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    answers.add(command);
    await answerGate?.future;
    final result = await delegate.commitNativeAnswer(
      exercise,
      command,
      stillCurrent: stillCurrent,
    );
    if (loseAnswer) {
      loseAnswer = false;
      throw StateError('synthetic lost answer ACK');
    }
    return result;
  });
  @override
  Future<LearningSessionSummary> finishNativeExercise(
    NativeFinishIntent intent, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    finishes.add(intent);
    final result = await delegate.finishNativeExercise(
      intent,
      stillCurrent: stillCurrent,
    );
    if (loseFinish) {
      loseFinish = false;
      throw StateError('synthetic lost finish ACK');
    }
    return result;
  });
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture f, {
  bool ready = true,
  String language = 'th',
  double scale = 1,
  bool reducedMotion = false,
}) async {
  _resume(tester);
  final owners = f.owners.stream;
  f.language.value = language;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: f.navigator,
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              f.summary = await Navigator.of(context)
                  .push<LearningSessionSummary>(
                    MaterialPageRoute(
                      builder: (_) => ValueListenableBuilder<String>(
                        valueListenable: f.language,
                        builder: (_, code, _) => WordScrambleScreen(
                          session: f.session,
                          learning: f.learning,
                          ownerChanges: owners,
                          languageCode: code,
                        ),
                      ),
                    ),
                  );
            },
            child: const Text('Open Scramble'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Scramble'));
  await tester.pump();
  f.owners.add(configuredOwnerId);
  if (ready) {
    await _ready(tester, f);
  }
}

Future<void> _ready(WidgetTester tester, _Fixture f) async {
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  await _reveal(tester, find.byKey(const ValueKey('scramble-response')));
  await _until(
    tester,
    () =>
        tester
            .widget<TextField>(find.byKey(const ValueKey('scramble-response')))
            .enabled ==
        true,
  );
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await _reveal(tester, target);
  await tester.tap(target.hitTestable());
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String response) async {
  final target = find.byKey(const ValueKey('scramble-response'));
  await _reveal(tester, target);
  await tester.enterText(target, response);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) =>
    _tap(tester, const ValueKey('scramble-save'));
Future<void> _finishReady(WidgetTester tester, _Fixture f) async {
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  await _reveal(tester, find.byKey(const ValueKey('scramble-finish')));
}

Future<void> _retryReady(WidgetTester tester, _Fixture f) async {
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  await _reveal(tester, find.byKey(const ValueKey('scramble-retry')));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Scramble did not reach the expected observable state',
  );
}

void _resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
