import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/cloze_session_harness.dart';

void main() {
  for (final replaceContext in [true, false]) {
    testWidgets('Optional time replacement preserves pronunciation source '
        'context=$replaceContext', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = (await tester.runAsync(_Harness.open))!;
      try {
        final start = (await tester.runAsync(
          () => h.base.learning.prepareSourceBoundVoicePracticeStart(
            expectedOwnerId: configuredOwnerId,
            practiceKind: VoiceLearningTimePracticeKind.pronunciation,
            callerContext: LearningTimeCallerContext.ordinary,
            stillCurrent: () => true,
          ),
        ))!;
        final session = (await tester.runAsync(
          () => h.base.learning.startSourceBoundVocabularySession(
            start,
            operationStillCurrent: () => true,
          ),
        ))!;
        final word = session.questions.single.word;
        final voice = VoiceUseCases(h.voice);
        Widget app(bool replaced) => MaterialApp(
          home: SpeakToTextScreen(
            correctWord: word.spelling,
            wordId: word.id,
            sessionId: session.id,
            sourceOwnerId: configuredOwnerId,
            contentRevision: word.contentRevision,
            sourceStart: start,
            learning: h.base.learning,
            voice: voice,
            learningTime: replaced && !replaceContext ? null : h.time,
            learningTimeCallerContext: replaced && replaceContext
                ? LearningTimeCallerContext.researchControlled
                : LearningTimeCallerContext.ordinary,
          ),
        );
        await tester.pumpWidget(app(false));
        await _until(tester, () => h.voice.requests == 1);
        expect(find.text(word.spelling), findsOneWidget);
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        expect(find.text(word.spelling), findsOneWidget);
        expect(await h.count(tester, 'learning_sessions'), 1);
        expect(await h.count(tester, 'answer_attempts'), 0);
        expect(await h.count(tester, 'learning_time_segments'), 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    });
  }

  for (final dictation in [true, false]) {
    for (final replaceContext in [true, false]) {
      testWidgets('Optional time replacement preserves the native draft '
          'dictation=$dictation context=$replaceContext', (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final h = (await tester.runAsync(_Harness.open))!;
        try {
          final exercise = (await tester.runAsync(
            () async => dictation
                ? await h.base.learning.prepareDictation(
                    categoryId: configuredCategoryId,
                    stillCurrent: () => true,
                  )
                : await h.base.prepare(ClozeVariant.typed),
          ))!;
          final voice = VoiceUseCases(h.voice);
          final ownerStream = h.owners.stream;
          Widget app({required bool replaced}) => MaterialApp(
            home: dictation
                ? DictationQuizScreen(
                    session: exercise as DictationSession,
                    learning: h.base.learning,
                    voice: voice,
                    ownerChanges: ownerStream,
                    learningTime: replaced && !replaceContext ? null : h.time,
                    learningTimeCallerContext: replaced && replaceContext
                        ? LearningTimeCallerContext.researchControlled
                        : LearningTimeCallerContext.ordinary,
                  )
                : FillInTheBlanksScreen(
                    session: exercise as ClozeSession,
                    learning: h.base.learning,
                    ownerChanges: ownerStream,
                    learningTime: replaced && !replaceContext ? null : h.time,
                    learningTimeCallerContext: replaced && replaceContext
                        ? LearningTimeCallerContext.researchControlled
                        : LearningTimeCallerContext.ordinary,
                  ),
          );
          await tester.pumpWidget(app(replaced: false));
          h.owners.add(configuredOwnerId);
          final input = find.byKey(
            ValueKey(dictation ? 'dictation-response' : 'cloze-response'),
          );
          await _until(
            tester,
            () =>
                input.evaluate().isNotEmpty &&
                tester.widget<TextField>(input).enabled == true,
          );
          await tester.enterText(input, exercise.word.spelling);
          await tester.pump();
          await _until(tester, () => h.accepting);
          await tester.pumpWidget(app(replaced: true));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(input).controller!.text,
            exercise.word.spelling,
          );
          expect(tester.widget<TextField>(input).enabled, isTrue);
          h.advance(const Duration(seconds: 4));
          final save = find.byKey(
            ValueKey(dictation ? 'dictation-save' : 'cloze-save'),
          );
          await _until(
            tester,
            () => tester.widget<FilledButton>(save).onPressed != null,
          );
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          await tester.ensureVisible(save);
          await _until(tester, () => save.hitTestable().evaluate().isNotEmpty);
          await tester.tap(save.hitTestable());
          final feedback = find.byKey(
            ValueKey(dictation ? 'dictation-feedback' : 'cloze-feedback'),
          );
          await _until(tester, () => feedback.evaluate().isNotEmpty);
          expect(await h.count(tester, 'answer_attempts'), 1);
          await tester.runAsync(h.time.retryPending);
          expect(await h.count(tester, 'learning_time_segments'), 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(h.close);
        }
      });
    }
  }

  testWidgets('An old audio stop ACK cannot admit a newer Dictation playback', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = (await tester.runAsync(_Harness.open))!;
    final oldStop = Completer<void>();
    try {
      final exercise = (await tester.runAsync(
        () => h.base.learning.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(
            session: exercise,
            learning: h.base.learning,
            voice: VoiceUseCases(h.voice),
            ownerChanges: h.owners.stream,
            learningTime: h.time,
            learningTimeCallerContext: LearningTimeCallerContext.ordinary,
          ),
        ),
      );
      h.owners.add(configuredOwnerId);
      final input = find.byKey(const ValueKey('dictation-response'));
      await _until(
        tester,
        () =>
            input.evaluate().isNotEmpty &&
            tester.widget<TextField>(input).enabled == true,
      );
      h.voice.stopGate = oldStop;
      await tester.enterText(input, exercise.word.spelling);
      await _until(tester, () => h.voice.stops == 2);
      final replay = find.byKey(const ValueKey('dictation-normal'));
      await tester.ensureVisible(replay);
      await tester.tap(replay);
      await _until(
        tester,
        () =>
            h.voice.requests == 2 &&
            tester.widget<TextField>(input).enabled == true,
      );
      oldStop.complete();
      await _until(tester, () => h.voice.completedStops == 3);
      await tester.runAsync(() => h.time.read(const OwnerTimeRead()));
      await tester.pumpAndSettle();
      h.advance(const Duration(seconds: 4));
      final save = find.byKey(const ValueKey('dictation-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('dictation-feedback'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.runAsync(h.time.retryPending);
      expect(await h.count(tester, 'learning_time_segments'), 0);
      expect(await h.count(tester, 'answer_attempts'), 1);
      expect(tester.takeException(), isNull);
    } finally {
      if (!oldStop.isCompleted) oldStop.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(h.close);
    }
  });

  for (final dictation in [true, false]) {
    final name = dictation ? 'Dictation' : 'Typed Cloze';
    for (final caller in LearningTimeCallerContext.values) {
      testWidgets(
        '$name records only explicitly ordinary confirmed inputs $caller',
        (tester) async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          final h = (await tester.runAsync(_Harness.open))!;
          try {
            final exercise = await tester.runAsync(
              () async => dictation
                  ? await h.base.learning.prepareDictation(
                      categoryId: configuredCategoryId,
                      stillCurrent: () => true,
                    )
                  : await h.base.prepare(ClozeVariant.typed),
            );
            expect(exercise, isNotNull);
            await tester.pumpWidget(
              MaterialApp(
                home: dictation
                    ? DictationQuizScreen(
                        session: exercise! as DictationSession,
                        learning: h.base.learning,
                        voice: VoiceUseCases(h.voice),
                        ownerChanges: h.owners.stream,
                        learningTime: h.time,
                        learningTimeCallerContext: caller,
                      )
                    : FillInTheBlanksScreen(
                        session: exercise! as ClozeSession,
                        learning: h.base.learning,
                        ownerChanges: h.owners.stream,
                        learningTime: h.time,
                        learningTimeCallerContext: caller,
                      ),
              ),
            );
            h.owners.add(configuredOwnerId);
            final input = find.byKey(
              ValueKey(dictation ? 'dictation-response' : 'cloze-response'),
            );
            await _until(
              tester,
              () =>
                  input.evaluate().isNotEmpty &&
                  tester.widget<TextField>(input).enabled == true,
            );
            if (!dictation && caller == LearningTimeCallerContext.ordinary) {
              await _until(
                tester,
                () =>
                    h.time.liveLease != null &&
                    h.time.acceptsInteraction(h.time.liveLease!),
              );
            }
            expect(await h.count(tester, 'learning_time_scopes'), 0);
            expect(await h.count(tester, 'learning_time_segments'), 0);
            h.advance(const Duration(seconds: 3));
            await tester.ensureVisible(input);
            await tester.enterText(input, exercise.word.spelling);
            await tester.pump();
            if (dictation && caller == LearningTimeCallerContext.ordinary) {
              await _until(tester, () => h.accepting);
            }
            h.advance(const Duration(seconds: 2));
            final save = find.byKey(
              ValueKey(dictation ? 'dictation-save' : 'cloze-save'),
            );
            await _until(
              tester,
              () => tester.widget<FilledButton>(save).onPressed != null,
            );
            await tester.ensureVisible(save);
            await tester.pumpAndSettle();
            await tester.tap(save);
            final feedback = find.byKey(
              ValueKey(dictation ? 'dictation-feedback' : 'cloze-feedback'),
            );
            await _until(tester, () => feedback.evaluate().isNotEmpty);
            await tester.runAsync(h.time.retryPending);
            final read = await tester.runAsync(
              () => h.time.read(const OwnerTimeRead()),
            );
            expect(
              read!.activeDurationUs,
              caller == LearningTimeCallerContext.ordinary
                  ? dictation
                        ? 2000000
                        : 5000000
                  : 0,
            );
            expect(await h.count(tester, 'answer_attempts'), 1);
            expect(await h.count(tester, 'events_v2'), 0);
            expect(await h.count(tester, 'research_consents'), 0);
            expect(await h.count(tester, 'points_ledger_entries'), 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await tester.runAsync(h.close);
          }
        },
      );
    }
  }

  testWidgets('Dictation does not count reference audio or its terminal tail', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = (await tester.runAsync(_Harness.open))!;
    try {
      final exercise = (await tester.runAsync(
        () => h.base.learning.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ),
      ))!;
      h.voice.gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(
            session: exercise,
            learning: h.base.learning,
            voice: VoiceUseCases(h.voice),
            ownerChanges: h.owners.stream,
            learningTime: h.time,
            learningTimeCallerContext: LearningTimeCallerContext.ordinary,
          ),
        ),
      );
      h.owners.add(configuredOwnerId);
      await _until(tester, () => h.voice.requests == 1);
      h.advance(const Duration(seconds: 45));
      expect(h.time.liveLease, isNull);
      h.voice.gate!.complete();
      final input = find.byKey(const ValueKey('dictation-response'));
      await _until(
        tester,
        () =>
            input.evaluate().isNotEmpty &&
            tester.widget<TextField>(input).enabled == true,
      );
      expect(h.time.liveLease, isNull);
      h.advance(const Duration(seconds: 2));
      await tester.ensureVisible(input);
      await tester.enterText(input, exercise.word.spelling);
      await _until(tester, () => h.accepting);
      expect(h.voice.stops, 2);
      h.advance(const Duration(seconds: 3));
      await tester.enterText(input, '${exercise.word.spelling}x');
      await tester.pump();
      h.advance(const Duration(seconds: 20));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(h.time.retryPending);
      final read = await tester.runAsync(
        () => h.time.read(const OwnerTimeRead()),
      );
      expect(read!.activeDurationUs, 3000000);
      expect(await h.count(tester, 'answer_attempts'), 0);
    } finally {
      if (h.voice.gate case final gate? when !gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(h.close);
    }
  });

  for (final external in [false, true]) {
    testWidgets('Shadowing records only actual local prompt before playback '
        'external=$external', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = (await tester.runAsync(_Harness.open))!;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ShadowingChallengeScreen(
              referenceSentence: external ? 'Synthetic external prompt' : null,
              voice: VoiceUseCases(h.voice),
              learning: h.base.learning,
              learningTime: h.time,
              learningTimeCallerContext: LearningTimeCallerContext.ordinary,
            ),
          ),
        );
        final play = find.byKey(const ValueKey('shadowing-play-reference'));
        await _until(
          tester,
          () =>
              play.evaluate().isNotEmpty &&
              tester.widget<OutlinedButton>(play).onPressed != null,
        );
        if (!external) await _until(tester, () => h.accepting);
        expect(await h.count(tester, 'learning_time_scopes'), 0);
        h.advance(const Duration(seconds: 3));
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(h.voice.requests, 1);
        h.advance(const Duration(seconds: 20));
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(h.voice.requests, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(h.time.retryPending);
        final read = await tester.runAsync(
          () => h.time.read(const OwnerTimeRead()),
        );
        expect(read!.activeDurationUs, external ? 0 : 3000000);
        expect(await h.count(tester, 'learning_sessions'), external ? 0 : 1);
        expect(await h.count(tester, 'answer_attempts'), 0);
        expect(await h.count(tester, 'events_v2'), 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    });
  }
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

final class _Harness {
  _Harness(this.base) {
    time = LearningTimeUseCases(
      repository: DriftLearningTimeRepository(
        database: base.database,
        ownerWrites: base.storage.ownerWrites,
        learning: base.repository,
      ),
      ownerChanges: owners.stream,
      monotonicMicros: () => micros,
      nowUtc: () => base.now,
      generateId: () => 'synthetic-native-time-${++sequence}',
    );
  }
  final ClozeSessionHarness base;
  final owners = StreamController<String?>.broadcast(sync: true);
  final voice = _Voice();
  late final LearningTimeUseCases time;
  int micros = 0;
  int sequence = 0;
  bool get accepting =>
      time.liveLease != null && time.acceptsInteraction(time.liveLease!);

  static Future<_Harness> open() async {
    final h = _Harness(await ClozeSessionHarness.open());
    h.owners.add(configuredOwnerId);
    await h.time.changes
        .firstWhere((_) => h.time.preference != null)
        .timeout(const Duration(seconds: 5));
    final preference = await h.time.setEnabled(
      true,
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    expect(preference?.enabled, isTrue);
    return h;
  }

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
    base.now = base.now.add(duration);
  }

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => base.storage.count(table)))!;
  Future<void> close() async {
    await time.retryPending();
    await time.dispose();
    await owners.close();
    await base.close();
  }
}

final class _Voice implements VoiceProvider {
  Completer<void>? gate;
  Completer<void>? stopGate;
  int requests = 0;
  int stops = 0;
  int completedStops = 0;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests++;
    await gate?.future;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    final pending = stopGate;
    stopGate = null;
    await pending?.future;
    completedStops++;
  }
}
