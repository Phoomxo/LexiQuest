import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';

import '../support/cloze_session_harness.dart';

void main() {
  for (final variant in ClozeVariant.values) {
    testWidgets(
      'accepted $variant renders one masked gap and finishes actual saved facts',
      (tester) async {
        final f = await _Fixture.open(tester, variant);
        try {
          await _mount(tester, f);
          expect(find.text(f.session.content.sentence), findsNothing);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('cloze-meaning-cue')))
                .data,
            contains(f.session.word.meaning),
          );
          expect(find.byKey(const ValueKey('cloze-feedback')), findsNothing);
          expect(find.textContaining('AI'), findsWidgets);
          expect(await f.count(tester, 'learning_sessions'), 1);
          expect(await f.count(tester, 'answer_attempts'), 0);
          if (variant == ClozeVariant.typed) {
            expect(find.text(f.session.word.spelling), findsNothing);
          } else {
            final exercise = f.session as ChoiceClozeSession;
            for (final word in exercise.choices) {
              expect(
                find.byKey(ValueKey('cloze-option-${word.id}')),
                findsOneWidget,
              );
            }
          }
          f.repository.answerGate = Completer<void>();
          await _answer(tester, f, correct: variant == ClozeVariant.typed);
          await _until(tester, () => f.repository.answers.isNotEmpty);
          expect(find.byKey(const ValueKey('cloze-feedback')), findsNothing);
          expect(await f.count(tester, 'answer_attempts'), 0);
          if (variant == ClozeVariant.typed) {
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('cloze-response')),
                  )
                  .enabled,
              isFalse,
            );
          } else {
            final exercise = f.session as ChoiceClozeSession;
            for (final word in exercise.choices) {
              expect(
                tester
                    .widget<RadioListTile<String>>(
                      find.byKey(ValueKey('cloze-option-${word.id}')),
                    )
                    .enabled,
                isFalse,
              );
            }
          }
          final frozen = f.repository.answers.single;
          f.h.now = f.h.now.add(const Duration(seconds: 3));
          f.repository.answerGate!.complete();
          await tester.runAsync(f.repository.settle);
          await _finishReady(tester, f);
          expect(
            frozen.evidenceContext.evidenceClass.name,
            variant == ClozeVariant.typed ? 'guidedPractice' : 'recognition',
          );
          expect(
            frozen.evidenceContext.hintLevel,
            variant == ClozeVariant.typed ? 1 : 0,
          );
          expect(await f.count(tester, 'srs_states'), 0);
          expect(await f.count(tester, 'points_ledger_entries'), 0);
          await tester.tap(find.byKey(const ValueKey('cloze-finish')));
          await _until(tester, () => f.summary != null);
          expect(f.summary!.state, 'completed');
          expect(
            f.summary!.correctCount,
            variant == ClozeVariant.typed ? 1 : 0,
          );
          expect(f.summary!.wrongCount, variant == ClozeVariant.choice ? 1 : 0);
          expect(await f.count(tester, 'answer_attempts'), 1);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  for (final variant in ClozeVariant.values) {
    testWidgets(
      'owned meaning cue masks whole target in text and semantics ($variant)',
      (tester) async {
        final f = await _Fixture.open(
          tester,
          variant,
          glossContainsSpelling: true,
        );
        final semantics = tester.ensureSemantics();
        try {
          await _mount(tester, f);
          final cue = find.byKey(const ValueKey('cloze-meaning-cue'));
          await tester.ensureVisible(cue);
          await tester.pump();
          expect(cue.hitTestable(), findsOneWidget);
          final text = tester.widget<Text>(cue).data!;
          expect(
            text,
            contains(
              'synthetic gloss _____ / _____ / ${f.session.word.spelling}ary',
            ),
          );
          expect(
            RegExp(
              r'\b' + RegExp.escape(f.session.word.spelling) + r'\b',
              caseSensitive: false,
            ).hasMatch(text),
            isFalse,
          );
          expect(tester.getSemantics(cue).label, text);
          if (variant == ClozeVariant.typed) {
            expect(find.text(f.session.word.spelling), findsNothing);
          }
          expect(find.byKey(const ValueKey('cloze-feedback')), findsNothing);
          f.repository.answerGate = Completer<void>();
          await _answer(tester, f);
          await _until(tester, () => f.repository.answers.isNotEmpty);
          expect(find.byKey(const ValueKey('cloze-feedback')), findsNothing);
          f.repository.answerGate!.complete();
          await _finishReady(tester, f);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('cloze-feedback')))
                .data,
            contains(f.session.word.spelling),
          );
          expect(await f.count(tester, 'answer_attempts'), 1);
        } finally {
          semantics.dispose();
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'lost start save and finish ACKs retain original native handles',
    (tester) async {
      final f = await _Fixture.open(tester, ClozeVariant.typed);
      try {
        f.repository.loseStart = true;
        await _mount(tester, f, ready: false);
        await _retryReady(tester);
        await tester.tap(find.byKey(const ValueKey('cloze-retry')));
        await _ready(tester, f);
        expect(
          identical(f.repository.starts.first, f.repository.starts.last),
          isTrue,
        );
        f.repository.loseAnswer = true;
        await _answer(tester, f);
        await _retryReady(tester);
        await tester.tap(find.byKey(const ValueKey('cloze-retry')));
        await _finishReady(tester, f);
        expect(
          identical(f.repository.answers.first, f.repository.answers.last),
          isTrue,
        );
        f.repository.loseFinish = true;
        await tester.tap(find.byKey(const ValueKey('cloze-finish')));
        await _retryReady(tester);
        f.h.now = f.h.now.add(const Duration(minutes: 1));
        await tester.tap(find.byKey(const ValueKey('cloze-retry')));
        await _until(tester, () => f.summary != null);
        expect(
          identical(f.repository.finishes.first, f.repository.finishes.last),
          isTrue,
        );
        expect(await f.count(tester, 'learning_sessions'), 1);
        expect(await f.count(tester, 'answer_attempts'), 1);
        expect(
          (await tester.runAsync(
            () => f.h.storage.session(f.session.id),
          ))!['ended_at_utc_ms'],
          f.repository.finishes.first.endedAtUtc.millisecondsSinceEpoch,
        );
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final invalidation in [
    'owner ABA',
    'owner error',
    'owner done',
    'covered',
    'paused',
    'disposed',
  ]) {
    testWidgets(
      'pending actual Cloze capture is cancelled after $invalidation',
      (tester) async {
        final f = await _Fixture.open(tester, ClozeVariant.typed);
        try {
          await _mount(tester, f);
          f.repository.answerGate = Completer<void>();
          await _answer(tester, f);
          await _until(tester, () => f.repository.answers.isNotEmpty);
          switch (invalidation) {
            case 'owner ABA':
              await tester.runAsync(
                () => f.h.storage.switchOwner(configuredOtherOwnerId),
              );
              f.owners.add(configuredOtherOwnerId);
              await tester.runAsync(
                () => f.h.storage.switchOwner(configuredOwnerId),
              );
              f.owners.add(configuredOwnerId);
            case 'owner error':
              f.owners.addError(StateError('synthetic owner error'));
            case 'owner done':
              unawaited(f.owners.close());
            case 'covered':
              unawaited(
                f.navigator.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('Other activity')),
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
              expect(tester.binding.framesEnabled, isFalse);
              tester.binding.scheduleForcedFrame();
            case 'disposed':
              await tester.pumpWidget(const SizedBox.shrink());
          }
          await tester.pump();
          f.repository.answerGate!.complete();
          await tester.runAsync(f.repository.settle);
          if (invalidation == 'paused') {
            tester.binding.scheduleForcedFrame();
          }
          await tester.pump();
          expect(await f.count(tester, 'answer_attempts'), 0);
          expect(f.summary, isNull);
          expect(find.byKey(const ValueKey('cloze-feedback')), findsNothing);
          if (invalidation != 'covered') {
            expect(find.byKey(const ValueKey('cloze-response')), findsNothing);
          }
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets('back without save leaves the started session unfinished', (
    tester,
  ) async {
    final f = await _Fixture.open(tester, ClozeVariant.typed);
    try {
      await _mount(tester, f);
      await tester.tap(find.byKey(const ValueKey('cloze-back')));
      await tester.pumpAndSettle();
      expect(f.summary, isNull);
      expect(await f.count(tester, 'answer_attempts'), 0);
      expect(
        (await tester.runAsync(
          () => f.h.storage.session(f.session.id),
        ))!['state'],
        'active',
      );
      expect(f.repository.finishes, isEmpty);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'English 320px 200percent keyboard reaches typed save and finish',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await _Fixture.open(tester, ClozeVariant.typed);
      try {
        await _mount(tester, f, scale: 2, language: 'en');
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await _answer(tester, f);
        await _until(tester, () => f.repository.answers.isNotEmpty);
        await tester.runAsync(f.repository.settle);
        await _finishReady(tester, f);
        await tester.tap(find.byKey(const ValueKey('cloze-finish')));
        await _until(tester, () => f.summary != null);
        expect(tester.takeException(), isNull);
      } finally {
        tester.view.resetViewInsets();
        await f.close(tester);
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.h, this.repository, this.learning, this.session);
  final ClozeSessionHarness h;
  final _AckRepository repository;
  final LearningUseCases learning;
  final ClozeSession session;
  final owners = StreamController<String?>.broadcast(sync: true);
  final navigator = GlobalKey<NavigatorState>();
  LearningSessionSummary? summary;

  static Future<_Fixture> open(
    WidgetTester tester,
    ClozeVariant variant, {
    bool glossContainsSpelling = false,
  }) async {
    final h = (await tester.runAsync(ClozeSessionHarness.open))!;
    if (glossContainsSpelling) {
      await tester.runAsync(
        () => h.database.customStatement(
          "UPDATE vocabulary_words SET meaning = 'synthetic gloss ' || spelling || ' / ' || UPPER(spelling) || ' / ' || spelling || 'ary' WHERE owner_id = ?",
          [configuredOwnerId],
        ),
      );
    }
    final repository = _AckRepository(h.repository);
    var id = 0;
    final learning = LearningUseCases(
      owners: h.storage.owners,
      repository: repository,
      generateId: () => 'cloze-ui-${++id}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'synthetic-ui'),
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

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => h.storage.count(table)))!;
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
}) async {
  _resume(tester);
  final owners = f.owners.stream;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: f.navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              f.summary = await Navigator.of(context)
                  .push<LearningSessionSummary>(
                    MaterialPageRoute(
                      builder: (_) => FillInTheBlanksScreen(
                        session: f.session,
                        learning: f.learning,
                        ownerChanges: owners,
                        languageCode: language,
                      ),
                    ),
                  );
            },
            child: const Text('Open Cloze'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Cloze'));
  await tester.pump();
  f.owners.add(configuredOwnerId);
  if (ready) {
    await _ready(tester, f);
  }
}

Future<void> _ready(WidgetTester tester, _Fixture f) async {
  await _until(
    tester,
    () =>
        find.byType(FillInTheBlanksScreen).evaluate().isNotEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty,
  );
  final answer = f.session is TypedClozeSession
      ? find.byKey(const ValueKey('cloze-response'))
      : find.byKey(ValueKey('cloze-option-${f.session.word.id}'));
  await tester.scrollUntilVisible(
    answer,
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await _until(
    tester,
    () => f.session is TypedClozeSession
        ? tester.widget<TextField>(answer).enabled == true
        : tester.widget<RadioListTile<String>>(answer).enabled == true,
  );
}

Future<void> _answer(
  WidgetTester tester,
  _Fixture f, {
  bool correct = true,
}) async {
  if (f.session is TypedClozeSession) {
    await tester.enterText(
      find.byKey(const ValueKey('cloze-response')),
      correct ? f.session.word.spelling : 'wrong',
    );
  } else {
    final exercise = f.session as ChoiceClozeSession;
    final option = correct
        ? exercise.word
        : exercise.choices.firstWhere((word) => word.id != exercise.word.id);
    await tester.tap(find.byKey(ValueKey('cloze-option-${option.id}')));
  }
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('cloze-save')),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const ValueKey('cloze-save')));
  await tester.pump();
}

Future<void> _finishReady(WidgetTester tester, _Fixture f) async {
  await _until(tester, () => f.repository.answers.isNotEmpty);
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('cloze-finish')),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await _until(
    tester,
    () =>
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('cloze-finish')))
            .onPressed !=
        null,
  );
}

Future<void> _retryReady(WidgetTester tester) => _until(
  tester,
  () => find.byKey(const ValueKey('cloze-retry')).evaluate().isNotEmpty,
);
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
    reason: 'Cloze did not reach the expected observable state',
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
