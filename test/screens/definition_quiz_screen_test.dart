import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../support/authored_lexical_pack.dart';
import '../support/configured_quiz_harness.dart';
import '../support/progress_owner_fixture.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  for (final input in LexicalQuizInput.values) {
    testWidgets(
      '$input uses authored content and canonical feedback at 320px 200 percent',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = (await tester.runAsync(() => _Fixture.open(input)))!;
        addTearDown(() => _close(tester, fixture));
        final question = fixture.launch.preparedPlan!.questions.first;
        await tester.pumpWidget(
          _app(
            fixture,
            QuizScreen(
              learning: fixture.learning,
              preparedLaunch: fixture.launch,
              expectedOwnerId: configuredOwnerId,
              ownerChanges: fixture.ownerChanges,
            ),
          ),
        );
        await _wait(
          tester,
          () => find.text(question.prompt).evaluate().isNotEmpty,
        );
        expect(
          find.byKey(const ValueKey('definition-contrastive-explanation')),
          findsNothing,
        );
        if (input == LexicalQuizInput.definitionTyped) {
          final field = find.byKey(const ValueKey('definition-response'));
          await tester.ensureVisible(field);
          await tester.enterText(field, question.correctAnswer);
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: question.correctAnswer,
              selection: TextSelection.collapsed(
                offset: question.correctAnswer.length,
              ),
              composing: TextRange(
                start: 0,
                end: question.correctAnswer.length,
              ),
            ),
          );
          await tester.pump();
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('definition-submit')),
                )
                .onPressed,
            isNull,
          );
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: question.correctAnswer,
              selection: TextSelection.collapsed(
                offset: question.correctAnswer.length,
              ),
            ),
          );
          await tester.pump();
          await _tap(
            tester,
            find.byKey(const ValueKey('definition-save-draft')),
          );
          await _wait(
            tester,
            () => find
                .text('เก็บร่างแล้ว ยังไม่บันทึกคำตอบ')
                .evaluate()
                .isNotEmpty,
          );
          expect(
            await tester.runAsync(() => fixture.h.count('answer_attempts')),
            0,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pumpWidget(
            _app(
              fixture,
              QuizScreen(
                learning: fixture.learning,
                resumeSessionId: fixture.launch.session.id,
                expectedOwnerId: configuredOwnerId,
                ownerChanges: fixture.ownerChanges,
              ),
            ),
          );
          await _wait(tester, () => field.evaluate().isNotEmpty);
          expect(
            tester.widget<TextField>(field).controller!.text,
            question.correctAnswer,
          );
          await _tap(tester, find.byKey(const ValueKey('definition-submit')));
          await _wait(tester, () => find.text('ถูกต้อง').evaluate().isNotEmpty);
        } else {
          final wrong = question.options.firstWhere(
            (value) => value != question.correctAnswer,
          );
          await _tap(tester, find.widgetWithText(FilledButton, wrong));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('definition-contrastive-explanation'))
                .evaluate()
                .isNotEmpty,
          );
          final content = question.lexical! as DefinitionChoiceContent;
          expect(
            find.text(
              content.authoredOptions
                  .firstWhere((option) => option.pin.entry.spelling == wrong)
                  .contrastiveExplanation!,
            ),
            findsOneWidget,
          );
        }
        expect(
          await tester.runAsync(() => fixture.h.count('answer_attempts')),
          1,
        );
        final progress = await tester.runAsync(
          () => DriftProgressQueries(
            fixture.h.database,
          ).load(ownerId: configuredOwnerId, nowUtc: fixture.h.now),
        );
        final retention = progress!.skills.singleWhere(
          (skill) => skill.key == 'retention',
        );
        expect(
          retention.sampleSize,
          input == LexicalQuizInput.definitionTyped ? 1 : 0,
        );
        expect(
          retention.accuracy,
          input == LexicalQuizInput.definitionTyped ? 1 : null,
        );
        expect(
          (await tester.runAsync(fixture.h.researchCounts))!.values,
          everyElement(0),
        );
        await _tap(tester, find.text('ดูผลการเรียน'));
        await _wait(
          tester,
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        final result = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        expect(
          result.correctAnswers,
          input == LexicalQuizInput.definitionTyped ? 1 : 0,
        );
        expect(
          result.wrongAnswers,
          input == LexicalQuizInput.definitionTyped ? 0 : 1,
        );
        expect(
          await tester.runAsync(() => fixture.h.count('answer_attempts')),
          1,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'manual feedback audio starts only after the answer ACK and retires on exit',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _Fixture.open(
          LexicalQuizInput.definitionChoice,
          feedbackAudio: true,
        ),
      ))!;
      addTearDown(() => _close(tester, fixture));
      final voice = _FeedbackVoice();
      final question = fixture.launch.preparedPlan!.questions.first;
      await tester.pumpWidget(
        _app(
          fixture,
          QuizScreen(
            learning: fixture.learning,
            preparedLaunch: fixture.launch,
            expectedOwnerId: configuredOwnerId,
            ownerChanges: fixture.ownerChanges,
            voice: VoiceUseCases(voice),
          ),
          systemReduceMotion: false,
        ),
      );
      await _wait(
        tester,
        () => find.text(question.prompt).evaluate().isNotEmpty,
      );
      expect(voice.requests, isEmpty);
      final audio = find.byKey(const ValueKey('definition-feedback-audio'));
      expect(audio, findsNothing);
      await _tap(
        tester,
        find.widgetWithText(FilledButton, question.correctAnswer),
      );
      await _wait(tester, () => find.text('ถูกต้อง').evaluate().isNotEmpty);
      final before = await tester.runAsync(fixture.h.snapshot);
      await _tap(tester, audio);
      await _wait(tester, () => voice.requests.length == 1);
      expect(voice.requests.single.text, question.correctAnswer);
      expect(tester.getSize(audio).height, greaterThanOrEqualTo(64));
      expect(MediaQuery.disableAnimationsOf(tester.element(audio)), isTrue);
      expect(await tester.runAsync(fixture.h.snapshot), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(voice.stops, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  _Fixture fixture,
  Widget screen, {
  bool systemReduceMotion = true,
}) => MaterialApp(
  theme: M3Theme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(2),
      disableAnimations: systemReduceMotion,
    ),
    child: child!,
  ),
  home: screen,
);

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 160; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (ready()) return;
  }
  fail('Definition lesson did not reach its expected visible state.');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 16));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 16));
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _close(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  Object? error;
  await tester.runAsync(() async {
    unawaited(
      fixture.close().then<void>(
        (_) => closed = true,
        onError: (Object failure) {
          error = failure;
          closed = true;
        },
      ),
    );
  });
  await _wait(tester, () => closed);
  if (error != null) throw error!;
}

final class _Fixture {
  _Fixture(this.h);
  final ConfiguredQuizHarness h;
  late final LearningPackUseCases packs;
  late final LearningUseCases learning;
  late final ConfiguredQuizLaunch launch;
  final ownerChanges = persistentProgressOwnerFixture(configuredOwnerId);
  static Future<_Fixture> open(
    LexicalQuizInput input, {
    bool feedbackAudio = false,
  }) async {
    final fixture = _Fixture(await ConfiguredQuizHarness.open());
    var ids = 0;
    final reader = DriftLearningPackRepository(
      database: fixture.h.database,
      ownerWrites: fixture.h.ownerWrites,
    );
    fixture.packs = LearningPackUseCases(
      repository: reader,
      nowUtc: () => fixture.h.now,
      generateId: () => 'synthetic-definition-ui-${++ids}',
    );
    final scope = await fixture.packs.captureOwner(stillCurrent: () => true);
    final pack = await fixture.packs.importPack(
      fixture.packs.prepareImport(scope: scope!, pack: authoredLexicalPack()),
    );
    fixture.learning = LearningUseCases(
      owners: fixture.h.owners,
      repository: DriftLearningRepository(
        fixture.h.database,
        ownerWrites: fixture.h.ownerWrites,
        lexicalContent: reader,
      ),
      generateId: () => 'synthetic-definition-ui-${++ids}',
      nowUtc: () => fixture.h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-ui',
        buildId: 'synthetic-ui',
      ),
    );
    fixture.launch = await fixture.learning.prepareLexicalQuiz(
      expectedOwnerId: configuredOwnerId,
      packVersionId: pack.id,
      entryCodes: const ['cat', 'dog'],
      input: input,
      limit: 1,
      settings: LexicalQuizSettings(
        manualAudio: feedbackAudio,
        accessibleInput: feedbackAudio,
        reduceMotion: feedbackAudio,
      ),
      stillCurrent: () => true,
    );
    return fixture;
  }

  Future<void> close() async {
    await packs.dispose();
    await h.close();
  }
}

final class _FeedbackVoice implements VoiceProvider {
  final requests = <VoiceRequest>[];
  int stops = 0;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
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
  }
}
