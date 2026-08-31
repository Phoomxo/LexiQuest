import 'dart:async';
import 'dart:convert';

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
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
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
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/screens/definition_quiz_screen.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/matching_mode_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

Future<void> _scrollToModeEntry(WidgetTester tester, String entryId) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  final entry = find.byKey(ValueKey<String>(entryId));
  await tester.scrollUntilVisible(entry, 240, scrollable: scrollable);
  await tester.pump();
}

Future<void> _openConfiguredMode(
  WidgetTester tester,
  Finder modeEntry, {
  bool settleAfterStart = true,
  int? hintBudget,
  int? itemCount = 1,
  SessionDirection? direction,
  String? packLabel,
  int? timeLimitSeconds,
  bool untimed = false,
}) async {
  await tester.tap(modeEntry);
  await tester.pumpAndSettle();
  expect(find.byType(SessionConfigurationSheet), findsOneWidget);
  if (itemCount != null) {
    await tester.enterText(
      find.byKey(const ValueKey('session-item-count')),
      '$itemCount',
    );
  }
  if (direction != null) {
    final directionField = find.byKey(const ValueKey('session-direction'));
    await tester.ensureVisible(directionField);
    await tester.tap(directionField);
    await tester.pumpAndSettle();
    final label = switch (direction) {
      SessionDirection.forward => 'Prompt to answer',
      SessionDirection.reverse => 'Answer to prompt',
      SessionDirection.mixed => 'Mixed directions',
    };
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }
  if (packLabel != null) {
    final packField = find.byKey(const ValueKey('session-pack'));
    await tester.ensureVisible(packField);
    await tester.tap(packField);
    await tester.pumpAndSettle();
    await tester.tap(find.text(packLabel).last);
    await tester.pumpAndSettle();
  }
  if (hintBudget != null) {
    final hintBudgetField = find.byKey(const ValueKey('session-hint-budget'));
    await tester.ensureVisible(hintBudgetField);
    await tester.tap(hintBudgetField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('$hintBudget').last);
    await tester.pumpAndSettle();
  }
  if (timeLimitSeconds != null) {
    await tester.enterText(
      find.byKey(const ValueKey('session-time-limit-seconds')),
      '$timeLimitSeconds',
    );
  }
  if (untimed) {
    final untimedOption = find.byKey(const ValueKey('session-timing-untimed'));
    await tester.ensureVisible(untimedOption);
    await tester.tap(untimedOption);
    await tester.pumpAndSettle();
  }
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final start = find.byKey(const ValueKey('session-config-start'));
  await tester.ensureVisible(start);
  await tester.pump();
  await tester.tap(start);
  if (settleAfterStart) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'f16 validated count and reverse direction govern delivered meaning quiz',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        itemCount: 1,
        direction: SessionDirection.reverse,
      );

      final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(screen.sessionConfiguration?.itemCount, 1);
      expect(screen.sessionConfiguration?.direction, SessionDirection.reverse);
      expect(find.text('lasting'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey<String>(
            'meaning-quiz-option-word:srs-gate-vocabulary-durable',
          ),
        ),
        findsOneWidget,
      );
      expect(harness.controllers.single.state.itemCount, 1);
    },
  );

  testWidgets('f16 exact pinned pack revision governs delivered vocabulary', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(pinnedPack: _testPinnedPack());
    addTearDown(harness.close);
    await harness.pump(tester);

    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
      packLabel: 'Pinned f16 pack revision 3',
    );

    final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
    expect(screen.sessionConfiguration?.packIdentity, _testPackIdentity);
    expect(harness.controllers.single.state.itemCount, 1);
    expect(find.text('durable'), findsWidgets);
  });

  testWidgets('f16 pinned pack content drift renders a typed reset prompt', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      pinnedPack: _testPinnedPack(
        vocabularyWordIds: const <String>['word:missing-from-owner-library'],
      ),
    );
    addTearDown(harness.close);
    await harness.pump(tester);

    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
      packLabel: 'Pinned f16 pack revision 3',
    );

    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(
      find.text('The selected learning-pack revision is no longer available.'),
      findsOneWidget,
    );
    expect(
      harness.controllers.single.state.status,
      LessonSessionStatus.planned,
    );
  });

  testWidgets('f16 production Choose path renders stale stored reset prompt', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create();
    addTearDown(harness.close);
    final owner = await harness.dependencies.localOwners!
        .getOrCreateActiveOwner();
    final registration = harness.dependencies.lessonModes!.resolve(
      LessonMode.meaningQuiz,
    )!;
    const currentLimits = SessionConfigurationProtocolLimits.standard();
    final staleLimits = currentLimits.copyWith(protocolVersion: 'stale');
    const policy = SessionConfigurationPolicy();
    final stale = policy.validate(
      draft: policy
          .defaultsFor(registration: registration, limits: staleLimits)
          .copyWith(itemCount: 1),
      registration: registration,
      limits: staleLimits,
      ownerId: owner.id,
      availablePackIdentities: const <ContentIdentity>[],
    );
    await harness.sessionConfigurations.save(
      stale,
      updatedAtUtc: DateTime.utc(2026, 8, 26),
    );
    await harness.pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The study protocol changed after this session was configured.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('f16 persisted protocol drift opens typed reset sheet', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(staleProtocol: true);
    addTearDown(harness.close);
    await harness.pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-configuration-reset-prompt')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The study protocol changed after this session was configured.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('session-config-reset')));
    await tester.pumpAndSettle();

    expect(find.byType(SessionConfigurationSheet), findsNothing);
    expect(find.byType(ChooseModeScreen), findsOneWidget);
    expect(harness.controllers, isEmpty);
  });

  testWidgets(
    'f16 opens one validated configuration sheet before route construction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
            lessonModes: buildLessonModeRegistry(),
          ),
        ),
      );

      final tile = find.byKey(const ValueKey<String>('home/learn/quiz'));
      final dynamic configuredTile = tester.widget(tile);
      configuredTile.onTap();
      configuredTile.onTap();
      await tester.pumpAndSettle();

      expect(find.byType(SessionConfigurationSheet), findsOneWidget);
      expect(find.byType(ProductionFeatureGate), findsNothing);
      expect(find.byType(UnifiedLessonShell), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('session-config-start')),
      );
      await tester.tap(find.byKey(const ValueKey('session-config-start')));
      await tester.pumpAndSettle();

      expect(find.byType(SessionConfigurationSheet), findsNothing);
      expect(find.byType(ProductionFeatureGate), findsOneWidget);
    },
  );

  testWidgets(
    'f16 emergency-off between validation and start prevents navigation',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: features,
            lessonModes: buildLessonModeRegistry(),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();
      expect(find.byType(SessionConfigurationSheet), findsOneWidget);

      features.emergencyOff(Feature.quiz);
      await tester.ensureVisible(
        find.byKey(const ValueKey('session-config-start')),
      );
      await tester.tap(find.byKey(const ValueKey('session-config-start')));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(find.byType(UnifiedLessonShell), findsNothing);
      expect(
        find.text('This lesson mode is no longer available.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('f16 a retained live-off mode callback cannot configure', (
    tester,
  ) async {
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(features.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: features,
          lessonModes: buildLessonModeRegistry(),
        ),
      ),
    );
    final tile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('home/learn/quiz')),
        matching: find.byType(ListTile),
      ),
    );
    final retainedOpen = tile.onTap!;

    features.emergencyOff(Feature.quiz);
    retainedOpen();
    await tester.pumpAndSettle();

    expect(find.byType(SessionConfigurationSheet), findsNothing);
    expect(find.byType(UnifiedLessonShell), findsNothing);
    expect(
      find.text('This lesson mode is no longer available.'),
      findsOneWidget,
    );
  });

  testWidgets('f13 shows every registered production native mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
          lessonModes: buildLessonModeRegistry(),
        ),
      ),
    );

    const entryIdsInCatalogOrder = <String>[
      'home/learn/associative-reading',
      'home/learn/reading/cefr',
      'home/learn/quiz/dictation',
      'home/learn/quiz/sentence-scramble',
      'home/learn/quiz/word-scramble',
      'home/learn/speech/speaking',
      'home/learn/speech/shadowing',
    ];
    for (final entryId in entryIdsInCatalogOrder) {
      await _scrollToModeEntry(tester, entryId);
      expect(
        find.byKey(ValueKey<String>(entryId)),
        findsOneWidget,
        reason: '$entryId must have one Choose Mode parent',
      );
    }
  });

  testWidgets('f13 speaking tile is reachable in the lazy catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          featureRegistry: const BuildFeatureRegistry.allEnabled(),
          lessonModes: buildLessonModeRegistry(),
        ),
      ),
    );

    await _scrollToModeEntry(tester, 'home/learn/speech/speaking');
    expect(
      find.byKey(const ValueKey<String>('home/learn/speech/speaking')),
      findsOneWidget,
    );
  });

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
        find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
        findsNothing,
        reason: 'typed recall stays hidden without its registry authority',
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
      expect(
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        findsNothing,
        reason: 'f10 remains implemented-off by default',
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

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
      );

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
      var learningId = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'choose-mode-id-${++learningId}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'f05-choose-mode-test',
        ),
      );
      var vocabularyId = 0;
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => vocabularyId++ < 2
            ? 'choose-mode-vocabulary-id'
            : 'choose-mode-vocabulary-id-two',
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
          cefrLevel: 'C2',
        ),
      );
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'stable',
          meaning: 'not likely to change',
          partOfSpeech: 'adjective',
          cefrLevel: 'C2',
        ),
      );
      final modes = buildLessonModeRegistry(
        matchingDeliveryState: LessonModeDeliveryState.enabled,
      );
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
        speechPractice: SpeechPracticeUseCases(_InertSpeechGateway()),
        features: features,
        localOwners: owners,
        lessonModes: modes,
        sessionConfigurations: DriftSessionConfigurationStore(database),
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
          entryId: 'home/learn/quiz/typed-recall',
          mode: LessonMode.typedRecall,
          routeName: 'learning/typed-recall',
        ),
        (
          entryId: 'home/learn/quiz/matching',
          mode: LessonMode.matching,
          routeName: 'learning/matching',
        ),
        (
          entryId: 'home/learn/quiz/cloze',
          mode: LessonMode.cloze,
          routeName: 'learning/cloze',
        ),
        (
          entryId: 'home/learn/quiz/definition',
          mode: LessonMode.definitionQuiz,
          routeName: 'learning/definition-quiz',
        ),
        (
          entryId: 'home/learn/reading/cefr',
          mode: LessonMode.cefrReading,
          routeName: 'learning/cefr-reading',
        ),
        (
          entryId: 'home/learn/quiz/dictation',
          mode: LessonMode.dictation,
          routeName: 'game/dictation',
        ),
        (
          entryId: 'home/learn/quiz/sentence-scramble',
          mode: LessonMode.sentenceScramble,
          routeName: 'game/sentence-scramble',
        ),
        (
          entryId: 'home/learn/quiz/word-scramble',
          mode: LessonMode.wordScramble,
          routeName: 'game/word-scramble',
        ),
        (
          entryId: 'home/learn/speech/speaking',
          mode: LessonMode.speaking,
          routeName: 'practice/speaking',
        ),
        (
          entryId: 'home/learn/speech/shadowing',
          mode: LessonMode.shadowing,
          routeName: 'practice/shadowing',
        ),
        (
          entryId: 'home/learn/srs',
          mode: LessonMode.flashcard,
          routeName: 'learning/srs',
        ),
      ];
      for (final (index, routeCase) in cases.indexed) {
        await _scrollToModeEntry(tester, routeCase.entryId);
        final entry = find.byKey(ValueKey<String>(routeCase.entryId));
        await tester.pump();
        await _openConfiguredMode(
          tester,
          entry,
          itemCount: routeCase.mode == LessonMode.matching ? 2 : 1,
        );

        if (routeCase.mode == LessonMode.associativeReading) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isNot(isA<TypedRecallModeAdapter>()),
          );
          expect(controllerBuilds, 0);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          await tester.tap(find.text('Start reading'));
          await tester.pumpAndSettle();
        }

        expect(
          controllerBuilds,
          index + 1,
          reason: '${routeCase.mode.id} must create one controller',
        );
        expect(
          find.byType(UnifiedLessonShell),
          findsOneWidget,
          reason: '${routeCase.mode.id} must retain one shell',
        );
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
          expect(
            tester.widget<QuizScreen>(find.byType(QuizScreen)).typedRecall,
            isFalse,
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
        if (routeCase.mode == LessonMode.typedRecall) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<TypedRecallModeAdapter>(),
          );
          final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
          expect(
            screen.typedRecallModeAdapter,
            same(modes.resolveTypedRecall()!.adapter),
          );
          expect(screen.typedRecall, isTrue);
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
        if (routeCase.mode == LessonMode.matching) {
          expect(
            modes.find(routeCase.mode)!.adapter,
            isA<MatchingModeAdapter>(),
          );
          expect(
            tester
                .widget<MatchingModeScreen>(find.byType(MatchingModeScreen))
                .modeAdapter,
            same(modes.find(routeCase.mode)!.adapter),
          );
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.cefrReading) {
          final screen = tester.widget<CefrArticleReaderScreen>(
            find.byType(CefrArticleReaderScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.cefrLevel, 'C2');
          expect(screen.sessionId, controller.state.sessionId);
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(screen.wordId, startsWith('word:choose-mode-vocabulary-id'));
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.dictation) {
          final screen = tester.widget<DictationQuizScreen>(
            find.byType(DictationQuizScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.sentenceScramble) {
          final screen = tester.widget<SentenceScrambleScreen>(
            find.byType(SentenceScrambleScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.wordScramble) {
          final screen = tester.widget<WordScrambleScreen>(
            find.byType(WordScrambleScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.speaking) {
          final screen = tester.widget<SpeakToTextScreen>(
            find.byType(SpeakToTextScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }
        if (routeCase.mode == LessonMode.shadowing) {
          final screen = tester.widget<ShadowingChallengeScreen>(
            find.byType(ShadowingChallengeScreen),
          );
          expect(screen.modeAdapter, same(modes.find(routeCase.mode)!.adapter));
          expect(screen.ownerId, 'local:choose-mode-owner');
          expect(controller.state.status, LessonSessionStatus.active);
        }

        if (const <LessonMode>{
          LessonMode.dictation,
          LessonMode.speaking,
          LessonMode.shadowing,
          LessonMode.cefrReading,
          LessonMode.sentenceScramble,
          LessonMode.wordScramble,
        }.contains(routeCase.mode)) {
          final parentFeature = modes.find(routeCase.mode)!.feature;
          features.emergencyOff(parentFeature);
          await tester.pumpAndSettle();
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
          expect(find.byType(UnifiedLessonShell), findsNothing);
          expect(
            controller.state.status,
            LessonSessionStatus.abandoned,
            reason:
                '${routeCase.mode.id} must reconcile when its parent turns off',
          );
          features.clearOverride(parentFeature);
          Navigator.of(
            tester.element(find.byType(ProductionFeatureUnavailable)),
          ).pop();
          await tester.pumpAndSettle();
          continue;
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

      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await tester.ensureVisible(srsTile);
      await tester.pump();
      await _openConfiguredMode(
        tester,
        srsTile,
        itemCount: 1,
        settleAfterStart: false,
      );
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
    'unclassified CEFR word keeps shell and reconciles its pinned session',
    (tester) async {
      final harness = await _SrsGateHarness.create(vocabularyCefrLevel: null);
      addTearDown(harness.close);
      await harness.pump(tester);

      await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/reading/cefr')),
      );

      expect(find.byType(CefrArticleReaderScreen), findsNothing);
      expect(find.byType(UnifiedLessonShell), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.abandoned,
      );
      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(sessions.where((session) => session.state == 'active'), isEmpty);
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'canonical A2 through C2 CEFR routes preserve pinned word and session identity',
    (tester) async {
      for (final level in const <String>['A2', 'B1', 'B2', 'C1', 'C2']) {
        final harness = await _SrsGateHarness.create(
          vocabularyCefrLevel: level,
        );
        await harness.pump(tester);

        await _scrollToModeEntry(tester, 'home/learn/reading/cefr');
        await _openConfiguredMode(
          tester,
          find.byKey(const ValueKey<String>('home/learn/reading/cefr')),
        );

        final controller = harness.controllers.single;
        final reader = tester.widget<CefrArticleReaderScreen>(
          find.byType(CefrArticleReaderScreen),
        );
        expect(reader.cefrLevel, level);
        expect(reader.sessionId, controller.state.sessionId);
        expect(reader.wordId, 'word:srs-gate-vocabulary');

        harness.features.emergencyOff(Feature.reading);
        await tester.pumpAndSettle();
        expect(controller.state.status, LessonSessionStatus.abandoned);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await harness.close();
      }
    },
  );

  testWidgets(
    'Definition Quiz emergency-off terminally closes its durable shell session',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/definition')),
        itemCount: 1,
      );
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

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
        itemCount: 1,
      );
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
    'Matching off fences a retained pair and closes durable session plus F24',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableMatching: true);
      addTearDown(harness.close);
      await harness.pump(tester);

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
      );
      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.active,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('matching-word-word:srs-gate-vocabulary'),
        ),
      );
      await tester.pump();
      final retained = tester
          .widget<OutlinedButton>(
            find.byKey(
              const ValueKey<String>(
                'matching-meaning-word:srs-gate-vocabulary',
              ),
            ),
          )
          .onPressed!;
      harness.monotonicMicros = const Duration(seconds: 2).inMicroseconds;

      harness.features.emergencyOff(Feature.quiz);
      retained();
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(MatchingModeScreen), findsNothing);
      expect(harness.repository.answerCalls, 0);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.abandoned,
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final activeSessions = await (harness.database.select(
        harness.database.learningSessions,
      )..where((row) => row.state.equals('active'))).get();
      expect(activeSessions, isEmpty);
      final matchingAttempts = await (harness.database.select(
        harness.database.answerAttempts,
      )..where((row) => row.promptMode.equals('matchingPair'))).get();
      expect(matchingAttempts, isEmpty);
      final segments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(segments, hasLength(1));
      expect(segments.single.activeDurationMs, 2000);
    },
  );

  testWidgets(
    'f16 Matching recovery ignores a newer mutable configuration preference',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableMatching: true);
      addTearDown(harness.close);
      final learning = harness.dependencies.learning!;
      const adapter = MatchingModeAdapter();
      final owner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      final registration = harness.dependencies.lessonModes!.resolve(
        LessonMode.matching,
      )!;
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final configuration = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 2),
        registration: registration,
        limits: limits,
        ownerId: owner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      await harness.sessionConfigurations.save(
        configuration,
        updatedAtUtc: DateTime.utc(2026, 8, 25, 15),
      );
      final prepared = await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        itemCount: configuration.itemCount,
        sessionConfiguration: configuration,
      );
      final close = learning.captureSessionClose(
        sessionId: prepared.session.id,
      );
      await prepared.persistClose(close: close, timeoutRequested: true);
      await close.finish();
      expect(harness.repository.finishCalls, 1);
      final newerPreference = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 3),
        registration: registration,
        limits: limits,
        ownerId: owner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      await harness.sessionConfigurations.save(
        newerPreference,
        updatedAtUtc: DateTime.utc(2026, 8, 25, 16),
      );

      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: null,
      );
      await tester.runAsync(() async {
        await harness.repository.matchingTerminalAcknowledged.future.timeout(
          const Duration(seconds: 1),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(ScoreScreen), findsOneWidget);
      expect(harness.repository.finishCalls, 2);
      expect(harness.repository.abandonCalls, 0);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.completed,
      );
      expect(
        harness.activeTimes.single.state,
        ActiveLearningTimeState.finished,
      );
      final timeSegments = await harness.database
          .select(harness.database.learningTimeSegments)
          .get();
      expect(
        timeSegments.map(
          (segment) => segment.endedAtUtcMs >= segment.startedAtUtcMs,
        ),
        everyElement(isTrue),
      );
      final checkpoints =
          await (harness.database.select(harness.database.eventsV2)..where(
                (row) => row.eventType.equals('LearningActivityCheckpoint'),
              ))
              .get();
      final latest = checkpoints
          .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
          .reduce(
            (left, right) =>
                (left['revision'] as int) > (right['revision'] as int)
                ? left
                : right,
          );
      expect(latest['terminalAcknowledged'], isTrue);
      expect(
        (latest['state'] as Map<String, dynamic>)['summaryPresented'],
        isTrue,
      );
      await tester.pump();
      expect(harness.repository.finishCalls, 2);
    },
  );

  testWidgets(
    'f16 Matching configuration drift requires an explicit discard decision',
    (tester) async {
      final harness = await _SrsGateHarness.create(enableMatching: true);
      addTearDown(harness.close);
      final learning = harness.dependencies.learning!;
      const adapter = MatchingModeAdapter();
      final owner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      final registration = harness.dependencies.lessonModes!.resolve(
        LessonMode.matching,
      )!;
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final pinned = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 2),
        registration: registration,
        limits: limits,
        ownerId: owner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        itemCount: pinned.itemCount,
        sessionConfiguration: pinned,
      );

      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 3,
      );

      expect(
        find.byKey(const ValueKey('session-configuration-recovery-prompt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-config-recovery-resume')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-config-recovery-discard')),
        findsOneWidget,
      );
      expect(harness.controllers, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('session-config-recovery-discard')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(harness.repository.abandonCalls, 1);
      expect(harness.controllers.single.sessionConfiguration?.itemCount, 3);
    },
  );

  testWidgets(
    'Matching recovery load and discard retain the owner captured before awaits',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        switchOwnerDuringProtocolResolution: true,
      );
      addTearDown(harness.close);
      final learning = harness.dependencies.learning!;
      final originalOwner = await harness.dependencies.localOwners!
          .getOrCreateActiveOwner();
      final registration = harness.dependencies.lessonModes!.resolve(
        LessonMode.matching,
      )!;
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final pinned = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 2),
        registration: registration,
        limits: limits,
        ownerId: originalOwner.id,
        availablePackIdentities: const <ContentIdentity>[],
      );
      final prepared = await const MatchingModeAdapter().prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        itemCount: pinned.itemCount,
        sessionConfiguration: pinned,
      );

      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 3,
      );

      expect(
        find.byKey(const ValueKey('session-configuration-recovery-prompt')),
        findsOneWidget,
        reason: 'the pre-await owner must still recover its active session',
      );
      await harness.database
          .into(harness.database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'matching-next-owner-active',
              ownerId: _OwnerSwitchingProtocolProvider.nextOwnerId,
              activityType: 'quiz',
              state: 'active',
              startedAtUtcMs: DateTime.utc(
                2026,
                8,
                25,
                15,
                1,
              ).millisecondsSinceEpoch,
              appVersion: 'test',
              buildId: 'next-owner',
            ),
          );
      await tester.tap(
        find.byKey(const ValueKey('session-config-recovery-discard')),
      );
      await tester.pumpAndSettle();

      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      expect(
        sessions.singleWhere((row) => row.id == prepared.session.id).state,
        'abandoned',
      );
      expect(
        sessions
            .singleWhere((row) => row.id == 'matching-next-owner-active')
            .state,
        'active',
      );
    },
  );

  testWidgets(
    'f16 Flashcard retirement waits for admitted evidence and terminal close',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        blockAnswer: true,
        blockAbandon: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await tester.ensureVisible(srsTile);
      await tester.pump();
      await _openConfiguredMode(tester, srsTile, itemCount: 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('flashcard-remembered')),
      );
      await tester.runAsync(
        () => harness.repository.answerEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.features.emergencyOff(Feature.srs);
      await tester.pump();
      harness.repository.answerRelease.complete();
      harness.repository.abandonRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.answerCalls, 1);
      expect(harness.repository.finishCalls, 1);
      expect(harness.repository.abandonCalls, 0);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.completed,
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'f16 Matching retirement waits through checkpoint and evidence cleanup',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        blockMatchingCheckpoint: true,
        blockAbandon: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
      );
      const wordId = 'word:srs-gate-vocabulary';
      await tester.tap(
        find.byKey(const ValueKey<String>('matching-word-$wordId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('matching-meaning-$wordId')),
      );
      await tester.runAsync(
        () => harness.repository.matchingCheckpointEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      await tester.pump();
      expect(harness.repository.abandonCalls, 0);
      harness.repository.matchingCheckpointRelease.complete();
      harness.repository.abandonRelease.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.answerCalls, 1);
      expect(harness.repository.abandonCalls, 1);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(2),
      );
      final checkpoints =
          await (harness.database.select(harness.database.eventsV2)..where(
                (row) => row.eventType.equals('LearningActivityCheckpoint'),
              ))
              .get();
      final latest = checkpoints
          .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
          .reduce(
            (left, right) =>
                (left['revision'] as int) > (right['revision'] as int)
                ? left
                : right,
          );
      expect(
        (latest['state'] as Map<String, dynamic>)['pendingEvidence'],
        isNull,
      );
    },
  );

  testWidgets(
    'f16 Matching committed close lost ack survives emergency retirement and restart',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        loseMatchingCloseAckOnce: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
      );
      for (final wordId in const <String>[
        'word:srs-gate-vocabulary',
        'word:srs-gate-vocabulary-two',
      ]) {
        await tester.tap(find.byKey(ValueKey<String>('matching-word-$wordId')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey<String>('matching-meaning-$wordId')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey<String>('matching-finish')));
      await tester.runAsync(
        () => harness.repository.matchingCloseCommitted.future.timeout(
          const Duration(seconds: 1),
        ),
      );

      harness.features.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      final sessions = await harness.database
          .select(harness.database.learningSessions)
          .get();
      final configured = sessions.singleWhere(
        (session) => session.activityType == MatchingModeAdapter.activityType,
      );
      expect(configured.state, 'completed');
      expect(harness.repository.abandonCalls, 0);
      expect(harness.repository.matchingCloseAppendCalls, 2);
      final recovered = await const MatchingModeAdapter().prepareSession(
        learning: harness.dependencies.learning!,
        evidence: harness.dependencies.currentActivityEvidence!,
        itemCount: 2,
        sessionConfiguration: harness.controllers.single.sessionConfiguration,
      );
      expect(recovered.session.id, configured.id);
      expect(recovered.completedSummary?.id, configured.id);
      final reconciled = await recovered.reconcileCompleted(
        completeSession: (close) =>
            close.requiresRetry ? close.retry() : close.finish(),
      );
      expect(reconciled.id, configured.id);
    },
  );

  testWidgets(
    'f16 Flashcard lost-ack retry and close survive finite effort expiry',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        loseAnswerAckOnce: true,
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await tester.ensureVisible(srsTile);
      await tester.pump();
      await _openConfiguredMode(
        tester,
        srsTile,
        itemCount: 1,
        timeLimitSeconds: 60,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('flashcard-remembered')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('current-evidence-retry')),
        findsOneWidget,
      );

      harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;
      await expectLater(
        harness.controllers.single.recordActiveLearningInteraction(
          DateTime.utc(2026, 8, 25, 15, 1),
        ),
        throwsA(isA<SessionConfigurationLimitReached>()),
      );
      await tester.pumpAndSettle();
      final retry = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(harness.repository.answerCalls, 2);
      expect(harness.repository.finishCalls, 1);
      expect(
        harness.controllers.single.state.status,
        LessonSessionStatus.completed,
      );
      expect(
        harness.controllers.single.configurationActiveEffort,
        const Duration(seconds: 60),
      );
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  testWidgets('f16 Matching lost-ack retry survives finite effort expiry', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      enableMatching: true,
      loseAnswerAckOnce: true,
      deterministicConfigurationClock: true,
    );
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
      itemCount: 2,
      timeLimitSeconds: 60,
    );
    const wordId = 'word:srs-gate-vocabulary';
    await tester.tap(
      find.byKey(const ValueKey<String>('matching-word-$wordId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('matching-meaning-$wordId')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
      findsOneWidget,
    );

    harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;
    await expectLater(
      harness.controllers.single.recordActiveLearningInteraction(
        DateTime.utc(2026, 8, 25, 15, 1),
      ),
      throwsA(isA<SessionConfigurationLimitReached>()),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey<String>('current-evidence-retry'));
    tester.widget<FilledButton>(retry).onPressed!();
    await tester.pumpAndSettle();

    expect(harness.repository.answerCalls, 2);
    expect(
      harness.controllers.single.configurationActiveEffort,
      const Duration(seconds: 60),
    );
    expect(
      await harness.database.select(harness.database.answerAttempts).get(),
      hasLength(2),
    );
    expect(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
      findsNothing,
    );
  });

  testWidgets(
    'f16 untimed Matching idle time never schedules wall-clock completion',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
        untimed: true,
      );

      expect(
        find.text(
          'Untimed accessibility session. Active effort remains bounded.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(hours: 1));
      await tester.pump();

      expect(find.byType(MatchingModeScreen), findsOneWidget);
      expect(find.byType(ScoreScreen), findsNothing);
      expect(harness.repository.finishCalls, 0);
    },
  );

  testWidgets(
    'f16 Flashcard boundary tap cannot write after finite effort expires',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await tester.ensureVisible(srsTile);
      await tester.pump();
      await _openConfiguredMode(
        tester,
        srsTile,
        itemCount: 1,
        timeLimitSeconds: 60,
      );
      harness.repository.blockConfigurationEffort();
      harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;

      await tester.tap(
        find.byKey(const ValueKey<String>('flashcard-remembered')),
      );
      await tester.runAsync(
        () => harness.repository.configurationEffortEntered.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.repository.releaseConfigurationEffort();
      await tester.pumpAndSettle();

      expect(harness.controllers.single.configurationLimitReached, isTrue);
      expect(harness.repository.answerCalls, 0);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'f16 Matching boundary tap cannot write after finite effort expires',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableMatching: true,
        deterministicConfigurationClock: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/matching')),
        itemCount: 2,
        timeLimitSeconds: 60,
      );
      const wordId = 'word:srs-gate-vocabulary';
      await tester.tap(
        find.byKey(const ValueKey<String>('matching-word-$wordId')),
      );
      await tester.pumpAndSettle();
      harness.repository.blockConfigurationEffort();
      harness.monotonicMicros = const Duration(seconds: 60).inMicroseconds;

      await tester.tap(
        find.byKey(const ValueKey<String>('matching-meaning-$wordId')),
      );
      await tester.runAsync(
        () => harness.repository.configurationEffortEntered.timeout(
          const Duration(seconds: 1),
        ),
      );
      harness.repository.releaseConfigurationEffort();
      await tester.pumpAndSettle();

      expect(harness.controllers.single.configurationLimitReached, isTrue);
      expect(harness.repository.answerCalls, 0);
      expect(
        await harness.database.select(harness.database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'SRS off synchronously fences a retained rating before terminal close',
    (tester) async {
      final harness = await _SrsGateHarness.create(blockAbandon: true);
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await tester.ensureVisible(srsTile);
      await tester.pump();
      await _openConfiguredMode(tester, srsTile, itemCount: 1);

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
      final srsTile = find.byKey(const ValueKey<String>('home/learn/srs'));
      await tester.ensureVisible(srsTile);
      await tester.pump();
      await _openConfiguredMode(tester, srsTile, itemCount: 1);

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

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        itemCount: 1,
        settleAfterStart: false,
      );
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

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/cloze')),
        itemCount: 1,
        settleAfterStart: false,
      );
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
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
    );

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

  testWidgets(
    'typed route choice freezes hinted recognition until durable commit',
    (tester) async {
      final harness = await _SrsGateHarness.create();
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsBefore = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
        itemCount: 1,
        hintBudget: 2,
      );
      final controller = harness.controllers.single;
      final showStrategy = find.widgetWithText(FilledButton, 'Show strategy');
      tester.widget<FilledButton>(showStrategy).onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 1);

      final choice = find.byKey(
        const ValueKey<String>(
          'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
        ),
      );
      final submitChoice = tester.widget<FilledButton>(choice).onPressed!;
      harness.repository.armAnswerBlock();
      submitChoice();
      await tester.runAsync(
        () => harness.repository.answerEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      final revealContext = find.widgetWithText(FilledButton, 'Reveal context');
      tester.widget<FilledButton>(revealContext).onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 2);

      harness.repository.answerRelease.complete();
      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final attempt = (await tester.runAsync(() async {
        return (await harness.database
                .select(harness.database.answerAttempts)
                .get())
            .singleWhere((row) => row.promptMode == 'meaningChoice');
      }))!;
      final context = EvidenceContext.fromJson(
        (jsonDecode(attempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      final command = harness.repository.commands.single;
      final commandEventContext = EvidenceContext.fromJson(
        (command.event!.payload['evidenceContext'] as Map)
            .cast<String, Object?>(),
      );
      expect(attempt.isCorrect, isTrue);
      expect(
        command.evidenceContext.evidenceClass,
        EvidenceClass.guidedPractice,
      );
      expect(command.evidenceContext.hintLevel, 1);
      expect(commandEventContext.evidenceClass, EvidenceClass.guidedPractice);
      expect(commandEventContext.hintLevel, 1);
      expect(context.evidenceClass, EvidenceClass.guidedPractice);
      expect(context.hintLevel, 1);
      final srsAfter = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;
      expect(srsAfter, srsBefore);
      expect(controller.hintState!.hintLevel, 0);
    },
  );

  testWidgets(
    'typed recall freezes support through pending mutation then resets it',
    (tester) async {
      final harness = await _SrsGateHarness.create(
        enableTypedHintSequence: true,
      );
      addTearDown(harness.close);
      await harness.pump(tester);
      final srsBefore = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;

      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
        itemCount: 3,
        hintBudget: 2,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
          ),
        ),
      );
      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.tap(next);
      final input = find.byKey(const ValueKey<String>('typed-recall-input'));
      for (var pump = 0; pump < 50 && input.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(find.text('able to recover'), findsOneWidget);
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Show strategy'),
          )
          .onPressed!();
      await tester.pump();
      expect(
        find.text(
          'Recall the spelling pattern before entering the whole word.',
        ),
        findsOneWidget,
      );
      final controller = harness.controllers.single;
      expect(controller.hintState!.hintLevel, 1);

      harness.repository.armAnswerBlock();
      await tester.enterText(input, 'resilient');
      final submit = find.byKey(const ValueKey<String>('typed-recall-submit'));
      await tester.pump();
      tester.widget<FilledButton>(submit).onPressed!();
      await tester.runAsync(
        () => harness.repository.answerEntered.future.timeout(
          const Duration(seconds: 1),
        ),
      );
      expect(
        controller.hintState!.hintLevel,
        1,
        reason: 'per-item support must remain frozen while evidence is pending',
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Reveal context'),
          )
          .onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 2);

      harness.repository.answerRelease.complete();
      for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final typedAttempt = (await tester.runAsync(() async {
        return (await harness.database
                .select(harness.database.answerAttempts)
                .get())
            .singleWhere((attempt) => attempt.promptMode == 'typedRecall');
      }))!;
      final typedContext = EvidenceContext.fromJson(
        (jsonDecode(typedAttempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      final typedCommand = harness.repository.commands.singleWhere(
        (command) => command.promptMode == 'typedRecall',
      );
      final typedEventContext = EvidenceContext.fromJson(
        (typedCommand.event!.payload['evidenceContext'] as Map)
            .cast<String, Object?>(),
      );
      expect(typedAttempt.isCorrect, isTrue);
      expect(
        typedCommand.evidenceContext.evidenceClass,
        EvidenceClass.guidedPractice,
      );
      expect(typedCommand.evidenceContext.hintLevel, 1);
      expect(typedEventContext.evidenceClass, EvidenceClass.guidedPractice);
      expect(typedEventContext.hintLevel, 1);
      expect(typedContext.evidenceClass, EvidenceClass.guidedPractice);
      expect(typedContext.hintLevel, 1);
      final srsAfter = (await tester.runAsync(() async {
        return <Map<String, dynamic>>[
          for (final row
              in await harness.database
                  .select(harness.database.srsStates)
                  .get())
            row.toJson(),
        ];
      }))!;
      expect(srsAfter, srsBefore);
      expect(controller.hintState!.hintLevel, 0);
      expect(find.text('Show strategy'), findsOneWidget);

      tester.widget<FilledButton>(next).onPressed!();
      await tester.pump();
      expect(controller.hintState!.hintLevel, 0);
      expect(find.text('Show strategy'), findsOneWidget);
    },
  );

  testWidgets('Quiz off synchronously rejects a retained typed callback', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(
      blockAbandon: true,
      enableMatching: true,
    );
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz/typed-recall')),
      itemCount: 2,
      hintBudget: 2,
    );

    final choice = find.byKey(
      const ValueKey<String>(
        'meaning-quiz-option-word:srs-gate-vocabulary-lasting',
      ),
    );
    tester.widget<FilledButton>(choice).onPressed!();
    final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
    for (var pump = 0; pump < 50 && next.evaluate().isEmpty; pump++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    tester.widget<FilledButton>(next).onPressed!();
    final input = find.byKey(const ValueKey<String>('typed-recall-input'));
    for (var pump = 0; pump < 50 && input.evaluate().isEmpty; pump++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.tap(find.text('Show strategy'));
    await tester.pump();
    await tester.tap(find.text('Reveal context'));
    await tester.pump();
    expect(harness.controllers.single.hintState!.hintLevel, 2);
    await tester.enterText(input, 'stable');
    await tester.pump();
    final submit = find.byKey(const ValueKey<String>('typed-recall-submit'));
    final staleSubmit = tester.widget<FilledButton>(submit).onPressed!;

    harness.features.emergencyOff(Feature.quiz);
    staleSubmit();
    await tester.runAsync(
      () => harness.repository.abandonEntered.future.timeout(
        const Duration(seconds: 1),
      ),
    );
    harness.repository.abandonRelease.complete();
    await tester.pumpAndSettle();

    expect(
      harness.repository.answerCalls,
      1,
      reason: 'only the accepted first recognition may reach persistence',
    );
    final attempts = await harness.database
        .select(harness.database.answerAttempts)
        .get();
    expect(
      attempts.where((attempt) => attempt.promptMode == 'typedRecall'),
      isEmpty,
    );
  });

  testWidgets('Quiz off freezes time while accepted evidence settles', (
    tester,
  ) async {
    final harness = await _SrsGateHarness.create(blockAnswer: true);
    addTearDown(harness.close);
    await harness.pump(tester);
    await _openConfiguredMode(
      tester,
      find.byKey(const ValueKey<String>('home/learn/quiz')),
      itemCount: 1,
    );

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
      await _openConfiguredMode(
        tester,
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        itemCount: 1,
      );

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

const _testPackIdentity = ContentIdentity(
  type: ContentType.learningPack,
  id: 'pack:f16-pinned',
  revision: 3,
);

LearningPackDetail _testPinnedPack({
  List<String> vocabularyWordIds = const <String>['word:srs-gate-vocabulary'],
}) => LearningPackDetail(
  summary: LearningPackSummary(
    packId: _testPackIdentity.id,
    revision: _testPackIdentity.revision,
    title: 'Pinned f16 pack',
    cefrLevel: 'A1',
    topic: 'durability',
    skill: 'recognition',
    goal: 'practice',
    contentIdentity: _testPackIdentity,
  ),
  vocabularyWordIds: vocabularyWordIds,
);

final class _StaleSessionConfigurationProtocolProvider
    implements SessionConfigurationProtocolProvider {
  const _StaleSessionConfigurationProtocolProvider();

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(String ownerId) =>
      Future<SessionConfigurationProtocolLimits>.error(
        const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.staleProtocol,
        ),
      );
}

final class _OwnerSwitchingProtocolProvider
    implements SessionConfigurationProtocolProvider {
  _OwnerSwitchingProtocolProvider({
    required this.delegate,
    required this.database,
  });

  static const nextOwnerId = 'matching-recovery-next-owner';

  final SessionConfigurationProtocolProvider delegate;
  final AppDatabase database;
  bool _switched = false;

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async {
    final limits = await delegate.resolveForOwner(ownerId);
    if (_switched) return limits;
    _switched = true;
    await database.transaction(() async {
      await database.customStatement(
        'UPDATE local_owners SET is_active = 0 WHERE id = ?',
        <Object?>[ownerId],
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: nextOwnerId,
              createdAtUtcMs: DateTime.utc(
                2026,
                8,
                25,
                15,
                1,
              ).millisecondsSinceEpoch,
            ),
          );
    });
    return limits;
  }
}

final class _PinnedPackRepository implements LearningPackRepository {
  const _PinnedPackRepository(this.detail);

  final LearningPackDetail detail;

  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async {
    if (packId != detail.summary.packId ||
        revision != detail.summary.revision) {
      throw StateError('Pinned pack version unavailable.');
    }
    return detail;
  }

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      filter.matches(detail.summary)
      ? <LearningPackSummary>[detail.summary]
      : const <LearningPackSummary>[];
}

final class _SrsGateHarness {
  _SrsGateHarness._({
    required this.database,
    required this.features,
    required this.repository,
    required this.dependencies,
    required this.controllers,
    required this.activeTimes,
    required this.sessionConfigurations,
  });

  final AppDatabase database;
  final RuntimeFeatureRegistry features;
  final _CoordinatedLearningRepository repository;
  final AppDependencies dependencies;
  final List<UnifiedLessonController> controllers;
  final List<ActiveLearningTimeController> activeTimes;
  final DriftSessionConfigurationStore sessionConfigurations;
  int monotonicMicros = 0;

  static Future<_SrsGateHarness> create({
    bool delayDue = false,
    bool delayQuiz = false,
    bool blockAbandon = false,
    bool blockAnswer = false,
    bool blockFinish = false,
    bool loseAnswerAckOnce = false,
    bool loseMatchingCloseAckOnce = false,
    bool blockMatchingCheckpoint = false,
    bool enableMatching = false,
    bool enableTypedHintSequence = false,
    bool deterministicConfigurationClock = false,
    String? vocabularyCefrLevel = 'A1',
    LearningPackDetail? pinnedPack,
    bool staleProtocol = false,
    bool switchOwnerDuringProtocolResolution = false,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 8, 25, 15);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'srs-gate-owner',
      nowUtc: () => now,
    );
    var vocabularyId = 0;
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => switch (vocabularyId++) {
        0 || 1 => 'srs-gate-vocabulary',
        2 => 'srs-gate-vocabulary-two',
        _ => 'srs-gate-vocabulary-three',
      },
      nowUtc: () => now,
    );
    final category = await vocabulary.createCategory('SRS gate');
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'durable',
        meaning: 'lasting',
        partOfSpeech: 'adjective',
        cefrLevel: vocabularyCefrLevel,
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
    if (enableMatching || enableTypedHintSequence) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'stable',
          meaning: 'not likely to change',
          partOfSpeech: 'adjective',
        ),
      );
    }
    if (enableTypedHintSequence) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'resilient',
          meaning: 'able to recover',
          partOfSpeech: 'adjective',
        ),
      );
    }
    final repository = _CoordinatedLearningRepository(
      driftLearning,
      delayDue: delayDue,
      delayQuiz: delayQuiz,
      blockAbandon: blockAbandon,
      blockAnswer: blockAnswer,
      blockFinish: blockFinish,
      loseAnswerAckOnce: loseAnswerAckOnce,
      loseMatchingCloseAckOnce: loseMatchingCloseAckOnce,
      blockMatchingCheckpoint: blockMatchingCheckpoint,
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
    final modes = buildLessonModeRegistry(
      matchingDeliveryState: enableMatching
          ? LessonModeDeliveryState.enabled
          : LessonModeDeliveryState.implementedOff,
    );
    final research = InertResearchDependencies(database);
    final sessionConfigurations = DriftSessionConfigurationStore(database);
    final persistedSessionConfigurationProtocols =
        PersistedSessionConfigurationProtocolProvider(
          currentResearchState: research.assignedLearningEventContext,
          rolloutMode: research.evidencePolicyRolloutModeProvider,
          nowUtc: () => now,
          catalog: SessionConfigurationProtocolCatalog(
            baseline: const SessionConfigurationProtocolLimits.standard(),
          ),
        );
    final SessionConfigurationProtocolProvider sessionConfigurationProtocols =
        staleProtocol
        ? const _StaleSessionConfigurationProtocolProvider()
        : switchOwnerDuringProtocolResolution
        ? _OwnerSwitchingProtocolProvider(
            delegate: persistedSessionConfigurationProtocols,
            database: database,
          )
        : persistedSessionConfigurationProtocols;
    final studyPlanning = pinnedPack == null
        ? null
        : StudyPlanningUseCases(
            packs: _PinnedPackRepository(pinnedPack),
            progress: ProgressUseCases(
              owners: owners,
              queries: DriftProgressQueries(database),
              nowUtc: () => now,
            ),
          );
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
      sessionConfigurationProtocols: sessionConfigurationProtocols,
      sessionConfigurations: sessionConfigurations,
      currentActivityEvidence: CurrentActivityEvidenceAdapter(
        learning: learning,
      ),
      associativeLearning: InMemoryAssociativeLearningAdapter(),
      studyPlanning: studyPlanning,
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
          configurationMonotonicMicros: deterministicConfigurationClock
              ? () => harness.monotonicMicros
              : null,
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
      sessionConfigurations: sessionConfigurations,
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
    implements
        LearningRepository,
        LearningSessionLifecycleRepository,
        SessionConfiguredLearningRepository,
        LearningActivityRecoveryRepository,
        PinnedLearningContentRepository {
  _CoordinatedLearningRepository(
    this.delegate, {
    required this.delayDue,
    required this.delayQuiz,
    required this.blockAbandon,
    required this.blockAnswer,
    required this.blockFinish,
    required this._loseAnswerAckOnce,
    required this._loseMatchingCloseAckOnce,
    required this._blockMatchingCheckpoint,
  });

  final LearningRepository delegate;
  final bool delayDue;
  final bool delayQuiz;
  final bool blockAbandon;
  bool blockAnswer;
  final bool blockFinish;
  bool _loseAnswerAckOnce;
  bool _loseMatchingCloseAckOnce;
  bool _blockMatchingCheckpoint;
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
  final Completer<void> matchingTerminalAcknowledged = Completer<void>();
  final Completer<void> matchingCheckpointEntered = Completer<void>();
  final Completer<void> matchingCheckpointRelease = Completer<void>();
  final Completer<void> matchingCloseCommitted = Completer<void>();
  Completer<void>? _configurationEffortEntered;
  Completer<void>? _configurationEffortRelease;
  int abandonCalls = 0;
  int answerCalls = 0;
  int finishCalls = 0;
  int matchingCloseAppendCalls = 0;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];

  void armAnswerBlock() => blockAnswer = true;

  Future<void> get configurationEffortEntered =>
      _configurationEffortEntered!.future;

  void blockConfigurationEffort() {
    _configurationEffortEntered = Completer<void>();
    _configurationEffortRelease = Completer<void>();
  }

  void releaseConfigurationEffort() {
    final release = _configurationEffortRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

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
  Future<List<QuizWord>> listPinnedQuizWords({
    required String ownerId,
    required List<String> wordIds,
  }) => (delegate as PinnedLearningContentRepository).listPinnedQuizWords(
    ownerId: ownerId,
    wordIds: wordIds,
  );

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
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) => (delegate as SessionConfiguredLearningRepository)
      .loadSessionConfigurationState(ownerId: ownerId, sessionId: sessionId);

  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) async {
    final entered = _configurationEffortEntered;
    final release = _configurationEffortRelease;
    if (entered != null && release != null) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      _configurationEffortEntered = null;
      _configurationEffortRelease = null;
    }
    return (delegate as SessionConfiguredLearningRepository)
        .addSessionConfigurationActiveEffort(
          ownerId: ownerId,
          sessionId: sessionId,
          configurationIdentity: configurationIdentity,
          delta: delta,
        );
  }

  @override
  Future<void> startSessionWithCheckpoint({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
  }) => (delegate as LearningActivityRecoveryRepository)
      .startSessionWithCheckpoint(session: session, checkpoint: checkpoint);

  @override
  Future<LearningActivityRecovery?> loadLatestActivityRecovery({
    required String ownerId,
    required String activityType,
  }) => (delegate as LearningActivityRecoveryRepository)
      .loadLatestActivityRecovery(ownerId: ownerId, activityType: activityType);

  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    if (checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.state['pendingCloseAtUtc'] != null &&
        !checkpoint.terminalAcknowledged) {
      matchingCloseAppendCalls += 1;
    }
    if (_blockMatchingCheckpoint &&
        checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.state['pendingEvidence'] != null) {
      _blockMatchingCheckpoint = false;
      if (!matchingCheckpointEntered.isCompleted) {
        matchingCheckpointEntered.complete();
      }
      await matchingCheckpointRelease.future;
    }
    await (delegate as LearningActivityRecoveryRepository)
        .appendActivityCheckpoint(ownerId: ownerId, checkpoint: checkpoint);
    if (_loseMatchingCloseAckOnce &&
        checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.state['pendingCloseAtUtc'] != null &&
        !checkpoint.terminalAcknowledged) {
      _loseMatchingCloseAckOnce = false;
      if (!matchingCloseCommitted.isCompleted) {
        matchingCloseCommitted.complete();
      }
      throw StateError('simulated committed close checkpoint ack loss');
    }
    if (checkpoint.activityType == MatchingModeAdapter.activityType &&
        checkpoint.terminalAcknowledged &&
        !matchingTerminalAcknowledged.isCompleted) {
      matchingTerminalAcknowledged.complete();
    }
  }

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
    commands.add(command);
    if (blockAnswer) {
      if (!answerEntered.isCompleted) answerEntered.complete();
      await answerRelease.future;
    }
    final result = await delegate.recordAnswer(command);
    if (_loseAnswerAckOnce) {
      _loseAnswerAckOnce = false;
      throw StateError('simulated committed answer acknowledgement loss');
    }
    return result;
  }

  void releaseAll() {
    releaseConfigurationEffort();
    if (!dueRelease.isCompleted) dueRelease.complete();
    if (!quizRelease.isCompleted) quizRelease.complete();
    if (!answerRelease.isCompleted) answerRelease.complete();
    if (!abandonRelease.isCompleted) abandonRelease.complete();
    if (!finishRelease.isCompleted) finishRelease.complete();
    if (!matchingCheckpointRelease.isCompleted) {
      matchingCheckpointRelease.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

final class _InertSpeechGateway implements SpeechRecognitionGateway {
  @override
  bool get isListening => false;

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.unavailable;

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}
