import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide AssociationRecord, AssociativeMemoryState, LocalOwner;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

const _typedChecksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('B3 Associative Reading Session Screen Tests', () {
    late AppDatabase database;
    late DriftLocalOwnerRepository owners;
    late LearningUseCases learning;
    late InMemoryAssociativeLearningAdapter associativeLearning;
    var id = 0;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'reading-owner',
        nowUtc: () => DateTime.utc(2026, 8, 9, 10),
      );
      await owners.getOrCreateActiveOwner();
      learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'reading-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 10),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-reading-screen-test',
        ),
      );
      associativeLearning = InMemoryAssociativeLearningAdapter();
    });

    tearDown(() => database.close());

    Widget session({
      List<String> targetWords = const ['ephemeral', 'resilient'],
      Map<String, String>? targetWordIds,
      AssociativeLearningPort? port,
      LearningUseCases? learningUseCases,
      CurrentActivityEvidenceAdapter? evidenceAdapter,
      TypedRecallModeAdapter? modeAdapter,
      List<TypedRecallPrompt>? recallPrompts,
      FeatureRegistry? featureRegistry,
      String? sessionId,
    }) {
      final resolvedLearning = learningUseCases ?? learning;
      final resolvedPrompts =
          recallPrompts ??
          (targetWordIds == null
              ? null
              : <TypedRecallPrompt>[
                  for (final word in targetWords)
                    if (targetWordIds[word] case final wordId?)
                      TypedRecallPrompt(
                        wordId: wordId.trim(),
                        canonicalAnswer: word,
                        promptKind: TypedRecallPromptKind.context,
                        normalizationRevision:
                            typedRecallNormalizationRevisionV1,
                        contentRevision: 1,
                        contentChecksumSha256: _typedChecksum,
                      ),
                ]);
      return MaterialApp(
        home: AssociativeReadingSessionScreen(
          cefrLevel: 'B2',
          targetWords: targetWords,
          targetWordIds: targetWordIds,
          passageText:
              'Life is filled with ephemeral moments that require a resilient spirit to appreciate.',
          learning: resolvedLearning,
          evidenceAdapter:
              evidenceAdapter ??
              CurrentActivityEvidenceAdapter(learning: resolvedLearning),
          modeAdapter: modeAdapter,
          recallPrompts: resolvedPrompts,
          featureRegistry: featureRegistry,
          associativeLearning: port ?? associativeLearning,
          sessionId: sessionId,
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

    Future<void> pumpInitialization(WidgetTester tester) async {
      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
    }

    testWidgets(
      'progress-load failure abandons the durable session and hides learning actions',
      (tester) async {
        final handle = (await tester.runAsync(
          learning.startAssociativeReadingSessionHandle,
        ))!;
        final failingLearning = LearningUseCases(
          owners: owners,
          repository: _FailingProgressLearningRepository(
            DriftLearningRepository(database),
          ),
          generateId: () => 'reading-failure-${++id}',
          nowUtc: () => DateTime.utc(2026, 8, 9, 10, 1),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'associative-reading-load-failure',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'B2',
              targetWords: const ['resilient'],
              targetWordIds: const {'resilient': 'word-resilient'},
              passageText: 'A resilient learner keeps trying.',
              learning: failingLearning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: failingLearning,
              ),
              associativeLearning: associativeLearning,
              sessionId: handle.id,
              sessionStartedAtUtc: handle.startedAtUtc,
            ),
          ),
        );
        await pumpInitialization(tester);

        expect(
          find.byKey(
            const ValueKey<String>(
              'associative-reading-initialization-failure',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Stage 1: Supported Reading'), findsNothing);
        expect(find.text('Complete & Continue'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await pumpInitialization(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          (await tester.runAsync(
            () => database.select(database.readingEvents).get(),
          ))!,
          isEmpty,
        );
        expect(
          (await tester.runAsync(
            () => database.select(database.readingProgressEntries).get(),
          ))!,
          isEmpty,
        );
        final stored = (await tester.runAsync(
          () => (database.select(
            database.learningSessions,
          )..where((row) => row.id.equals(handle.id))).getSingle(),
        ))!;
        expect(stored.state, 'abandoned');
      },
    );

    testWidgets(
      'lifecycle-start failure abandons the durable session and hides learning actions',
      (tester) async {
        final handle = (await tester.runAsync(
          learning.startAssociativeReadingSessionHandle,
        ))!;
        final adapter = buildLegacyLessonModeRegistry()
            .find(LessonMode.associativeReading)!
            .adapter;
        final controller = UnifiedLessonController(
          learning: learning,
          adapter: adapter,
        );
        await tester.runAsync(
          () => controller.start(
            LessonStartCommand(
              mode: LessonMode.associativeReading,
              sessionId: 'session:already-active',
              startedAtUtc: handle.startedAtUtc,
              itemCount: 1,
            ),
          ),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedLessonShell(
              controller: controller,
              nowUtc: () => handle.startedAtUtc,
              builder: (_) => AssociativeReadingSessionScreen(
                cefrLevel: 'B2',
                targetWords: const ['resilient'],
                targetWordIds: const {'resilient': 'word-resilient'},
                passageText: 'A resilient learner keeps trying.',
                learning: learning,
                evidenceAdapter: CurrentActivityEvidenceAdapter(
                  learning: learning,
                ),
                associativeLearning: associativeLearning,
                sessionId: handle.id,
                sessionStartedAtUtc: handle.startedAtUtc,
              ),
            ),
          ),
        );
        await pumpInitialization(tester);

        expect(
          find.byKey(
            const ValueKey<String>(
              'associative-reading-initialization-failure',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Stage 1: Supported Reading'), findsNothing);
        expect(find.text('Complete & Continue'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await pumpInitialization(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          (await tester.runAsync(
            () => database.select(database.readingEvents).get(),
          ))!,
          isEmpty,
        );
        expect(
          (await tester.runAsync(
            () => database.select(database.readingProgressEntries).get(),
          ))!,
          isEmpty,
        );
        final stored = (await tester.runAsync(
          () => (database.select(
            database.learningSessions,
          )..where((row) => row.id.equals(handle.id))).getSingle(),
        ))!;
        expect(stored.state, 'abandoned');
      },
    );

    testWidgets('Renders stages and progresses through 6 stages', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(session());
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

      expect(find.text('Associative Reading (B2)'), findsOneWidget);
      expect(find.text('Stage 1: Supported Reading'), findsOneWidget);
      expect(find.textContaining('ephemeral moments'), findsOneWidget);

      for (var stage = 2; stage <= 6; stage++) {
        if (stage == 5) {
          for (var index = 0; index < 2; index++) {
            await tester.enterText(
              find.byType(TextField).at(index),
              'memory cue $index',
            );
          }
        }
        await tester.tap(find.text('Complete & Continue'));
        final title = 'Stage $stage: ${_stageName(stage)}';
        await pumpUntilFound(tester, find.text(title));
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Ready to finish'), findsOneWidget);
    });

    testWidgets('Stage 3 shows one TextField per target word', (tester) async {
      await tester.pumpWidget(session());
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(
          tester,
          find.text('Stage ${i + 2}: ${_stageName(i + 2)}'),
        );
      }

      expect(find.text('Stage 3: Active Recall'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Word 1'), findsOneWidget);
      expect(find.text('Word 2'), findsOneWidget);
    });

    testWidgets(
      'Stage 4 saves owner-scoped association and initial memory state',
      (tester) async {
        await tester.pumpWidget(
          session(
            targetWords: const ['banana'],
            targetWordIds: const {'banana': 'word-banana'},
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Complete & Continue'));
          await pumpUntilFound(
            tester,
            find.text('Stage ${i + 2}: ${_stageName(i + 2)}'),
          );
        }
        expect(find.text('Stage 4: Memory Association'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'yellow fruit');
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));
        expect(find.text('Stage 5: Context Transfer'), findsOneWidget);

        final owner = await owners.getOrCreateActiveOwner();
        final associations = await associativeLearning.getAssociationsForWord(
          owner.id,
          'word-banana',
        );
        final memory = await associativeLearning.getMemoryState(
          owner.id,
          'word-banana',
        );
        expect(associations, hasLength(1));
        expect(associations.single.content, 'yellow fruit');
        expect(associations.single.type, 'keyword');
        expect(memory, isNotNull);
        expect(memory!.ownerId, owner.id);
        expect(memory.wordKey, 'word-banana');
      },
    );

    testWidgets('renders typed unavailable state when learning is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['banana'],
            passageText: 'The banana is yellow.',
            associativeLearning: associativeLearning,
          ),
        ),
      );
      await tester.pump();

      final state = tester.widget<AssociativeReadingUnavailable>(
        find.byType(AssociativeReadingUnavailable),
      );
      expect(state.reason, AssociativeReadingUnavailableReason.learning);
    });

    testWidgets(
      'renders typed unavailable state when associative persistence is absent',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'A2',
              targetWords: const ['banana'],
              passageText: 'The banana is yellow.',
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
            ),
          ),
        );
        await tester.pump();

        final state = tester.widget<AssociativeReadingUnavailable>(
          find.byType(AssociativeReadingUnavailable),
        );
        expect(
          state.reason,
          AssociativeReadingUnavailableReason.associativeLearning,
        );
      },
    );

    testWidgets('retry reuses pending evidence identity', (tester) async {
      final repository = _RetryLearningRepository();
      var nextId = 0;
      final retryLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'associative-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 14, 10, 0, nextId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['rail station'],
            targetWordIds: const {'rail station': 'word-rail-station'},
            passageText: 'The rail station is nearby.',
            learning: retryLearning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(
              learning: retryLearning,
            ),
            associativeLearning: associativeLearning,
            sessionId: 'session-1',
            modeAdapter: const TypedRecallModeAdapter(),
            recallPrompts: <TypedRecallPrompt>[
              TypedRecallPrompt(
                wordId: 'word-rail-station',
                canonicalAnswer: 'rail station',
                promptKind: TypedRecallPromptKind.context,
                normalizationRevision: typedRecallNormalizationRevisionV1,
                contentRevision: 7,
                contentChecksumSha256: _typedChecksum,
              ),
            ],
          ),
        ),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
      for (var stage = 2; stage <= 3; stage++) {
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(
          tester,
          find.text('Stage $stage: ${_stageName(stage)}'),
        );
      }
      await tester.enterText(find.byType(TextField), '  RAIL   STATION  ');

      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 3: Active Recall'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(AssociativeReadingSessionScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('current-evidence-retry')),
      );
      await pumpUntilFound(tester, find.text('Stage 4: Memory Association'));

      expect(repository.commands, hasLength(2));
      final first = repository.commands.first;
      final retry = repository.commands.last;
      expect(retry.id, first.id);
      expect(retry.occurredAtUtc, first.occurredAtUtc);
      expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
      expect(
        retry.evidenceContext.evidenceClass,
        EvidenceClass.independentRecall,
      );
      expect(retry.evidenceContext.skillId, 'associative-recall');
      expect(retry.isCorrect, isTrue);
      expect(
        retry.providerProvenance,
        'typed-recall:vocabulary-text-v1:context:exact',
      );
      expect(
        retry.evidenceContext.contentRevision,
        'lexical-typed-recall:word-rail-station@7:$_typedChecksum',
      );
      expect(retry.providerProvenance, isNot(contains('RAIL   STATION')));
    });

    testWidgets(
      'Stage 3 freezes the whole batch and retries only incomplete evidence',
      (tester) async {
        final repository = _PartialBatchLearningRepository();
        var nextId = 0;
        final batchLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'batch-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 14, 11, 0, nextId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'A2',
              targetWords: const ['banana', 'apple'],
              targetWordIds: const {
                'banana': 'word-banana',
                'apple': 'word-apple',
              },
              passageText: 'Banana and apple.',
              learning: batchLearning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: batchLearning,
              ),
              associativeLearning: associativeLearning,
              sessionId: 'session-1',
              recallPrompts: <TypedRecallPrompt>[
                TypedRecallPrompt(
                  wordId: 'word-banana',
                  canonicalAnswer: 'banana',
                  promptKind: TypedRecallPromptKind.context,
                  normalizationRevision: typedRecallNormalizationRevisionV1,
                  contentRevision: 1,
                  contentChecksumSha256: _typedChecksum,
                ),
                TypedRecallPrompt(
                  wordId: 'word-apple',
                  canonicalAnswer: 'apple',
                  promptKind: TypedRecallPromptKind.context,
                  normalizationRevision: typedRecallNormalizationRevisionV1,
                  contentRevision: 1,
                  contentChecksumSha256: _typedChecksum,
                ),
              ],
            ),
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (var stage = 2; stage <= 3; stage++) {
          await tester.tap(find.text('Complete & Continue'));
          await pumpUntilFound(
            tester,
            find.text('Stage $stage: ${_stageName(stage)}'),
          );
        }
        await tester.enterText(find.byType(TextField).at(0), 'banana');
        await tester.enterText(find.byType(TextField).at(1), 'wrong');

        await tester.tap(find.text('Complete & Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Stage 3: Active Recall'), findsOneWidget);
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .every((field) => field.enabled == false),
          isTrue,
        );
        final fields = tester
            .widgetList<TextField>(find.byType(TextField))
            .toList();
        fields[0].controller!.text = 'mutated-after-capture';
        fields[1].controller!.text = 'apple';
        ScaffoldMessenger.of(
          tester.element(find.byType(AssociativeReadingSessionScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('current-evidence-retry')),
        );
        await pumpUntilFound(tester, find.text('Stage 4: Memory Association'));

        expect(repository.commands, hasLength(3));
        final banana = repository.commands.where(
          (command) => command.wordId == 'word-banana',
        );
        final apple = repository.commands
            .where((command) => command.wordId == 'word-apple')
            .toList();
        expect(banana, hasLength(1));
        expect(apple, hasLength(2));
        expect(apple.last.id, apple.first.id);
        expect(apple.last.occurredAtUtc, apple.first.occurredAtUtc);
        expect(apple.last.isCorrect, isFalse);
        expect(
          apple.last.evidenceContext.toJson(),
          apple.first.evidenceContext.toJson(),
        );
      },
    );

    test(
      'plain Drift commits hinted then independent typed recall and terminates',
      () async {
        final owner = await owners.getOrCreateActiveOwner();
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category-plain-hints',
                ownerId: owner.id,
                name: 'Plain hints',
                normalizedName: 'plain hints',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final entry in const <(String, String)>[
          ('word-plain-anchor', 'anchor'),
          ('word-plain-beacon', 'beacon'),
        ]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: entry.$1,
                  ownerId: owner.id,
                  categoryId: 'category-plain-hints',
                  spelling: entry.$2,
                  normalizedSpelling: entry.$2,
                  meaning: '${entry.$2} meaning',
                  normalizedMeaning: '${entry.$2} meaning',
                  partOfSpeech: 'noun',
                  contentRevision: const Value(1),
                  contentChecksumSha256: const Value(_typedChecksum),
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }

        final handle = await learning.startAssociativeReadingSessionHandle();
        final registry = buildLessonModeRegistry();
        final controller = UnifiedLessonController(
          learning: learning,
          adapter: registry.find(LessonMode.associativeReading)!.adapter,
        );
        addTearDown(controller.dispose);
        await controller.start(
          LessonStartCommand(
            sessionId: handle.id,
            mode: LessonMode.associativeReading,
            itemCount: 2,
            startedAtUtc: handle.startedAtUtc,
          ),
        );
        final typedRecall = registry.typedRecall!.adapter;
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        TypedRecallPrompt prompt(String wordId, String answer) =>
            TypedRecallPrompt(
              wordId: wordId,
              canonicalAnswer: answer,
              promptKind: TypedRecallPromptKind.context,
              normalizationRevision: typedRecallNormalizationRevisionV1,
              contentRevision: 1,
              contentChecksumSha256: _typedChecksum,
            );

        controller.revealNextHint();
        expect(controller.hintState!.hintLevel, 1);
        final guided = typedRecall.capture(
          evidence: evidence,
          sessionId: handle.id,
          prompt: prompt('word-plain-anchor', 'anchor'),
          response: 'anchor',
          responseTimeMs: null,
          attemptNumber: 1,
          support: TypedRecallSupport(
            hint: controller.snapshotHintUsageForAcceptedEvidence(),
          ),
        );
        await guided.pending.record();
        expect(guided.evaluation.evidenceClass, EvidenceClass.guidedPractice);
        expect(guided.evaluation.hintLevel, 1);
        expect(await database.select(database.srsStates).get(), isEmpty);

        controller.resetHintsAfterAcceptedEvidence();
        expect(controller.hintState!.hintLevel, 0);
        final independent = typedRecall.capture(
          evidence: evidence,
          sessionId: handle.id,
          prompt: prompt('word-plain-beacon', 'beacon'),
          response: 'beacon',
          responseTimeMs: null,
          attemptNumber: 2,
          support: TypedRecallSupport(
            hint: controller.snapshotHintUsageForAcceptedEvidence(),
          ),
        );
        await independent.pending.record();
        expect(
          independent.evaluation.evidenceClass,
          EvidenceClass.independentRecall,
        );
        expect(independent.evaluation.hintLevel, 0);
        expect(
          (await database.select(database.srsStates).get()).map(
            (row) => row.wordId,
          ),
          <String>['word-plain-beacon'],
        );

        final close = learning.captureSessionClose(sessionId: handle.id);
        await controller.completeCapturedSession(
          close,
          handle.startedAtUtc.add(const Duration(minutes: 1)),
        );
        expect(controller.state.status, LessonSessionStatus.completed);
        expect(
          (await database.select(database.answerAttempts).get()).map(
            (row) => row.evidenceClass,
          ),
          <String>[
            EvidenceClass.guidedPractice.name,
            EvidenceClass.independentRecall.name,
          ],
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    testWidgets(
      'Stage 3 consumes one shell hint then resets support per committed item',
      (tester) async {
        final handle = (await tester.runAsync(() async {
          final owner = await owners.getOrCreateActiveOwner();
          await database
              .into(database.vocabularyCategories)
              .insert(
                VocabularyCategoriesCompanion.insert(
                  id: 'category-hints',
                  ownerId: owner.id,
                  name: 'Hints',
                  normalizedName: 'hints',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
          for (final entry in const <(String, String)>[
            ('word-anchor', 'anchor'),
            ('word-beacon', 'beacon'),
          ]) {
            await database
                .into(database.vocabularyWords)
                .insert(
                  VocabularyWordsCompanion.insert(
                    id: entry.$1,
                    ownerId: owner.id,
                    categoryId: 'category-hints',
                    spelling: entry.$2,
                    normalizedSpelling: entry.$2,
                    meaning: '${entry.$2} meaning',
                    normalizedMeaning: '${entry.$2} meaning',
                    partOfSpeech: 'noun',
                    contentRevision: const Value(1),
                    contentChecksumSha256: const Value(_typedChecksum),
                    createdAtUtcMs: 1,
                    updatedAtUtcMs: 1,
                  ),
                );
          }
          return learning.startAssociativeReadingSessionHandle();
        }))!;
        final registry = buildLessonModeRegistry();
        final controller = UnifiedLessonController(
          learning: learning,
          adapter: registry.find(LessonMode.associativeReading)!.adapter,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedLessonShell(
              controller: controller,
              nowUtc: () => handle.startedAtUtc,
              builder: (_) => AssociativeReadingSessionScreen(
                cefrLevel: 'B1',
                targetWords: const <String>['anchor', 'beacon'],
                targetWordIds: const <String, String>{
                  'anchor': 'word-anchor',
                  'beacon': 'word-beacon',
                },
                recallPrompts: <TypedRecallPrompt>[
                  TypedRecallPrompt(
                    wordId: 'word-anchor',
                    canonicalAnswer: 'anchor',
                    promptKind: TypedRecallPromptKind.context,
                    normalizationRevision: typedRecallNormalizationRevisionV1,
                    contentRevision: 1,
                    contentChecksumSha256: _typedChecksum,
                  ),
                  TypedRecallPrompt(
                    wordId: 'word-beacon',
                    canonicalAnswer: 'beacon',
                    promptKind: TypedRecallPromptKind.context,
                    normalizationRevision: typedRecallNormalizationRevisionV1,
                    contentRevision: 1,
                    contentChecksumSha256: _typedChecksum,
                  ),
                ],
                passageText: 'An anchor steadies us while a beacon guides us.',
                learning: learning,
                evidenceAdapter: CurrentActivityEvidenceAdapter(
                  learning: learning,
                ),
                associativeLearning: associativeLearning,
                sessionId: handle.id,
                sessionStartedAtUtc: handle.startedAtUtc,
                modeAdapter: registry.typedRecall!.adapter,
                featureRegistry: const BuildFeatureRegistry.allEnabled(),
              ),
            ),
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (var stage = 2; stage <= 3; stage++) {
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete & Continue'),
              )
              .onPressed!();
          await pumpUntilFound(
            tester,
            find.text('Stage $stage: ${_stageName(stage)}'),
          );
        }
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Show strategy'),
            )
            .onPressed!();
        await tester.pump();
        await tester.enterText(find.byType(TextField).at(0), 'anchor');
        await tester.enterText(find.byType(TextField).at(1), 'beacon');

        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete & Continue'),
            )
            .onPressed!();
        await pumpUntilFound(tester, find.text('Stage 4: Memory Association'));

        final attempts = (await tester.runAsync(
          () => database.select(database.answerAttempts).get(),
        ))!;
        final contexts = <EvidenceContext>[
          for (final attempt in attempts)
            EvidenceContext.fromJson(
              (jsonDecode(attempt.evidenceContextJson) as Map)
                  .cast<String, Object?>(),
            ),
        ];
        expect(
          contexts.map((context) => context.evidenceClass),
          <EvidenceClass>[
            EvidenceClass.guidedPractice,
            EvidenceClass.independentRecall,
          ],
        );
        expect(contexts.map((context) => context.hintLevel), <int>[1, 0]);
        final srs = (await tester.runAsync(
          () => database.select(database.srsStates).get(),
        ))!;
        expect(srs.map((row) => row.wordId), <String>['word-beacon']);
        expect(controller.hintState!.hintLevel, 0);
      },
    );

    testWidgets(
      'Stage 3 rejects over-limit raw input without locking retry or persistence',
      (tester) async {
        final repository = _OrderedCompletionLearningRepository();
        final contractLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'over-limit-${++id}',
          nowUtc: () => DateTime.utc(2026, 8, 26, 13, 0, id),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f11-limit'),
        );
        await tester.pumpWidget(
          session(
            targetWords: const <String>['anchor'],
            targetWordIds: const <String, String>{'anchor': 'word-anchor'},
            learningUseCases: contractLearning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(
              learning: contractLearning,
            ),
            modeAdapter: const TypedRecallModeAdapter(),
            sessionId: 'over-limit-session',
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (var stage = 2; stage <= 3; stage++) {
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete & Continue'),
              )
              .onPressed!();
          await pumpUntilFound(
            tester,
            find.text('Stage $stage: ${_stageName(stage)}'),
          );
        }
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.maxLength, TypedRecallModeAdapter.maxAnswerScalars);
        field.controller!.text = 'x' * 121;

        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete & Continue'),
            )
            .onPressed!();
        await tester.pump();
        expect(find.text('Stage 3: Active Recall'), findsOneWidget);
        expect(repository.answerCommands, isEmpty);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );

        field.controller!.text = 'anchor';
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete & Continue'),
            )
            .onPressed!();
        await pumpUntilFound(tester, find.text('Stage 4: Memory Association'));
        expect(repository.answerCommands, hasLength(1));
        expect(
          repository.answerCommands.single.providerProvenance,
          isNot(contains('x' * 121)),
        );
      },
    );

    testWidgets('quiz emergency-off fences a stale associative typed submit', (
      tester,
    ) async {
      final repository = _OrderedCompletionLearningRepository();
      final contractLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'live-off-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 26, 14, 0, id),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f11-live-off'),
      );
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      await tester.pumpWidget(
        session(
          targetWords: const <String>['anchor'],
          targetWordIds: const <String, String>{'anchor': 'word-anchor'},
          learningUseCases: contractLearning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(
            learning: contractLearning,
          ),
          modeAdapter: const TypedRecallModeAdapter(),
          featureRegistry: features,
          sessionId: 'live-off-session',
        ),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
      for (var stage = 2; stage <= 3; stage++) {
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete & Continue'),
            )
            .onPressed!();
        await pumpUntilFound(
          tester,
          find.text('Stage $stage: ${_stageName(stage)}'),
        );
      }
      await tester.enterText(find.byType(TextField), 'anchor');
      final staleSubmit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Complete & Continue'),
          )
          .onPressed!;

      features.emergencyOff(Feature.quiz);
      staleSubmit();
      await tester.pump();

      expect(repository.answerCommands, isEmpty);
      expect(find.text('Stage 3: Active Recall'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete & Continue'),
            )
            .onPressed,
        isNull,
      );
    });

    final invalidMappings = <({String name, Map<String, String>? wordIds})>[
      (name: 'missing map', wordIds: null),
      (name: 'missing target', wordIds: const {'banana': 'word-banana'}),
      (
        name: 'blank ID',
        wordIds: const {'banana': 'word-banana', 'apple': '   '},
      ),
      (
        name: 'duplicate trimmed IDs',
        wordIds: const {'banana': 'word-shared', 'apple': ' word-shared '},
      ),
    ];
    for (final invalid in invalidMappings) {
      testWidgets('Stage 3 rejects ${invalid.name} before capturing evidence', (
        tester,
      ) async {
        final repository = _OrderedCompletionLearningRepository();
        var learningId = 0;
        var evidenceIdCalls = 0;
        final contractLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'reading-contract-${++learningId}',
          nowUtc: () => DateTime.utc(2026, 8, 14, 12, 0, learningId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'associative-mapping-contract',
          ),
        );
        final evidenceAdapter = CurrentActivityEvidenceAdapter(
          learning: contractLearning,
          generateId: () {
            evidenceIdCalls++;
            return 'mapping-evidence-$evidenceIdCalls';
          },
        );
        await tester.pumpWidget(
          session(
            targetWords: const ['banana', 'apple'],
            targetWordIds: invalid.wordIds,
            learningUseCases: contractLearning,
            evidenceAdapter: evidenceAdapter,
            sessionId: 'mapping-session',
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (var stage = 2; stage <= 3; stage++) {
          await tester.tap(find.text('Complete & Continue'));
          await pumpUntilFound(
            tester,
            find.text('Stage $stage: ${_stageName(stage)}'),
          );
        }
        await tester.enterText(find.byType(TextField).at(0), 'banana');
        await tester.enterText(find.byType(TextField).at(1), 'apple');
        final progressBeforeSubmit = repository.progressCommands.length;

        await tester.tap(find.text('Complete & Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Stage 3: Active Recall'), findsOneWidget);
        expect(evidenceIdCalls, 0);
        expect(repository.answerCommands, isEmpty);
        expect(repository.progressCommands, hasLength(progressBeforeSubmit));
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .every((field) => field.enabled == true),
          isTrue,
        );
        expect(
          find.text(
            'Active recall word mapping is invalid. '
            'Restart this reading activity.',
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets(
      'Stage 6 orders close before one retryable completion progress write',
      (tester) async {
        final firstFinishRelease = Completer<void>();
        addTearDown(() {
          if (!firstFinishRelease.isCompleted) firstFinishRelease.complete();
        });
        final repository = _OrderedCompletionLearningRepository(
          failFinishOnce: true,
          failCompletedProgressOnce: true,
          firstFinishRelease: firstFinishRelease,
        );
        var nextId = 0;
        final orderedLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'ordered-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 14, 13, 0, nextId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'associative-completion-contract',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  key: const ValueKey<String>('open-associative-route'),
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => AssociativeReadingSessionScreen(
                          cefrLevel: 'A2',
                          targetWords: const ['banana'],
                          targetWordIds: const {'banana': 'word-banana'},
                          passageText: 'The banana is yellow.',
                          documentId: 'document-1',
                          documentRevision: 7,
                          learning: orderedLearning,
                          evidenceAdapter: CurrentActivityEvidenceAdapter(
                            learning: orderedLearning,
                          ),
                          associativeLearning: associativeLearning,
                          sessionId: 'session-1',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open associative reading'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('open-associative-route')),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 2: Cue Fading'));
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 3: Active Recall'));
        await tester.enterText(find.byType(TextField), 'banana');
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 4: Memory Association'));
        await tester.enterText(find.byType(TextField), 'yellow fruit');
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));
        await tester.enterText(find.byType(TextField), 'I ate a banana.');
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 6: Finish'));

        final finish = find.widgetWithText(FilledButton, 'Finish Session');
        final staleFinishHandler = tester
            .widget<FilledButton>(finish)
            .onPressed!;
        await tester.tap(finish);
        for (
          var pump = 0;
          pump < 20 && repository.finishCalls.isEmpty;
          pump++
        ) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        await tester.pump();

        expect(repository.completedProgressCommands, isEmpty);
        expect(repository.finishCalls, hasLength(1));
        expect(repository.answerCommands, hasLength(1));
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(
                  const ValueKey<String>('current-session-close-retry'),
                ),
              )
              .onPressed,
          isNull,
        );
        staleFinishHandler();
        await tester.pump(const Duration(milliseconds: 1));
        expect(repository.finishCalls, hasLength(1));
        expect(repository.completedProgressCommands, isEmpty);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          find.byType(AssociativeReadingSessionScreen),
          findsOneWidget,
          reason: 'pending session close must veto route back',
        );

        firstFinishRelease.complete();
        await tester.pumpAndSettle();
        var retry = find.byKey(
          const ValueKey<String>('current-session-close-retry'),
        );
        expect(retry, findsOneWidget);
        expect(repository.completedProgressCommands, isEmpty);
        staleFinishHandler();
        await tester.pump();
        expect(repository.finishCalls, hasLength(1));
        expect(repository.answerCommands, hasLength(1));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AssociativeReadingSessionScreen), findsOneWidget);

        final closeRetryHandler = tester.widget<FilledButton>(retry).onPressed;
        expect(closeRetryHandler, isNotNull);
        closeRetryHandler!();
        await tester.pumpAndSettle();

        expect(repository.finishCalls, hasLength(2));
        expect(repository.finishCalls.last, repository.finishCalls.first);
        expect(repository.answerCommands, hasLength(1));
        final failedCompletion = repository.completedProgressCommands;
        expect(failedCompletion, hasLength(1));
        retry = find.byKey(
          const ValueKey<String>('current-reading-progress-retry'),
        );
        expect(retry, findsOneWidget);
        staleFinishHandler();
        await tester.pump();
        expect(repository.finishCalls, hasLength(2));
        expect(repository.completedProgressCommands, hasLength(1));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AssociativeReadingSessionScreen), findsOneWidget);

        final progressRetryHandler = tester
            .widget<FilledButton>(retry)
            .onPressed;
        expect(progressRetryHandler, isNotNull);
        progressRetryHandler!();
        await tester.pumpAndSettle();

        expect(repository.finishCalls, hasLength(2));
        expect(repository.answerCommands, hasLength(1));
        expect(repository.completedProgressCommands, hasLength(2));
        final firstProgress = repository.completedProgressCommands.first;
        final retriedProgress = repository.completedProgressCommands.last;
        expect(retriedProgress.eventId, firstProgress.eventId);
        expect(retriedProgress.ownerId, firstProgress.ownerId);
        expect(retriedProgress.documentId, firstProgress.documentId);
        expect(
          retriedProgress.documentRevision,
          firstProgress.documentRevision,
        );
        expect(retriedProgress.position, firstProgress.position);
        expect(retriedProgress.isCompleted, isTrue);
        expect(retriedProgress.occurredAtUtc, firstProgress.occurredAtUtc);
        expect(find.byType(AssociativeReadingSessionScreen), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('open-associative-route')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'stage checkpoint freezes identity, blocks exit, and excludes lifecycle duplicates',
      (tester) async {
        final firstProgressRelease = Completer<void>();
        addTearDown(() {
          if (!firstProgressRelease.isCompleted) {
            firstProgressRelease.complete();
          }
        });
        final repository = _OrderedCompletionLearningRepository(
          failIncompleteProgressOnce: true,
          firstIncompleteProgressRelease: firstProgressRelease,
        );
        var nextId = 0;
        final checkpointLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'checkpoint-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 15, 9, 0, nextId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'associative-checkpoint-contract',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  key: const ValueKey<String>('open-checkpoint-route'),
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => AssociativeReadingSessionScreen(
                          cefrLevel: 'A2',
                          targetWords: const ['banana'],
                          targetWordIds: const {'banana': 'word-banana'},
                          passageText: 'The banana is yellow.',
                          documentId: 'checkpoint-document',
                          documentRevision: 3,
                          learning: checkpointLearning,
                          evidenceAdapter: CurrentActivityEvidenceAdapter(
                            learning: checkpointLearning,
                          ),
                          associativeLearning: associativeLearning,
                          sessionId: 'checkpoint-session',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open checkpoint reading'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('open-checkpoint-route')),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

        final continueButton = find.widgetWithText(
          FilledButton,
          'Complete & Continue',
        );
        final staleContinueHandler = tester
            .widget<FilledButton>(continueButton)
            .onPressed!;
        await tester.tap(continueButton);
        for (
          var pump = 0;
          pump < 20 && repository.progressCommands.isEmpty;
          pump++
        ) {
          await tester.pump(const Duration(milliseconds: 1));
        }

        staleContinueHandler();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(repository.progressCommands, hasLength(1));
        expect(
          find.byType(AssociativeReadingSessionScreen),
          findsOneWidget,
          reason: 'an in-flight checkpoint must veto route disposal',
        );

        firstProgressRelease.complete();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        final retry = find.byKey(
          const ValueKey<String>('current-reading-checkpoint-retry'),
        );
        expect(retry, findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AssociativeReadingSessionScreen), findsOneWidget);

        final retryHandler = tester.widget<FilledButton>(retry).onPressed;
        expect(retryHandler, isNotNull);
        retryHandler!();
        await pumpUntilFound(tester, find.text('Stage 2: Cue Fading'));

        expect(repository.progressCommands, hasLength(2));
        final first = repository.progressCommands.first;
        final retried = repository.progressCommands.last;
        expect(retried.eventId, first.eventId);
        expect(retried.ownerId, first.ownerId);
        expect(retried.documentId, first.documentId);
        expect(retried.documentRevision, first.documentRevision);
        expect(retried.position, first.position);
        expect(retried.isCompleted, first.isCompleted);
        expect(retried.occurredAtUtc, first.occurredAtUtc);
      },
    );

    testWidgets(
      'Stage 4 freezes a multiword batch and retries only the failed write',
      (tester) async {
        final port = _PartialAssociationPort();
        await tester.pumpWidget(
          session(
            targetWords: const ['banana', 'apple'],
            targetWordIds: const {
              'banana': 'word-banana',
              'apple': 'word-apple',
            },
            port: port,
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (var stage = 2; stage <= 4; stage++) {
          await tester.tap(find.text('Complete & Continue'));
          await pumpUntilFound(
            tester,
            find.text('Stage $stage: ${_stageName(stage)}'),
          );
        }

        await tester.enterText(find.byType(TextField).at(0), 'yellow fruit');
        await tester.enterText(find.byType(TextField).at(1), 'red fruit');
        await tester.tap(find.text('Complete & Continue'));
        await tester.pumpAndSettle();

        expect(find.text('Stage 4: Memory Association'), findsOneWidget);
        expect(port.calls, hasLength(2));
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .every((field) => field.enabled == false),
          isTrue,
          reason: 'frozen association inputs must not diverge before retry',
        );
        final popScope = find.byWidgetPredicate(
          (widget) => widget is PopScope,
          description: 'associative reading PopScope',
        );
        expect(tester.widget<PopScope<Object?>>(popScope).canPop, isFalse);
        final retry = find.byKey(
          const ValueKey<String>('current-association-retry'),
        );
        expect(retry, findsOneWidget);

        tester
                .widgetList<TextField>(find.byType(TextField))
                .first
                .controller!
                .text =
            'mutated after capture';
        final retryHandler = tester.widget<FilledButton>(retry).onPressed;
        expect(retryHandler, isNotNull);
        retryHandler!();
        await pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));

        expect(port.calls, hasLength(3));
        final bananaCalls = port.calls
            .where((record) => record.wordKey == 'word-banana')
            .toList(growable: false);
        final appleCalls = port.calls
            .where((record) => record.wordKey == 'word-apple')
            .toList(growable: false);
        expect(bananaCalls, hasLength(1));
        expect(appleCalls, hasLength(2));
        expect(appleCalls.last.associationId, appleCalls.first.associationId);
        expect(appleCalls.last.createdAtUtc, appleCalls.first.createdAtUtc);
        expect(appleCalls.last.content, 'red fruit');
        expect(
          (await port.getAssociationsForWord(
            'local:reading-owner',
            'word-banana',
          )).single.content,
          'yellow fruit',
        );
        expect(
          (await port.getAssociationsForWord(
            'local:reading-owner',
            'word-apple',
          )).single.content,
          'red fruit',
        );
      },
    );

    testWidgets(
      'Stage 4 snapshots cues and word mappings before owner resolution',
      (tester) async {
        final gatedOwners = _SwitchableOwnerRepository(owners);
        var nextId = 0;
        final gatedLearning = LearningUseCases(
          owners: gatedOwners,
          repository: DriftLearningRepository(database),
          generateId: () => 'association-snapshot-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 16, 9, 0, nextId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'association-snapshot-contract',
          ),
        );
        final port = _RecordingAssociationPort();
        const originalIds = {'banana': 'word-banana', 'apple': 'word-apple'};

        await tester.pumpWidget(
          session(
            targetWords: const ['banana', 'apple'],
            targetWordIds: originalIds,
            port: port,
            learningUseCases: gatedLearning,
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (var stage = 2; stage <= 4; stage++) {
          await tester.tap(find.text('Complete & Continue'));
          await pumpUntilFound(
            tester,
            find.text('Stage $stage: ${_stageName(stage)}'),
          );
        }

        await tester.enterText(find.byType(TextField).at(0), 'yellow fruit');
        await tester.enterText(find.byType(TextField).at(1), 'red fruit');
        gatedOwners.blockNextOwnerResolution();
        await tester.tap(find.text('Complete & Continue'));
        await tester.pump();
        await tester.runAsync(() => gatedOwners.didBlock);

        tester
                .widgetList<TextField>(find.byType(TextField))
                .first
                .controller!
                .text =
            'mutated while owner was resolving';
        await tester.pumpWidget(
          session(
            targetWords: const ['banana', 'apple'],
            targetWordIds: const {
              'banana': 'changed-banana',
              'apple': 'changed-apple',
            },
            port: port,
            learningUseCases: gatedLearning,
          ),
        );
        gatedOwners.release();
        await pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));

        expect(port.calls.map((record) => record.wordKey), <String>[
          'word-banana',
          'word-apple',
        ]);
        expect(port.calls.map((record) => record.content), <String>[
          'yellow fruit',
          'red fruit',
        ]);
        expect(
          port.calls.map((record) => record.createdAtUtc).toSet(),
          hasLength(1),
        );
      },
    );

    testWidgets('Stage 5 locks its draft while checkpoint retry is pending', (
      tester,
    ) async {
      final repository = _StageFiveCheckpointRepository();
      var nextId = 0;
      final checkpointLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'stage-five-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 16, 10, 0, nextId),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'stage-five-checkpoint-contract',
        ),
      );
      await tester.pumpWidget(session(learningUseCases: checkpointLearning));
      await pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));

      await tester.enterText(find.byType(TextField), 'A resilient response.');
      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('current-reading-checkpoint-retry')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });
}

final class _OrderedCompletionLearningRepository implements LearningRepository {
  _OrderedCompletionLearningRepository({
    this.failFinishOnce = false,
    this.failCompletedProgressOnce = false,
    this.failIncompleteProgressOnce = false,
    this.firstFinishRelease,
    this.firstIncompleteProgressRelease,
  });

  final bool failFinishOnce;
  final bool failCompletedProgressOnce;
  final bool failIncompleteProgressOnce;
  final Completer<void>? firstFinishRelease;
  final Completer<void>? firstIncompleteProgressRelease;
  final List<RecordAnswerCommand> answerCommands = <RecordAnswerCommand>[];
  final List<ReadingProgressCommand> progressCommands =
      <ReadingProgressCommand>[];
  final List<({String ownerId, String sessionId, DateTime endedAtUtc})>
  finishCalls = <({String ownerId, String sessionId, DateTime endedAtUtc})>[];
  var _completedProgressFailed = false;
  var _incompleteProgressFailed = false;

  Iterable<ReadingProgressCommand> get completedProgressCommands =>
      progressCommands.where((command) => command.isCompleted);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => null;

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) async {
    progressCommands.add(command);
    if (!command.isCompleted &&
        failIncompleteProgressOnce &&
        !_incompleteProgressFailed) {
      _incompleteProgressFailed = true;
      await firstIncompleteProgressRelease?.future;
      throw StateError('simulated stage checkpoint failure');
    }
    if (command.isCompleted &&
        failCompletedProgressOnce &&
        !_completedProgressFailed) {
      _completedProgressFailed = true;
      throw StateError('simulated completion progress failure');
    }
    return ReadingProgressSnapshot(
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      lastPosition: command.position,
      isCompleted: command.isCompleted,
      updatedAtUtc: command.occurredAtUtc,
    );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    answerCommands.add(command);
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
      activityType: 'associativeReading',
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

final class _FailingProgressLearningRepository
    implements LearningRepository, LearningSessionLifecycleRepository {
  _FailingProgressLearningRepository(this._delegate);

  final DriftLearningRepository _delegate;

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => Future<ReadingProgressSnapshot?>.error(
    StateError('simulated reading-progress load failure'),
  );

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => _delegate.saveReadingProgress(command);

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) => _delegate.abandonSession(
    ownerId: ownerId,
    sessionId: sessionId,
    abandonedAtUtc: abandonedAtUtc,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryLearningRepository implements LearningRepository {
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  var _recordFailed = false;

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => null;

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) async {
    return ReadingProgressSnapshot(
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      lastPosition: command.position,
      isCompleted: command.isCompleted,
      updatedAtUtc: command.occurredAtUtc,
    );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (!_recordFailed) {
      _recordFailed = true;
      throw StateError('simulated local failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PartialBatchLearningRepository implements LearningRepository {
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  bool _appleFailed = false;

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => null;

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) async => ReadingProgressSnapshot(
    documentId: command.documentId,
    documentRevision: command.documentRevision,
    lastPosition: command.position,
    isCompleted: command.isCompleted,
    updatedAtUtc: command.occurredAtUtc,
  );

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (command.wordId == 'word-apple' && !_appleFailed) {
      _appleFailed = true;
      throw StateError('simulated second-item failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PartialAssociationPort implements AssociativeLearningPort {
  final InMemoryAssociativeLearningAdapter _delegate =
      InMemoryAssociativeLearningAdapter();
  final List<AssociationRecord> calls = <AssociationRecord>[];
  var _failedApple = false;

  @override
  Future<void> saveAssociationAndMemoryState(
    AssociationRecord record,
    AssociativeMemoryState initialState,
  ) async {
    calls.add(record);
    if (record.wordKey == 'word-apple' && !_failedApple) {
      _failedApple = true;
      throw StateError('simulated second association failure');
    }
    await _delegate.saveAssociationAndMemoryState(record, initialState);
  }

  @override
  Future<List<AssociationRecord>> getAssociationsForWord(
    String ownerId,
    String wordKey,
  ) => _delegate.getAssociationsForWord(ownerId, wordKey);

  @override
  Future<AssociativeMemoryState?> getMemoryState(
    String ownerId,
    String wordKey,
  ) => _delegate.getMemoryState(ownerId, wordKey);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingAssociationPort implements AssociativeLearningPort {
  final InMemoryAssociativeLearningAdapter _delegate =
      InMemoryAssociativeLearningAdapter();
  final List<AssociationRecord> calls = <AssociationRecord>[];

  @override
  Future<void> saveAssociationAndMemoryState(
    AssociationRecord record,
    AssociativeMemoryState initialState,
  ) async {
    calls.add(record);
    await _delegate.saveAssociationAndMemoryState(record, initialState);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SwitchableOwnerRepository implements LocalOwnerRepository {
  _SwitchableOwnerRepository(this._delegate);

  final LocalOwnerRepository _delegate;
  Completer<void>? _blocked;
  Completer<void>? _release;

  void blockNextOwnerResolution() {
    _blocked = Completer<void>();
    _release = Completer<void>();
  }

  Future<void> get didBlock => _blocked!.future;

  void release() => _release!.complete();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    final blocked = _blocked;
    final release = _release;
    if (blocked != null && release != null && !blocked.isCompleted) {
      blocked.complete();
      await release.future;
      if (identical(_blocked, blocked)) {
        _blocked = null;
        _release = null;
      }
    }
    return _delegate.getOrCreateActiveOwner();
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      _delegate.bindFirebaseUid(ownerId, firebaseUid);
}

final class _StageFiveCheckpointRepository implements LearningRepository {
  final List<ReadingProgressCommand> commands = <ReadingProgressCommand>[];
  var _failed = false;

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => ReadingProgressSnapshot(
    documentId: documentId,
    documentRevision: documentRevision,
    lastPosition: 5,
    isCompleted: false,
    updatedAtUtc: DateTime.utc(2026, 8, 16, 9),
  );

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) async {
    commands.add(command);
    if (!_failed) {
      _failed = true;
      throw StateError('simulated Stage 5 checkpoint failure');
    }
    return ReadingProgressSnapshot(
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      lastPosition: command.position,
      isCompleted: command.isCompleted,
      updatedAtUtc: command.occurredAtUtc,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _stageName(int stage) => switch (stage) {
  2 => 'Cue Fading',
  3 => 'Active Recall',
  4 => 'Memory Association',
  5 => 'Context Transfer',
  6 => 'Finish',
  _ => throw ArgumentError.value(stage),
};
