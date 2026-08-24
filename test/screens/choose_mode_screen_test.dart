import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/flashcard_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/learning_time_capture_rollout.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/definition_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'shows only canonical production modes and does not navigate without an adapter',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('home/learn/associative-reading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home/learn/srs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home/learn/quiz/definition')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
        findsOneWidget,
      );
      expect(find.byType(ListTile), findsNWidgets(5));

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(ChooseModeScreen))).canPop(),
        isFalse,
      );
    },
  );

  testWidgets(
    'resolved mode always enters through the fail-closed feature gate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
            lessonModes: buildLessonModeRegistry(),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureGate), findsOneWidget);
      final unavailable = tester.widget<ProductionFeatureUnavailable>(
        find.byType(ProductionFeatureUnavailable),
      );
      expect(
        unavailable.reason,
        ProductionFeatureUnavailableReason.missingDependency,
      );
    },
  );

  testWidgets(
    'every production mode reaches one controller-backed shell on its stable route',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 24, 12);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'choose-mode-owner',
        nowUtc: () => now,
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'choose-mode-id',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'f05-choose-mode-test',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => 'choose-mode-vocabulary-id',
        nowUtc: () => now,
      );
      await owners.getOrCreateActiveOwner();
      final category = await vocabulary.createCategory('Reading');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'durable',
          meaning: 'able to last',
          partOfSpeech: 'adjective',
        ),
      );
      final modes = buildLessonModeRegistry();
      final research = InertResearchDependencies(database);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      var controllerBuilds = 0;
      final dependencies = AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _GuestSession(),
        quest: testQuestUseCases(),
        experiments: research.experiments,
        consents: research.consents,
        experimentAssignments: research.experimentAssignments,
        assignedLearningEventContext: research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            research.evidencePolicyRolloutModeProvider,
        learning: learning,
        vocabulary: vocabulary,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
        features: features,
        lessonModes: modes,
        createLessonController: (adapter) {
          controllerBuilds += 1;
          return UnifiedLessonController(learning: learning, adapter: adapter);
        },
        associativeLearning: InMemoryAssociativeLearningAdapter(),
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: const MaterialApp(home: ChooseModeScreen()),
        ),
      );

      const cases = <({String entryId, LessonMode mode, String routeName})>[
        (
          entryId: 'home/learn/associative-reading',
          mode: LessonMode.associativeReading,
          routeName: 'learning/associative-reading/session',
        ),
        (
          entryId: 'home/learn/quiz',
          mode: LessonMode.meaningQuiz,
          routeName: 'learning/quiz',
        ),
        (
          entryId: 'home/learn/quiz/definition',
          mode: LessonMode.definitionQuiz,
          routeName: 'learning/definition-quiz',
        ),
        (
          entryId: 'home/learn/quiz/cloze',
          mode: LessonMode.cloze,
          routeName: 'learning/cloze',
        ),
        (
          entryId: 'home/learn/srs',
          mode: LessonMode.flashcard,
          routeName: 'learning/srs',
        ),
      ];
      for (final (index, routeCase) in cases.indexed) {
        await tester.tap(find.byKey(ValueKey<String>(routeCase.entryId)));
        await tester.pumpAndSettle();

        if (routeCase.mode == LessonMode.associativeReading) {
          expect(controllerBuilds, 0);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          await tester.tap(find.text('Start reading'));
          await tester.pumpAndSettle();
        }

        expect(controllerBuilds, index + 1);
        expect(find.byType(UnifiedLessonShell), findsOneWidget);
        final shell = tester.widget<UnifiedLessonShell>(
          find.byType(UnifiedLessonShell),
        );
        expect(
          ModalRoute.of(
            tester.element(find.byType(UnifiedLessonShell)),
          )?.settings.name,
          routeCase.routeName,
        );
        final controller = shell.controller!;
        expect(controller.state.mode, routeCase.mode);
        if (routeCase.mode == LessonMode.flashcard) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<FlashcardModeAdapter>(),
          );
          expect(
            tester
                .widget<SrsFlashcardsScreen>(find.byType(SrsFlashcardsScreen))
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
        }
        if (routeCase.mode == LessonMode.meaningQuiz) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<MeaningQuizModeAdapter>(),
          );
          expect(
            tester.widget<QuizScreen>(find.byType(QuizScreen)).modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);

          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(controller.state.status, LessonSessionStatus.paused);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.definitionQuiz) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<DefinitionQuizModeAdapter>(),
          );
          expect(
            tester
                .widget<DefinitionQuizScreen>(find.byType(DefinitionQuizScreen))
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.cloze) {
          expect(modes.find(routeCase.mode)!.adapter, isA<ClozeModeAdapter>());
          expect(
            tester
                .widget<FillInTheBlanksScreen>(
                  find.byType(FillInTheBlanksScreen),
                )
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }

        if (routeCase.mode == LessonMode.flashcard) {
          features.emergencyOff(Feature.srs);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
          expect(find.byType(SrsFlashcardsScreen), findsNothing);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          continue;
        }

        Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
        await tester.pumpAndSettle();
        if (routeCase.mode == LessonMode.associativeReading) {
          Navigator.of(tester.element(find.text('Start reading'))).pop();
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'SRS off during delayed due load compensates the later durable session',
    (tester) async {
      final harness = await _SrsGateHarness.create(delayDue: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/srs')));
      await tester.pump();
      await tester.runAsync(
        () => harness.repository.dueEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.srs);
      harness.repository.dueRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(SrsFlashcardsScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions, hasLength(2));
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.abandoned,
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.inactive,
      );
      expect(
        await harness.database
            .select(harness.database.learningTimeSegments)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Definition Quiz emergency-off terminally closes its durable shell session',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/quiz/definition')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DefinitionQuizScreen), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(DefinitionQuizScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'Cloze emergency-off closes its durable session and F24 at acceptance cutoff',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FillInTheBlanksScreen), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(FillInTheBlanksScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'SRS off synchronously fences a retained rating before terminal close',
    (tester) async {
      final harness = await _SrsGateHarness.create(blockAbandon: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('home/learn/srs')));
      await tester.pumpAndSettle();

      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      expect(harness.activeTimes.single.state, ActiveLearningTimeState.active);
      final srsBefore =
          (await harness.database.select(harness.database.srsStates).get())
              .single
              .toJson();
      final staleRemembered = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('flashcard-remembered')),
          )
          .onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.srs);
      staleRemembered();
      await tester.runAsync(
        () => harness.repository.abandonEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.repository.abandonRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(SrsFlashcardsScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions, hasLength(2));
      final gatedSession = sessions.singleWhere(
        (session) => session.id == harness.controllers.single.state.sessionId,
      );
      expect(gatedSession.state, 'abandoned');
      expect(gatedSession.endedAtUtcMs, isNotNull);
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(1),
      );
      expect(
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson(),
        srsBefore,
      );
    },
  );

  testWidgets(
    'SRS off awaits an accepted completion instead of racing abandonment',
    (tester) async {
      final harness = await _SrsGateHarness.create(blockFinish: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('home/learn/srs')));
      await tester.pumpAndSettle();

      final remembered = find.byKey(
        const ValueKey<String>('flashcard-remembered'),
      );
      final staleNotRemembered = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('flashcard-not-remembered')),
          )
          .onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;
      await tester.tap(remembered);
      await tester.runAsync(
        () => harness.repository.finishEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      final attemptsAtOff = await harness.database
          .select(harness.database.answerAttempts)
          .get();
      final srsAtOff =
          (await harness.database.select(harness.database.srsStates).get())
              .single
              .toJson();

      harness.features.emergencyOff(Feature.srs);
      staleNotRemembered();
      expect(harness.repository.abandonCalls, 0);
      harness.repository.finishRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.finishCalls, 1);
      expect(harness.repository.abandonCalls, 0);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions
            .singleWhere(
              (session) =>
                  session.id == harness.controllers.single.state.sessionId,
            )
            .state,
        'completed',
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(attemptsAtOff.length),
      );
      expect(
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson(),
        srsAtOff,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'Quiz off during delayed initialization compensates the returned session',
    (tester) async {
      final harness = await _SrsGateHarness.create(delayQuiz: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pump();
      await tester.runAsync(
        () => harness.repository.quizEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      harness.repository.quizRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(QuizScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions, hasLength(2));
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.inactive,
      );
      expect(
        await harness.database
            .select(harness.database.learningTimeSegments)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Cloze off during delayed initialization compensates before screen attach',
    (tester) async {
      final harness = await _SrsGateHarness.create(delayQuiz: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
      );
      await tester.pump();
      await tester.runAsync(
        () => harness.repository.quizEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      harness.repository.quizRelease.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(FillInTheBlanksScreen), findsNothing);
      expect(harness.repository.abandonCalls, 1);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.inactive,
      );
      expect(
        await harness.database
            .select(harness.database.learningTimeSegments)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets('Quiz off synchronously rejects a retained answer callback', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(blockAbandon: true);
    addTearDown(harness.close);
    await harness.pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
    await tester.pumpAndSettle();

    final answer = find.byKey(
      const ValueKey<String>(
        'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
      ),
    );
    final staleAnswer = tester.widget<FilledButton>(answer).onPressed!;
    final srsBefore =
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson();
    harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

    harness.features.emergencyOff(Feature.quiz);
    staleAnswer();
    await tester.runAsync(
      () => harness.repository.abandonEntered.future.timeout(
        const Duration(seconds: 1),
      ),
    );
    harness.repository.abandonRelease.complete();
    await tester.pumpAndSettle();

    expect(harness.repository.answerCalls, 0);
    expect(harness.repository.abandonCalls, 1);
    expect(
      await harness.database.select(harness.database.answerAttempts).get(),
      hasLength(1),
      reason: 'only the pre-existing SRS seed may remain',
    );
    expect(
      (await harness.database.select(harness.database.srsStates).get()).single
          .toJson(),
      srsBefore,
    );
    final sessions = await harness.database
        .select(harness.database.learningSessions)
        .get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(
      sessions.where((session) => session.state == 'abandoned'),
      hasLength(1),
    );
    final segments = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(segments, hasLength(1));
    expect(segments.single.activeDurationMs, 2000);
  });

  testWidgets('Quiz off freezes time while accepted evidence settles', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(blockAnswer: true);
    addTearDown(harness.close);
    await harness.pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
    await tester.pumpAndSettle();

    final answer = find.byKey(
      const ValueKey<String>(
        'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
      ),
    );
    final staleAnswer = tester.widget<FilledButton>(answer).onPressed!;
    final srsBefore =
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson();
    harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;
    staleAnswer();
    await tester.runAsync(
      () => harness.repository.answerEntered.future.timeout(
        const Duration(seconds: 1),
      ),
    );

    harness.features.emergencyOff(Feature.quiz);
    staleAnswer();
    await tester.pump();
    expect(
      harness.repository.abandonCalls,
      0,
      reason: 'terminalization must wait the accepted evidence operation',
    );
    harness.monotonicMicros = const Duration(hours: 1).inMicroseconds;
    await tester.pump(const Duration(minutes: 10));
    await tester.pump();
    expect(
      harness.activeTimes.single.state,
      ActiveLearningTimeState.finished,
      reason: 'F24 must close while the accepted evidence write is blocked',
    );
    final segmentsWhileBlocked = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(segmentsWhileBlocked, hasLength(1));
    expect(segmentsWhileBlocked.single.activeDurationMs, 2000);
    harness.repository.answerRelease.complete();
    await tester.pumpAndSettle();

    expect(harness.repository.answerCalls, 1);
    expect(harness.repository.abandonCalls, 1);
    final attempts = await harness.database
        .select(harness.database.answerAttempts)
        .get();
    expect(attempts, hasLength(2));
    final recognition = attempts.singleWhere(
      (attempt) => attempt.promptMode == 'meaningChoice',
    );
    expect(recognition.evidenceClass, EvidenceClass.recognition.name);
    expect(
      (await harness.database.select(harness.database.srsStates).get()).single
          .toJson(),
      srsBefore,
    );
    final sessions = await harness.database
        .select(harness.database.learningSessions)
        .get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(
      sessions.where((session) => session.state == 'abandoned'),
      hasLength(1),
    );
    final segments = await harness.database
        .select(harness.database.learningTimeSegments)
        .get();
    expect(segments, hasLength(1));
    expect(segments.single.activeDurationMs, 2000);
  });

  testWidgets(
    'Quiz off awaits an accepted final completion without abandonment race',
    (tester) async {
      final harness = await _SrsGateHarness.create(blockFinish: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();

      final answer = find.byKey(
        const ValueKey<String>(
          'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
        ),
      );
      final staleAnswer = tester.widget<FilledButton>(answer).onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;
      await tester.tap(answer);
      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(next, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.runAsync(
        () => harness.repository.finishEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      final attemptsAtOff = await harness.database
          .select(harness.database.answerAttempts)
          .get();
      final srsAtOff =
          (await harness.database.select(harness.database.srsStates).get())
              .single
              .toJson();

      harness.features.emergencyOff(Feature.quiz);
      staleAnswer();
      expect(harness.repository.abandonCalls, 0);
      harness.repository.finishRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.finishCalls, 1);
      expect(harness.repository.abandonCalls, 0);
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'completed'),
        hasLength(2),
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(attemptsAtOff.length),
      );
      expect(
        (await harness.database.select(harness.database.srsStates).get()).single
            .toJson(),
        srsAtOff,
      );
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );
}

final class _SrsGateHarness {
  _SrsGateHarness._({
    required this.database,
    required this.features,
    required this.repository,
    required this.dependencies,
    required this.controllers,
    required this.activeTimes,
  });

  final AppDatabase database;
  final RuntimeFeatureRegistry features;
  final _CoordinatedLearningRepository repository;
  final AppDependencies dependencies;
  final List<UnifiedLessonController> controllers;
  final List<ActiveLearningTimeController> activeTimes;
  int monotonicMicros = 0;

  static Future<_SrsGateHarness> create({
    bool delayDue = false,
    bool delayQuiz = false,
    bool blockAbandon = false,
    bool blockAnswer = false,
    bool blockFinish = false,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 8, 25, 15);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'srs-gate-owner',
      nowUtc: () => now,
    );
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'srs-gate-vocabulary',
      nowUtc: () => now,
    );
    final category = await vocabulary.createCategory('SRS gate');
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'durable',
        meaning: 'lasting',
        partOfSpeech: 'adjective',
      ),
    );
    final driftLearning = DriftLearningRepository(database);
    var seedId = 0;
    final seedTime = now.subtract(const Duration(days: 2));
    final seedLearning = LearningUseCases(
      owners: owners,
      repository: driftLearning,
      generateId: () => 'srs-gate-seed-${++seedId}',
      nowUtc: () => seedTime,
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'f06-live-srs-gate-seed',
      ),
    );
    final seedSession = await seedLearning.startQuiz();
    await seedLearning.recordEvidence(
      sourceEvidenceId: 'attempt:srs-gate-seed',
      occurredAtUtc: seedTime,
      sessionId: seedSession.id,
      wordId: seedSession.questions.single.word.id,
      promptMode: 'srsRecall',
      isCorrect: true,
      responseTimeMs: 100,
      attemptNumber: 1,
      evidenceContext: EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'srs-recall',
        hintLevel: 0,
        contentRevision: 'built-in-v1',
        engagementAllowed: true,
      ),
    );
    await seedLearning.finishSession(seedSession.id);
    final repository = _CoordinatedLearningRepository(
      driftLearning,
      delayDue: delayDue,
      delayQuiz: delayQuiz,
      blockAbandon: blockAbandon,
      blockAnswer: blockAnswer,
      blockFinish: blockFinish,
    );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'srs-gate-${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'f06-live-srs-gate',
      ),
    );
    final learningTime = DriftLearningTimeRepository(database, owners: owners);
    final controllers = <UnifiedLessonController>[];
    final activeTimes = <ActiveLearningTimeController>[];
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    final modes = buildLessonModeRegistry();
    final research = InertResearchDependencies(database);
    late final _SrsGateHarness harness;
    final dependencies = AppDependencies(
      initialRoute: AppRoute.home,
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      quest: testQuestUseCases(),
      experiments: research.experiments,
      consents: research.consents,
      experimentAssignments: research.experimentAssignments,
      assignedLearningEventContext: research.assignedLearningEventContext,
      evidencePolicyRolloutModeProvider:
          research.evidencePolicyRolloutModeProvider,
      features: features,
      database: database,
      localOwners: owners,
      learning: learning,
      vocabulary: vocabulary,
      lessonModes: modes,
      currentActivityEvidence: CurrentActivityEvidenceAdapter(
        learning: learning,
      ),
      learningTime: learningTime,
      learningTimeCaptureRollout: const LearningTimeCaptureRollout.internal(),
      createLessonController: (adapter) {
        final activeTime = ActiveLearningTimeController(
          repository: learningTime,
          monotonicMicros: () => harness.monotonicMicros,
          nowUtc: () => now,
          timezoneContext: (_) => const LearningTimeZoneContext(
            timezoneId: 'Etc/UTC',
            utcOffsetMinutes: 0,
          ),
        );
        activeTimes.add(activeTime);
        final controller = UnifiedLessonController(
          learning: learning,
          adapter: adapter,
          activeLearningTime: activeTime,
        );
        controllers.add(controller);
        return controller;
      },
    );
    harness = _SrsGateHarness._(
      database: database,
      features: features,
      repository: repository,
      dependencies: dependencies,
      controllers: controllers,
      activeTimes: activeTimes,
    );
    return harness;
  }

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: const MaterialApp(home: ChooseModeScreen()),
    ),
  );

  Future<void> close() async {
    repository.releaseAll();
    features.dispose();
    await database.close();
  }
}

final class _CoordinatedLearningRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _CoordinatedLearningRepository(
    this.delegate, {
    required this.delayDue,
    required this.delayQuiz,
    required this.blockAbandon,
    required this.blockAnswer,
    required this.blockFinish,
  });

  final LearningRepository delegate;
  final bool delayDue;
  final bool delayQuiz;
  final bool blockAbandon;
  final bool blockAnswer;
  final bool blockFinish;
  final Completer<void> dueEntered = Completer<void>();
  final Completer<void> dueRelease = Completer<void>();
  final Completer<void> quizEntered = Completer<void>();
  final Completer<void> quizRelease = Completer<void>();
  final Completer<void> answerEntered = Completer<void>();
  final Completer<void> answerRelease = Completer<void>();
  final Completer<void> abandonEntered = Completer<void>();
  final Completer<void> abandonRelease = Completer<void>();
  final Completer<void> finishEntered = Completer<void>();
  final Completer<void> finishRelease = Completer<void>();
  int abandonCalls = 0;
  int answerCalls = 0;
  int finishCalls = 0;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async {
    if (delayQuiz) {
      if (!quizEntered.isCompleted) quizEntered.complete();
      await quizRelease.future;
    }
    return delegate.listQuizWords(
      ownerId: ownerId,
      categoryId: categoryId,
      limit: limit,
    );
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    if (delayDue) {
      if (!dueEntered.isCompleted) dueEntered.complete();
      await dueRelease.future;
    }
    return delegate.listDueWords(
      ownerId: ownerId,
      nowUtc: nowUtc,
      limit: limit,
    );
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {
    abandonCalls += 1;
    if (blockAbandon) {
      if (!abandonEntered.isCompleted) abandonEntered.complete();
      await abandonRelease.future;
    }
    return (delegate as LearningSessionLifecycleRepository).abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls += 1;
    if (blockFinish) {
      if (!finishEntered.isCompleted) finishEntered.complete();
      await finishRelease.future;
    }
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    answerCalls += 1;
    if (blockAnswer) {
      if (!answerEntered.isCompleted) answerEntered.complete();
      await answerRelease.future;
    }
    return delegate.recordAnswer(command);
  }

  void releaseAll() {
    if (!dueRelease.isCompleted) dueRelease.complete();
    if (!quizRelease.isCompleted) quizRelease.complete();
    if (!answerRelease.isCompleted) answerRelease.complete();
    if (!abandonRelease.isCompleted) abandonRelease.complete();
    if (!finishRelease.isCompleted) finishRelease.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
