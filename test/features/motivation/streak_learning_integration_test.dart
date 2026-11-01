import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_learning_day_recorder.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late LearningUseCases learning;
  late StreakUseCases streak;
  var nextId = 0;
  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    nextId = 0;
    learning = LearningUseCases(
      owners: h.owners,
      repository: DriftLearningRepository(
        h.database,
        ownerWrites: h.ownerWrites,
      ),
      generateId: () => 'synthetic-learning-${++nextId}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-1',
        buildId: 'synthetic-streak',
      ),
    );
    streak = StreakUseCases(
      repository: DriftStreakRepository(
        h.database,
        ownerWrites: h.ownerWrites,
        nowUtc: () => h.now,
      ),
      nowUtc: () => h.now,
    );
  });
  tearDown(() => h.close());

  test('canonical answer captures its day with no optional callback', () async {
    final session = await learning.startQuiz(limit: 3);
    await _answerQuiz(learning, session, correct: true, responseTimeMs: 300);
    final row = await h.database.select(h.database.learningDayLog).getSingle();
    final answer = await h.database
        .select(h.database.answerAttempts)
        .getSingle();
    expect(row.sourceAttemptId, answer.id);
    expect(row.firstSessionAtUtcMs, answer.occurredAtUtcMs);
    expect(row.policyVersion, 1);
    expect(row.timezoneId, 'UTC');
    expect((await streak.getCurrentStreak()).currentStreakDays, 1);
    expect((await h.researchCounts()).values, everyElement(0));
  });

  test(
    'incorrect answers still acknowledge one genuine learning day',
    () async {
      final session = await learning.startQuiz(limit: 3);
      await _answerQuiz(learning, session, correct: false, responseTimeMs: 500);
      expect(
        await DriftStreakRepository(
          h.database,
        ).getLearningDays(configuredOwnerId, nowUtc: h.now),
        ['2026-10-29'],
      );
      expect((await streak.getCurrentStreak()).currentStreakDays, 1);
    },
  );

  test('second answer preserves the first day source receipt', () async {
    final session = await learning.startQuiz(limit: 3);
    await _answerQuiz(learning, session, correct: true, responseTimeMs: 300);
    final original = await h.database
        .select(h.database.learningDayLog)
        .getSingle();
    await _answerQuiz(learning, session, correct: false, responseTimeMs: 400);
    expect(
      (await h.database.select(h.database.learningDayLog).getSingle()).toJson(),
      original.toJson(),
    );
    expect((await streak.getCurrentStreak()).currentStreakDays, 1);
  });

  test(
    'an interrupted day insert rolls back the canonical answer too',
    () async {
      final session = await learning.startQuiz(limit: 3);
      final before = await h.snapshot();
      await expectLater(
        h.database.runWithInterceptor(
          () => _answerQuiz(
            learning,
            session,
            correct: true,
            responseTimeMs: 300,
          ),
          interceptor: _FailDayReceipt(),
        ),
        throwsA(anything),
      );
      final after = await h.snapshot();
      expect(await h.count('answer_attempts'), 0);
      expect(await h.count('learning_day_log'), 0);
      for (final table in [
        'points_ledger_entries',
        'srs_states',
        'events_v2',
        'outbox_operations',
      ]) {
        expect(after[table], before[table], reason: table);
      }
    },
  );

  test('day receipt helper rejects an ambient-free write', () async {
    final before = await h.snapshot();
    await expectLater(
      DriftLearningDayRecorder(
        h.database,
        ownerWrites: h.ownerWrites,
      ).recordAnswer('synthetic-not-issued'),
      throwsA(isA<StateError>()),
    );
    expect(await h.snapshot(), before);
  });
}

final class _FailDayReceipt extends QueryInterceptor {
  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.toLowerCase().contains('learning_day_log')) {
      throw StateError('synthetic day receipt failure');
    }
    return executor.runInsert(statement, args);
  }
}

Future<void> _answerQuiz(
  LearningUseCases learning,
  QuizSession session, {
  required bool correct,
  required int responseTimeMs,
}) async {
  var state = await learning.resumeQuiz(
    sessionId: session.id,
    expectedOwnerId: session.configured!.ownerId,
  );
  if (state.checkpoint is AnsweredQuizQuestion) {
    state = await learning.advanceQuiz(
      sessionId: state.sessionId,
      expectedOwnerId: state.ownerId,
      expectedRevision: state.checkpointRevision,
    );
  }
  final question = state.plan.questions[state.checkpoint.questionOrdinal];
  final ordinal = question.options.indexWhere(
    (option) => (option == question.correctAnswer) == correct,
  );
  final pending = await learning.prepareQuizAnswer(
    sessionId: state.sessionId,
    expectedOwnerId: state.ownerId,
    expectedRevision: state.checkpointRevision,
    selectedOptionOrdinal: ordinal,
    responseTimeMs: responseTimeMs,
  );
  await learning.commitQuizAnswer(
    sessionId: state.sessionId,
    expectedOwnerId: state.ownerId,
    expectedRevision: pending.checkpointRevision,
  );
}
