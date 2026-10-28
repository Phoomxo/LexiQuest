import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness harness;
  late LearningUseCases learning;
  var id = 0;

  LearningUseCases freshLearning() => LearningUseCases(
    owners: harness.owners,
    repository: DriftLearningRepository(
      harness.database,
      ownerWrites: harness.ownerWrites,
    ),
    generateId: () => 'screen-${++id}',
    nowUtc: () => harness.now,
    buildInfo: const AppBuildInfo(
      version: 'synthetic-ui',
      buildId: 'synthetic-v16',
    ),
  );

  setUp(() async {
    harness = await ConfiguredQuizHarness.open();
    id = 0;
    learning = freshLearning();
  });
  tearDown(() => harness.close());

  Future<ConfiguredQuizState> start({int count = 1}) async =>
      learning.startConfiguredQuiz(
        await learning.prepareConfiguredQuiz(
          configuration: QuizConfiguration.category(
            categoryId: configuredCategoryId,
            limit: count,
          ),
          expectedOwnerId: configuredOwnerId,
        ),
      );

  Future<ConfiguredQuizState> answer(
    ConfiguredQuizState quiz, {
    bool reveal = false,
  }) async {
    final question = quiz.plan.questions[quiz.checkpoint.questionOrdinal];
    final pending = await learning.prepareQuizAnswer(
      sessionId: quiz.sessionId,
      expectedOwnerId: quiz.ownerId,
      expectedRevision: quiz.checkpointRevision,
      selectedOptionOrdinal: reveal
          ? null
          : question.options.indexOf(question.correctAnswer),
      revealed: reveal,
      responseTimeMs: 350,
    );
    return (await learning.commitQuizAnswer(
      sessionId: pending.sessionId,
      expectedOwnerId: pending.ownerId,
      expectedRevision: pending.checkpointRevision,
    )).state;
  }

  Future<void> mount(WidgetTester tester, ConfiguredQuizState quiz) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          learning: freshLearning(),
          resumeSessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
        ),
      ),
    );
    await _until(
      tester,
      find.text(
        quiz.plan.questions[quiz.checkpoint.questionOrdinal].word.spelling,
      ),
    );
  }

  testWidgets(
    'exact awaiting resume reads the accepted deck without starting again',
    (tester) async {
      final quiz = (await tester.runAsync(() => start(count: 2)))!;
      final before = await tester.runAsync(harness.snapshot);
      await mount(tester, quiz);
      expect(find.text('คำถาม 1 จาก 2'), findsOneWidget);
      for (final option in quiz.plan.questions.first.options) {
        expect(find.widgetWithText(FilledButton, option), findsOneWidget);
      }
      expect(await tester.runAsync(harness.snapshot), before);
    },
  );

  testWidgets(
    'seen then hidden hint survives route recreation and resumed latency is null',
    (tester) async {
      var quiz = (await tester.runAsync(() => start()))!;
      quiz = (await tester.runAsync(
        () => learning.setQuizHint(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
          visible: true,
        ),
      ))!;
      quiz = (await tester.runAsync(
        () => learning.setQuizHint(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
          visible: false,
        ),
      ))!;
      final hintAt = quiz.checkpoint.assistance.hintFirstShownAtUtcMs;
      harness.now = harness.now.add(const Duration(days: 1));
      await mount(tester, quiz);
      expect(find.text('noun'), findsNothing);
      await tester.tap(find.text(quiz.plan.questions.first.correctAnswer));
      await _until(tester, find.text('ถูกต้อง'));
      final attempt = (await tester.runAsync(
        () => harness.database
            .select(harness.database.answerAttempts)
            .getSingle(),
      ))!;
      final context = jsonDecode(attempt.evidenceContextJson) as Map;
      expect(attempt.responseTimeMs, isNull);
      expect(context['hintLevel'], 1);
      expect(attempt.evidenceClass, 'guidedPractice');
      final saved = (await tester.runAsync(
        () => learning.resumeQuiz(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
        ),
      ))!;
      expect(saved.checkpoint.assistance.hintFirstShownAtUtcMs, hintAt);
    },
  );

  testWidgets('pending receipt resumes and retry keeps its exact occurrence', (
    tester,
  ) async {
    var quiz = (await tester.runAsync(() => start()))!;
    quiz = (await tester.runAsync(
      () => learning.prepareQuizAnswer(
        sessionId: quiz.sessionId,
        expectedOwnerId: quiz.ownerId,
        expectedRevision: quiz.checkpointRevision,
        selectedOptionOrdinal: quiz.plan.questions.first.options.indexOf(
          quiz.plan.questions.first.correctAnswer,
        ),
        responseTimeMs: 750,
      ),
    ))!;
    final receipt = quiz.checkpoint.answer!;
    final expectedCommand = receipt.toCommand(sessionId: quiz.sessionId);
    harness.now = harness.now.add(const Duration(days: 1));
    await mount(tester, quiz);
    expect(find.text('ถูกต้อง'), findsNothing);
    expect(await tester.runAsync(() => harness.count('answer_attempts')), 0);
    await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
    await _until(tester, find.text('ถูกต้อง'));
    final attempt = (await tester.runAsync(
      () =>
          harness.database.select(harness.database.answerAttempts).getSingle(),
    ))!;
    expect(attempt.id, expectedCommand.id);
    expect(attempt.ownerId, expectedCommand.ownerId);
    expect(
      attempt.occurredAtUtcMs,
      expectedCommand.occurredAtUtc.millisecondsSinceEpoch,
    );
    expect(attempt.responseTimeMs, 750);
    expect(
      jsonDecode(attempt.evidenceContextJson),
      expectedCommand.evidenceContext.toJson(),
    );
    final before = await tester.runAsync(harness.snapshot);
    await mount(tester, quiz);
    await _until(tester, find.text('ถูกต้อง'));
    expect(await tester.runAsync(harness.snapshot), before);
  });

  testWidgets(
    'answered resume advances the existing cursor without another answer',
    (tester) async {
      var quiz = (await tester.runAsync(() => start(count: 2)))!;
      quiz = (await tester.runAsync(() => answer(quiz)))!;
      final firstAttempt = (await tester.runAsync(
        () => harness.database
            .select(harness.database.answerAttempts)
            .getSingle(),
      ))!;
      await mount(tester, quiz);
      await _until(tester, find.text('ถูกต้อง'));
      await tester.tap(find.text('คำถามถัดไป'));
      await _until(tester, find.text('คำถาม 2 จาก 2'));
      expect(find.text(quiz.plan.questions[1].word.spelling), findsOneWidget);
      final attempts = (await tester.runAsync(
        () => harness.database.select(harness.database.answerAttempts).get(),
      ))!;
      expect(attempts, hasLength(1));
      expect(attempts.single.toJson(), firstAttempt.toJson());
      final sessions = (await tester.runAsync(
        () => harness.database.select(harness.database.learningSessions).get(),
      ))!;
      expect(sessions, hasLength(1));
      expect(sessions.single.id, quiz.sessionId);
    },
  );

  testWidgets(
    'closing resume retains original time and callback failure still reaches score',
    (tester) async {
      var quiz = (await tester.runAsync(() => start()))!;
      quiz = (await tester.runAsync(() => answer(quiz)))!;
      quiz = (await tester.runAsync(
        () => learning.prepareQuizFinish(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
        ),
      ))!;
      final endedAt = quiz.checkpoint.close!.endedAtUtcMs;
      harness.now = harness.now.add(const Duration(days: 3));
      var callbackCount = 0;
      ConfiguredQuizFinishResult? callbackResult;
      Map<String, Object?>? rowDuringCallback;
      var scoreVisibleDuringCallback = false;
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            learning: freshLearning(),
            resumeSessionId: quiz.sessionId,
            expectedOwnerId: quiz.ownerId,
            onCanonicalFinished: (result) async {
              callbackCount++;
              callbackResult = result;
              scoreVisibleDuringCallback = find
                  .byType(ScoreScreen)
                  .evaluate()
                  .isNotEmpty;
              rowDuringCallback = await harness.session(quiz.sessionId);
              throw StateError('synthetic optional study offer failure');
            },
          ),
        ),
      );
      await _until(tester, find.text('คำตอบครบแล้ว พร้อมบันทึกผลรอบนี้'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _until(tester, find.byType(ScoreScreen));
      expect(find.text('100%'), findsOneWidget);
      expect(callbackCount, 1);
      expect(callbackResult!.state.checkpoint, isA<CompletedQuizSession>());
      expect(callbackResult!.state.endedAtUtc!.millisecondsSinceEpoch, endedAt);
      expect(scoreVisibleDuringCallback, isFalse);
      expect(rowDuringCallback!['state'], 'completed');
      expect(
        jsonDecode(rowDuringCallback!['checkpoint_json']! as String)['phase'],
        'completed',
      );
      final row = (await tester.runAsync(
        () => harness.session(quiz.sessionId),
      ))!;
      expect(row['ended_at_utc_ms'], endedAt);
      expect(
        await tester.runAsync(() => harness.count('learning_sessions')),
        1,
      );
      expect(await tester.runAsync(() => harness.count('answer_attempts')), 1);
      expect(
        await tester.runAsync(() => harness.count('reward_transactions')),
        1,
      );
    },
  );

  testWidgets(
    'completed resume keeps canonical mistakes and existing reward facts',
    (tester) async {
      var quiz = (await tester.runAsync(() => start()))!;
      quiz = (await tester.runAsync(() => answer(quiz, reveal: true)))!;
      quiz = (await tester.runAsync(
        () => learning.prepareQuizFinish(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
        ),
      ))!;
      final result = (await tester.runAsync(
        () => learning.finishConfiguredQuiz(
          sessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
          expectedRevision: quiz.checkpointRevision,
        ),
      ))!;
      final before = await tester.runAsync(harness.snapshot);
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            learning: freshLearning(),
            resumeSessionId: quiz.sessionId,
            expectedOwnerId: quiz.ownerId,
          ),
        ),
      );
      await _until(tester, find.text('บันทึกผลรอบนี้แล้ว'));
      await tester.tap(find.text('ดูผลการเรียน'));
      await _until(tester, find.byType(ScoreScreen));
      expect(find.text('ฝึกคำที่ผิด (1)'), findsOneWidget);
      expect(
        result.state.mistakeWords.single.id,
        quiz.plan.questions.first.word.id,
      );
      expect(await tester.runAsync(harness.snapshot), before);
    },
  );

  testWidgets(
    'content drift denies exact resume without creating a replacement',
    (tester) async {
      final quiz = (await tester.runAsync(() => start()))!;
      await tester.runAsync(
        () => harness.database.customStatement(
          'UPDATE vocabulary_words SET meaning = ?, local_revision = local_revision + 1 WHERE id = ?',
          ['Changed synthetic meaning', quiz.plan.questions.first.word.id],
        ),
      );
      final before = await tester.runAsync(harness.snapshot);
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(
            learning: freshLearning(),
            resumeSessionId: quiz.sessionId,
            expectedOwnerId: quiz.ownerId,
          ),
        ),
      );
      await _until(tester, find.textContaining('เปิดแบบทดสอบไม่สำเร็จ'));
      expect(find.text(quiz.plan.questions.first.word.spelling), findsNothing);
      expect(await tester.runAsync(harness.snapshot), before);
    },
  );

  testWidgets('unavailable old-owner resume never starts a new session', (
    tester,
  ) async {
    final quiz = (await tester.runAsync(() => start()))!;
    await tester.runAsync(() => harness.switchOwner(configuredOtherOwnerId));
    final before = await tester.runAsync(harness.snapshot);
    await tester.pumpWidget(
      MaterialApp(
        home: QuizScreen(
          learning: freshLearning(),
          resumeSessionId: quiz.sessionId,
          expectedOwnerId: quiz.ownerId,
        ),
      ),
    );
    await _until(tester, find.text('บัญชีเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'));
    expect(find.text(quiz.plan.questions.first.word.spelling), findsNothing);
    expect(find.text('ลองอีกครั้ง'), findsNothing);
    expect(await tester.runAsync(harness.snapshot), before);
  });
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
