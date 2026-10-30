import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/widgets/handwriting_scratchpad.dart';

import '../support/cloze_session_harness.dart';

const _toggle = ValueKey('scratchpad-toggle');
const _canvas = ValueKey('scratchpad-canvas');
const _undo = ValueKey('scratchpad-undo');
const _clear = ValueKey('scratchpad-clear');
const _status = ValueKey('scratchpad-status');
const _input = ValueKey('cloze-response');
const _save = ValueKey('cloze-save');
const _finish = ValueKey('cloze-finish');
const _retry = ValueKey('cloze-retry');

void main() {
  testWidgets(
    'existing Typed Cloze survives direct owner invalidation during a frame',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _type(tester, 'SYNTHETIC_PRIVATE_TYPED_DRAFT');
        final submitted = tester
            .widget<TextField>(find.byKey(_input))
            .onSubmitted!;
        final before = await f.snapshot(tester);
        SchedulerPhase? observed;
        f.frameHook = () {
          observed = SchedulerBinding.instance.schedulerPhase;
          f.owners.add(null);
          f.owners.add(configuredOwnerId);
        };
        f.frameVersion.value++;
        await tester.pump();
        await tester.pump();
        expect(observed, SchedulerPhase.persistentCallbacks);
        expect(tester.takeException(), isNull);
        expect(find.byKey(_input, skipOffstage: false), findsNothing);
        expect(
          find.textContaining(
            'SYNTHETIC_PRIVATE_TYPED_DRAFT',
            skipOffstage: false,
          ),
          findsNothing,
        );
        submitted('SYNTHETIC_PRIVATE_TYPED_DRAFT');
        await tester.pump();
        await _settle(tester, f);
        expect(f.repository.answers, isEmpty);
        expect(await f.snapshot(tester), before);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'Typed Cloze ink is optional, ephemeral and cannot enable its text writer',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _reveal(tester, find.byKey(_toggle));
        expect(find.byKey(_canvas), findsNothing);
        final before = await f.snapshot(tester);
        await _expand(tester);
        _expectInk(tester, 0);
        await _stroke(tester);
        _expectInk(tester, 1);
        await _reveal(tester, find.byKey(_save));
        expect(
          tester.widget<FilledButton>(find.byKey(_save)).onPressed,
          isNull,
        );
        expect(f.repository.answers, isEmpty);
        expect(await f.snapshot(tester), before);

        await _type(tester, f.session.word.spelling);
        await _stroke(tester);
        _expectInk(tester, 2);
        await _tap(tester, _undo);
        _expectInk(tester, 1);
        await _tap(tester, _clear);
        _expectInk(tester, 0);
        await _reveal(tester, find.byKey(_input));
        expect(
          tester.widget<TextField>(find.byKey(_input)).controller!.text,
          f.session.word.spelling,
        );
        expect(f.repository.answers, isEmpty);
        expect(await f.snapshot(tester), before);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'Typed Cloze freezes ink at Save and compares it only after the real typed ACK',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _expand(tester);
        await _stroke(tester);
        final canEdit = _liveCanEdit(tester, f.session);
        await _reveal(tester, find.byKey(_undo));
        final retainedUndo = tester
            .widget<ButtonStyleButton>(find.byKey(_undo))
            .onPressed!;
        await _reveal(tester, find.byKey(_clear));
        final retainedClear = tester
            .widget<ButtonStyleButton>(find.byKey(_clear))
            .onPressed!;
        await _type(tester, f.session.word.spelling);
        f.repository.answerGate = Completer<void>();
        await _tap(tester, _save);
        await _until(tester, () => f.repository.answers.isNotEmpty);
        expect(canEdit(), isFalse);
        expect(find.byKey(const ValueKey('cloze-feedback')), findsNothing);
        expect(await f.count(tester, 'answer_attempts'), 0);
        retainedUndo();
        retainedClear();
        await _stroke(tester);
        _expectInk(tester, 1);
        f.repository.answerGate!.complete();
        await _saved(tester, f);
        await _reveal(tester, find.byKey(_status));
        _expectInk(tester, 1);
        expect(_statusText(tester).toLowerCase(), contains('read-only'));
        expect(canEdit(), isFalse);
        await _reveal(tester, find.byKey(const ValueKey('cloze-feedback')));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('cloze-feedback')))
              .data,
          contains(f.session.word.spelling),
        );
        expect(
          find.textContaining(
            RegExp(
              r'(typed.*(checked|scored)|(checks|scores).*typed)',
              caseSensitive: false,
            ),
          ),
          findsWidgets,
        );
        await _assertCanonical(tester, f);
        await _tap(tester, _finish);
        await _until(tester, () => f.summary != null);
        expect(f.summary!.correctCount, 1);
        expect(f.summary!.wrongCount, 0);
        expect(f.summary!.score, 100);
        await _assertCanonical(tester, f);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'ink survives lost typed Save and Finish ACKs without another command or wire fact',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _expand(tester);
        await _stroke(tester);
        await _type(tester, f.session.word.spelling);
        f.repository.loseAnswer = true;
        await _tap(tester, _save);
        await _settle(tester, f);
        await _reveal(tester, find.byKey(_retry));
        await _reveal(tester, find.byKey(_status));
        _expectInk(tester, 1);
        expect(_liveCanEdit(tester, f.session)(), isFalse);
        final saved = await f.snapshot(tester);
        f.h.now = f.h.now.add(const Duration(seconds: 9));
        await _tap(tester, _retry);
        await _saved(tester, f);
        expect(
          identical(f.repository.answers.first, f.repository.answers.last),
          isTrue,
        );
        expect(await f.snapshot(tester), saved);
        f.repository.loseFinish = true;
        await _tap(tester, _finish);
        await _settle(tester, f);
        await _reveal(tester, find.byKey(_retry));
        await _reveal(tester, find.byKey(_status));
        _expectInk(tester, 1);
        final completed = await f.snapshot(tester);
        f.h.now = f.h.now.add(const Duration(minutes: 1));
        await _tap(tester, _retry);
        await _until(tester, () => f.summary != null);
        expect(
          identical(f.repository.finishes.first, f.repository.finishes.last),
          isTrue,
        );
        expect(await f.snapshot(tester), completed);
        await _assertCanonical(tester, f);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final loss in [
    'null',
    'aba',
    'error',
    'done',
    'route',
    'paused',
    'hidden',
    'learning',
    'session',
  ]) {
    testWidgets(
      'Typed Cloze removes old-owner ink and denies retained input after $loss',
      (tester) async {
        final f = await _Fixture.open(tester);
        try {
          await _mount(tester, f);
          await _expand(tester);
          await _stroke(tester);
          await _type(tester, 'SYNTHETIC_PRIVATE_INK_OWNER');
          final canEdit = _liveCanEdit(tester, f.session);
          final submitted = tester
              .widget<TextField>(find.byKey(_input))
              .onSubmitted!;
          final before = await f.snapshot(tester);
          await _lose(tester, f, loss);
          expect(canEdit(), isFalse);
          submitted('SYNTHETIC_PRIVATE_INK_OWNER');
          if (loss == 'paused') tester.binding.scheduleForcedFrame();
          await tester.pump();
          await _settle(tester, f);
          expect(tester.takeException(), isNull);
          expect(find.byKey(_toggle, skipOffstage: false), findsNothing);
          expect(find.byKey(_canvas, skipOffstage: false), findsNothing);
          expect(find.byKey(_input, skipOffstage: false), findsNothing);
          expect(
            find.textContaining(
              'SYNTHETIC_PRIVATE_INK_OWNER',
              skipOffstage: false,
            ),
            findsNothing,
          );
          expect(f.repository.answers, isEmpty);
          expect(await f.snapshot(tester), before);
          if (loss == 'route') {
            f.navigator.currentState!.pop();
            await tester.pumpAndSettle();
            expect(find.byKey(_toggle), findsNothing);
            expect(find.byKey(_input), findsNothing);
          }
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'a new accepted Typed Cloze attempt starts collapsed with no previous ink',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _expand(tester);
        await _stroke(tester);
        await _type(tester, f.session.word.spelling);
        await _tap(tester, _save);
        await _saved(tester, f);
        await _tap(tester, _finish);
        await _until(tester, () => f.summary != null);
        await tester.pumpAndSettle();
        f.session = (await tester.runAsync<ClozeSession?>(
          () => f.learning.prepareCloze(
            categoryId: configuredCategoryId,
            variant: ClozeVariant.typed,
            stillCurrent: () => true,
          ),
        ))!;
        await _open(tester, f);
        await _reveal(tester, find.byKey(_toggle));
        expect(find.byKey(_canvas), findsNothing);
        await _expand(tester);
        _expectInk(tester, 0);
        expect(await f.count(tester, 'learning_sessions'), 2);
        expect(await f.count(tester, 'answer_attempts'), 1);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language Typed Cloze scratchpad and keyboard writer remain reachable at320px200percent with actual IME',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final f = await _Fixture.open(tester);
        try {
          await _mount(tester, f, language: language, scale: 2);
          await _expand(tester);
          await _stroke(tester);
          await _type(tester, f.session.word.spelling);
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await tester.pump();
          await tester.pumpAndSettle();
          await _reveal(tester, find.byKey(_save));
          final saveLabel = find
              .descendant(of: find.byKey(_save), matching: find.byType(Text))
              .first;
          for (
            var i = 0;
            i < 16 && !Focus.of(tester.element(saveLabel)).hasFocus;
            i++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(Focus.of(tester.element(saveLabel)).hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _saved(tester, f);
          await _reveal(tester, find.byKey(_finish));
          expect(find.byKey(_finish).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tap(tester, _finish);
          await _until(tester, () => f.summary != null);
          await _assertCanonical(tester, f);
        } finally {
          tester.view.resetViewInsets();
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'Choice Cloze keeps its existing choice writer and exposes no scratchpad',
    (tester) async {
      final f = await _Fixture.open(tester, variant: ClozeVariant.choice);
      try {
        await _mount(tester, f);
        expect(find.byKey(_toggle), findsNothing);
        expect(find.byKey(_canvas), findsNothing);
        expect(find.byKey(_input), findsNothing);
        await _tap(tester, ValueKey('cloze-option-${f.session.word.id}'));
        await _tap(tester, _save);
        await _saved(tester, f);
        await _tap(tester, _finish);
        await _until(tester, () => f.summary != null);
        await _assertCanonical(tester, f);
        expect(f.repository.answers.single.promptMode, 'clozeChoice');
      } finally {
        await f.close(tester);
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.h, this.repository, this.learning, this.session);
  final ClozeSessionHarness h;
  final _AckRepository repository;
  LearningUseCases learning;
  ClozeSession session;
  final owners = StreamController<String?>.broadcast(sync: true);
  late final ownerSource = owners.stream;
  final navigator = GlobalKey<NavigatorState>();
  final frameVersion = ValueNotifier<int>(0);
  final hostVersion = ValueNotifier<int>(0);
  final visible = ValueNotifier<bool>(true);
  VoidCallback? frameHook;
  LearningSessionSummary? summary;

  static Future<_Fixture> open(
    WidgetTester tester, {
    ClozeVariant variant = ClozeVariant.typed,
  }) async {
    final h = (await tester.runAsync(ClozeSessionHarness.open))!;
    final repository = _AckRepository(h.repository);
    var id = 0;
    final learning = LearningUseCases(
      owners: h.storage.owners,
      repository: repository,
      generateId: () => 'synthetic-scratchpad-${++id}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: '1.0.0',
        buildId: 'synthetic-scratchpad',
      ),
      contentProvider: h.provider,
    );
    final session = await tester.runAsync(
      () => learning.prepareCloze(
        categoryId: configuredCategoryId,
        variant: variant,
        stillCurrent: () => true,
      ),
    );
    return _Fixture(h, repository, learning, session!);
  }

  Future<Map<String, List<String>>> snapshot(WidgetTester tester) async =>
      (await tester.runAsync(h.storage.snapshot))!;
  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => h.storage.count(table)))!;
  Future<void> close(WidgetTester tester) async {
    if (repository.answerGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    _resume(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _settle(tester, this);
    if (!owners.isClosed) {
      await tester.runAsync(
        () => owners.close().timeout(const Duration(seconds: 3)),
      );
    }
    await tester.runAsync(() => h.close().timeout(const Duration(seconds: 3)));
    frameVersion.dispose();
    hostVersion.dispose();
    visible.dispose();
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
  Completer<void>? answerGate;
  bool loseAnswer = false;
  bool loseFinish = false;

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
    return delegate.startNativeExercise(exercise, stillCurrent: stillCurrent);
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
      throw StateError('synthetic lost typed answer ACK');
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
      throw StateError('synthetic lost typed finish ACK');
    }
    return result;
  });
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture f, {
  String language = 'en',
  double scale = 1,
}) async {
  _resume(tester);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: f.navigator,
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Stack(
          children: [
            child!,
            Positioned(
              top: 0,
              left: 0,
              child: ValueListenableBuilder<int>(
                valueListenable: f.frameVersion,
                builder: (_, _, _) {
                  final hook = f.frameHook;
                  f.frameHook = null;
                  hook?.call();
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              f.summary = await Navigator.of(context)
                  .push<LearningSessionSummary>(
                    MaterialPageRoute<LearningSessionSummary>(
                      builder: (_) => ValueListenableBuilder<int>(
                        valueListenable: f.hostVersion,
                        builder: (_, _, _) => ValueListenableBuilder<bool>(
                          valueListenable: f.visible,
                          builder: (_, visible, _) => Visibility(
                            visible: visible,
                            maintainState: true,
                            child: FillInTheBlanksScreen(
                              session: f.session,
                              learning: f.learning,
                              ownerChanges: f.ownerSource,
                              languageCode: language,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
            },
            child: const Text('Open real Cloze'),
          ),
        ),
      ),
    ),
  );
  await _open(tester, f);
}

Future<void> _open(WidgetTester tester, _Fixture f) async {
  await tester.tap(find.text('Open real Cloze'));
  await tester.pump();
  f.owners.add(configuredOwnerId);
  await _until(
    tester,
    () =>
        find.byType(FillInTheBlanksScreen).evaluate().isNotEmpty &&
        ModalRoute.of(
              tester.element(find.byType(FillInTheBlanksScreen)),
            )?.animation?.status ==
            AnimationStatus.completed,
  );
  await _until(tester, () => f.repository.starts.isNotEmpty);
  await _settle(tester, f);
  final answer = f.session is TypedClozeSession
      ? find.byKey(_input)
      : find.byKey(ValueKey('cloze-option-${f.session.word.id}'));
  await _reveal(tester, answer);
  await _until(
    tester,
    () => f.session is TypedClozeSession
        ? tester.widget<TextField>(answer).enabled == true
        : tester.widget<RadioListTile<String>>(answer).enabled == true,
  );
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.pump();
  final scrollable = find
      .descendant(
        of: find.byType(FillInTheBlanksScreen),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  if (target.evaluate().isEmpty) {
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    for (var index = 0; index < 200 && target.evaluate().isEmpty; index++) {
      final bounds = tester.getRect(scrollable);
      await tester.dragFrom(
        Offset(bounds.left + 8, bounds.center.dy),
        const Offset(0, -120),
      );
      position.jumpTo(position.pixels);
      await tester.pump();
    }
  }
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: .35);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await _reveal(tester, target);
  await tester.tap(target.hitTestable());
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await _reveal(tester, find.byKey(_input));
  await tester.enterText(find.byKey(_input), text);
  await tester.pump();
}

Future<void> _expand(WidgetTester tester) async {
  await _tap(tester, _toggle);
  await _reveal(tester, find.byKey(_canvas));
}

Future<void> _stroke(WidgetTester tester) async {
  final canvas = find.byKey(_canvas);
  await _reveal(tester, canvas);
  final rect = tester.getRect(canvas);
  final gesture = await tester.startGesture(
    rect.topLeft + Offset(rect.width * .25, rect.height * .35),
  );
  await gesture.moveTo(
    rect.topLeft + Offset(rect.width * .55, rect.height * .6),
  );
  await gesture.up();
  await tester.pump();
}

String _statusText(WidgetTester tester) => find
    .descendant(
      of: find.byKey(_status),
      matching: find.byType(Text),
      matchRoot: true,
    )
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .join(' ');
void _expectInk(WidgetTester tester, int count) {
  expect(find.byKey(_status), findsOneWidget);
  expect(
    _statusText(tester),
    count == 0 ? contains('No strokes') : contains('$count stroke'),
  );
}

bool Function() _liveCanEdit(WidgetTester tester, ClozeSession session) =>
    tester
        .widget<HandwritingScratchpad>(find.byKey(ObjectKey(session)))
        .canEdit;
Future<void> _saved(WidgetTester tester, _Fixture f) async {
  await _until(tester, () => f.repository.answers.isNotEmpty);
  await _settle(tester, f);
  await _reveal(tester, find.byKey(_finish));
  await _until(
    tester,
    () => tester.widget<FilledButton>(find.byKey(_finish)).onPressed != null,
  );
}

Future<void> _settle(WidgetTester tester, _Fixture f) async {
  await tester.runAsync(
    () => f.repository.settle().timeout(const Duration(seconds: 3)),
  );
  await tester.pump();
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
    reason: 'Real Cloze did not reach the expected observable state',
  );
}

Future<void> _lose(WidgetTester tester, _Fixture f, String loss) async {
  switch (loss) {
    case 'null':
      f.owners.add(null);
      f.owners.add(configuredOwnerId);
    case 'aba':
      await tester.runAsync(
        () => f.h.storage.switchOwner(configuredOtherOwnerId),
      );
      f.owners.add(configuredOtherOwnerId);
      await tester.runAsync(() => f.h.storage.switchOwner(configuredOwnerId));
      f.owners.add(configuredOwnerId);
    case 'error':
      f.owners.addError(StateError('SYNTHETIC_PRIVATE_OWNER_ERROR'));
    case 'done':
      await tester.runAsync(f.owners.close);
    case 'route':
      unawaited(
        f.navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Synthetic other route')),
          ),
        ),
      );
    case 'paused':
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      tester.binding.scheduleForcedFrame();
    case 'hidden':
      f.visible.value = false;
    case 'learning':
      f.learning = f.h.useCases();
      f.hostVersion.value++;
    case 'session':
      f.session = (await tester.runAsync<ClozeSession?>(
        () => f.learning.prepareCloze(
          categoryId: configuredCategoryId,
          variant: ClozeVariant.typed,
          stillCurrent: () => true,
        ),
      ))!;
      f.hostVersion.value++;
  }
  await tester.pump();
  if (loss != 'paused') await tester.pumpAndSettle();
}

Future<void> _assertCanonical(WidgetTester tester, _Fixture f) async {
  final snapshot = await f.snapshot(tester);
  expect(snapshot['answer_attempts'], hasLength(1));
  expect(snapshot['outbox_operations'], hasLength(1));
  final attempt = jsonDecode(snapshot['answer_attempts']!.single) as Map;
  final typed = f.session is TypedClozeSession;
  expect(attempt['session_id'], f.session.id);
  expect(attempt['word_id'], f.session.word.id);
  expect(attempt['prompt_mode'], typed ? 'clozeTyped' : 'clozeChoice');
  expect(attempt['evidence_class'], typed ? 'guidedPractice' : 'recognition');
  final context = jsonDecode(attempt['evidence_context_json'] as String);
  expect(
    context,
    captureCurrentActivityEvidence(
      promptMode: typed ? 'clozeTyped' : 'clozeChoice',
      contentRevision: f.session.evidenceContentRevision,
    ).toJson(),
  );
  expect(attempt['provider_provenance'], f.session.providerProvenance);
  final operation = jsonDecode(snapshot['outbox_operations']!.single) as Map;
  expect(operation['entity_type'], 'attempt');
  expect(operation['entity_id'], attempt['id']);
  expect(operation['payload_version'], 2);
  for (final table in [
    'srs_states',
    'points_ledger_entries',
    'reward_transactions',
    'achievement_unlocks',
    'quest_instances',
    'quest_objective_progress',
    'streak_states',
    'research_consents',
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
    'assessment_runs',
    'events_v2',
  ]) {
    expect(snapshot[table], isEmpty, reason: table);
  }
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
