import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late LearningUseCases useCases;

  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    useCases = _useCases(h);
  });
  tearDown(() => h.close());

  for (final activity in ['shadowing', 'srsReview', 'pronunciation']) {
    test(
      '$activity keeps ordinary capture without a configured quiz plan',
      () async {
        await h.database.customStatement(
          'INSERT INTO learning_sessions '
          '(id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, app_version, build_id) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'synthetic-unchanged-prior-session',
            configuredOtherOwnerId,
            'srsReview',
            'completed',
            configuredStart
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
            configuredStart
                .subtract(const Duration(hours: 12))
                .millisecondsSinceEpoch,
            'synthetic-previous-build',
            'synthetic-previous-build',
          ],
        );
        final prior = await h.session('synthetic-unchanged-prior-session');
        QuizSession? session;
        SrsReviewSession? review;
        final String promptMode;
        switch (activity) {
          case 'shadowing':
            session = await useCases.startShadowing(limit: 1);
            promptMode = 'shadowing';
          case 'srsReview':
            final prepared = await useCases.prepareSrsReview(
              expectedOwnerId: configuredOwnerId,
              sourceWordIds: configuredWordIds.take(1),
              limit: 1,
              stillCurrent: () => true,
            );
            review = await useCases.startSrsReview(
              prepared!,
              stillCurrent: () => true,
            );
            promptMode = 'srsRecall';
          case 'pronunciation':
            session = await useCases.startSourcePronunciationForWords(
              wordIds: configuredWordIds.take(1),
              limit: 1,
            );
            promptMode = 'pronunciationTranscript';
          default:
            throw StateError('unreachable synthetic activity');
        }
        final sessionId = review?.id ?? session!.id;
        final created = await h.session(sessionId);
        expect(created['activity_type'], activity);
        expect(created['accepted_plan_id'], isNull);
        expect(created['accepted_plan_json'], isNull);
        expect(created['checkpoint_revision'], 0);
        expect(created['checkpoint_json'], isNull);
        h.now = h.now.add(const Duration(seconds: 3));
        final word = review?.words.single ?? session!.questions.single.word;
        final recorded = review != null
            ? await useCases.commitSrsRating(
                useCases.prepareSrsRating(
                  review: review,
                  cardIndex: 0,
                  recalled: true,
                  responseTimeMs: 3000,
                ),
                stillCurrent: () => true,
              )
            : await useCases.recordAnswer(
                sessionId: sessionId,
                wordId: word.id,
                promptMode: promptMode,
                isCorrect: true,
                responseTimeMs: 3000,
                attemptNumber: 1,
                attemptId: 'synthetic-legacy-$activity-answer',
                occurredAtUtc: h.now,
                evidenceContext: captureCurrentActivityEvidence(
                  promptMode: promptMode,
                  contentRevision: word.contentRevision,
                ),
              );
        h.now = h.now.add(const Duration(seconds: 1));
        final summary = review != null
            ? await useCases.finishSrsReview(
                useCases.prepareSrsFinish(review),
                stillCurrent: () => true,
              )
            : await useCases.finishSession(sessionId);
        final completed = await h.session(sessionId);
        expect(recorded.inserted, isTrue);
        expect(summary.state, 'completed');
        expect(summary.correctCount, 1);
        expect(completed['accepted_plan_json'], isNull);
        expect(completed['checkpoint_revision'], 0);
        expect(completed['checkpoint_json'], isNull);
        expect(await h.session('synthetic-unchanged-prior-session'), prior);
        expect(await h.count('answer_attempts'), 1);
        expect(await h.count('srs_states'), 1);
        expect(await h.count('points_ledger_entries'), 1);
        expect((await h.researchCounts()).values, everyElement(0));
      },
    );
  }

  for (final activity in ['quiz', 'weaknessPractice', 'sourcePractice']) {
    test(
      'the $activity QuizScreen entry creates its actual activity and meaning-quiz plan',
      () async {
        final QuizSession session;
        switch (activity) {
          case 'quiz':
            session = await useCases.startQuiz(
              categoryId: configuredCategoryId,
              limit: 2,
            );
          case 'weaknessPractice':
            session = await useCases.startWeaknessPractice(
              wordIds: configuredWordIds.take(2),
              limit: 2,
            );
          case 'sourcePractice':
            session = await useCases.startSourcePracticeForWords(
              wordIds: configuredWordIds.take(2),
              limit: 2,
            );
          default:
            throw StateError('unreachable synthetic activity');
        }

        final row = await h.session(session.id);
        final plan = AcceptedQuizPlan.parse(
          id: row['accepted_plan_id']! as String,
          json: row['accepted_plan_json']! as String,
        );
        expect(row['activity_type'], activity);
        expect(plan.activityType, activity);
        expect(plan.mode, 'meaning-quiz');
        expect(
          plan.questions.map((question) => question.word.id),
          configuredWordIds.take(2),
        );
        expect(row['checkpoint_revision'], 1);
        expect(await h.count('learning_sessions'), 1);
        expect(await h.count('outbox_operations'), 0);
        expect((await h.researchCounts()).values, everyElement(0));
      },
    );
  }

  test(
    'stable launch retry reuses the first stored options after live pool changes',
    () async {
      final launch = await useCases.prepareConfiguredQuiz(
        expectedOwnerId: configuredOwnerId,
        configuration: QuizConfiguration.sourcePractice(
          wordIds: configuredWordIds.take(2),
          limit: 2,
        ),
      );
      final first = await useCases.startConfiguredQuiz(launch);
      await h.addWord(
        id: 'synthetic-new-pool-word',
        spelling: 'addition',
        meaning: 'a changed option pool',
      );
      h.now = h.now.add(const Duration(hours: 2));

      final replay = await useCases.startConfiguredQuiz(launch);

      expect(replay.sessionId, first.sessionId);
      expect(replay.startedAtUtc, first.startedAtUtc);
      expect(replay.plan.stableSerialization, first.plan.stableSerialization);
      expect(await h.count('learning_sessions'), 1);
      expect(await h.count('outbox_operations'), 0);
    },
  );

  test(
    'configured calls cannot fall back to a legacy-only repository',
    () async {
      final legacy = _LegacyOnlyRepository(_repository(h));
      useCases = _useCases(h, repository: legacy);
      final before = await h.snapshot();

      await expectLater(
        useCases.startQuiz(categoryId: configuredCategoryId, limit: 1),
        throwsStateError,
      );

      expect(await h.snapshot(), before);
    },
  );

  test(
    'pending answer retry preserves its first ID time selection and exact context',
    () async {
      final first = await _start(useCases);
      h.now = h.now.add(const Duration(seconds: 3));
      final selected = first.plan.questions.first.options.indexOf(
        first.plan.questions.first.correctAnswer,
      );
      final pending = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        selectedOptionOrdinal: selected,
        responseTimeMs: 3000,
      );
      final bytes = (await h.session(first.sessionId))['checkpoint_json'];
      h.now = h.now.add(const Duration(days: 1));

      final replay = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        selectedOptionOrdinal: selected,
        responseTimeMs: 900000,
      );

      expect(replay.checkpointRevision, pending.checkpointRevision);
      expect((await h.session(first.sessionId))['checkpoint_json'], bytes);
      expect(
        replay.checkpoint.answer!.attemptId,
        pending.checkpoint.answer!.attemptId,
      );
      expect(
        replay.checkpoint.answer!.occurredAtUtcMs,
        configuredStart.add(const Duration(seconds: 3)).millisecondsSinceEpoch,
      );
      expect(replay.checkpoint.answer!.responseTimeMs, 3000);
      expect(replay.checkpoint.answer!.selectedOptionOrdinal, selected);
      expect(
        replay.checkpoint.answer!.evidenceContext.toJson(),
        pending.checkpoint.answer!.evidenceContext.toJson(),
      );
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test(
    'a delayed first-question command cannot acknowledge the next pending answer',
    () async {
      final first = await _start(useCases, limit: 2);
      final firstPending = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        selectedOptionOrdinal: 0,
        responseTimeMs: 100,
      );
      final firstCommitted = await useCases.commitQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: firstPending.checkpointRevision,
      );
      final next = await useCases.advanceQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: firstCommitted.state.checkpointRevision,
      );
      final nextPending = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: next.checkpointRevision,
        selectedOptionOrdinal: 0,
        responseTimeMs: 200,
      );
      final before = await h.snapshot();
      await expectLater(
        useCases.prepareQuizAnswer(
          sessionId: first.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: first.checkpointRevision,
          selectedOptionOrdinal: 0,
          responseTimeMs: 300,
        ),
        throwsStateError,
      );
      expect(nextPending.checkpoint.answer!.wordId, configuredWordIds[1]);
      expect(await h.snapshot(), before);
      expect(await h.count('answer_attempts'), 1);
    },
  );

  test('a changed selection cannot replace the first pending answer', () async {
    final first = await _start(useCases, limit: 2);
    final pending = await useCases.prepareQuizAnswer(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: first.checkpointRevision,
      selectedOptionOrdinal: 0,
      responseTimeMs: 100,
    );
    final before = await h.snapshot();

    await expectLater(
      useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        selectedOptionOrdinal: 1,
        responseTimeMs: 200,
      ),
      throwsA(anything),
    );

    expect(pending.checkpoint, isA<PendingQuizAnswer>());
    expect(await h.snapshot(), before);
  });

  test(
    'hiding a durable hint cannot erase assisted evidence after resume',
    () async {
      final first = await _start(useCases);
      h.now = h.now.add(const Duration(seconds: 1));
      final hinted = await useCases.setQuizHint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        visible: true,
      );
      final firstHintTime = hinted.checkpoint.assistance.hintFirstShownAtUtcMs;
      h.now = h.now.add(const Duration(minutes: 1));
      final hintReplay = await useCases.setQuizHint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        visible: true,
      );
      expect(hintReplay.checkpointRevision, hinted.checkpointRevision);
      expect(
        hintReplay.checkpoint.assistance.hintFirstShownAtUtcMs,
        firstHintTime,
      );
      final hidden = await useCases.setQuizHint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: hinted.checkpointRevision,
        visible: false,
      );
      useCases = _useCases(h);
      final resumed = await useCases.resumeQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
      );
      final pending = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: resumed.checkpointRevision,
        selectedOptionOrdinal: 0,
        responseTimeMs: 100,
      );

      expect(hidden.checkpoint.assistance.hintVisible, isFalse);
      expect(
        firstHintTime,
        configuredStart.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      );
      expect(
        resumed.checkpoint.assistance.hintFirstShownAtUtcMs,
        firstHintTime,
      );
      expect(pending.checkpoint.answer!.evidenceContext.hintLevel, 1);
      expect(
        pending.checkpoint.answer!.evidenceContext.evidenceClass.name,
        'guidedPractice',
      );
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test('a failed durable hint write returns no assisted state', () async {
    final first = await _start(useCases);
    final before = await h.snapshot();
    await h.database.customStatement(
      'CREATE TEMP TRIGGER synthetic_hint_failure '
      'BEFORE UPDATE OF checkpoint_json ON learning_sessions '
      "BEGIN SELECT RAISE(ABORT, 'synthetic hint persistence failure'); END",
    );

    await expectLater(
      useCases.setQuizHint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        visible: true,
      ),
      throwsA(anything),
    );

    expect(await h.snapshot(), before);
    final stored =
        jsonDecode(
              (await h.session(first.sessionId))['checkpoint_json']! as String,
            )
            as Map<String, dynamic>;
    expect(
      (stored['assistance'] as Map<String, dynamic>)['hintFirstShownAtUtcMs'],
      isNull,
    );
  });

  test(
    'reveal is durable before the canonical wrong answer is recorded',
    () async {
      final first = await _start(useCases);
      h.now = h.now.add(const Duration(seconds: 2));

      final pending = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        revealed: true,
        responseTimeMs: 2000,
      );

      expect(pending.checkpoint.answer!.selectedOptionOrdinal, isNull);
      expect(pending.checkpoint.answer!.revealed, isTrue);
      expect(pending.checkpoint.answer!.isCorrect, isFalse);
      expect(pending.checkpoint.answer!.evidenceContext.hintLevel, 2);
      expect(
        pending.checkpoint.assistance.revealRequestedAtUtcMs,
        configuredStart.add(const Duration(seconds: 2)).millisecondsSinceEpoch,
      );
      expect(await h.count('answer_attempts'), 0);
      final committed = await useCases.commitQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      final row = await h.session(first.sessionId);
      expect(committed.record.inserted, isTrue);
      expect(row['correct_count'], 0);
      expect(row['wrong_count'], 1);
    },
  );

  for (final restore in ['explicit resume', 'new use case instance']) {
    test('$restore does not invent continuous response latency', () async {
      final first = await _start(useCases);
      h.now = h.now.add(const Duration(days: 1));
      if (restore == 'explicit resume') {
        await useCases.resumeQuiz(
          sessionId: first.sessionId,
          expectedOwnerId: configuredOwnerId,
        );
      } else {
        useCases = _useCases(h);
      }

      final pending = await useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        selectedOptionOrdinal: 0,
        responseTimeMs: 500,
      );

      expect(pending.checkpoint.answer!.responseTimeMs, isNull);
    });
  }

  test(
    'a freshly advanced next question measures live latency after resume',
    () async {
      final first = await _start(useCases, limit: 2);
      await useCases.resumeQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
      );
      final answered = await _answerCurrent(useCases, first);
      final next = await useCases.advanceQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: answered.checkpointRevision,
      );

      final pending = await useCases.prepareQuizAnswer(
        sessionId: next.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: next.checkpointRevision,
        selectedOptionOrdinal: 0,
        responseTimeMs: 750,
      );

      expect(next.checkpoint.questionOrdinal, 1);
      expect(pending.checkpoint.answer!.responseTimeMs, 750);
    },
  );

  test(
    'finish retry retains its first close time and canonical reward effects',
    () async {
      final first = await _start(useCases);
      final answered = await _answerCurrent(useCases, first);
      h.now = configuredStart.add(const Duration(minutes: 2));
      final closing = await useCases.prepareQuizFinish(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: answered.checkpointRevision,
      );
      h.now = h.now.add(const Duration(days: 1));
      final preparedReplay = await useCases.prepareQuizFinish(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: answered.checkpointRevision,
      );
      final firstFinish = await useCases.finishConfiguredQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: closing.checkpointRevision,
      );
      final afterFirst = await h.snapshot();

      final replay = await useCases.finishConfiguredQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: closing.checkpointRevision,
      );

      expect(
        preparedReplay.checkpoint.close!.endedAtUtcMs,
        closing.checkpoint.close!.endedAtUtcMs,
      );
      expect(
        firstFinish.state.endedAtUtc,
        configuredStart.add(const Duration(minutes: 2)),
      );
      expect(replay.state.endedAtUtc, firstFinish.state.endedAtUtc);
      expect(replay.summary.score, 100);
      expect(await h.snapshot(), afterFirst);
      expect(await h.count('answer_attempts'), 1);
      expect(await h.count('points_ledger_entries'), 1);
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'failed finish ACK rolls back completion and its achievement outbox',
    () async {
      final first = await _start(useCases);
      final answered = await _answerCurrent(useCases, first);
      h.now = configuredStart.add(const Duration(minutes: 2));
      final closing = await useCases.prepareQuizFinish(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: answered.checkpointRevision,
      );
      final before = await h.snapshot();
      await h.database.customStatement(
        'CREATE TEMP TRIGGER synthetic_finish_ack_failure '
        'BEFORE UPDATE OF checkpoint_json ON learning_sessions '
        "BEGIN SELECT RAISE(ABORT, 'synthetic finish ACK failure'); END",
      );
      await expectLater(
        useCases.finishConfiguredQuiz(
          sessionId: first.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: closing.checkpointRevision,
        ),
        throwsA(anything),
      );
      expect(await h.snapshot(), before);
      expect((await h.session(first.sessionId))['state'], 'active');
      await h.database.customStatement(
        'DROP TRIGGER synthetic_finish_ack_failure',
      );
      final done = await useCases.finishConfiguredQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: closing.checkpointRevision,
      );
      expect(done.state.state, 'completed');
      expect(
        done.state.endedAtUtc,
        configuredStart.add(const Duration(minutes: 2)),
      );
    },
  );

  test('abandon remains terminal across resume and retries', () async {
    final first = await _start(useCases);
    h.now = configuredStart.add(const Duration(minutes: 2));
    final abandoned = await useCases.abandonQuiz(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: first.checkpointRevision,
    );
    h.now = h.now.add(const Duration(days: 1));
    final before = await h.snapshot();
    final resumed = await useCases.resumeQuiz(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
    );
    final replay = await useCases.abandonQuiz(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: first.checkpointRevision,
    );
    await expectLater(
      useCases.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: abandoned.checkpointRevision,
        selectedOptionOrdinal: 0,
      ),
      throwsA(anything),
    );
    await expectLater(
      useCases.finishConfiguredQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: abandoned.checkpointRevision,
      ),
      throwsA(anything),
    );
    expect(resumed.state, 'abandoned');
    expect(replay.endedAtUtc, configuredStart.add(const Duration(minutes: 2)));
    expect(await h.snapshot(), before);
    expect(await h.count('learning_sessions'), 1);
    expect(await h.count('answer_attempts'), 0);
  });

  test('an already committed answer does not repeat secondary hooks', () async {
    var questCalls = 0;
    var streakCalls = 0;
    useCases = _useCases(
      h,
      questEventSink: (_) async {
        questCalls++;
      },
      streakEventSink: () async {
        streakCalls++;
      },
    );
    final first = await _start(useCases);
    final pending = await useCases.prepareQuizAnswer(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: first.checkpointRevision,
      selectedOptionOrdinal: 0,
      responseTimeMs: 100,
    );

    await useCases.commitQuizAnswer(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: pending.checkpointRevision,
    );
    final before = await h.snapshot();
    final replay = await useCases.commitQuizAnswer(
      sessionId: first.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: pending.checkpointRevision,
    );

    expect(replay.record.inserted, isFalse);
    expect(questCalls, 1);
    expect(streakCalls, 1);
    expect(await h.snapshot(), before);
  });
}

DriftLearningRepository _repository(ConfiguredQuizHarness h) =>
    DriftLearningRepository(h.database, ownerWrites: h.ownerWrites);

LearningUseCases _useCases(
  ConfiguredQuizHarness h, {
  LearningRepository? repository,
  QuestEventSink? questEventSink,
  StreakEventSink? streakEventSink,
}) {
  var sequence = 0;
  return LearningUseCases(
    owners: h.owners,
    repository: repository ?? _repository(h),
    generateId: () => 'synthetic-configured-${++sequence}',
    nowUtc: () => h.now,
    buildInfo: const AppBuildInfo(
      version: 'synthetic-v1',
      buildId: 'synthetic-build-1',
    ),
    eventAdapter: const EventV1ToV2Adapter(
      appVersion: 'synthetic-v1',
      buildId: 'synthetic-build-1',
    ),
    questEventSink: questEventSink,
    streakEventSink: streakEventSink,
  );
}

Future<ConfiguredQuizState> _start(
  LearningUseCases useCases, {
  int limit = 1,
}) async => useCases.startConfiguredQuiz(
  await useCases.prepareConfiguredQuiz(
    expectedOwnerId: configuredOwnerId,
    configuration: QuizConfiguration.category(
      categoryId: configuredCategoryId,
      limit: limit,
    ),
  ),
);

Future<ConfiguredQuizState> _answerCurrent(
  LearningUseCases useCases,
  ConfiguredQuizState state,
) async {
  final question = state.plan.questions[state.checkpoint.questionOrdinal];
  final pending = await useCases.prepareQuizAnswer(
    sessionId: state.sessionId,
    expectedOwnerId: configuredOwnerId,
    expectedRevision: state.checkpointRevision,
    selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
    responseTimeMs: 100,
  );
  return (await useCases.commitQuizAnswer(
    sessionId: state.sessionId,
    expectedOwnerId: configuredOwnerId,
    expectedRevision: pending.checkpointRevision,
  )).state;
}

final class _LegacyOnlyRepository implements LearningRepository {
  _LegacyOnlyRepository(this.delegate);
  final LearningRepository delegate;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      delegate.recordAnswer(command);

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);
}
