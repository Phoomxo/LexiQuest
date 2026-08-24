import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_associative_learning_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
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
import 'package:vocab_learning_app/screens/associative_reading_launcher_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late VocabularyUseCases vocabulary;
  late LearningUseCases learning;
  late DriftAssociativeLearningAdapter associativeLearning;
  late AppDependencies dependencies;
  var id = 0;
  var monotonicMicros = 0;

  AppDependencies makeDependencies({
    FeatureRegistry features = const BuildFeatureRegistry.fieldDefaults(),
    LearningTimeIdleScheduler? scheduleLearningTimeIdle,
  }) {
    final research = InertResearchDependencies(database);
    final lessonModes = buildLegacyLessonModeRegistry();
    final learningTime = DriftLearningTimeRepository(database, owners: owners);
    return AppDependencies(
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
      vocabulary: vocabulary,
      learning: learning,
      lessonModes: lessonModes,
      createLessonController: (adapter) => UnifiedLessonController(
        learning: learning,
        adapter: adapter,
        activeLearningTime: ActiveLearningTimeController(
          repository: learningTime,
          monotonicMicros: () => monotonicMicros,
          nowUtc: () => DateTime.utc(2026, 8, 9, 11),
          timezoneContext: (_) => const LearningTimeZoneContext(
            timezoneId: 'Asia/Bangkok',
            utcOffsetMinutes: 420,
          ),
          scheduleIdle: scheduleLearningTimeIdle,
        ),
      ),
      learningTime: learningTime,
      learningTimeCaptureRollout: const LearningTimeCaptureRollout.internal(),
      currentActivityEvidence: CurrentActivityEvidenceAdapter(
        learning: learning,
      ),
      associativeLearning: associativeLearning,
    );
  }

  setUp(() async {
    id = 0;
    monotonicMicros = 0;
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'launcher-owner',
      nowUtc: () => DateTime.utc(2026, 8, 9, 11),
    );
    await owners.getOrCreateActiveOwner();
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'launcher-${++id}',
      nowUtc: () => DateTime.utc(2026, 8, 9, 11),
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'learning-${++id}',
      nowUtc: () => DateTime.utc(2026, 8, 9, 11),
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'associative-launcher-test',
      ),
    );
    associativeLearning = DriftAssociativeLearningAdapter(database);
    dependencies = makeDependencies();
  });

  Future<void> pump(WidgetTester tester, Widget home) {
    return tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(home: home),
      ),
    );
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 100,
  }) async {
    for (var index = 0; index < maxPumps; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    fail('Widget did not appear after $maxPumps bounded pumps: $finder');
  }

  Future<void> seedWords(int count) async {
    final category = await vocabulary.createCategory('Reading');
    for (var index = 0; index < count; index++) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'word-$index',
          meaning: 'meaning-$index',
          partOfSpeech: 'noun',
          cefrLevel: 'B1',
        ),
      );
    }
  }

  Future<void> closeHarness(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'visible reading feature reaches launcher and injects up to 10 owned words',
    (tester) async {
      await tester.runAsync(() => seedWords(12));
      await pump(tester, const ChooseModeScreen());
      await tester.pump();

      expect(find.text('Associative Reading'), findsOneWidget);
      await tester.tap(find.text('Associative Reading'));
      await pumpUntilFound(tester, find.text('Start reading'));
      expect(find.byType(AssociativeReadingLauncherScreen), findsOneWidget);
      expect(find.text('Start reading'), findsOneWidget);

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

      final session = tester.widget<AssociativeReadingSessionScreen>(
        find.byType(AssociativeReadingSessionScreen),
      );
      final activeOwner = (await tester.runAsync(
        owners.getOrCreateActiveOwner,
      ))!;
      final ownedWords = (await tester.runAsync(
        () => vocabulary.getGameWords(limit: 100),
      ))!;
      final ownedIds = ownedWords.map((word) => word.id).toSet();
      expect(session.targetWords, hasLength(10));
      expect(session.targetWordIds, hasLength(10));
      expect(session.targetWordIds!.values, everyElement(isIn(ownedIds)));
      expect(session.targetWordIds!.values, hasLength(10));
      expect(
        ownedWords.map((word) => word.ownerId),
        everyElement(activeOwner.id),
      );
      expect(identical(session.learning, learning), isTrue);
      expect(
        identical(session.associativeLearning, associativeLearning),
        isTrue,
      );
      expect(session.cefrLevel, 'B1');
      expect(
        session.documentId,
        matches(RegExp(r'^associative-reading:[0-9a-f]{64}$')),
      );
      expect(session.documentRevision, inInclusiveRange(1, 4503599627370496));
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  for (final testCase in const [
    (
      label: 'baseline',
      firstRevision: 5,
      secondRevision: 1,
      reverse: false,
      firstCefr: null,
      expectedCefr: 'A2',
    ),
    (
      label: 'content revision',
      firstRevision: 5,
      secondRevision: 2,
      reverse: false,
      firstCefr: null,
      expectedCefr: 'A2',
    ),
    (
      label: 'reversed order',
      firstRevision: 5,
      secondRevision: 2,
      reverse: true,
      firstCefr: null,
      expectedCefr: 'A2',
    ),
    (
      label: 'effective CEFR revision',
      firstRevision: 6,
      secondRevision: 2,
      reverse: false,
      firstCefr: 'C1',
      expectedCefr: 'C1',
    ),
  ]) {
    testWidgets('document identity and revision track ordered word revisions: '
        '${testCase.label}', (tester) async {
      try {
        final seeded = await tester
            .runAsync<({String firstId, String secondId})>(() async {
              final category = await vocabulary.createCategory('Identity');
              final first = await vocabulary.createWord(
                CreateWordCommand(
                  categoryId: category.id,
                  spelling: 'alpha',
                  meaning: 'first meaning',
                  partOfSpeech: 'noun',
                ),
              );
              final second = await vocabulary.createWord(
                CreateWordCommand(
                  categoryId: category.id,
                  spelling: 'beta',
                  meaning: 'second meaning',
                  partOfSpeech: 'noun',
                ),
              );
              await (database.update(
                database.vocabularyWords,
              )..where((row) => row.id.equals(first.id))).write(
                VocabularyWordsCompanion(
                  localRevision: Value(testCase.firstRevision),
                  cefrLevel: Value(testCase.firstCefr),
                  normalizedSpelling: Value(
                    testCase.reverse ? 'z-alpha' : 'alpha',
                  ),
                ),
              );
              await (database.update(
                database.vocabularyWords,
              )..where((row) => row.id.equals(second.id))).write(
                VocabularyWordsCompanion(
                  meaning: Value(
                    testCase.secondRevision > 1
                        ? 'second meaning revised'
                        : 'second meaning',
                  ),
                  normalizedMeaning: Value(
                    testCase.secondRevision > 1
                        ? 'second meaning revised'
                        : 'second meaning',
                  ),
                  localRevision: Value(testCase.secondRevision),
                  normalizedSpelling: Value(
                    testCase.reverse ? 'a-beta' : 'beta',
                  ),
                ),
              );
              return (firstId: first.id, secondId: second.id);
            });
        final firstId = seeded!.firstId;
        final secondId = seeded.secondId;

        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        final session = tester.widget<AssociativeReadingSessionScreen>(
          find.byType(AssociativeReadingSessionScreen),
        );
        final revisions = <String, int>{
          firstId: testCase.firstRevision,
          secondId: testCase.secondRevision,
        };
        final orderedPairs = <List<Object>>[
          for (final word in session.targetWords)
            [
              session.targetWordIds![word]!,
              revisions[session.targetWordIds![word]]!,
            ],
        ];
        final digest = sha256
            .convert(utf8.encode(jsonEncode(orderedPairs)))
            .toString();
        final expectedRevision =
            int.parse(digest.substring(0, 13), radix: 16) + 1;

        expect(
          session.targetWords,
          testCase.reverse ? const ['beta', 'alpha'] : const ['alpha', 'beta'],
        );
        expect(session.cefrLevel, testCase.expectedCefr);
        expect(session.documentId, 'associative-reading:$digest');
        expect(session.documentRevision, expectedRevision);
        expect(session.sessionId, isA<String>());
        final storedSession = await database
            .select(database.learningSessions)
            .getSingle();
        expect(storedSession.id, session.sessionId);
        expect(storedSession.activityType, 'associativeReading');
        expect(storedSession.state, 'active');
      } finally {
        await closeHarness(tester);
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  }

  testWidgets('hidden reading feature omits the reading tile', (tester) async {
    dependencies = makeDependencies(
      features: const BuildFeatureRegistry({
        Feature.reading: FeatureState.hidden,
      }),
    );
    await pump(tester, const ChooseModeScreen());
    await tester.pump();

    expect(find.text('Associative Reading'), findsNothing);
    await closeHarness(tester);
  });

  testWidgets(
    'duplicate display spellings keep one target with one durable word ID',
    (tester) async {
      await tester.runAsync(() async {
        final firstCategory = await vocabulary.createCategory('First');
        final secondCategory = await vocabulary.createCategory('Second');
        for (final category in [firstCategory, secondCategory]) {
          await vocabulary.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'echo',
              meaning: category.name,
              partOfSpeech: 'noun',
              cefrLevel: 'A2',
            ),
          );
        }
      });
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(tester, find.text('Start reading'));

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      final session = tester.widget<AssociativeReadingSessionScreen>(
        find.byType(AssociativeReadingSessionScreen),
      );

      expect(session.targetWords, hasLength(session.targetWordIds!.length));
      expect(session.targetWords, hasLength(1));
      expect(session.targetWordIds, contains('echo'));
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'each repeated reading launch owns a fresh terminal time lifecycle',
    (tester) async {
      await tester.runAsync(() => seedWords(1));
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(tester, find.text('Start reading'));

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
      monotonicMicros += const Duration(minutes: 4).inMicroseconds;
      await tester.tap(find.text('Stage 1: Supported Reading'));
      await tester.pump();
      monotonicMicros += const Duration(minutes: 4).inMicroseconds;
      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Start reading'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      monotonicMicros += const Duration(seconds: 5).inMicroseconds;
      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Start reading'));
      await tester.pumpAndSettle();

      final sessions = await database.select(database.learningSessions).get();
      final segments = await database
          .select(database.learningTimeSegments)
          .get();
      expect(sessions, hasLength(2));
      expect(sessions.map((row) => row.id).toSet(), hasLength(2));
      expect(sessions.map((row) => row.state), everyElement('abandoned'));
      expect(segments, hasLength(3));
      final durationsBySession = <String, int>{};
      for (final row in segments) {
        durationsBySession.update(
          row.sessionId,
          (duration) => duration + row.activeDurationMs,
          ifAbsent: () => row.activeDurationMs,
        );
      }
      expect(durationsBySession.values.toSet(), <int>{5000, 480000});
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'text input renews active effort across the idle boundary',
    (tester) async {
      await tester.runAsync(() => seedWords(1));
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(tester, find.text('Start reading'));

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
      await tester.tap(find.text('Complete & Continue'));
      await pumpUntilFound(tester, find.text('Stage 2: Cue Fading'));
      await tester.tap(find.text('Complete & Continue'));
      await pumpUntilFound(tester, find.text('Stage 3: Active Recall'));

      monotonicMicros = const Duration(minutes: 4).inMicroseconds;
      await tester.enterText(find.byType(TextField), 'w');
      await tester.pumpAndSettle();
      monotonicMicros = const Duration(minutes: 8).inMicroseconds;
      await tester.enterText(find.byType(TextField), 'word-0');
      await tester.pumpAndSettle();

      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Start reading'));
      await tester.pumpAndSettle();

      final segments = await database
          .select(database.learningTimeSegments)
          .get();
      expect(
        segments.fold<int>(
          0,
          (total, segment) => total + segment.activeDurationMs,
        ),
        const Duration(minutes: 8).inMilliseconds,
      );
      expect(
        segments.map((segment) => segment.activeDurationMs),
        everyElement(
          lessThanOrEqualTo(const Duration(minutes: 5).inMilliseconds),
        ),
      );
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'failed claimed compensation exits to one successful launcher fallback',
    (tester) async {
      final repository = _FailingProgressAndAbandonRepository(
        DriftLearningRepository(database),
        failuresBeforeSuccess: 1,
      );
      learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'learning-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 11),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-launcher-failed-claim-fallback',
        ),
      );
      dependencies = makeDependencies();

      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byKey(
            const ValueKey<String>(
              'associative-reading-initialization-failure',
            ),
          ),
        );
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;
        expect(repository.abandonCalls, 1);
        await expectLater(
          controller.recordActiveLearningInteraction(
            DateTime.utc(2026, 8, 9, 11, 1),
          ),
          throwsStateError,
        );

        await tester.pageBack();
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.pumpAndSettle();

        final sessions = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        final segments = (await tester.runAsync(
          () => database.select(database.learningTimeSegments).get(),
        ))!;
        expect(repository.abandonCalls, 2);
        expect(repository.successfulAbandons, 1);
        expect(sessions.single.state, 'abandoned');
        expect(sessions.where((row) => row.state == 'active'), isEmpty);
        expect(segments, isEmpty);
        expect(
          find.text('Could not start associative reading. Try again.'),
          findsNothing,
        );
      } finally {
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'failed launcher fallback stays explicit and bounded without retry loop',
    (tester) async {
      final repository = _FailingProgressAndAbandonRepository(
        DriftLearningRepository(database),
        failuresBeforeSuccess: 2,
      );
      learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'learning-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 11),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-launcher-explicit-terminal-failure',
        ),
      );
      dependencies = makeDependencies();

      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byKey(
            const ValueKey<String>(
              'associative-reading-initialization-failure',
            ),
          ),
        );
        expect(repository.abandonCalls, 1);

        await tester.pageBack();
        await pumpUntilFound(tester, find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.text('Could not start associative reading. Try again.'),
        );
        await tester.pump(const Duration(seconds: 1));

        final sessions = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        final segments = (await tester.runAsync(
          () => database.select(database.learningTimeSegments).get(),
        ))!;
        expect(repository.abandonCalls, 2);
        expect(repository.successfulAbandons, 0);
        expect(sessions.single.state, 'active');
        expect(segments, isEmpty);
      } finally {
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'successful failure compensation terminally stops restored lifecycle time',
    (tester) async {
      final repository = _CompletedProgressFailOnceAbandonRepository(
        DriftLearningRepository(database),
      );
      learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'learning-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 11),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-launcher-restored-time-failure',
        ),
      );
      final idleCallbacks = <FutureOr<void> Function()>[];
      var idleCancellations = 0;
      dependencies = makeDependencies(
        scheduleLearningTimeIdle: (delay, callback) {
          idleCallbacks.add(callback);
          return () => idleCancellations += 1;
        },
      );

      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byKey(
            const ValueKey<String>(
              'associative-reading-initialization-failure',
            ),
          ),
        );
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;

        expect(repository.abandonCalls, 2);
        expect(repository.successfulAbandons, 1);
        expect(idleCallbacks, hasLength(2));
        expect(idleCancellations, greaterThanOrEqualTo(2));
        final sessionsBeforeIdle = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(sessionsBeforeIdle.single.state, 'abandoned');

        monotonicMicros = const Duration(minutes: 6).inMicroseconds;
        await tester.runAsync(() async {
          await Future<void>.sync(idleCallbacks.last);
        });
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        final segments = (await tester.runAsync(
          () => database.select(database.learningTimeSegments).get(),
        ))!;
        final sessionsAfterIdle = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(segments, isEmpty);
        expect(sessionsAfterIdle.single.state, 'abandoned');
        expect(repository.abandonCalls, 2);
        await expectLater(
          controller.recordActiveLearningInteraction(
            DateTime.utc(2026, 8, 9, 11, 6),
          ),
          throwsStateError,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(repository.abandonCalls, 2);
      } finally {
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'claimed progress-load compensation publishes typed failure exactly once',
    (tester) async {
      final repository = _FailingProgressCountingLearningRepository(
        DriftLearningRepository(database),
      );
      learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'learning-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 11),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-launcher-progress-failure',
        ),
      );
      dependencies = makeDependencies();

      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byKey(
            const ValueKey<String>(
              'associative-reading-initialization-failure',
            ),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        final beforeReturn = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(beforeReturn, hasLength(1));
        expect(beforeReturn.single.state, 'abandoned');
        expect(repository.abandonCalls, 1);

        await tester.pageBack();
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.pumpAndSettle();

        final afterReturn = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(afterReturn.where((row) => row.state == 'active'), isEmpty);
        expect(repository.abandonCalls, 1);
        expect(
          find.text('Could not start associative reading. Try again.'),
          findsNothing,
        );
      } finally {
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'initialization abandon and emergency rollback share one terminal claim',
    (tester) async {
      final repository = _BlockedAbandonAfterProgressFailureRepository(
        DriftLearningRepository(database),
      );
      learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'learning-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 11),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-launcher-terminal-claim-race',
        ),
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      dependencies = makeDependencies(features: registry);

      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        await tester.runAsync(() => repository.firstAbandonStarted);
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;
        expect(controller.state.status, LessonSessionStatus.planned);

        registry.emergencyOff(Feature.reading);
        await tester.pump();
        expect(find.byType(AssociativeReadingSessionScreen), findsNothing);
        expect(find.byType(UnifiedLessonShell), findsNothing);

        repository.releaseAbandon();
        await tester.runAsync(() => repository.firstAbandonCompleted);
        await tester.pumpAndSettle();

        final sessions = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        final segments = (await tester.runAsync(
          () => database.select(database.learningTimeSegments).get(),
        ))!;
        expect(repository.abandonCalls, 1);
        expect(sessions, hasLength(1));
        expect(sessions.single.state, 'abandoned');
        expect(sessions.where((row) => row.state == 'active'), isEmpty);
        expect(segments, isEmpty);
        await expectLater(
          controller.recordActiveLearningInteraction(
            DateTime.utc(2026, 8, 9, 11, 1),
          ),
          throwsStateError,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(repository.abandonCalls, 1);
        expect(
          find.text('Could not start associative reading. Try again.'),
          findsNothing,
        );
      } finally {
        repository.releaseAbandon();
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'delayed progress completion cannot reclaim terminal ownership after emergency off',
    (tester) async {
      final repository = _DelayedProgressCountingLearningRepository(
        DriftLearningRepository(database),
      );
      learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'learning-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 11),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-launcher-delayed-progress',
        ),
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      dependencies = makeDependencies(features: registry);

      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const AssociativeReadingLauncherScreen());
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        expect(repository.progressLoadCalls, 1);
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;
        expect(controller.state.status, LessonSessionStatus.planned);

        registry.emergencyOff(Feature.reading);
        await tester.pumpAndSettle();
        expect(find.byType(AssociativeReadingSessionScreen), findsNothing);
        expect(controller.state.status, LessonSessionStatus.abandoned);
        expect(repository.abandonCalls, 1);

        repository.completeProgressLoad();
        await tester.pumpAndSettle();

        final sessions = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(repository.abandonCalls, 1);
        expect(sessions, hasLength(1));
        expect(sessions.single.state, 'abandoned');
        expect(sessions.where((row) => row.state == 'active'), isEmpty);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(repository.abandonCalls, 1);
      } finally {
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'open reading session follows the live emergency-off gate',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      dependencies = makeDependencies(features: registry);
      try {
        await tester.runAsync(() => seedWords(1));
        await pump(tester, const ChooseModeScreen());
        await tester.tap(
          find.byKey(const ValueKey<String>('home/learn/associative-reading')),
        );
        await pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;
        expect(controller.state.status, LessonSessionStatus.active);

        registry.emergencyOff(Feature.reading);
        await tester.pump();

        expect(find.byType(AssociativeReadingSessionScreen), findsNothing);
        expect(find.byType(UnifiedLessonShell), findsNothing);
        final unavailable = tester
            .widgetList<ProductionFeatureUnavailable>(
              find.byType(ProductionFeatureUnavailable),
            )
            .toList(growable: false);
        expect(unavailable, isNotEmpty);
        expect(
          unavailable.map((widget) => widget.feature),
          everyElement(Feature.reading),
        );
        expect(
          unavailable.map((widget) => widget.state),
          everyElement(FeatureState.emergencyOff),
        );
        await expectLater(
          controller.recordActiveLearningInteraction(
            DateTime.utc(2026, 8, 9, 11, 1),
          ),
          throwsStateError,
        );
        await tester.pumpAndSettle();
        final sessions = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(sessions, hasLength(1));
        expect(sessions.single.state, 'abandoned');
        expect(sessions.single.endedAtUtcMs, isA<int>());
        expect(sessions.where((row) => row.state == 'active'), isEmpty);

        await tester.pageBack();
        await tester.pumpAndSettle();
        final sessionsAfterRouteReturn = (await tester.runAsync(
          () => database.select(database.learningSessions).get(),
        ))!;
        expect(
          sessionsAfterRouteReturn.where((row) => row.state == 'active'),
          isEmpty,
        );
      } finally {
        await closeHarness(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'completed reading replay closes its fresh durable session',
    (tester) async {
      await tester.runAsync(() => seedWords(1));
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(tester, find.text('Start reading'));

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
      final first = tester.widget<AssociativeReadingSessionScreen>(
        find.byType(AssociativeReadingSessionScreen),
      );
      await tester.runAsync(
        () => learning.saveReadingProgress(
          documentId: first.documentId!,
          documentRevision: first.documentRevision,
          position: 6,
          isCompleted: true,
        ),
      );
      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Start reading'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start reading'));
      await pumpUntilFound(
        tester,
        find.byType(AssociativeReadingSessionScreen),
      );
      await pumpUntilFound(tester, find.text('Stage 6: Finish'));
      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Start reading'));
      await tester.pumpAndSettle();

      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(2));
      expect(sessions.map((row) => row.state), everyElement('abandoned'));
      expect(sessions.where((row) => row.state == 'active'), isEmpty);
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'empty vocabulary action opens vocabulary creation',
    (tester) async {
      await pump(tester, const AssociativeReadingLauncherScreen());
      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('associative-reading-empty')),
      );

      expect(
        find.byKey(const ValueKey('associative-reading-empty')),
        findsOneWidget,
      );
      expect(find.text('Create vocabulary'), findsOneWidget);
      await tester.tap(find.text('Create vocabulary'));
      await pumpUntilFound(tester, find.byType(CategoriesPage));

      expect(find.byType(CategoriesPage), findsOneWidget);
      await closeHarness(tester);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

final class _FailingProgressCountingLearningRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _FailingProgressCountingLearningRepository(this._delegate);

  final DriftLearningRepository _delegate;
  int abandonCalls = 0;

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      _delegate.startSession(session);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => Future<ReadingProgressSnapshot?>.error(
    StateError('simulated reading-progress load failure'),
  );

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) {
    abandonCalls += 1;
    return _delegate.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DelayedProgressCountingLearningRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _DelayedProgressCountingLearningRepository(this._delegate);

  final DriftLearningRepository _delegate;
  final Completer<ReadingProgressSnapshot?> _progress =
      Completer<ReadingProgressSnapshot?>();
  int progressLoadCalls = 0;
  int abandonCalls = 0;

  void completeProgressLoad() {
    _progress.complete(null);
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      _delegate.startSession(session);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) {
    progressLoadCalls += 1;
    return _progress.future;
  }

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) {
    abandonCalls += 1;
    return _delegate.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BlockedAbandonAfterProgressFailureRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _BlockedAbandonAfterProgressFailureRepository(this._delegate);

  final DriftLearningRepository _delegate;
  final Completer<void> _firstAbandonStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();
  final Completer<void> _firstAbandonCompleted = Completer<void>();
  int abandonCalls = 0;

  Future<void> get firstAbandonStarted => _firstAbandonStarted.future;
  Future<void> get firstAbandonCompleted => _firstAbandonCompleted.future;

  void releaseAbandon() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      _delegate.startSession(session);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => Future<ReadingProgressSnapshot?>.error(
    StateError('simulated reading-progress load failure'),
  );

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {
    abandonCalls += 1;
    if (!_firstAbandonStarted.isCompleted) _firstAbandonStarted.complete();
    await _release.future;
    try {
      return await _delegate.abandonSession(
        ownerId: ownerId,
        sessionId: sessionId,
        abandonedAtUtc: abandonedAtUtc,
      );
    } finally {
      if (!_firstAbandonCompleted.isCompleted) {
        _firstAbandonCompleted.complete();
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CompletedProgressFailOnceAbandonRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _CompletedProgressFailOnceAbandonRepository(this._delegate);

  final DriftLearningRepository _delegate;
  int abandonCalls = 0;
  int successfulAbandons = 0;

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      _delegate.startSession(session);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => ReadingProgressSnapshot(
    documentId: documentId,
    documentRevision: documentRevision,
    lastPosition: 6,
    isCompleted: true,
    updatedAtUtc: DateTime.utc(2026, 8, 9, 11),
  );

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {
    abandonCalls += 1;
    if (abandonCalls == 1) {
      throw StateError('simulated first lifecycle abandon failure');
    }
    final result = await _delegate.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
    successfulAbandons += 1;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailingProgressAndAbandonRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _FailingProgressAndAbandonRepository(
    this._delegate, {
    required this.failuresBeforeSuccess,
  });

  final DriftLearningRepository _delegate;
  final int failuresBeforeSuccess;
  int abandonCalls = 0;
  int successfulAbandons = 0;

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      _delegate.startSession(session);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => Future<ReadingProgressSnapshot?>.error(
    StateError('simulated reading-progress load failure'),
  );

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {
    abandonCalls += 1;
    if (abandonCalls <= failuresBeforeSuccess) {
      throw StateError('simulated terminal compensation failure');
    }
    final result = await _delegate.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
    successfulAbandons += 1;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
