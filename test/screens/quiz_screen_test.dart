import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  var id = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    id = 0;
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++id}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
  });

  tearDown(() => database.close());

  test('adapter pins deterministic bidirectional recognition questions', () {
    const adapter = MeaningQuizModeAdapter();
    final session = QuizSession(
      id: 'session:pinned-meaning-quiz',
      startedAtUtc: DateTime.utc(2026, 8, 26, 9),
      questions: const <QuizQuestion>[
        QuizQuestion(
          word: QuizWord(
            id: 'word-1',
            categoryId: 'category-1',
            spelling: 'station',
            meaning: 'สถานี',
            partOfSpeech: 'noun',
          ),
          options: <String>['สถานี', 'สนามบิน', 'โรงแรม', 'ตลาด'],
        ),
        QuizQuestion(
          word: QuizWord(
            id: 'word-2',
            categoryId: 'category-1',
            spelling: 'airport',
            meaning: 'สนามบิน',
            partOfSpeech: 'noun',
          ),
          options: <String>['สนามบิน', 'สถานี', 'ตลาด', 'โรงแรม'],
        ),
        QuizQuestion(
          word: QuizWord(
            id: 'word-3',
            categoryId: 'category-1',
            spelling: 'hotel',
            meaning: 'โรงแรม',
            partOfSpeech: 'noun',
          ),
          options: <String>['โรงแรม', 'ตลาด', 'สถานี', 'สนามบิน'],
        ),
        QuizQuestion(
          word: QuizWord(
            id: 'word-4',
            categoryId: 'category-1',
            spelling: 'market',
            meaning: 'ตลาด',
            partOfSpeech: 'noun',
          ),
          options: <String>['ตลาด', 'โรงแรม', 'สนามบิน', 'สถานี'],
        ),
      ],
    );

    final first = adapter.pinQuestions(session);
    final replay = adapter.pinQuestions(session);

    expect(first.map((question) => question.direction), <MeaningQuizDirection>[
      MeaningQuizDirection.wordToMeaning,
      MeaningQuizDirection.meaningToWord,
      MeaningQuizDirection.wordToMeaning,
      MeaningQuizDirection.meaningToWord,
    ]);
    expect(first[0].prompt, 'station');
    expect(first[0].correctOption, 'สถานี');
    expect(first[1].prompt, 'สนามบิน');
    expect(first[1].correctOption, 'airport');
    expect(
      first.map((question) => question.options),
      replay.map((q) => q.options),
    );
    expect(first.every((question) => question.options.length == 4), isTrue);
    expect(
      first.every(
        (question) =>
            question.options.toSet().length == question.options.length,
      ),
      isTrue,
    );

    final ambiguous = adapter.pinQuestions(
      QuizSession(
        id: 'session:ambiguous-meaning-quiz',
        startedAtUtc: DateTime.utc(2026, 8, 26, 9),
        questions: const <QuizQuestion>[
          QuizQuestion(
            word: QuizWord(
              id: 'word-lead-metal',
              categoryId: 'category-1',
              spelling: 'Lead',
              meaning: 'ตะกั่ว',
              partOfSpeech: 'noun',
              normalizedSpelling: 'lead',
              normalizedMeaning: 'ตะกั่ว',
            ),
            options: <String>[],
          ),
          QuizQuestion(
            word: QuizWord(
              id: 'word-airport',
              categoryId: 'category-1',
              spelling: 'AIRPORT',
              meaning: 'Air Port',
              partOfSpeech: 'noun',
              normalizedSpelling: 'airport',
              normalizedMeaning: 'air port',
            ),
            options: <String>[],
          ),
          QuizQuestion(
            word: QuizWord(
              id: 'word-lead-verb',
              categoryId: 'category-1',
              spelling: '  lead ',
              meaning: 'นำทาง',
              partOfSpeech: 'verb',
              normalizedSpelling: 'lead',
              normalizedMeaning: 'นำทาง',
            ),
            options: <String>[],
          ),
          QuizQuestion(
            word: QuizWord(
              id: 'word-airfield',
              categoryId: 'category-1',
              spelling: 'airfield',
              meaning: ' air   port ',
              partOfSpeech: 'noun',
              normalizedSpelling: 'airfield',
              normalizedMeaning: 'air port',
            ),
            options: <String>[],
          ),
        ],
      ),
    );
    expect(ambiguous[0].options, isNot(contains('นำทาง')));
    expect(ambiguous[1].options, isNot(contains('airfield')));
  });

  test(
    'review rejects corrupt feedback context before write without retry debt',
    () async {
      final durableSession = await learning.startQuiz(
        categoryId: 'category-1',
        limit: 1,
      );
      final corruptSession = QuizSession(
        id: durableSession.id,
        startedAtUtc: durableSession.startedAtUtc,
        questions: const <QuizQuestion>[
          QuizQuestion(
            word: QuizWord(
              id: 'word-1',
              categoryId: 'category-1',
              spelling: 'station',
              meaning: '   ',
              partOfSpeech: 'noun',
            ),
            options: <String>['   '],
          ),
        ],
      );
      final review = const MeaningQuizModeAdapter().createReview(
        session: corruptSession,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
      );
      addTearDown(review.dispose);

      expect(
        () => review.answer(option: '   ', responseTimeMs: 250),
        throwsArgumentError,
      );

      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(review.phase, MeaningQuizReviewPhase.awaitingAnswer);
      expect(review.requiresRetry, isFalse);
      expect(review.persistenceLocked, isFalse);
    },
  );

  test('quiz words preserve canonical vocabulary equivalence keys', () async {
    final session = await learning.startQuiz(
      categoryId: 'category-1',
      limit: 1,
    );

    expect(session.questions.single.word.normalizedSpelling, 'station');
    expect(session.questions.single.word.normalizedMeaning, 'สถานี');
  });

  testWidgets(
    'screen records both directions as recognition and feedback is read-only',
    (tester) async {
      await tester.runAsync(() async {
        final ownerId = (await owners.getOrCreateActiveOwner()).id;
        await _insertWord(
          database,
          ownerId: ownerId,
          id: 'word-2',
          spelling: 'airport',
          meaning: 'สนามบิน',
        );
        await _insertWord(
          database,
          ownerId: ownerId,
          id: 'word-3',
          spelling: 'hotel',
          meaning: 'โรงแรม',
        );
        await _insertWord(
          database,
          ownerId: ownerId,
          id: 'word-4',
          spelling: 'market',
          meaning: 'ตลาด',
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            categoryId: 'category-1',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
            modeAdapter: const MeaningQuizModeAdapter(),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));

      await tester.tap(find.text('สถานี'));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('answer-feedback-panel')),
      );
      expect(find.text('Correct answer: สถานี'), findsOneWidget);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
        reason: 'rendering committed feedback must not submit another event',
      );

      final next = find.byKey(const ValueKey<String>('meaning-quiz-next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('สนามบิน'), findsOneWidget);
      expect(find.text('airport'), findsOneWidget);
      expect(find.text('station'), findsOneWidget);

      await tester.tap(find.text('airport'));
      await _pumpUntilFound(tester, find.text('Correct answer: airport'));

      final attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(2));
      expect(attempts.map((attempt) => attempt.promptMode), <String>[
        'meaningChoice',
        'wordChoice',
      ]);
      expect(attempts.map((attempt) => attempt.evidenceClass).toSet(), <String>{
        EvidenceClass.recognition.name,
      });
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(
        (await database.select(database.eventsV2).get()).where(
          (event) => event.eventId.startsWith('learning-event:'),
        ),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'commit then ack loss retries the frozen recognition without duplication',
    (tester) async {
      final repository = _FailFirstLearningRepository(
        DriftLearningRepository(database),
        commitThenLoseAckOnce: true,
      );
      var retryId = 0;
      final retryLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'lost-ack-${++retryId}',
        nowUtc: () => DateTime.utc(2026, 8, 26, 10, 0, retryId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f07-test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            categoryId: 'category-1',
            learning: retryLearning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(
              learning: retryLearning,
            ),
            modeAdapter: const MeaningQuizModeAdapter(),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));

      await tester.tap(find.text('สถานี'));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('current-evidence-retry')),
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
        reason: 'the first write committed before its acknowledgement was lost',
      );
      expect(
        find.byKey(const ValueKey<String>('answer-feedback-panel')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('current-evidence-retry')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('answer-feedback-panel')),
      );

      expect(repository.commands, hasLength(2));
      final first = repository.commands.first;
      final retry = repository.commands.last;
      expect(retry.id, first.id);
      expect(retry.ownerId, first.ownerId);
      expect(retry.sessionId, first.sessionId);
      expect(retry.wordId, first.wordId);
      expect(retry.promptMode, first.promptMode);
      expect(retry.isCorrect, first.isCorrect);
      expect(retry.responseTimeMs, first.responseTimeMs);
      expect(retry.attemptNumber, first.attemptNumber);
      expect(retry.occurredAtUtc, first.occurredAtUtc);
      expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
      expect(retry.providerProvenance, first.providerProvenance);
      expect(retry.event?.toJson(), first.event?.toJson());
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(
        (await database.select(database.eventsV2).get()).where(
          (event) => event.eventId.startsWith('learning-event:'),
        ),
        hasLength(1),
      );
      expect(find.text('Correct answer: สถานี'), findsOneWidget);
    },
  );

  testWidgets('answer is durable before score screen is shown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          categoryId: 'category-1',
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));

    expect(find.text('station'), findsOneWidget);
    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
    await tester.tap(find.text('ดูผลการเรียน'));
    await _pumpUntilFound(tester, find.byType(ScoreScreen));

    expect(find.byType(ScoreScreen), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    final session = await database
        .select(database.learningSessions)
        .getSingle();
    expect(session.state, 'completed');
  });

  testWidgets(
    'post-commit haptic failure keeps answer locked and navigation available',
    (tester) async {
      final hapticAttempted = Completer<void>();
      var hapticCalls = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          hapticCalls += 1;
          if (!hapticAttempted.isCompleted) hapticAttempted.complete();
          throw PlatformException(code: 'haptic-unavailable');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            categoryId: 'category-1',
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('station'));

      await tester.tap(find.text('สถานี'));
      await tester.runAsync(() async {
        await hapticAttempted.future;
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(hapticCalls, 1);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(find.text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง'), findsNothing);
      expect(find.text('ดูผลการเรียน'), findsOneWidget);
      final answerButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('สถานี'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(answerButton.onPressed, isNull);

      await tester.tap(find.text('ดูผลการเรียน'));
      await _pumpUntilFound(tester, find.byType(ScoreScreen));

      expect(find.byType(ScoreScreen), findsOneWidget);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  testWidgets('missing category shows honest empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          categoryId: 'missing',
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    final emptyState = find.textContaining('ยังไม่มีคำศัพท์สำหรับ Quiz');
    await _pumpUntilFound(tester, emptyState);

    expect(emptyState, findsOneWidget);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  testWidgets('retry reuses pending evidence identity', (tester) async {
    final repository = _FailFirstLearningRepository(
      DriftLearningRepository(database),
    );
    var retryId = 0;
    final retryLearning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'retry-${++retryId}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 10, 2, retryId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          categoryId: 'category-1',
          learning: retryLearning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(
            learning: retryLearning,
          ),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('station'));

    await tester.tap(find.text('สถานี'));
    await _pumpUntilFound(tester, find.byType(SnackBar));
    final answerButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('สถานี'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(answerButton.onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
    );
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));

    expect(repository.commands, hasLength(2));
    final first = repository.commands.first;
    final retry = repository.commands.last;
    expect(retry.id, first.id);
    expect(retry.ownerId, first.ownerId);
    expect(retry.sessionId, first.sessionId);
    expect(retry.wordId, first.wordId);
    expect(retry.promptMode, first.promptMode);
    expect(retry.isCorrect, first.isCorrect);
    expect(retry.responseTimeMs, first.responseTimeMs);
    expect(retry.attemptNumber, first.attemptNumber);
    expect(retry.occurredAtUtc, first.occurredAtUtc);
    expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
    expect(retry.providerProvenance, first.providerProvenance);
    expect(retry.event?.toJson(), first.event?.toJson());
    expect(retry.evidenceContext.evidenceClass, EvidenceClass.recognition);
    expect(
      retry.evidenceContext.classificationSource,
      EvidenceClassificationSource.legacyInferred,
    );
  });

  testWidgets('back cannot discard an in-flight or retryable answer', (
    tester,
  ) async {
    final firstAnswerRelease = Completer<void>();
    addTearDown(() {
      if (!firstAnswerRelease.isCompleted) firstAnswerRelease.complete();
    });
    final repository = _FailFirstLearningRepository(
      DriftLearningRepository(database),
      firstAnswerRelease: firstAnswerRelease,
    );
    var retryId = 0;
    final retryLearning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'route-lock-${++retryId}',
      nowUtc: () => DateTime.utc(2026, 8, 21, 10, 0, retryId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const ValueKey<String>('open-quiz-route'),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => QuizScreen(
                      categoryId: 'category-1',
                      learning: retryLearning,
                      evidenceAdapter: CurrentActivityEvidenceAdapter(
                        learning: retryLearning,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open quiz'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-quiz-route')));
    await _pumpUntilFound(tester, find.text('station'));

    await tester.tap(find.text('สถานี'));
    for (var pump = 0; pump < 20 && repository.commands.isEmpty; pump++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(repository.commands, hasLength(1));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byType(QuizScreen),
      findsOneWidget,
      reason: 'back must not discard an answer write in flight',
    );

    firstAnswerRelease.complete();
    final retryButton = find.byKey(
      const ValueKey<String>('current-evidence-retry'),
    );
    await _pumpUntilFound(tester, retryButton);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byType(QuizScreen),
      findsOneWidget,
      reason: 'back must preserve the exact retryable answer',
    );

    final answerRetryHandler = tester
        .widget<FilledButton>(retryButton)
        .onPressed;
    expect(answerRetryHandler, isNotNull);
    answerRetryHandler!();
    await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));

    expect(repository.commands, hasLength(2));
    expect(repository.commands.last.id, repository.commands.first.id);
    expect(
      repository.commands.last.occurredAtUtc,
      repository.commands.first.occurredAtUtc,
    );
  });

  testWidgets(
    'final close keeps one frozen retry and blocks back and stale completion',
    (tester) async {
      final firstFinishRelease = Completer<void>();
      addTearDown(() {
        if (!firstFinishRelease.isCompleted) firstFinishRelease.complete();
      });
      final repository = _FailFirstLearningRepository(
        DriftLearningRepository(database),
        failAnswerOnce: false,
        failFinishOnce: true,
        firstFinishRelease: firstFinishRelease,
      );
      var nextId = 0;
      var clockTick = 0;
      final closeLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'close-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 21, 11, 0, clockTick++),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const ValueKey<String>('open-quiz-route'),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => QuizScreen(
                        categoryId: 'category-1',
                        learning: closeLearning,
                        evidenceAdapter: CurrentActivityEvidenceAdapter(
                          learning: closeLearning,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open quiz'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('open-quiz-route')));
      await _pumpUntilFound(tester, find.text('station'));
      await tester.tap(find.text('สถานี'));
      final finishButton = find.widgetWithText(FilledButton, 'ดูผลการเรียน');
      await _pumpUntilFound(tester, finishButton);
      final staleFinishHandler = tester
          .widget<FilledButton>(finishButton)
          .onPressed!;

      await tester.tap(finishButton);
      for (var pump = 0; pump < 20 && repository.finishCalls.isEmpty; pump++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(repository.finishCalls, hasLength(1));

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(QuizScreen),
        findsOneWidget,
        reason: 'back must not discard a session close in flight',
      );

      firstFinishRelease.complete();
      final retryButton = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      await _pumpUntilFound(tester, retryButton);
      expect(find.text('Retry session completion'), findsOneWidget);

      staleFinishHandler();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        repository.finishCalls,
        hasLength(1),
        reason: 'a stale completion callback must honor the pending close',
      );

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(QuizScreen),
        findsOneWidget,
        reason: 'back must preserve the retry-required session close',
      );

      final closeRetryHandler = tester
          .widget<FilledButton>(retryButton)
          .onPressed;
      expect(closeRetryHandler, isNotNull);
      closeRetryHandler!();
      await _pumpUntilFound(tester, find.byType(ScoreScreen));

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(2));
      expect(repository.finishCalls.last, repository.finishCalls.first);
      expect(find.byType(ScoreScreen), findsOneWidget);
    },
  );
}

final class _FailFirstLearningRepository implements LearningRepository {
  _FailFirstLearningRepository(
    this.delegate, {
    this.failAnswerOnce = true,
    this.failFinishOnce = false,
    this.commitThenLoseAckOnce = false,
    this.firstAnswerRelease,
    this.firstFinishRelease,
  });

  final LearningRepository delegate;
  final bool failAnswerOnce;
  final bool failFinishOnce;
  final bool commitThenLoseAckOnce;
  final Completer<void>? firstAnswerRelease;
  final Completer<void>? firstFinishRelease;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  final List<({String ownerId, String sessionId, DateTime endedAtUtc})>
  finishCalls = <({String ownerId, String sessionId, DateTime endedAtUtc})>[];
  bool _answerFailed = false;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (commands.length == 1) await firstAnswerRelease?.future;
    if (commitThenLoseAckOnce && !_answerFailed) {
      _answerFailed = true;
      await delegate.recordAnswer(command);
      throw StateError('simulated acknowledgement loss after commit');
    }
    if (failAnswerOnce && !_answerFailed) {
      _answerFailed = true;
      throw StateError('simulated local failure');
    }
    return delegate.recordAnswer(command);
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
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _insertWord(
  AppDatabase database, {
  required String ownerId,
  required String id,
  required String spelling,
  required String meaning,
}) {
  return database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: id,
          ownerId: ownerId,
          categoryId: 'category-1',
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
