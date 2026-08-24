import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  test(
    'moves planned active paused active completed through legal transitions',
    () async {
      final fixture = await _fixture();
      expect(fixture.controller.state.status, LessonSessionStatus.planned);

      await fixture.controller.start(fixture.startCommand);
      expect(fixture.controller.state.status, LessonSessionStatus.active);

      await fixture.controller.pause(
        fixture.now.add(const Duration(seconds: 1)),
      );
      expect(fixture.controller.state.status, LessonSessionStatus.paused);

      await fixture.controller.resume(
        fixture.now.add(const Duration(seconds: 2)),
      );
      expect(fixture.controller.state.status, LessonSessionStatus.active);

      await fixture.controller.complete(
        fixture.now.add(const Duration(seconds: 3)),
      );
      expect(fixture.controller.state.status, LessonSessionStatus.completed);
      expect(fixture.repository.finishCalls, 1);
    },
  );

  test(
    'abandons planned, active, and paused sessions without an alternate writer',
    () async {
      for (final startingStatus in <LessonSessionStatus>[
        LessonSessionStatus.planned,
        LessonSessionStatus.active,
        LessonSessionStatus.paused,
      ]) {
        final fixture = await _fixture();
        if (startingStatus != LessonSessionStatus.planned) {
          await fixture.controller.start(fixture.startCommand);
        }
        if (startingStatus == LessonSessionStatus.paused) {
          await fixture.controller.pause(
            fixture.now.add(const Duration(seconds: 1)),
          );
        }

        await fixture.controller.abandon(
          fixture.now.add(const Duration(seconds: 2)),
        );

        expect(fixture.controller.state.status, LessonSessionStatus.abandoned);
        expect(
          fixture.repository.scopedAbandonCalls,
          startingStatus == LessonSessionStatus.planned ? 0 : 1,
        );
        expect(fixture.repository.bulkAbandonCalls, 0);
        await fixture.database.close();
      }
    },
  );

  test('abandon durably targets only the controller session', () async {
    final fixture = await _fixture();
    await fixture.controller.start(fixture.startCommand);
    final ownerId =
        (await fixture.database
                .select(fixture.database.localOwners)
                .getSingle())
            .id;
    await fixture.repository.startSession(
      LearningSessionDraft(
        id: 'session:recoverable-peer',
        ownerId: ownerId,
        activityType: 'quiz',
        startedAtUtc: fixture.now.add(const Duration(seconds: 1)),
        appVersion: 'test',
        buildId: 'f05-test',
      ),
    );
    final abandonedAt = fixture.now.add(const Duration(seconds: 2));

    await fixture.controller.abandon(abandonedAt);

    final sessions = {
      for (final row
          in await fixture.database
              .select(fixture.database.learningSessions)
              .get())
        row.id: row,
    };
    expect(sessions[fixture.startCommand.sessionId]!.state, 'abandoned');
    expect(
      sessions[fixture.startCommand.sessionId]!.endedAtUtcMs,
      abandonedAt.millisecondsSinceEpoch,
    );
    expect(sessions['session:recoverable-peer']!.state, 'active');
    expect(sessions['session:recoverable-peer']!.endedAtUtcMs, isNull);
    expect(fixture.repository.scopedAbandonCalls, 1);
    expect(fixture.repository.bulkAbandonCalls, 0);
  });

  test('rejects illegal transitions and submissions while paused', () async {
    final fixture = await _fixture();
    await expectLater(fixture.controller.pause(fixture.now), throwsStateError);
    await fixture.controller.start(fixture.startCommand);
    await expectLater(
      fixture.controller.start(fixture.startCommand),
      throwsStateError,
    );
    await expectLater(fixture.controller.resume(fixture.now), throwsStateError);
    await fixture.controller.pause(fixture.now);
    await expectLater(
      fixture.controller.submit(fixture.submission()),
      throwsStateError,
    );
    await fixture.controller.abandon(fixture.now);
    await expectLater(
      fixture.controller.complete(fixture.now),
      throwsStateError,
    );
  });

  test(
    'deduplicates concurrent and committed submissions by frozen identity',
    () async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      final submission = fixture.submission();

      final first = fixture.controller.submit(submission);
      final duplicate = fixture.controller.submit(submission);
      final results = await Future.wait(<Future<AnswerRecordResult>>[
        first,
        duplicate,
      ]);
      final replay = await fixture.controller.submit(submission);

      expect(results.every((result) => result.inserted), isTrue);
      expect(replay, same(results.first));
      expect(fixture.repository.recordCalls, 1);
      expect(fixture.adapter.classifyCalls, 1);
      expect(fixture.controller.state.committedResponseCount, 1);
    },
  );

  test(
    'retry after lost ACK reuses exact evidence identity and payload',
    () async {
      final fixture = await _fixture(failAfterFirstRecord: true);
      await fixture.controller.start(fixture.startCommand);
      final submission = fixture.submission(
        sourceEvidenceId: 'stable-evidence',
      );

      await expectLater(
        fixture.controller.submit(submission),
        throwsStateError,
      );
      expect(fixture.controller.state.committedResponseCount, 0);

      final retried = await fixture.controller.submit(submission);
      expect(retried.inserted, isFalse);
      expect(fixture.repository.recordCalls, 1);
      expect(fixture.repository.replayCalls, 2);
      expect(
        (await fixture.database.select(fixture.database.answerAttempts).get())
            .single
            .id,
        'stable-evidence',
      );

      final changed = fixture.submission(
        sourceEvidenceId: 'stable-evidence',
        isCorrect: false,
      );
      await expectLater(fixture.controller.submit(changed), throwsStateError);
    },
  );

  test('deduplicates completion and preserves one canonical close', () async {
    final fixture = await _fixture();
    await fixture.controller.start(fixture.startCommand);

    await Future.wait(<Future<void>>[
      fixture.controller.complete(fixture.now),
      fixture.controller.complete(fixture.now),
    ]);
    await fixture.controller.complete(fixture.now);

    expect(fixture.controller.state.status, LessonSessionStatus.completed);
    expect(fixture.repository.finishCalls, 1);
  });

  test(
    'accepted submit commits before queued completion closes the session',
    () async {
      final fixture = await _fixture(blockRecord: true);
      await fixture.controller.start(fixture.startCommand);

      final submit = fixture.controller.submit(fixture.submission());
      await fixture.repository.recordStarted.future;
      final complete = fixture.controller.complete(fixture.now);
      await Future<void>.delayed(Duration.zero);
      final finishCallsBeforeSubmitRelease = fixture.repository.finishCalls;

      fixture.repository.releaseRecord();
      await submit;
      await complete;

      expect(finishCallsBeforeSubmitRelease, 0);
      expect(fixture.repository.recordCalls, 1);
      expect(fixture.repository.finishCalls, 1);
      expect(fixture.controller.state.status, LessonSessionStatus.completed);
    },
  );

  test(
    'first accepted completion excludes competing abandon and pause',
    () async {
      final fixture = await _fixture(blockFinish: true);
      await fixture.controller.start(fixture.startCommand);

      final complete = fixture.controller.complete(fixture.now);
      await fixture.repository.finishStarted.future;
      final abandon = fixture.controller.abandon(fixture.now);
      final pause = fixture.controller.pause(fixture.now);
      final abandonExpectation = expectLater(abandon, throwsStateError);
      final pauseExpectation = expectLater(pause, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final stateBeforeFinishRelease = fixture.controller.state.status;
      final abandonCallsBeforeFinishRelease =
          fixture.repository.scopedAbandonCalls;

      fixture.repository.releaseFinish();
      await complete;
      await abandonExpectation;
      await pauseExpectation;

      expect(stateBeforeFinishRelease, LessonSessionStatus.active);
      expect(abandonCallsBeforeFinishRelease, 0);
      expect(fixture.repository.finishCalls, 1);
      expect(fixture.repository.scopedAbandonCalls, 0);
      expect(fixture.repository.bulkAbandonCalls, 0);
      expect(fixture.controller.state.status, LessonSessionStatus.completed);
    },
  );

  test(
    'pause accepted after submit waits for that durable submission',
    () async {
      final fixture = await _fixture(blockRecord: true);
      await fixture.controller.start(fixture.startCommand);

      final submit = fixture.controller.submit(fixture.submission());
      await fixture.repository.recordStarted.future;
      var pauseSettled = false;
      final pause = fixture.controller
          .pause(fixture.now)
          .whenComplete(() => pauseSettled = true);
      await Future<void>.delayed(Duration.zero);
      final settledBeforeSubmitRelease = pauseSettled;

      fixture.repository.releaseRecord();
      await submit;
      await pause;

      expect(settledBeforeSubmitRelease, isFalse);
      expect(fixture.controller.state.status, LessonSessionStatus.paused);
    },
  );

  test(
    'dispose suppresses state notification but preserves an accepted durable write',
    () async {
      final fixture = await _fixture(blockRecord: true);
      await fixture.controller.start(fixture.startCommand);
      var notifications = 0;
      fixture.controller.addListener(() => notifications += 1);

      final submit = fixture.controller.submit(fixture.submission());
      await fixture.repository.recordStarted.future;
      fixture.controller.dispose();
      fixture.repository.releaseRecord();

      final result = await submit;
      final attempts = await fixture.database
          .select(fixture.database.answerAttempts)
          .get();

      expect(result.inserted, isTrue);
      expect(attempts, hasLength(1));
      expect(notifications, 0);
      expect(fixture.controller.state.committedResponseCount, 0);
    },
  );

  testWidgets('background lifecycle pauses one active lesson', (tester) async {
    final fixture = await _fixture();
    await fixture.controller.start(fixture.startCommand);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          nowUtc: () => fixture.now.add(const Duration(seconds: 5)),
          builder: (_) => const Text('lesson body'),
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(fixture.controller.state.status, LessonSessionStatus.paused);
    expect(find.text('lesson body'), findsOneWidget);
  });
}

final class _Fixture {
  const _Fixture({
    required this.database,
    required this.repository,
    required this.adapter,
    required this.controller,
    required this.startCommand,
    required this.now,
    required this.wordId,
  });

  final AppDatabase database;
  final _CountingRepository repository;
  final _Adapter adapter;
  final UnifiedLessonController controller;
  final LessonStartCommand startCommand;
  final DateTime now;
  final String wordId;

  LessonSubmission submission({
    String sourceEvidenceId = 'evidence-1',
    bool isCorrect = true,
  }) => LessonSubmission(
    response: LessonResponse(
      sourceEvidenceId: sourceEvidenceId,
      occurredAtUtc: now.add(const Duration(milliseconds: 400)),
      sessionId: startCommand.sessionId,
      wordId: wordId,
      promptMode: 'meaningChoice',
      isCorrect: isCorrect,
      responseTimeMs: 400,
      attemptNumber: 1,
    ),
    support: LessonSupport(
      evidenceContext: EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'legacy-meaning-quiz',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      ),
    ),
  );
}

Future<_Fixture> _fixture({
  bool failAfterFirstRecord = false,
  bool blockRecord = false,
  bool blockFinish = false,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final now = DateTime.utc(2026, 8, 24, 9);
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'lesson-owner',
    nowUtc: () => now,
  );
  final owner = await owners.getOrCreateActiveOwner();
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'lesson-category',
          ownerId: owner.id,
          name: 'Lesson',
          normalizedName: 'lesson',
          createdAtUtcMs: now.millisecondsSinceEpoch,
          updatedAtUtcMs: now.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'lesson-word',
          ownerId: owner.id,
          categoryId: 'lesson-category',
          spelling: 'lesson',
          normalizedSpelling: 'lesson',
          meaning: 'บทเรียน',
          normalizedMeaning: 'บทเรียน',
          partOfSpeech: 'noun',
          createdAtUtcMs: now.millisecondsSinceEpoch,
          updatedAtUtcMs: now.millisecondsSinceEpoch,
        ),
      );
  final repository = _CountingRepository(
    DriftLearningRepository(database),
    failAfterFirstRecord: failAfterFirstRecord,
    blockRecord: blockRecord,
    blockFinish: blockFinish,
  );
  var nextId = 0;
  final learning = LearningUseCases(
    owners: owners,
    repository: repository,
    generateId: () => 'lesson-${++nextId}',
    nowUtc: () => now,
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'f05-test'),
  );
  final quiz = await learning.startQuiz(limit: 1);
  final adapter = _Adapter();
  final controller = UnifiedLessonController(
    learning: learning,
    adapter: adapter,
  );
  return _Fixture(
    database: database,
    repository: repository,
    adapter: adapter,
    controller: controller,
    startCommand: LessonStartCommand(
      mode: LessonMode.meaningQuiz,
      sessionId: quiz.id,
      startedAtUtc: quiz.startedAtUtc!,
      itemCount: quiz.questions.length,
    ),
    now: now,
    wordId: quiz.questions.single.word.id,
  );
}

final class _Adapter implements LessonModeAdapter {
  int classifyCalls = 0;

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    classifyCalls += 1;
    return support.evidenceContext;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      LessonItem(id: 'item-${cursor.index}');
}

final class _CountingRepository
    implements
        LearningRepository,
        LearningEvidenceReplayRepository,
        LearningSessionLifecycleRepository {
  _CountingRepository(
    this.delegate, {
    required this.failAfterFirstRecord,
    required this.blockRecord,
    required this.blockFinish,
  });

  final DriftLearningRepository delegate;
  final bool failAfterFirstRecord;
  final bool blockRecord;
  final bool blockFinish;
  final Completer<void> recordStarted = Completer<void>();
  final Completer<void> finishStarted = Completer<void>();
  final Completer<void> _recordRelease = Completer<void>();
  final Completer<void> _finishRelease = Completer<void>();
  int recordCalls = 0;
  int replayCalls = 0;
  int finishCalls = 0;
  int scopedAbandonCalls = 0;
  int bulkAbandonCalls = 0;
  bool _lostAckSent = false;

  void releaseRecord() {
    if (!_recordRelease.isCompleted) _recordRelease.complete();
  }

  void releaseFinish() {
    if (!_finishRelease.isCompleted) _finishRelease.complete();
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) {
    replayCalls += 1;
    return delegate.replayCommittedAnswer(candidate);
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    recordCalls += 1;
    if (!recordStarted.isCompleted) recordStarted.complete();
    if (blockRecord) await _recordRelease.future;
    final result = await delegate.recordAnswer(command);
    if (failAfterFirstRecord && !_lostAckSent) {
      _lostAckSent = true;
      throw StateError('lost ACK');
    }
    return result;
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls += 1;
    if (!finishStarted.isCompleted) finishStarted.complete();
    if (blockFinish) await _finishRelease.future;
    return delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<void> abandonActiveSessions({required String ownerId}) {
    bulkAbandonCalls += 1;
    return delegate.abandonActiveSessions(ownerId: ownerId);
  }

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) {
    scopedAbandonCalls += 1;
    return delegate.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }

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
  Future<LearningSessionSummary?> getActiveSession({required String ownerId}) =>
      delegate.getActiveSession(ownerId: ownerId);

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) => delegate.listSessionHistory(ownerId: ownerId, limit: limit);

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
