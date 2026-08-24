import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/flashcard_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SharedPreferences mock removed — SrsService dependency eliminated (Phase 0 W14-15).
  });

  testWidgets('SrsFlashcardsScreen renders front side and auto-plays audio', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final wordList = [
      {
        'word': 'apple',
        'translation': 'แอปเปิ้ล',
        'example': 'An apple a day.',
      },
    ];

    await _pumpLegacyCompatibility(
      tester,
      wordList: wordList,
      voice: VoiceUseCases(provider: fakeVoice, disposeProvider: () async {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(fakeVoice.spokenRequests.length, 1);
  });

  testWidgets('background stops the auto-play route session', (tester) async {
    final provider = FakeVoiceProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await _pumpLegacyCompatibility(
        tester,
        wordList: const [
          {'word': 'apple', 'translation': 'apple', 'example': 'apple'},
        ],
        voice: voice,
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => provider.stopEntered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );

      expect(provider.stopCalls, 1);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets('a due-review load completed in background cannot start voice', (
    tester,
  ) async {
    final repository = _DeferredLearningRepository();
    final learning = LearningUseCases(
      owners: _ScenarioOwnerRepository(),
      repository: repository,
      generateId: () => 'session',
      nowUtc: () => DateTime.utc(2026, 8, 11),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    final provider = FakeVoiceProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            voice: voice,
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const FlashcardModeAdapter(),
          ),
        ),
      );
      await tester.runAsync(
        () => repository.entered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      repository.due.complete(const <QuizWord>[
        QuizWord(
          id: 'word-1',
          categoryId: 'category-1',
          spelling: 'deferred',
          meaning: 'late',
          partOfSpeech: 'adjective',
        ),
      ]);
      await tester.pump();
      await tester.pump();

      expect(provider.spokenRequests, isEmpty);
    } finally {
      if (!repository.due.isCompleted) repository.due.complete(const []);
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets(
    'Tapping card flips to back side displaying translation and buttons',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();
      final wordList = [
        {
          'word': 'banana',
          'translation': 'กล้วย',
          'example': 'Monkeys eat bananas.',
        },
      ];

      await _pumpLegacyCompatibility(
        tester,
        wordList: wordList,
        voice: VoiceUseCases(provider: fakeVoice, disposeProvider: () async {}),
      );
      await tester.pumpAndSettle();

      // Tap card to flip
      await tester.tap(find.text('banana'));
      await tester.pumpAndSettle();

      expect(find.text('จำได้แล้ว (Good)'), findsOneWidget);
      expect(find.text('จำไม่ได้ (Again)'), findsOneWidget);

      // Tap Good — compatibility deck: no-op (SrsService removed Phase 0 W14-15)
      await tester.tap(find.text('จำได้แล้ว (Good)'));
      await tester.pumpAndSettle();
      // UI advances to next card or shows empty state — no crash expected.
    },
  );

  testWidgets('load failure renders unavailable state without async leak', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SrsFlashcardsScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final remembered in <bool>[true, false]) {
    testWidgets(
      '${remembered ? 'remembered' : 'not-remembered'} retry reuses frozen evidence identity',
      (tester) async {
        final repository = _RetryLearningRepository();
        var nextId = 0;
        final learning = LearningUseCases(
          owners: _ScenarioOwnerRepository(),
          repository: repository,
          generateId: () => 'srs-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 11, 10, 0, nextId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        final voice = VoiceUseCases(
          provider: FakeVoiceProvider(),
          disposeProvider: () async {},
        );
        addTearDown(voice.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: SrsFlashcardsScreen(
              voice: voice,
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              modeAdapter: const FlashcardModeAdapter(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rating = find.byKey(
          ValueKey<String>(
            remembered ? 'flashcard-remembered' : 'flashcard-not-remembered',
          ),
        );
        await tester.tap(rating);
        await tester.pumpAndSettle();
        ScaffoldMessenger.of(
          tester.element(find.byType(SrsFlashcardsScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        expect(rating, findsNothing);
        final retryButton = find.byKey(
          const ValueKey<String>('current-evidence-retry'),
        );
        await tester.ensureVisible(retryButton);
        await tester.tap(retryButton);
        await tester.pumpAndSettle();

        expect(repository.commands, hasLength(2));
        final first = repository.commands.first;
        final retry = repository.commands.last;
        expect(retry.id, first.id);
        expect(retry.occurredAtUtc, first.occurredAtUtc);
        expect(retry.isCorrect, remembered);
        expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
        expect(
          retry.evidenceContext.evidenceClass,
          EvidenceClass.independentRecall,
        );
      },
    );
  }

  testWidgets(
    'assisted reveal stays exposure and survives an offline restart without changing SRS',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 25, 9);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'flashcard-owner',
        nowUtc: () => now,
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => 'flashcard-vocabulary-id',
        nowUtc: () => now,
      );
      final category = await vocabulary.createCategory('Flashcards');
      final word = await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'durable',
          meaning: 'lasting',
          partOfSpeech: 'adjective',
        ),
      );
      var nextId = 0;
      var clock = now.subtract(const Duration(days: 2));
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'flashcard-${++nextId}',
        nowUtc: () => clock.add(Duration(milliseconds: nextId)),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f06-test'),
      );
      final seedSession = await learning.startQuiz();
      await learning.recordEvidence(
        sourceEvidenceId: 'attempt:flashcard-seed',
        occurredAtUtc: clock,
        sessionId: seedSession.id,
        wordId: word.id,
        promptMode: 'srsRecall',
        isCorrect: true,
        responseTimeMs: 200,
        attemptNumber: 1,
        evidenceContext: EvidenceContext.legacyCompatibility(
          evidenceClass: EvidenceClass.independentRecall,
          skillId: 'srs-recall',
          hintLevel: 0,
          contentRevision: 'built-in-v1',
          engagementAllowed: true,
        ),
      );
      final before = (await database.select(database.srsStates).get()).single;
      clock = now;
      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const FlashcardModeAdapter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('durable'));
      for (
        var pump = 0;
        pump < 50 && find.text('lasting').evaluate().isEmpty;
        pump++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pumpAndSettle();

      final attempts = await database.select(database.answerAttempts).get();
      final srs = await database.select(database.srsStates).get();
      expect(attempts, hasLength(2));
      final exposure = attempts.singleWhere(
        (attempt) => attempt.promptMode == 'flashcardExposure',
      );
      expect(exposure.evidenceClass, EvidenceClass.exposure.name);
      expect(srs, hasLength(1));
      expect(srs.single.id, before.id);
      expect(srs.single.intervalDays, before.intervalDays);
      expect(srs.single.repetitions, before.repetitions);
      expect(srs.single.lapses, before.lapses);
      expect(srs.single.dueAtUtcMs, before.dueAtUtcMs);
      expect(find.text('lasting'), findsOneWidget);
      expect(find.text('จำได้แล้ว (Good)'), findsNothing);

      var restartId = 0;
      final restartedLearning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'flashcard-restart-${++restartId}',
        nowUtc: () => now.add(Duration(seconds: restartId)),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'f06-restart-test',
        ),
      );
      final dueAfterRestart = await restartedLearning.startDueReview();
      expect(dueAfterRestart.questions.single.word.id, word.id);
    },
  );

  testWidgets(
    'production controls remain accessible at narrow width and 200% text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _RetryLearningRepository(failAnswerOnce: false);
      final learning = LearningUseCases(
        owners: _ScenarioOwnerRepository(),
        repository: repository,
        generateId: () => 'accessible-flashcard',
        nowUtc: () => DateTime.utc(2026, 8, 25, 10),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f06-a11y'),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            home: SrsFlashcardsScreen(
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              modeAdapter: const FlashcardModeAdapter(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('durable'), findsOneWidget);
      expect(find.text('จำได้แล้ว (Good)'), findsOneWidget);
      expect(find.text('จำไม่ได้ (Again)'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Reveal answer for durable'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'final-card close failure keeps one answer and a route-safe close retry',
    (tester) async {
      final firstFinishRelease = Completer<void>();
      addTearDown(() {
        if (!firstFinishRelease.isCompleted) firstFinishRelease.complete();
      });
      final repository = _RetryLearningRepository(
        failAnswerOnce: false,
        failFinishOnce: true,
        firstFinishRelease: firstFinishRelease,
      );
      var nextId = 0;
      var clockTick = 0;
      final learning = LearningUseCases(
        owners: _ScenarioOwnerRepository(),
        repository: repository,
        generateId: () => 'srs-close-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 11, 11, 0, clockTick++),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final voice = VoiceUseCases(
        provider: FakeVoiceProvider(),
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const ValueKey<String>('open-srs-route'),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => SrsFlashcardsScreen(
                        voice: voice,
                        learning: learning,
                        evidenceAdapter: CurrentActivityEvidenceAdapter(
                          learning: learning,
                        ),
                        modeAdapter: const FlashcardModeAdapter(),
                      ),
                    ),
                  );
                },
                child: const Text('Open SRS review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('open-srs-route')));
      await tester.pumpAndSettle();
      final good = find.widgetWithText(FilledButton, 'จำได้แล้ว (Good)');
      final staleGoodHandler = tester.widget<FilledButton>(good).onPressed!;
      await tester.tap(good);
      for (var pump = 0; pump < 20 && repository.finishCalls.isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump();

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(1));
      expect(find.byType(SrsFlashcardsScreen), findsOneWidget);
      expect(find.text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว'), findsNothing);
      expect(good, findsNothing);
      expect(find.text('จำไม่ได้ (Again)'), findsNothing);

      firstFinishRelease.complete();
      await tester.pumpAndSettle();
      final retry = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      expect(
        retry,
        findsOneWidget,
        reason: 'a committed final answer still needs session-close retry',
      );
      expect(find.text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว'), findsNothing);
      expect(good, findsNothing);
      expect(find.text('จำไม่ได้ (Again)'), findsNothing);

      staleGoodHandler();
      await tester.pumpAndSettle();
      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(1));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byType(SrsFlashcardsScreen),
        findsOneWidget,
        reason: 'back must preserve the retry-required final session close',
      );

      final retryHandler = tester.widget<FilledButton>(retry).onPressed;
      expect(retryHandler, isNotNull);
      retryHandler!();
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(2));
      expect(repository.finishCalls.last, repository.finishCalls.first);
      expect(find.byType(SrsFlashcardsScreen), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('open-srs-route')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a successful final close stays terminal through the navigation frame',
    (tester) async {
      final firstFinishRelease = Completer<void>();
      addTearDown(() {
        if (!firstFinishRelease.isCompleted) firstFinishRelease.complete();
      });
      final repository = _RetryLearningRepository(
        failAnswerOnce: false,
        failFinishOnce: true,
        firstFinishRelease: firstFinishRelease,
      );
      var nextId = 0;
      final learning = LearningUseCases(
        owners: _ScenarioOwnerRepository(),
        repository: repository,
        generateId: () => 'srs-terminal-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 11, 12, 0, nextId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final voice = VoiceUseCases(
        provider: FakeVoiceProvider(),
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PopScope(
            canPop: false,
            child: SrsFlashcardsScreen(
              voice: voice,
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
              modeAdapter: const FlashcardModeAdapter(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final good = find.widgetWithText(FilledButton, 'จำได้แล้ว (Good)');
      final again = find.widgetWithText(OutlinedButton, 'จำไม่ได้ (Again)');
      final staleGoodHandler = tester.widget<FilledButton>(good).onPressed!;
      final staleAgainHandler = tester.widget<OutlinedButton>(again).onPressed!;
      await tester.tap(good);
      for (var pump = 0; pump < 20 && repository.finishCalls.isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      firstFinishRelease.complete();
      await tester.pumpAndSettle();

      final retry = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      final retryHandler = tester.widget<FilledButton>(retry).onPressed;
      expect(retryHandler, isNotNull);
      retryHandler!();
      for (
        var pump = 0;
        pump < 20 && repository.finishCalls.length < 2;
        pump++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      // Cross the production end-of-frame handoff without settling the
      // vetoed completion navigation.
      await tester.pump();

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(2));
      expect(find.byType(SrsFlashcardsScreen), findsOneWidget);
      expect(good, findsNothing);
      expect(again, findsNothing);

      staleGoodHandler();
      staleAgainHandler();
      for (
        var pump = 0;
        pump < 20 &&
            repository.commands.length == 1 &&
            repository.finishCalls.length == 2;
        pump++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        repository.commands,
        hasLength(1),
        reason: 'a terminal final card must reject retained rate callbacks',
      );
      expect(repository.finishCalls, hasLength(2));
      expect(good, findsNothing);
      expect(again, findsNothing);
    },
  );

  testWidgets(
    'stale flip and audio handlers stay locked through evidence and close',
    (tester) async {
      final firstAnswerRelease = Completer<void>();
      final firstFinishRelease = Completer<void>();
      addTearDown(() {
        if (!firstAnswerRelease.isCompleted) firstAnswerRelease.complete();
        if (!firstFinishRelease.isCompleted) firstFinishRelease.complete();
      });
      final repository = _RetryLearningRepository(
        failAnswerOnce: true,
        failFinishOnce: true,
        firstAnswerRelease: firstAnswerRelease,
        firstFinishRelease: firstFinishRelease,
      );
      var nextId = 0;
      final provider = FakeVoiceProvider();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      final learning = LearningUseCases(
        owners: _ScenarioOwnerRepository(),
        repository: repository,
        generateId: () => 'srs-lock-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 11, 13, 0, nextId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            voice: voice,
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const FlashcardModeAdapter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final audio = find.widgetWithIcon(IconButton, Icons.volume_up_outlined);
      final card = find
          .ancestor(
            of: find.text('durable'),
            matching: find.byType(GestureDetector),
          )
          .first;
      final staleAudioHandler = tester.widget<IconButton>(audio).onPressed!;
      final staleFlipHandler = tester.widget<GestureDetector>(card).onTap!;
      final good = find.widgetWithText(FilledButton, 'จำได้แล้ว (Good)');
      final staleGoodHandler = tester.widget<FilledButton>(good).onPressed!;
      final initialAudioCalls = provider.spokenRequests.length;

      staleGoodHandler();
      for (var pump = 0; pump < 20 && repository.commands.isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump();
      expect(repository.commands, hasLength(1));
      expect(
        tester.widget<IconButton>(audio).onPressed,
        isNull,
        reason: 'visible audio must disable while evidence is pending',
      );
      staleFlipHandler();
      staleAudioHandler();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('lasting'), findsNothing);
      expect(provider.spokenRequests, hasLength(initialAudioCalls));

      firstAnswerRelease.complete();
      await tester.pumpAndSettle();
      var retry = find.byKey(const ValueKey<String>('current-evidence-retry'));
      expect(retry, findsOneWidget);
      expect(
        find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(audio).onPressed, isNull);
      staleFlipHandler();
      staleAudioHandler();
      await tester.pump(const Duration(milliseconds: 500));
      expect(retry, findsOneWidget);
      expect(find.text('lasting'), findsNothing);
      expect(provider.spokenRequests, hasLength(initialAudioCalls));
      expect(
        find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );

      ScaffoldMessenger.of(
        tester.element(find.byType(SrsFlashcardsScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      final evidenceRetryHandler = tester.widget<FilledButton>(retry).onPressed;
      expect(evidenceRetryHandler, isNotNull);
      evidenceRetryHandler!();
      for (var pump = 0; pump < 20 && repository.finishCalls.isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump();
      expect(repository.commands, hasLength(2));
      expect(repository.finishCalls, hasLength(1));
      expect(tester.widget<IconButton>(audio).onPressed, isNull);
      staleFlipHandler();
      staleAudioHandler();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('lasting'), findsNothing);
      expect(provider.spokenRequests, hasLength(initialAudioCalls));

      firstFinishRelease.complete();
      await tester.pumpAndSettle();
      retry = find.byKey(const ValueKey<String>('current-evidence-retry'));
      expect(retry, findsOneWidget);
      expect(tester.widget<IconButton>(audio).onPressed, isNull);
      staleFlipHandler();
      staleAudioHandler();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repository.commands, hasLength(2));
      expect(repository.finishCalls, hasLength(1));
      expect(retry, findsOneWidget);
      expect(find.text('lasting'), findsNothing);
      expect(provider.spokenRequests, hasLength(initialAudioCalls));
      expect(
        find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpLegacyCompatibility(
  WidgetTester tester, {
  required List<Map<String, String>> wordList,
  required VoiceUseCases voice,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'legacy-flashcard-owner',
    nowUtc: () => DateTime.utc(2026, 8, 25),
  );
  final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: () => 'legacy-flashcard-id',
    nowUtc: () => DateTime.utc(2026, 8, 25),
    buildInfo: const AppBuildInfo(
      version: 'test',
      buildId: 'f06-legacy-flashcard-fixture',
    ),
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
    guestSessionService: _GuestSession(),
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
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        home: SrsFlashcardCompatibilityRoute(wordList: wordList, voice: voice),
      ),
    ),
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

final class _ScenarioOwnerRepository implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'owner-a', createdAtUtc: DateTime.utc(2026, 8, 11));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DeferredLearningRepository implements LearningRepository {
  final Completer<void> entered = Completer<void>();
  final Completer<List<QuizWord>> due = Completer<List<QuizWord>>();

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) {
    if (!entered.isCompleted) entered.complete();
    return due.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryLearningRepository implements LearningRepository {
  _RetryLearningRepository({
    this.failAnswerOnce = true,
    this.failFinishOnce = false,
    this.firstAnswerRelease,
    this.firstFinishRelease,
  });

  final bool failAnswerOnce;
  final bool failFinishOnce;
  final Completer<void>? firstAnswerRelease;
  final Completer<void>? firstFinishRelease;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  final List<({String ownerId, String sessionId, DateTime endedAtUtc})>
  finishCalls = <({String ownerId, String sessionId, DateTime endedAtUtc})>[];
  var _answerFailed = false;

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async => const <QuizWord>[
    QuizWord(
      id: 'word-1',
      categoryId: 'category-1',
      spelling: 'durable',
      meaning: 'lasting',
      partOfSpeech: 'adjective',
    ),
  ];

  @override
  Future<void> startSession(LearningSessionDraft session) async {}

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (commands.length == 1) await firstAnswerRelease?.future;
    if (failAnswerOnce && !_answerFailed) {
      _answerFailed = true;
      throw StateError('simulated local failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls.add((
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    ));
    if (failFinishOnce && finishCalls.length == 1) {
      await firstFinishRelease?.future;
      throw StateError('simulated session-close failure');
    }
    return LearningSessionSummary(
      id: sessionId,
      ownerId: ownerId,
      activityType: 'srsReview',
      state: 'completed',
      startedAtUtc: endedAtUtc,
      endedAtUtc: endedAtUtc,
      correctCount: 1,
      wrongCount: 0,
      score: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
