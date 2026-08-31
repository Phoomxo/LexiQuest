import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/accessibility/presentation/accessibility_scope.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/handwriting_scratchpad.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary_domain;
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/screens/definition_quiz_screen.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/matching_mode_screen.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/inert_research_dependencies.dart';
import '../support/accessibility_semantics_test_support.dart';
import '../support/production_accessibility_surface_matrix.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final screen in <Widget>[
      const LoginScreen(),
      const RegisterScreen(),
    ]) {
      testWidgets(
        '${screen.runtimeType} supports 200% text in ${brightness.name} mode',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: M3Theme.lightTheme,
              darkTheme: M3Theme.darkTheme,
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: screen,
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsWidgets);
          final context = tester.element(find.byType(Scaffold));
          expect(Theme.of(context).brightness, brightness);
        },
      );
    }

    testWidgets(
      'AnswerFeedbackPanel supports 200% text in ${brightness.name} mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: M3Theme.lightTheme,
            darkTheme: M3Theme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnswerFeedbackPanel(
                  feedback: AnswerFeedback.fromCommittedResult(
                    result: const AnswerRecordResult(
                      inserted: true,
                      isCorrect: false,
                      srs: null,
                    ),
                    context: const AnswerFeedbackContext(
                      canonicalCorrectAnswer: 'station',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Not quite'), findsOneWidget);
        expect(find.text('Correct answer: station'), findsOneWidget);
      },
    );
  }

  test(
    'f38 production gate: accessibility policy joins the exact real mode surface matrix',
    () {
      final declaredModes = AccessibilityPolicy.canonical().declarations.keys
          .toSet();
      expect(productionAccessibilitySurfaceTypes.keys.toSet(), declaredModes);
      expect(
        productionAccessibilitySurfaceTypes,
        hasLength(LessonMode.values.length),
        reason:
            'a declared canonical mode without a real widget gate must fail '
            'the release matrix closed',
      );
    },
  );

  for (final surface in productionAccessibilitySurfaceTypes.entries) {
    testWidgets(
      'f38 production gate: ${surface.key.name} real surface owns prompt response and navigation',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        Future<void> Function()? cleanup;
        final declaration =
            AccessibilityPolicy.canonical().declarations[surface.key]!;
        expect(
          declaration.modeOwnedSemanticRoles,
          const <AccessibilitySemanticRole>{
            AccessibilitySemanticRole.prompt,
            AccessibilitySemanticRole.responseAndInput,
            AccessibilitySemanticRole.navigation,
          },
        );

        try {
          cleanup = await _pumpCanonicalProductionSurface(tester, surface.key);
          expect(tester.takeException(), isNull);
          final root = find.byType(surface.value);
          expect(
            root,
            findsOneWidget,
            reason:
                '${surface.key.name} must exercise its real production widget',
          );
          final sortOrders = tester
              .widgetList<Semantics>(
                find.descendant(of: root, matching: find.byType(Semantics)),
              )
              .map((semantics) => semantics.properties.sortKey)
              .whereType<OrdinalSortKey>()
              .map((key) => key.order)
              .toSet();
          expect(
            sortOrders,
            containsAll(<double>[
              AccessibilitySemanticRole.prompt.index.toDouble(),
              AccessibilitySemanticRole.responseAndInput.index.toDouble(),
              AccessibilitySemanticRole.navigation.index.toDouble(),
            ]),
            reason:
                '${surface.key.name} must expose real prompt, response/action, '
                'and route-navigation regions rather than metadata alone',
          );
          expectRenderedAccessibilityTraversal(
            tester,
            scope: root,
            roles: const <AccessibilitySemanticRole>[
              AccessibilitySemanticRole.prompt,
              AccessibilitySemanticRole.responseAndInput,
              AccessibilitySemanticRole.navigation,
            ],
            reason:
                '${surface.key.name} must expose the roles in the rendered '
                'SemanticsNode traversal, not merely declare sort-key widgets',
          );
        } finally {
          if (cleanup != null) await cleanup();
          semanticsHandle.dispose();
        }
      },
    );
  }

  testWidgets(
    'AccessibilityScope preserves 200 percent text and exposes platform accessibility state',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ({double textScale, bool highContrast, bool reducedMotion})? state;
      await tester.pumpWidget(
        _accessibilityApp(
          textScale: 2,
          highContrast: true,
          disableAnimations: true,
          home: AccessibilityScope(
            child: Builder(
              builder: (context) {
                final presentation = AccessibilityScope.of(context);
                state = (
                  textScale: presentation.textScale,
                  highContrast: presentation.highContrast,
                  reducedMotion: presentation.reducedMotion,
                );
                return const Scaffold(
                  body: SingleChildScrollView(
                    child: Text('Accessible lesson content'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(state, (textScale: 2, highContrast: true, reducedMotion: true));
      expect(tester.takeException(), isNull);
      expect(find.text('Accessible lesson content'), findsOneWidget);
    },
  );

  testWidgets(
    'UnifiedLessonShell installs an inherited accessibility scope for production children',
    (tester) async {
      AccessibilityScope? installedScope;
      ({double textScale, bool highContrast, bool reducedMotion})? state;
      await tester.pumpWidget(
        _accessibilityApp(
          textScale: 1.5,
          highContrast: true,
          disableAnimations: true,
          home: Scaffold(
            body: UnifiedLessonShell(
              builder: (context) {
                installedScope = context
                    .findAncestorWidgetOfExactType<AccessibilityScope>();
                final presentation = AccessibilityScope.of(context);
                state = (
                  textScale: presentation.textScale,
                  highContrast: presentation.highContrast,
                  reducedMotion: presentation.reducedMotion,
                );
                return const Text('Production lesson child');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(installedScope, isNotNull);
      expect(state, (textScale: 1.5, highContrast: true, reducedMotion: true));
    },
  );

  testWidgets(
    'high contrast feedback retains text icon and live semantics instead of color alone',
    (tester) async {
      await tester.pumpWidget(
        _accessibilityApp(
          highContrast: true,
          home: AccessibilityScope(child: Scaffold(body: _incorrectFeedback())),
        ),
      );
      await tester.pump();

      expect(
        AccessibilityScope.of(
          tester.element(find.byType(Scaffold)),
        ).highContrast,
        isTrue,
      );
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(
        find.bySemanticsLabel('Not quite. Correct answer: station. Try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'f38 review: AccessibilityScope applies a concrete high contrast theme',
    (tester) async {
      ColorScheme? standardScheme;
      ColorScheme? highContrastScheme;
      bool? observedHighContrast;

      await tester.pumpWidget(
        _accessibilityApp(
          home: AccessibilityScope(
            child: Builder(
              builder: (context) {
                standardScheme = Theme.of(context).colorScheme;
                return const Scaffold(body: Text('Standard contrast'));
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        _accessibilityApp(
          highContrast: true,
          home: AccessibilityScope(
            child: Builder(
              builder: (context) {
                observedHighContrast = AccessibilityScope.of(
                  context,
                ).highContrast;
                highContrastScheme = Theme.of(context).colorScheme;
                return const Scaffold(body: Text('High contrast'));
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(observedHighContrast, isTrue);
      expect(standardScheme, isNotNull);
      expect(highContrastScheme, isNotNull);
      expect(
        highContrastScheme,
        isNot(standardScheme),
        reason:
            'the platform high-contrast signal must alter the descendant '
            'Theme instead of remaining metadata only',
      );
    },
  );

  testWidgets(
    'reduced motion keeps committed feedback readable and interactive',
    (tester) async {
      await tester.pumpWidget(
        _accessibilityApp(
          disableAnimations: true,
          home: AccessibilityScope(child: Scaffold(body: _incorrectFeedback())),
        ),
      );
      await tester.pump();

      expect(
        AccessibilityScope.of(
          tester.element(find.byType(Scaffold)),
        ).reducedMotion,
        isTrue,
      );
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    },
  );

  testWidgets(
    'scope gives handwriting typed and self-check alternatives focus and switch semantics',
    (tester) async {
      final controller = HandwritingScratchpadController();
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _accessibilityApp(
            home: AccessibilityScope(
              child: Scaffold(
                body: HandwritingScratchpad(controller: controller),
              ),
            ),
          ),
        );
        await tester.pump();

        final editable = find.byType(EditableText);
        final editableFocus = tester.widget<EditableText>(editable).focusNode;
        expect(find.byType(FocusTraversalGroup), findsWidgets);
        editableFocus.requestFocus();
        await tester.pump();
        expect(editableFocus.hasFocus, isTrue);
        final editableSemantics = tester
            .getSemantics(editable)
            .getSemanticsData();
        expect(editableSemantics.flagsCollection.isTextField, isTrue);
        expect(
          editableSemantics.flagsCollection.isEnabled.toBoolOrNull() == true,
          isTrue,
          reason: 'the typed alternative must remain enabled for switch input',
        );
        expect(
          editableSemantics.hasAction(SemanticsAction.tap),
          isTrue,
          reason:
              'the typed alternative must be directly editable by semantics',
        );
        expect(
          tester
              .getSemantics(find.widgetWithText(FilledButton, 'I checked it'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester
              .getSemantics(
                find.widgetWithText(OutlinedButton, 'I need more practice'),
              )
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNot(same(editableFocus)));
        expect(find.text('Typed accessibility alternative'), findsOneWidget);
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'scope cannot invent an untimed alternative beyond adapter capabilities',
    (tester) async {
      final registry = buildLessonModeRegistry();
      final matching = registry.registrations.singleWhere(
        (registration) => registration.mode == LessonMode.matching,
      );
      final policy = AccessibilityPolicy.canonical();

      await tester.pumpWidget(
        _accessibilityApp(
          disableAnimations: true,
          home: AccessibilityScope(
            child: const Scaffold(
              body: Text('Session configuration remains authoritative'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        policy.declarations[matching.mode]!.supportsUntimedAlternative,
        (matching.adapter as SessionConfigurableLessonModeAdapter)
            .sessionConfigurationCapabilities
            .supportsUntimedAlternative,
      );
      expect(
        AccessibilityScope.of(
          tester.element(find.byType(Scaffold)),
        ).reducedMotion,
        isTrue,
      );
    },
  );

  testWidgets(
    'f38 mode surfaces: SRS reduced motion reveals the authorized card immediately',
    (tester) async {
      final voice = _f38VoiceUseCases();
      try {
        await _pumpReducedMotionLegacyFlashcard(tester, voice: voice);
        await tester.pumpAndSettle();

        expect(find.text('station'), findsOneWidget);
        await tester.tap(find.text('station'));
        await tester.pump();

        expect(find.text('สถานี'), findsOneWidget);
        expect(find.textContaining('Good'), findsOneWidget);
        expect(find.textContaining('Again'), findsOneWidget);
      } finally {
        await _disposeCanonicalProductionSurface(tester, <VoiceUseCases>[
          voice,
        ]);
      }
    },
  );

  testWidgets(
    'f38 mode surfaces: word scramble is static and keyboard selectable when motion is reduced',
    (tester) async {
      final letters = createStableScramble('ab');
      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _accessibilityApp(
            disableAnimations: true,
            home: const WordScrambleScreen(word: 'ab'),
          ),
        );
        await tester.pump();

        expect(
          tester
              .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
              .map((container) => container.duration)
              .toSet(),
          <Duration>{Duration.zero},
          reason: 'reduced motion must not retain the 300 ms slot transition',
        );
        expect(find.byType(Draggable<int>), findsNWidgets(letters.length));

        for (var index = 0; index < letters.length; index++) {
          final letter = letters[index];
          final control = find.bySemanticsLabel('Select letter $letter');
          expect(control, findsOneWidget);
          expect(
            tester
                .getSemantics(control)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
            reason: '$letter must be usable by keyboard and switch input',
          );

          await tester.tap(control);
          await tester.pump();
          expect(
            find.descendant(
              of: find.byType(DragTarget<int>).at(index),
              matching: find.text(letter),
            ),
            findsOneWidget,
            reason: 'the action must select the next empty response slot',
          );
        }
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'f38 mode surfaces: unavailable voice activities expose only a safe alternative action',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        for (final scenario in <({String name, Widget screen})>[
          (
            name: 'dictation',
            screen: const DictationQuizScreen(targetWord: 'station'),
          ),
          (
            name: 'speaking',
            screen: const SpeakToTextScreen(correctWord: 'station'),
          ),
          (
            name: 'shadowing',
            screen: const ShadowingChallengeScreen(
              referenceSentence: 'Keep going',
            ),
          ),
        ]) {
          await tester.pumpWidget(MaterialApp(home: scenario.screen));
          await tester.pump();

          expect(
            find.byType(MediaDependencyUnavailable),
            findsOneWidget,
            reason: '${scenario.name} must remain fail closed without media',
          );
          final alternative = find.bySemanticsLabel(
            'Choose a non-media activity',
          );
          expect(
            alternative,
            findsOneWidget,
            reason:
                '${scenario.name} needs an explicit focusable exit to a safe '
                'non-media alternative',
          );
          expect(
            tester
                .getSemantics(alternative)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(
            find.byType(EditableText),
            findsNothing,
            reason:
                '${scenario.name} must not fabricate a typed speech or '
                'dictation result while media is unavailable',
          );
          expect(
            find.text('ถูกต้อง'),
            findsNothing,
            reason:
                '${scenario.name} must not create feedback or evidence from '
                'the unavailable-media state',
          );
        }
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'f38 review: word scramble letter controls fit and work at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(240, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semanticsHandle = tester.ensureSemantics();
      try {
        final letters = createStableScramble('ab');
        await tester.pumpWidget(
          _accessibilityApp(
            textScale: 2,
            home: const WordScrambleScreen(word: 'ab'),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final letter in letters) {
          final control = find.bySemanticsLabel('Select letter $letter');
          final label = find.descendant(
            of: control,
            matching: find.text(letter),
          );
          expect(control, findsOneWidget);
          expect(label, findsOneWidget);
          final controlSize = tester.getSize(control);
          final labelSize = tester.getSize(label);
          expect(
            controlSize.height,
            greaterThanOrEqualTo(labelSize.height + 8),
            reason: '$letter must not be vertically clipped at 200% text',
          );
          expect(
            controlSize.width,
            greaterThanOrEqualTo(labelSize.width + 8),
            reason: '$letter must not be horizontally clipped at 200% text',
          );
          expect(
            tester
                .getSemantics(control)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
        }

        await tester.tap(
          find.bySemanticsLabel('Select letter ${letters.first}'),
        );
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(DragTarget<int>).first,
            matching: find.text(letters.first),
          ),
          findsOneWidget,
        );
      } finally {
        semanticsHandle.dispose();
      }
    },
  );
}

Future<Future<void> Function()> _pumpCanonicalProductionSurface(
  WidgetTester tester,
  LessonMode mode,
) async {
  final voices = <VoiceUseCases>[];

  VoiceUseCases voiceFixture() {
    final voice = _f38VoiceUseCases();
    voices.add(voice);
    return voice;
  }

  Future<void> cleanup() => _disposeCanonicalProductionSurface(tester, voices);

  if (mode == LessonMode.flashcard) {
    await _pumpReducedMotionLegacyFlashcard(
      tester,
      voice: voiceFixture(),
      throughLessonHost: true,
    );
    await _pumpUntilVisible(
      tester,
      find.bySemanticsLabel('Reveal answer for station'),
    );
    expect(find.byType(UnifiedLessonModeHost), findsOneWidget);
    return cleanup;
  }

  Widget screen;
  Finder ready;
  _F38ProductionLearningFixture? fixture;
  switch (mode) {
    case LessonMode.associativeReading:
      fixture = await _F38ProductionLearningFixture.create(mode);
      screen = AssociativeReadingSessionScreen(
        cefrLevel: 'A2',
        targetWords: const <String>['station'],
        passageText: 'The station is open.',
        documentId: 'reading:f38-production-gate',
        learning: fixture.learning,
        evidenceAdapter: fixture.evidence,
        modeAdapter: const TypedRecallModeAdapter(),
        associativeLearning: InMemoryAssociativeLearningAdapter(),
        ownerId: fixture.ownerId,
        targetWordIds: const <String, String>{'station': 'word:station'},
      );
      ready = find.text('Stage 1: Supported Reading');
    case LessonMode.meaningQuiz:
      fixture = await _F38ProductionLearningFixture.create(mode);
      screen = QuizScreen(
        categoryId: 'category:travel',
        learning: fixture.learning,
        evidenceAdapter: fixture.evidence,
        modeAdapter: const MeaningQuizModeAdapter(),
      );
      ready = find.byKey(const ValueKey<String>('meaning-quiz-prompt'));
    case LessonMode.typedRecall:
      fixture = await _F38ProductionLearningFixture.create(mode);
      screen = QuizScreen.typedRecall(
        categoryId: 'category:travel',
        learning: fixture.learning,
        evidenceAdapter: fixture.evidence,
        modeAdapter: const TypedRecallModeAdapter(),
      );
      ready = find.byKey(const ValueKey<String>('meaning-quiz-prompt'));
    case LessonMode.definitionQuiz:
      fixture = await _F38ProductionLearningFixture.create(mode);
      screen = DefinitionQuizScreen(
        categoryId: 'category:travel',
        learning: fixture.learning,
        evidenceAdapter: fixture.evidence,
        modeAdapter: const DefinitionQuizModeAdapter(),
        loadLexicalWords: (_) async => _f38ReviewedWords(mode),
      );
      ready = find.byKey(const ValueKey<String>('definition-quiz-prompt'));
    case LessonMode.cloze:
      fixture = await _F38ProductionLearningFixture.create(mode);
      screen = FillInTheBlanksScreen(
        categoryId: 'category:travel',
        learning: fixture.learning,
        evidenceAdapter: fixture.evidence,
        modeAdapter: const ClozeModeAdapter(),
        loadLexicalWords: (_) async => _f38ReviewedWords(mode),
      );
      ready = find.byKey(const ValueKey<String>('cloze-prompt'));
    case LessonMode.matching:
      fixture = await _F38ProductionLearningFixture.create(mode);
      screen = MatchingModeScreen(
        categoryId: 'category:travel',
        learning: fixture.learning,
        evidenceAdapter: fixture.evidence,
        modeAdapter: const MatchingModeAdapter(),
        timeLimit: const Duration(minutes: 10),
      );
      ready = find.bySemanticsLabel('0 of 3 pairs matched');
    case LessonMode.flashcard:
      throw StateError('flashcard is mounted by its compatibility authority');
    case LessonMode.handwritingScratchpad:
      screen = const Scaffold(body: HandwritingScratchpad());
      ready = find.text('Typed accessibility alternative');
    case LessonMode.dictation:
      screen = DictationQuizScreen(
        targetWord: 'station',
        voice: voiceFixture(),
      );
      ready = find.text('ตรวจคำตอบ');
    case LessonMode.speaking:
      screen = SpeakToTextScreen(
        correctWord: 'station',
        voice: voiceFixture(),
        speechPractice: SpeechPracticeUseCases(_F38PassiveSpeechGateway()),
      );
      ready = find.text('พูดคำว่า');
    case LessonMode.shadowing:
      screen = ShadowingChallengeScreen(
        referenceSentence: 'Keep going',
        voice: voiceFixture(),
        speechPractice: SpeechPracticeUseCases(_F38PassiveSpeechGateway()),
      );
      ready = find.text('ฟังเสียงต้นแบบ (1.0x)');
    case LessonMode.cefrReading:
      screen = CefrArticleReaderScreen(
        title: 'Travel by train',
        content: 'The station is open.',
        cefrLevel: 'A2',
        voice: voiceFixture(),
      );
      ready = find.text('Travel by train');
    case LessonMode.sentenceScramble:
      screen = SentenceScrambleScreen(
        targetSentence: 'Keep going',
        translation: 'เดินหน้าต่อไป',
        voice: voiceFixture(),
      );
      ready = find.text('เดินหน้าต่อไป');
    case LessonMode.wordScramble:
      screen = const WordScrambleScreen(word: 'station');
      ready = find.text('ตรวจสอบคำตอบ');
  }

  final productionFixture =
      fixture ?? await _F38ProductionLearningFixture.create(mode);
  final productionSurface = mode == LessonMode.associativeReading
      ? screen
      : UnifiedLessonModeHost(
          adapter: buildLessonModeRegistry().find(mode)!.adapter,
          learning: productionFixture.learning,
          createController: (adapter) => UnifiedLessonController(
            learning: productionFixture.learning,
            adapter: adapter,
          ),
          builder: (_) => screen,
        );
  final wrapped = _accessibilityApp(
    home: mode == LessonMode.associativeReading
        ? AccessibilityScope(child: productionSurface)
        : productionSurface,
  );
  await tester.pumpWidget(wrapped);
  await _pumpUntilVisible(
    tester,
    ready,
    maxAttempts: mode == LessonMode.associativeReading ? 100 : 50,
    delay: mode == LessonMode.associativeReading
        ? const Duration(milliseconds: 20)
        : const Duration(milliseconds: 10),
  );
  if (mode != LessonMode.associativeReading) {
    expect(find.byType(UnifiedLessonModeHost), findsOneWidget);
  }
  return cleanup;
}

Future<void> _disposeCanonicalProductionSurface(
  WidgetTester tester,
  List<VoiceUseCases> voices,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  for (final voice in voices.reversed) {
    await voice.dispose();
  }
  await tester.pump();
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 50,
  Duration delay = const Duration(milliseconds: 10),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    await tester.runAsync(() => Future<void>.delayed(delay));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the real production surface: $finder');
}

VoiceUseCases _f38VoiceUseCases() => VoiceUseCases(
  provider: const _F38SilentVoiceProvider(),
  disposeProvider: () async {},
);

final class _F38PassiveSpeechGateway implements SpeechRecognitionGateway {
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _F38ProductionLearningFixture {
  const _F38ProductionLearningFixture({
    required this.ownerId,
    required this.learning,
    required this.evidence,
  });

  final String ownerId;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;

  static Future<_F38ProductionLearningFixture> create(LessonMode mode) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 30, 9);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'f38-surface-${mode.name}',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category:travel',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: now.millisecondsSinceEpoch,
            updatedAtUtcMs: now.millisecondsSinceEpoch,
          ),
        );
    for (final word in _f38FixtureWords(mode)) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.id,
              ownerId: owner.id,
              categoryId: 'category:travel',
              spelling: word.spelling,
              normalizedSpelling: word.spelling,
              meaning: word.meaning,
              normalizedMeaning: word.meaning,
              partOfSpeech: 'noun',
              source: const Value<String>('pack'),
              isGlobal: const Value<bool>(true),
              contentRevision: Value(word.revision),
              contentChecksumSha256: Value(word.checksum),
              contentProvenance: Value(ContentProvenance.packaged.name),
              contentReviewState: Value(ContentReviewState.approved.name),
              contentPublicationState: Value(
                ContentPublicationState.published.name,
              ),
              createdAtUtcMs: now.millisecondsSinceEpoch,
              updatedAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );
    }
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'f38-${mode.name}-${++nextId}',
      nowUtc: () => now.add(Duration(milliseconds: nextId)),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'f38-surface'),
    );
    final evidence = CurrentActivityEvidenceAdapter(learning: learning);
    return _F38ProductionLearningFixture(
      ownerId: owner.id,
      learning: learning,
      evidence: evidence,
    );
  }
}

List<vocabulary_domain.VocabularyWord> _f38ReviewedWords(LessonMode mode) =>
    <vocabulary_domain.VocabularyWord>[
      _f38ReviewedWord(
        id: 'word:airport',
        spelling: 'airport',
        meaning: mode == LessonMode.cloze ? 'meaning' : 'ความหมาย',
        revision: 2,
        checksum: _f38CoreChecksum(
          spelling: 'airport',
          meaning: mode == LessonMode.cloze ? 'meaning' : 'ความหมาย',
        ),
        artifactChecksum: _f38ChecksumB,
        definition: 'A place where aircraft arrive and depart.',
        example: 'The airport is busy.',
      ),
      _f38ReviewedWord(
        id: 'word:station',
        spelling: 'station',
        meaning: mode == LessonMode.cloze ? 'meaning' : 'ความหมาย',
        revision: 3,
        checksum: _f38CoreChecksum(
          spelling: 'station',
          meaning: mode == LessonMode.cloze ? 'meaning' : 'ความหมาย',
        ),
        artifactChecksum: _f38ChecksumA,
        definition: 'A place where trains stop for passengers.',
        example: 'The station closes.',
      ),
    ];

vocabulary_domain.VocabularyWord _f38ReviewedWord({
  required String id,
  required String spelling,
  required String meaning,
  required int revision,
  required String checksum,
  required String artifactChecksum,
  required String definition,
  required String example,
}) => vocabulary_domain.VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling,
  normalizedSpelling: normalizeVocabularyText(spelling),
  meaning: meaning,
  normalizedMeaning: normalizeVocabularyText(meaning),
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 8, 1),
  updatedAtUtc: DateTime.utc(2026, 8, 2),
  contentRevision: revision,
  contentChecksumSha256: checksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: vocabulary_domain.RichLexicalMetadata(
    englishDefinition: definition,
    verifiedContentRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
    examples: <String>[example],
  ),
);

List<
  ({String id, String spelling, String meaning, int revision, String checksum})
>
_f38FixtureWords(LessonMode mode) {
  final values = switch (mode) {
    LessonMode.associativeReading => const <(String, String, String, int)>[],
    LessonMode.definitionQuiz => const <(String, String, String, int)>[
      ('word:airport', 'airport', 'ความหมาย', 2),
      ('word:station', 'station', 'ความหมาย', 3),
    ],
    LessonMode.cloze => const <(String, String, String, int)>[
      ('word:airport', 'airport', 'meaning', 2),
      ('word:station', 'station', 'meaning', 3),
    ],
    LessonMode.matching => const <(String, String, String, int)>[
      ('word:airport', 'airport', 'place for flights', 1),
      ('word:station', 'station', 'place for trains', 1),
      ('word:market', 'market', 'place to buy goods', 1),
    ],
    _ => const <(String, String, String, int)>[
      ('word:airport', 'airport', 'สนามบิน', 1),
      ('word:station', 'station', 'สถานี', 1),
    ],
  };
  return <
    ({
      String id,
      String spelling,
      String meaning,
      int revision,
      String checksum,
    })
  >[
    for (final value in values)
      (
        id: value.$1,
        spelling: value.$2,
        meaning: value.$3,
        revision: value.$4,
        checksum: _f38CoreChecksum(spelling: value.$2, meaning: value.$3),
      ),
  ];
}

String _f38CoreChecksum({required String spelling, required String meaning}) =>
    ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'category:travel',
      spelling: spelling,
      normalizedSpelling: spelling,
      meaning: meaning,
      normalizedMeaning: meaning,
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'pack',
      isGlobal: true,
    );

const _f38ChecksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _f38ChecksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Widget _accessibilityApp({
  required Widget home,
  double textScale = 1,
  bool highContrast = false,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: M3Theme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      highContrast: highContrast,
      disableAnimations: disableAnimations,
    ),
    child: child!,
  ),
  home: home,
);

Widget _incorrectFeedback() => AnswerFeedbackPanel(
  feedback: AnswerFeedback.fromCommittedResult(
    result: const AnswerRecordResult(
      inserted: true,
      isCorrect: false,
      srs: null,
    ),
    context: const AnswerFeedbackContext(canonicalCorrectAnswer: 'station'),
  ),
  onRetry: () {},
);

Future<void> _pumpReducedMotionLegacyFlashcard(
  WidgetTester tester, {
  required VoiceUseCases voice,
  bool throughLessonHost = false,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'f38-srs-owner',
    nowUtc: () => DateTime.utc(2026, 8, 30),
  );
  final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: () => 'f38-srs-learning',
    nowUtc: () => DateTime.utc(2026, 8, 30),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'f38-srs'),
  );
  final research = InertResearchDependencies(database);
  final dependencies = AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: const _F38GuestSession(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
    features: const BuildFeatureRegistry.allEnabled(),
    database: database,
    localOwners: owners,
    learning: learning,
  );
  final route = SrsFlashcardCompatibilityRoute(
    wordList: const <Map<String, String>>[
      <String, String>{
        'word': 'station',
        'translation': 'สถานี',
        'example': 'The train leaves the station.',
      },
    ],
    voice: voice,
  );
  final adapter = buildLessonModeRegistry().find(LessonMode.flashcard)!.adapter;
  final home = throughLessonHost
      ? UnifiedLessonModeHost(
          adapter: adapter,
          learning: learning,
          createController: (modeAdapter) =>
              UnifiedLessonController(learning: learning, adapter: modeAdapter),
          builder: (_) => route,
        )
      : route;
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: _accessibilityApp(disableAnimations: true, home: home),
    ),
  );
}

final class _F38GuestSession implements GuestSessionService {
  const _F38GuestSession();

  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

final class _F38SilentVoiceProvider implements VoiceProvider {
  const _F38SilentVoiceProvider();

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );

  @override
  Future<void> stop() async {}
}
