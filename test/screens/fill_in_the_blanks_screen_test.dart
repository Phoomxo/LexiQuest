import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/accessibility_semantics_test_support.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var generatedId = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'cloze-screen-owner',
      nowUtc: () => DateTime.utc(2026, 8, 25, 9),
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
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await _insertWord(
      database,
      owner.id,
      'word:airport',
      'airport',
      2,
      _coreChecksum(spelling: 'airport', meaning: 'meaning'),
    );
    await _insertWord(
      database,
      owner.id,
      'word:station',
      'station',
      3,
      _coreChecksum(spelling: 'station', meaning: 'meaning'),
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'screen-${++generatedId}',
      nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'f09-screen'),
    );
  });

  tearDown(() => database.close());

  testWidgets(
    'optional sentence media preserves two-answer cloze evidence and final close',
    (tester) async {
      final provider = _ClozeVoiceProvider();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      final gateway = _ClozeSpeechGateway();
      final speech = SpeechPracticeUseCases(gateway);
      final research = InertResearchDependencies(database);
      final dependencies = AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.ready,
          supabase: RuntimeAvailability.ready,
          backends: RuntimeAvailability.ready,
        ),
        config: null,
        guestSessionService: _ClozeGuestSessionService(),
        quest: testQuestUseCases(),
        features: const BuildFeatureRegistry({
          Feature.speechPractice: FeatureState.enabled,
        }),
        voice: voice,
        speechPractice: speech,
        experiments: research.experiments,
        consents: research.consents,
        experimentAssignments: research.experimentAssignments,
        assignedLearningEventContext: research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            research.evidencePolicyRolloutModeProvider,
      );
      try {
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: dependencies,
            child: MaterialApp(
              navigatorObservers: [appRouteObserver],
              home: UnifiedLessonModeHost(
                adapter: const ClozeModeAdapter(),
                learning: learning,
                createController: (adapter) => UnifiedLessonController(
                  learning: learning,
                  adapter: adapter,
                ),
                builder: (_) => _screen(learning),
              ),
            ),
          ),
        );
        await _pumpUntilFound(tester, find.text('The _____ is busy.'));
        expect(find.byKey(const Key('sentence-practice-listen')), findsNothing);
        expect(find.byKey(const Key('sentence-practice-speak')), findsNothing);
        await _tapClozeControl(tester, 'cloze-mode-selected');
        await _tapClozeControl(tester, 'cloze-option-word:airport-airport');
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(provider.requests, isEmpty);
        expect(gateway.starts, 0);
        expect(find.byKey(const Key('sentence-practice-listen')), findsNothing);
        await _tapClozeControl(tester, 'cloze-submit-selected');
        await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: airport'));
        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        final sessionId = attempts.single.sessionId;
        final pointsBefore = await database
            .select(database.pointsLedgerEntries)
            .get();
        final rewardsBefore = await database
            .select(database.rewardTransactions)
            .get();
        final srsBefore = await database.select(database.srsStates).get();

        await _tapClozeControl(tester, 'sentence-practice-listen');
        await tester.pumpAndSettle();
        expect(provider.requests.single.text, 'The airport is busy.');
        await _tapClozeControl(tester, 'sentence-practice-speak');
        await tester.pumpAndSettle();
        expect(gateway.starts, 1);
        final firstCallback = gateway.onEvent!;
        firstCallback(_clozeSpeechEvent('The airport is busy.'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('ระบบได้ยินว่า… The airport is busy.'),
          findsOneWidget,
        );
        await _tapClozeControl(tester, 'sentence-practice-speak');
        await tester.pumpAndSettle();
        expect(gateway.starts, 2);
        final lateCallback = gateway.onEvent!;
        await _tapClozeControl(tester, 'sentence-practice-skip');
        await tester.pumpAndSettle();
        expect(find.textContaining('ระบบได้ยินว่า'), findsNothing);
        expect(await database.select(database.answerAttempts).get(), attempts);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          pointsBefore,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          rewardsBefore,
        );
        expect(await database.select(database.srsStates).get(), srsBefore);
        expect(await database.select(database.speechEvidence).get(), isEmpty);
        final sessionsBefore = await database
            .select(database.learningSessions)
            .get();
        expect(sessionsBefore, hasLength(1));
        expect(sessionsBefore.single.state, 'active');

        gateway.permission = Completer<MediaPermissionState>();
        await _tapClozeControl(tester, 'sentence-practice-speak');
        await tester.pumpAndSettle();
        expect(gateway.permissionRequests, 3);
        expect(gateway.starts, 2);
        await _tapClozeControl(tester, 'cloze-next');
        await _pumpUntilFound(tester, find.text('The _____ closes.'));
        gateway.permission!.complete(MediaPermissionState.granted);
        lateCallback(_clozeSpeechEvent('stale airport transcript'));
        await tester.pumpAndSettle();
        expect(gateway.starts, 2);
        expect(find.textContaining('stale airport transcript'), findsNothing);
        expect(find.byKey(const Key('sentence-practice-speak')), findsNothing);
        expect(await database.select(database.answerAttempts).get(), attempts);

        await _tapClozeControl(tester, 'cloze-mode-selected');
        await _tapClozeControl(tester, 'cloze-option-word:station-station');
        await _tapClozeControl(tester, 'cloze-submit-selected');
        await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: station'));
        expect(find.text('The station closes.'), findsOneWidget);
        lateCallback(_clozeSpeechEvent('stale airport transcript'));
        await tester.pump();
        expect(find.textContaining('stale airport transcript'), findsNothing);
        await _tapClozeControl(tester, 'cloze-next');
        await _pumpUntilFound(tester, find.byType(ScoreScreen));
        final finalAttempts = await database
            .select(database.answerAttempts)
            .get();
        expect(finalAttempts, hasLength(2));
        expect(finalAttempts.map((attempt) => attempt.sessionId).toSet(), {
          sessionId,
        });
        expect(
          finalAttempts.every(
            (attempt) => attempt.promptMode == 'clozeSelected',
          ),
          isTrue,
        );
        final sessions = await database.select(database.learningSessions).get();
        expect(sessions, hasLength(1));
        expect(sessions.single.state, 'completed');
        expect(await database.select(database.speechEvidence).get(), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        final permission = gateway.permission;
        if (permission != null && !permission.isCompleted) {
          permission.complete(MediaPermissionState.granted);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await speech.dispose();
        await voice.dispose();
      }
    },
  );

  testWidgets(
    'word cards can change before explicit confirmation and practice is optional',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: _screen(learning)));
      await _pumpUntilFound(tester, find.text('The _____ is busy.'));
      expect(find.text('The airport is busy.'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('cloze-mode-selected')),
      );
      await tester.pump();
      final wrong = find.byKey(
        const ValueKey<String>('cloze-option-word:airport-station'),
      );
      await tester.ensureVisible(wrong);
      await tester.pump();
      await tester.tap(wrong);
      await tester.pump();
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      final correct = find.byKey(
        const ValueKey<String>('cloze-option-word:airport-airport'),
      );
      await tester.ensureVisible(correct);
      await tester.pump();
      await tester.tap(correct);
      await tester.pump();
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      final confirm = find.byKey(
        const ValueKey<String>('cloze-submit-selected'),
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: airport'));
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(find.text('The airport is busy.'), findsOneWidget);
      final next = find.byKey(const ValueKey<String>('cloze-next'));
      await tester.ensureVisible(next);
      await tester.pump();
      await tester.tap(next);
      await _pumpUntilFound(tester, find.text('The _____ closes.'));
      expect(find.text('The airport is busy.'), findsNothing);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'f38 ultra review: selected cloze controls stay in response semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: _screen(learning),
        ),
      );

      await _pumpUntilFound(tester, find.text('The _____ is busy.'));
      expect(tester.takeException(), isNull);
      expect(find.text('คำตอบที่ถูก: airport'), findsNothing);

      final option = find.byKey(
        const ValueKey<String>('cloze-option-word:airport-airport'),
      );
      expect(
        option,
        findsNothing,
        reason: 'answers stay hidden before mode choice',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('cloze-mode-selected')),
      );
      await tester.pump();
      expectInsideAccessibilityRole(
        scope: find.byType(FillInTheBlanksScreen),
        descendant: option,
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'selected cloze choices are response controls',
      );
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
      final confirm = find.byKey(
        const ValueKey<String>('cloze-submit-selected'),
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: airport'));

      final attempt =
          (await database.select(database.answerAttempts).get()).single;
      final context = _context(attempt.evidenceContextJson);
      expect(attempt.promptMode, 'clozeSelected');
      expect(context.evidenceClass, EvidenceClass.recognition);
      expect(context.hintLevel, 0);
      expect(
        context.contentRevision,
        _evidenceContentRevision(
          promptMode: 'clozeSelected',
          wordId: 'word:airport',
          spelling: 'airport',
          meaning: 'meaning',
          revision: 2,
          artifactChecksum: _checksumB,
        ),
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'f38 ultra review: cloze committed feedback follows response controls',
    (tester) => withAccessibilitySemantics(tester, () async {
      await tester.pumpWidget(MaterialApp(home: _screen(learning)));
      await _pumpUntilFound(tester, find.text('The _____ is busy.'));
      await tester.tap(
        find.byKey(const ValueKey<String>('cloze-mode-selected')),
      );
      await tester.pump();
      final option = find.byKey(
        const ValueKey<String>('cloze-option-word:airport-airport'),
      );
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
      final confirm = find.byKey(
        const ValueKey<String>('cloze-submit-selected'),
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: airport'));

      final root = find.byType(FillInTheBlanksScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byKey(const ValueKey<String>('answer-feedback-panel')),
        role: AccessibilitySemanticRole.feedback,
      );
      expectRenderedAccessibilityTraversal(
        tester,
        scope: root,
        roles: const <AccessibilitySemanticRole>[
          AccessibilitySemanticRole.prompt,
          AccessibilitySemanticRole.responseAndInput,
          AccessibilitySemanticRole.feedback,
          AccessibilitySemanticRole.navigation,
        ],
      );
    }),
  );

  testWidgets(
    'f38 ultra review: typed cloze controls stay in response semantics',
    (tester) async {
      const adapter = ClozeModeAdapter();
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonModeHost(
            adapter: adapter,
            learning: learning,
            createController: (modeAdapter) => UnifiedLessonController(
              learning: learning,
              adapter: modeAdapter,
            ),
            builder: (_) => _screen(learning, adapter: adapter),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('The _____ is busy.'));
      expect(
        find.byKey(const ValueKey<String>('cloze-option-word:airport-airport')),
        findsNothing,
        reason: 'typed recall cannot be exposed to selected-mode answers',
      );
      await tester.tap(find.byKey(const ValueKey<String>('cloze-mode-typed')));
      await tester.pump();
      expectInsideAccessibilityRole(
        scope: find.byType(FillInTheBlanksScreen),
        descendant: find.byKey(const ValueKey<String>('cloze-typed-answer')),
        role: AccessibilitySemanticRole.responseAndInput,
        reason: 'typed cloze input must remain in the response region',
      );
      expectInsideAccessibilityRole(
        scope: find.byType(FillInTheBlanksScreen),
        descendant: find.byKey(const ValueKey<String>('cloze-submit-typed')),
        role: AccessibilitySemanticRole.responseAndInput,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('cloze-typed-answer')),
        ' AIRPORT ',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('cloze-submit-typed')),
      );
      await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: airport'));

      var attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(1));
      expect(attempts.single.promptMode, 'clozeTyped');
      expect(
        _context(attempts.single.evidenceContextJson).evidenceClass,
        EvidenceClass.independentRecall,
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('cloze-next')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('cloze-next')));
      await _pumpUntilFound(tester, find.text('The _____ closes.'));
      await tester.tap(find.text('ดูวิธีคิด'));
      await tester.tap(find.byKey(const ValueKey<String>('cloze-mode-typed')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('cloze-typed-answer')),
        'station',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('cloze-submit-typed')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('cloze-submit-typed')),
      );
      await _pumpUntilFound(tester, find.text('คำตอบที่ถูก: station'));

      attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(2));
      final guided = _context(attempts.last.evidenceContextJson);
      expect(guided.evidenceClass, EvidenceClass.guidedPractice);
      expect(guided.hintLevel, 1);
      expect(await database.select(database.srsStates).get(), hasLength(1));
    },
  );

  testWidgets(
    'f38 ultra review: cloze skip owns prompt and response semantics',
    (tester) async {
      final words = _reviewedWords();
      final first = words.first.copyWith(
        contentReviewState: ContentReviewState.unreviewed,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FillInTheBlanksScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const ClozeModeAdapter(),
            loadLexicalWords: (_) async => <VocabularyWord>[first, words.last],
          ),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('cloze-skip')),
      );
      expect(
        find.bySemanticsLabel(
          'ข้ามข้อนี้ เนื่องจากตัวอย่างเติมคำยังไม่ผ่านการตรวจทาน',
        ),
        findsOneWidget,
      );
      final root = find.byType(FillInTheBlanksScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.bySemanticsLabel(
          'ข้ามข้อนี้ เนื่องจากตัวอย่างเติมคำยังไม่ผ่านการตรวจทาน',
        ),
        role: AccessibilitySemanticRole.prompt,
      );
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byKey(const ValueKey<String>('cloze-skip')),
        role: AccessibilitySemanticRole.responseAndInput,
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      await tester.tap(find.byKey(const ValueKey<String>('cloze-skip')));
      await _pumpUntilFound(tester, find.text('The _____ closes.'));
      expect(await database.select(database.answerAttempts).get(), isEmpty);
    },
  );

  testWidgets('route terminal acceptance fences a retained cloze callback', (
    tester,
  ) async {
    const adapter = ClozeModeAdapter();
    final controller = UnifiedLessonController(
      learning: learning,
      adapter: adapter,
    );
    addTearDown(controller.dispose);
    final routeLifecycle = UnifiedLessonRouteLifecycle(
      controller,
      learning,
      () => DateTime.utc(2026, 8, 25, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: controller,
          routeLifecycle: routeLifecycle,
          builder: (_) => _screen(learning, adapter: adapter),
        ),
      ),
    );
    final option = find.byKey(
      const ValueKey<String>('cloze-option-word:airport-airport'),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('cloze-mode-selected')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('cloze-mode-selected')));
    await tester.pump();
    expect(option, findsOneWidget);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();
    final retained = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey<String>('cloze-submit-selected')),
        )
        .onPressed!;

    final terminal = routeLifecycle.retire();
    retained();
    await tester.runAsync(() => terminal);
    await tester.pumpAndSettle();

    expect(routeLifecycle.acceptsOperations, isFalse);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'abandoned');
  });

  testWidgets(
    'terminal claim during delayed metadata load never attaches review',
    (tester) async {
      const adapter = ClozeModeAdapter();
      final controller = UnifiedLessonController(
        learning: learning,
        adapter: adapter,
      );
      addTearDown(controller.dispose);
      final routeLifecycle = UnifiedLessonRouteLifecycle(
        controller,
        learning,
        () => DateTime.utc(2026, 8, 25, 12),
      );
      final loaderEntered = Completer<void>();
      final loaderRelease = Completer<List<VocabularyWord>>();
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonShell(
            controller: controller,
            routeLifecycle: routeLifecycle,
            builder: (_) => FillInTheBlanksScreen(
              categoryId: 'category:travel',
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              modeAdapter: adapter,
              loadLexicalWords: (_) {
                if (!loaderEntered.isCompleted) loaderEntered.complete();
                return loaderRelease.future;
              },
            ),
          ),
        ),
      );
      for (var pump = 0; pump < 50 && !loaderEntered.isCompleted; pump += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(loaderEntered.isCompleted, isTrue);

      final terminal = routeLifecycle.retire();
      loaderRelease.complete(_reviewedWords());
      await tester.runAsync(() => terminal);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(routeLifecycle.acceptsOperations, isFalse);
      expect(
        find.byKey(const ValueKey<String>('cloze-input-mode')),
        findsNothing,
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.single.state, 'abandoned');
    },
  );

  testWidgets('metadata load failure terminally abandons the durable session', (
    tester,
  ) async {
    const adapter = ClozeModeAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonModeHost(
          adapter: adapter,
          learning: learning,
          createController: (modeAdapter) =>
              UnifiedLessonController(learning: learning, adapter: modeAdapter),
          builder: (_) => FillInTheBlanksScreen(
            categoryId: 'category:travel',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: adapter,
            loadLexicalWords: (_) => Future<List<VocabularyWord>>.error(
              StateError('simulated metadata failure'),
            ),
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.text('กิจกรรมเติมคำไม่พร้อมใช้งาน ข้อมูลการเรียนไม่เปลี่ยนแปลง'),
    );
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions.where((session) => session.state == 'active'), isEmpty);
    expect(
      sessions.where((session) => session.state == 'abandoned'),
      hasLength(1),
    );
  });
}

Widget _screen(LearningUseCases learning, {ClozeModeAdapter? adapter}) =>
    FillInTheBlanksScreen(
      categoryId: 'category:travel',
      learning: learning,
      evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
      modeAdapter: adapter ?? const ClozeModeAdapter(),
      loadLexicalWords: (_) async => _reviewedWords(),
    );

EvidenceContext _context(String json) => EvidenceContext.fromJson(
  (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>(),
);

List<VocabularyWord> _reviewedWords() => <VocabularyWord>[
  _lexicalWord(
    id: 'word:airport',
    spelling: 'airport',
    revision: 2,
    coreChecksum: _coreChecksum(spelling: 'airport', meaning: 'meaning'),
    artifactChecksum: _checksumB,
    example: 'The airport is busy.',
  ),
  _lexicalWord(
    id: 'word:station',
    spelling: 'station',
    revision: 3,
    coreChecksum: _coreChecksum(spelling: 'station', meaning: 'meaning'),
    artifactChecksum: _checksumA,
    example: 'The station closes.',
  ),
];

VocabularyWord _lexicalWord({
  required String id,
  required String spelling,
  required int revision,
  required String coreChecksum,
  required String artifactChecksum,
  required String example,
}) => VocabularyWord(
  id: id,
  ownerId: 'owner:packaged',
  categoryId: 'category:travel',
  spelling: spelling,
  normalizedSpelling: normalizeVocabularyText(spelling),
  meaning: 'meaning',
  normalizedMeaning: 'meaning',
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026, 8, 1),
  updatedAtUtc: DateTime.utc(2026, 8, 2),
  contentRevision: revision,
  contentChecksumSha256: coreChecksum,
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: RichLexicalMetadata(
    verifiedContentRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
    examples: <String>[example],
  ),
);

String _coreChecksum({required String spelling, required String meaning}) =>
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

String _evidenceContentRevision({
  required String promptMode,
  required String wordId,
  required String spelling,
  required String meaning,
  required int revision,
  required String artifactChecksum,
}) {
  final checksum = LexicalPromptArtifactResolver.canonicalPromptChecksumSha256(
    promptMode: promptMode,
    coreChecksumSha256: _coreChecksum(spelling: spelling, meaning: meaning),
    verifiedArtifactRevision: revision,
    verifiedArtifactChecksumSha256: artifactChecksum,
  );
  return LexicalPromptArtifactResolver.formatEvidenceContentRevision(
    promptMode: promptMode,
    wordId: wordId,
    revision: revision,
    checksumSha256: checksum,
  );
}

Future<void> _insertWord(
  AppDatabase database,
  String ownerId,
  String id,
  String spelling,
  int revision,
  String checksum,
) => database
    .into(database.vocabularyWords)
    .insert(
      VocabularyWordsCompanion.insert(
        id: id,
        ownerId: ownerId,
        categoryId: 'category:travel',
        spelling: spelling,
        normalizedSpelling: spelling,
        meaning: 'meaning',
        normalizedMeaning: 'meaning',
        partOfSpeech: 'noun',
        source: const Value<String>('pack'),
        isGlobal: const Value<bool>(true),
        contentRevision: Value(revision),
        contentChecksumSha256: Value(checksum),
        contentProvenance: Value(ContentProvenance.packaged.name),
        contentReviewState: Value(ContentReviewState.approved.name),
        contentPublicationState: Value(ContentPublicationState.published.name),
        createdAtUtcMs: 1,
        updatedAtUtcMs: 1,
      ),
    );

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _tapClozeControl(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

SpeechRecognitionEvent _clozeSpeechEvent(String transcript) =>
    SpeechRecognitionEvent(
      transcript: transcript,
      isFinal: true,
      recognizedAtUtc: DateTime.utc(2026, 9, 8),
      engine: 'synthetic-cloze-test',
      locale: 'en-US',
      recognitionConfidence: 0.98,
    );

class _ClozeSpeechGateway implements SpeechRecognitionGateway {
  Completer<MediaPermissionState>? permission;
  SpeechEventCallback? onEvent;
  int starts = 0;
  int permissionRequests = 0;

  @override
  bool isListening = false;

  @override
  Future<MediaPermissionState> requestPermission() async {
    permissionRequests++;
    return permission == null
        ? MediaPermissionState.granted
        : permission!.future;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String) onStatus,
  }) async {}

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    starts++;
    isListening = true;
    this.onEvent = onEvent;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }

  @override
  Future<void> cancel() async {
    isListening = false;
  }
}

class _ClozeVoiceProvider implements VoiceProvider {
  final requests = <VoiceRequest>[];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
      playbackCompleted: Future<void>.value(),
    );
  }

  @override
  Future<void> stop() async {}
}

class _ClozeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-cloze-media');
}

const _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
