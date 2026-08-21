import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
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
    expect(retry.occurredAtUtc, first.occurredAtUtc);
    expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
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
    this.firstAnswerRelease,
    this.firstFinishRelease,
  });

  final LearningRepository delegate;
  final bool failAnswerOnce;
  final bool failFinishOnce;
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
