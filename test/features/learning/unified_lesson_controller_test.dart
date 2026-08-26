import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/hint_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/hint_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/handwriting_scratchpad.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/review/application/learner_intent_use_cases.dart';
import 'package:vocab_learning_app/features/review/data/drift_content_quality_report_repository.dart';
import 'package:vocab_learning_app/features/review/data/drift_learner_intent_repository.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report_repository.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent_repository.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/focus_timer_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/focus_timer.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/features/time_tracking/presentation/focus_timer_widget.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../../support/inert_research_dependencies.dart';
import '../../support/test_quest_use_cases.dart';

void main() {
  test(
    'focus timer requires a capable adapter and the exact time authority',
    () async {
      final fixture = await _fixture();
      final activeTime = _activeTimeController(
        _MemoryLearningTimeRepository(),
        monotonicMicros: () => 0,
      );
      final otherTime = _activeTimeController(
        _MemoryLearningTimeRepository(),
        monotonicMicros: () => 0,
      );

      expect(
        () => UnifiedLessonController(
          learning: fixture.learning,
          adapter: _ActiveEffortAdapter(),
          activeLearningTime: activeTime,
          focusTimer: FocusTimerController(timeAuthority: activeTime),
          focusTimerFeature: Feature.quiz,
        ),
        throwsArgumentError,
      );
      expect(
        () => UnifiedLessonController(
          learning: fixture.learning,
          adapter: _FocusAdapter(),
          activeLearningTime: activeTime,
          focusTimer: FocusTimerController(timeAuthority: otherTime),
          focusTimerFeature: Feature.quiz,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'certified lesson lifecycle writes only monotonic active segments',
    () async {
      final timeRepository = _MemoryLearningTimeRepository();
      var monotonicMicros = 0;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => monotonicMicros,
      );
      final fixture = await _fixture(
        adapter: _ActiveEffortAdapter(),
        activeLearningTime: activeTime,
      );

      await fixture.controller.start(fixture.startCommand);
      monotonicMicros = const Duration(seconds: 12).inMicroseconds;
      await fixture.controller.pause(
        fixture.now.subtract(const Duration(seconds: 1)),
      );
      monotonicMicros += const Duration(seconds: 2).inMicroseconds;
      await fixture.controller.resume(
        fixture.now.add(const Duration(seconds: 1)),
      );
      monotonicMicros += const Duration(seconds: 8).inMicroseconds;
      await fixture.controller.complete(
        fixture.now.add(const Duration(seconds: 9)),
      );

      expect(timeRepository.segments, hasLength(2));
      expect(
        timeRepository.segments.first.activeDuration,
        const Duration(seconds: 12),
      );
      expect(
        timeRepository.segments.last.activeStartOffset,
        const Duration(seconds: 12),
      );
      expect(
        timeRepository.segments.last.activeDuration,
        const Duration(seconds: 8),
      );
    },
  );

  test(
    'non-certified and recreational adapters cannot receive the time writer',
    () async {
      final fixture = await _fixture();
      final activeTime = _activeTimeController(
        _MemoryLearningTimeRepository(),
        monotonicMicros: () => 0,
      );

      expect(
        () => UnifiedLessonController(
          learning: fixture.learning,
          adapter: _Adapter(),
          activeLearningTime: activeTime,
        ),
        throwsArgumentError,
      );
      expect(
        () => const LegacyLessonModeAdapter(LessonMode.meaningQuiz).classify(
          fixture
              .submission(evidenceClass: EvidenceClass.recreational)
              .response,
          fixture.submission(evidenceClass: EvidenceClass.recreational).support,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'time start failure remains isolated and the durable session is abandoned',
    () async {
      final timeRepository = _MemoryLearningTimeRepository()
        ..failActiveDuration = true;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => 0,
      );
      final fixture = await _fixture(
        adapter: _ActiveEffortAdapter(),
        activeLearningTime: activeTime,
      );

      await fixture.controller.start(fixture.startCommand);
      expect(fixture.controller.state.status, LessonSessionStatus.active);
      expect(fixture.controller.lastActiveLearningTimeFailure, isNotNull);
      fixture.controller.noteActiveLearningInteraction(
        fixture.now.add(const Duration(milliseconds: 500)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.controller.lastActiveLearningTimeFailure, isNotNull);
      await fixture.controller.abandon(
        fixture.now.add(const Duration(seconds: 1)),
      );

      final session =
          await (fixture.database.select(fixture.database.learningSessions)
                ..where((row) => row.id.equals(fixture.startCommand.sessionId)))
              .getSingle();
      expect(session.state, 'abandoned');
      expect(fixture.repository.scopedAbandonCalls, 1);
      expect(fixture.controller.lastActiveLearningTimeFailure, isNotNull);
    },
  );

  test('time append failure freezes completion until exact retry', () async {
    final timeRepository = _MemoryLearningTimeRepository();
    var monotonicMicros = 0;
    final activeTime = _activeTimeController(
      timeRepository,
      monotonicMicros: () => monotonicMicros,
    );
    final fixture = await _fixture(
      adapter: _ActiveEffortAdapter(),
      activeLearningTime: activeTime,
    );
    await fixture.controller.start(fixture.startCommand);
    monotonicMicros = const Duration(seconds: 5).inMicroseconds;
    timeRepository.failNextAppend = true;

    await expectLater(
      fixture.controller.complete(fixture.now.add(const Duration(seconds: 5))),
      throwsStateError,
    );

    expect(fixture.controller.state.status, LessonSessionStatus.active);
    expect(fixture.repository.finishCalls, 0);
    expect(fixture.controller.lastActiveLearningTimeFailure, isNotNull);
    expect(timeRepository.segments, isEmpty);

    monotonicMicros = const Duration(minutes: 1).inMicroseconds;
    await fixture.controller.complete(
      fixture.now.add(const Duration(minutes: 1)),
    );

    expect(fixture.controller.state.status, LessonSessionStatus.completed);
    expect(fixture.repository.finishCalls, 1);
    expect(fixture.controller.lastActiveLearningTimeFailure, isNull);
    expect(timeRepository.segments, hasLength(1));
    expect(
      timeRepository.segments.single.activeDuration,
      const Duration(seconds: 5),
    );
  });

  test(
    'route close exposes pre-write teardown retry and freezes its cutoff',
    () async {
      final timeRepository = _MemoryLearningTimeRepository();
      var monotonicMicros = 0;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => monotonicMicros,
      );
      final fixture = await _fixture(
        adapter: _ActiveEffortAdapter(),
        activeLearningTime: activeTime,
      );
      await fixture.controller.start(fixture.startCommand);
      var routeNow = fixture.now.add(const Duration(seconds: 5));
      var routeNowReads = 0;
      final route = UnifiedLessonRouteLifecycle(
        fixture.controller,
        fixture.learning,
        () {
          routeNowReads += 1;
          return routeNow;
        },
      );
      final close = fixture.learning.captureSessionClose(
        sessionId: fixture.startCommand.sessionId,
      );
      monotonicMicros = const Duration(seconds: 5).inMicroseconds;
      timeRepository.failNextAppend = true;

      await expectLater(route.complete(close), throwsStateError);

      expect(close.status, PendingLearningSessionCloseStatus.captured);
      expect(fixture.repository.finishCalls, 0);
      expect(fixture.controller.sessionCompletionRetryRequired, isTrue);
      expect(routeNowReads, 1);

      routeNow = fixture.now.add(const Duration(hours: 1));
      monotonicMicros = const Duration(hours: 1).inMicroseconds;
      await route.complete(close);

      expect(
        routeNowReads,
        1,
        reason: 'the accepted terminal cutoff is frozen',
      );
      expect(fixture.controller.sessionCompletionRetryRequired, isFalse);
      expect(fixture.repository.finishCalls, 1);
      expect(timeRepository.segments, hasLength(1));
      expect(
        timeRepository.segments.single.activeDuration,
        const Duration(seconds: 5),
      );
      expect(timeRepository.attempts, hasLength(2));
      expect(timeRepository.attempts.last, timeRepository.attempts.first);
    },
  );

  test(
    'post-write time and close acknowledgement loss replay one frozen sequence',
    () async {
      final timeRepository = _MemoryLearningTimeRepository();
      var monotonicMicros = 0;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => monotonicMicros,
      );
      final fixture = await _fixture(
        adapter: _ActiveEffortAdapter(),
        activeLearningTime: activeTime,
      );
      await fixture.controller.start(fixture.startCommand);
      var routeNow = fixture.now.add(const Duration(seconds: 7));
      final route = UnifiedLessonRouteLifecycle(
        fixture.controller,
        fixture.learning,
        () => routeNow,
      );
      final close = fixture.learning.captureSessionClose(
        sessionId: fixture.startCommand.sessionId,
      );
      monotonicMicros = const Duration(seconds: 7).inMicroseconds;
      timeRepository.loseNextAppendAcknowledgement = true;

      await expectLater(route.complete(close), throwsStateError);
      expect(timeRepository.segments, hasLength(1));
      expect(close.status, PendingLearningSessionCloseStatus.captured);
      expect(fixture.repository.finishCalls, 0);
      expect(fixture.controller.sessionCompletionRetryRequired, isTrue);

      fixture.repository.loseNextFinishAcknowledgement = true;
      routeNow = fixture.now.add(const Duration(hours: 2));
      monotonicMicros = const Duration(hours: 2).inMicroseconds;
      await expectLater(route.complete(close), throwsStateError);

      expect(timeRepository.segments, hasLength(1));
      expect(timeRepository.attempts, hasLength(2));
      expect(timeRepository.attempts.last, timeRepository.attempts.first);
      expect(close.requiresRetry, isTrue);
      expect(fixture.repository.finishCalls, 1);
      expect(fixture.controller.sessionCompletionRetryRequired, isTrue);

      await route.complete(close);

      expect(fixture.controller.state.status, LessonSessionStatus.completed);
      expect(fixture.controller.sessionCompletionRetryRequired, isFalse);
      expect(timeRepository.segments, hasLength(1));
      expect(fixture.repository.finishCalls, 2);
      final sessions = await fixture.database
          .select(fixture.database.learningSessions)
          .get();
      expect(
        sessions.singleWhere((session) => session.id == close.sessionId).state,
        'completed',
      );
    },
  );

  test('time append failure freezes abandonment until exact retry', () async {
    final timeRepository = _MemoryLearningTimeRepository();
    var monotonicMicros = 0;
    final activeTime = _activeTimeController(
      timeRepository,
      monotonicMicros: () => monotonicMicros,
    );
    final fixture = await _fixture(
      adapter: _ActiveEffortAdapter(),
      activeLearningTime: activeTime,
    );
    await fixture.controller.start(fixture.startCommand);
    monotonicMicros = const Duration(seconds: 5).inMicroseconds;
    timeRepository.failNextAppend = true;

    await expectLater(
      fixture.controller.abandon(fixture.now.add(const Duration(seconds: 5))),
      throwsStateError,
    );

    expect(fixture.controller.state.status, LessonSessionStatus.active);
    expect(fixture.repository.scopedAbandonCalls, 0);
    expect(fixture.controller.lastActiveLearningTimeFailure, isNotNull);
    expect(timeRepository.segments, isEmpty);

    monotonicMicros = const Duration(minutes: 1).inMicroseconds;
    await fixture.controller.abandon(
      fixture.now.add(const Duration(minutes: 1)),
    );

    expect(fixture.controller.state.status, LessonSessionStatus.abandoned);
    expect(fixture.repository.scopedAbandonCalls, 1);
    expect(fixture.controller.lastActiveLearningTimeFailure, isNull);
    expect(timeRepository.segments, hasLength(1));
    expect(
      timeRepository.segments.single.activeDuration,
      const Duration(seconds: 5),
    );
  });

  test('failed canonical completion does not count retry-wait time', () async {
    final timeRepository = _MemoryLearningTimeRepository();
    var monotonicMicros = 0;
    final activeTime = _activeTimeController(
      timeRepository,
      monotonicMicros: () => monotonicMicros,
    );
    final fixture = await _fixture(
      adapter: _ActiveEffortAdapter(),
      activeLearningTime: activeTime,
    );
    await fixture.controller.start(fixture.startCommand);
    monotonicMicros = const Duration(seconds: 5).inMicroseconds;
    fixture.repository.failNextFinish = true;

    await expectLater(
      fixture.controller.complete(fixture.now.add(const Duration(seconds: 5))),
      throwsStateError,
    );
    expect(activeTime.state, ActiveLearningTimeState.finished);
    expect(timeRepository.segments, hasLength(1));
    expect(fixture.controller.terminalMutationInFlight, isTrue);
    await expectLater(
      fixture.controller.submit(fixture.submission()),
      throwsStateError,
    );
    await expectLater(
      fixture.controller.pause(fixture.now.add(const Duration(seconds: 6))),
      throwsStateError,
    );
    await expectLater(
      fixture.controller.abandon(fixture.now.add(const Duration(seconds: 6))),
      throwsStateError,
    );
    expect(fixture.repository.recordCalls, 0);
    expect(fixture.repository.scopedAbandonCalls, 0);

    monotonicMicros = const Duration(minutes: 2).inMicroseconds;
    await fixture.controller.complete(
      fixture.now.add(const Duration(minutes: 2)),
    );

    expect(fixture.controller.state.status, LessonSessionStatus.completed);
    expect(fixture.controller.terminalMutationInFlight, isFalse);
    expect(fixture.repository.finishCalls, 2);
    expect(timeRepository.segments, hasLength(1));
    expect(
      timeRepository.segments.single.activeDuration,
      const Duration(seconds: 5),
    );
  });

  test(
    'failed captured completion keeps the exact close fenced until retry',
    () async {
      final timeRepository = _MemoryLearningTimeRepository();
      var monotonicMicros = 0;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => monotonicMicros,
      );
      final fixture = await _fixture(
        adapter: _ActiveEffortAdapter(),
        activeLearningTime: activeTime,
      );
      await fixture.controller.start(fixture.startCommand);
      final close = fixture.learning.captureSessionClose(
        sessionId: fixture.startCommand.sessionId,
      );
      monotonicMicros = const Duration(seconds: 5).inMicroseconds;
      fixture.repository.failNextFinish = true;

      await expectLater(
        fixture.controller.completeCapturedSession(
          close,
          fixture.now.add(const Duration(seconds: 5)),
        ),
        throwsStateError,
      );

      expect(activeTime.state, ActiveLearningTimeState.finished);
      expect(fixture.controller.terminalMutationInFlight, isTrue);
      await expectLater(
        fixture.controller.submit(fixture.submission()),
        throwsStateError,
      );
      await expectLater(
        fixture.controller.completeCapturedSession(
          fixture.learning.captureSessionClose(
            sessionId: fixture.startCommand.sessionId,
          ),
          fixture.now.add(const Duration(seconds: 6)),
        ),
        throwsStateError,
      );

      monotonicMicros = const Duration(minutes: 2).inMicroseconds;
      await fixture.controller.completeCapturedSession(
        close,
        fixture.now.add(const Duration(minutes: 2)),
      );

      expect(fixture.controller.state.status, LessonSessionStatus.completed);
      expect(fixture.controller.terminalMutationInFlight, isFalse);
      expect(fixture.repository.finishCalls, 2);
      expect(fixture.repository.recordCalls, 0);
      expect(timeRepository.segments, hasLength(1));
      expect(
        timeRepository.segments.single.activeDuration,
        const Duration(seconds: 5),
      );
    },
  );

  test('outer mutation queue preserves pause intent monotonic time', () async {
    final timeRepository = _MemoryLearningTimeRepository();
    var monotonicMicros = 0;
    final activeTime = _activeTimeController(
      timeRepository,
      monotonicMicros: () => monotonicMicros,
    );
    final fixture = await _fixture(
      adapter: _ActiveEffortAdapter(),
      blockRecord: true,
      activeLearningTime: activeTime,
    );
    await fixture.controller.start(fixture.startCommand);
    final submission = fixture.controller.submit(fixture.submission());
    await fixture.repository.recordStarted.future;

    monotonicMicros = const Duration(seconds: 10).inMicroseconds;
    final pause = fixture.controller.pause(
      fixture.now.add(const Duration(seconds: 10)),
    );
    monotonicMicros = const Duration(minutes: 1).inMicroseconds;
    fixture.repository.releaseRecord();
    await submission;
    await pause;

    expect(fixture.controller.state.status, LessonSessionStatus.paused);
    expect(timeRepository.segments, hasLength(1));
    expect(
      timeRepository.segments.single.activeDuration,
      const Duration(seconds: 10),
    );
  });

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
      expect((fixture.adapter as _Adapter).classifyCalls, 1);
      expect(fixture.controller.state.committedResponseCount, 1);
    },
  );

  test(
    'publishes one feedback view model from the committed result and frozen answer context',
    () async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      final submission = fixture.submission(isCorrect: false);

      final first = await fixture.controller.submit(submission);
      final duplicate = await fixture.controller.submit(submission);

      expect(first.isCorrect, isFalse);
      expect(duplicate, same(first));
      expect(fixture.controller.feedback, isNotNull);
      expect(fixture.controller.feedback!.isCorrect, isFalse);
      expect(fixture.controller.feedback!.canonicalCorrectAnswer, 'บทเรียน');
      expect(
        fixture.controller.feedback!.nextAction,
        AnswerFeedbackAction.retry,
      );
      expect(fixture.repository.recordCalls, 1);
    },
  );

  test(
    'rejects a duplicate evidence identity with changed feedback context',
    () async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      const sourceEvidenceId = 'feedback-context-evidence';

      await fixture.controller.submit(
        fixture.submission(sourceEvidenceId: sourceEvidenceId),
      );
      await expectLater(
        fixture.controller.submit(
          fixture.submission(
            sourceEvidenceId: sourceEvidenceId,
            canonicalCorrectAnswer: 'different reviewed answer',
          ),
        ),
        throwsStateError,
      );
      expect(fixture.repository.recordCalls, 1);
    },
  );

  test(
    'rejects a bookmark identity that is not the submitted lexical item',
    () async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);

      await expectLater(
        fixture.controller.submit(
          fixture.submission(
            bookmarkIdentity: const ContentIdentity(
              type: ContentType.learningPack,
              id: 'pack:wrong',
              revision: 1,
            ),
          ),
        ),
        throwsArgumentError,
      );

      expect(fixture.repository.recordCalls, 0);
      expect(fixture.controller.feedback, isNull);
    },
  );

  test(
    'rejects bookmark revision changes on a committed evidence replay',
    () async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      const sourceEvidenceId = 'bookmark-replay-evidence';

      await fixture.controller.submit(
        fixture.submission(
          sourceEvidenceId: sourceEvidenceId,
          bookmarkIdentity: ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: fixture.wordId,
            revision: 1,
          ),
        ),
      );
      await expectLater(
        fixture.controller.submit(
          fixture.submission(
            sourceEvidenceId: sourceEvidenceId,
            bookmarkIdentity: ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: fixture.wordId,
              revision: 2,
            ),
          ),
        ),
        throwsStateError,
      );

      expect(fixture.repository.recordCalls, 1);
    },
  );

  test(
    'rejects blank feedback context before a durable write and permits a corrected retry',
    () async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      const sourceEvidenceId = 'invalid-feedback-context';

      await expectLater(
        fixture.controller.submit(
          fixture.submission(
            sourceEvidenceId: sourceEvidenceId,
            canonicalCorrectAnswer: '   ',
          ),
        ),
        throwsArgumentError,
      );
      expect(fixture.repository.recordCalls, 0);
      expect(fixture.controller.feedback, isNull);
      expect(fixture.controller.state.committedResponseCount, 0);

      final corrected = await fixture.controller.submit(
        fixture.submission(
          sourceEvidenceId: sourceEvidenceId,
          canonicalCorrectAnswer: 'บทเรียน',
        ),
      );
      expect(corrected.isCorrect, isTrue);
      expect(fixture.repository.recordCalls, 1);
      expect(fixture.controller.feedback!.canonicalCorrectAnswer, 'บทเรียน');
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

  test('accepted pause synchronously excludes immediate hint reveal', () async {
    final adapter = _HintAdapter();
    final hints = HintUseCases(policy: adapter.hintPolicy);
    final fixture = await _fixture(adapter: adapter, hints: hints);
    await fixture.controller.start(fixture.startCommand);
    Object? listenerRevealError;
    var listenerSawPendingPause = false;
    fixture.controller.addListener(() {
      if (fixture.controller.state.status == LessonSessionStatus.active &&
          !fixture.controller.canRevealHint) {
        listenerSawPendingPause = true;
        try {
          fixture.controller.revealNextHint();
        } catch (error) {
          listenerRevealError = error;
        }
      }
    });

    final pause = fixture.controller.pause(fixture.now);

    expect(fixture.controller.state.status, LessonSessionStatus.active);
    expect(fixture.controller.canRevealHint, isFalse);
    expect(fixture.controller.revealNextHint, throwsStateError);
    expect(listenerSawPendingPause, isTrue);
    expect(listenerRevealError, isA<StateError>());

    await pause;
    expect(fixture.controller.state.status, LessonSessionStatus.paused);
    expect(hints.state.hintLevel, 0);
  });

  test('pause notification reentrancy reuses the accepted future', () async {
    final adapter = _HintAdapter();
    final hints = HintUseCases(policy: adapter.hintPolicy);
    final fixture = await _fixture(adapter: adapter, hints: hints);
    await fixture.controller.start(fixture.startCommand);
    Future<void>? reentrantPause;
    var pauseQueued = false;
    fixture.controller.addListener(() {
      if (!pauseQueued &&
          fixture.controller.state.status == LessonSessionStatus.active &&
          !fixture.controller.canRevealHint) {
        pauseQueued = true;
        reentrantPause = fixture.controller.pause(fixture.now);
      }
    });

    final acceptedPause = fixture.controller.pause(fixture.now);
    Object? reentrantError;
    try {
      await reentrantPause!;
    } catch (error) {
      reentrantError = error;
    }
    await acceptedPause;

    expect(reentrantPause, same(acceptedPause));
    expect(reentrantError, isNull);
    expect(fixture.controller.state.status, LessonSessionStatus.paused);
  });

  test(
    'dispose suppresses state notification but preserves an accepted durable write',
    () async {
      final fixture = await _fixture(blockRecord: true);
      await fixture.controller.start(fixture.startCommand);
      var notifications = 0;
      fixture.controller.addListener(() => notifications += 1);

      final submit = fixture.controller.submit(fixture.submission());
      await fixture.repository.recordStarted.future;
      notifications = 0;
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

  testWidgets('inactive lifecycle excludes time while input is unavailable', (
    tester,
  ) async {
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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(fixture.controller.state.status, LessonSessionStatus.paused);
  });

  testWidgets(
    'focus surface follows adapter capability and the live parent gate',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      final timeRepository = _MemoryLearningTimeRepository();
      var monotonicMicros = 0;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => monotonicMicros,
      );
      final focusTimer = FocusTimerController(timeAuthority: activeTime);
      final fixture = await _fixture(
        adapter: _FocusAdapter(),
        activeLearningTime: activeTime,
        focusTimer: focusTimer,
        focusTimerFeature: Feature.quiz,
      );
      await fixture.controller.start(fixture.startCommand);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _bookmarkDependencies(
            fixture.database,
            features: registry,
          ),
          child: MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              nowUtc: () =>
                  fixture.now.add(Duration(microseconds: monotonicMicros)),
              builder: (_) => const Text('lesson body'),
            ),
          ),
        ),
      );

      expect(find.byType(FocusTimerWidget), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('focus-timer/start')));
      await tester.pump();
      monotonicMicros += const Duration(seconds: 10).inMicroseconds;
      timeRepository.failNextAppend = true;
      registry.emergencyOff(Feature.quiz);
      await tester.pumpAndSettle();

      expect(find.byType(FocusTimerWidget), findsNothing);
      expect(focusTimer.snapshot.status, FocusTimerStatus.paused);
      expect(
        focusTimer.snapshot.pauseReason,
        FocusTimerPauseReason.featureDisabled,
      );
      expect(
        timeRepository.segments.single.captureSource,
        LearningTimeCaptureSource.focusTimer,
      );
      expect(
        timeRepository.segments.single.activeDuration,
        const Duration(seconds: 10),
      );
      expect(timeRepository.attempts, hasLength(2));
      expect(timeRepository.attempts.last, same(timeRepository.attempts.first));

      registry.setOverride(Feature.quiz, FeatureState.enabled);
      await tester.pump();
      expect(find.byType(FocusTimerWidget), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('focus-timer/resume')),
        findsOneWidget,
      );
      fixture.controller.dispose();
    },
  );

  testWidgets(
    'background leaves explicit focus paused when the lesson foregrounds',
    (tester) async {
      final timeRepository = _MemoryLearningTimeRepository();
      var monotonicMicros = 0;
      final activeTime = _activeTimeController(
        timeRepository,
        monotonicMicros: () => monotonicMicros,
      );
      final focusTimer = FocusTimerController(timeAuthority: activeTime);
      final fixture = await _fixture(
        adapter: _FocusAdapter(),
        activeLearningTime: activeTime,
        focusTimer: focusTimer,
        focusTimerFeature: Feature.quiz,
      );
      await fixture.controller.start(fixture.startCommand);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _bookmarkDependencies(
            fixture.database,
            features: registry,
          ),
          child: MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              nowUtc: () =>
                  fixture.now.add(Duration(microseconds: monotonicMicros)),
              builder: (_) => const Text('lesson body'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('focus-timer/start')));
      await tester.pump();
      monotonicMicros += const Duration(seconds: 7).inMicroseconds;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      monotonicMicros += const Duration(hours: 1).inMicroseconds;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(fixture.controller.state.status, LessonSessionStatus.active);
      expect(focusTimer.snapshot.status, FocusTimerStatus.paused);
      expect(
        focusTimer.snapshot.pauseReason,
        FocusTimerPauseReason.processBackground,
      );
      expect(
        timeRepository.segments.single.activeDuration,
        const Duration(seconds: 7),
      );
      fixture.controller.dispose();
    },
  );

  for (final transition in _FocusEntryTransition.values) {
    test(
      'accepted focus ${transition.name} settles before process background',
      () => _expectFocusSettlesBeforeBackground(transition),
    );
    test(
      'accepted focus ${transition.name} settles before emergency-off',
      () => _expectFocusSettlesBeforeEmergencyOff(transition),
    );
    test(
      'accepted focus ${transition.name} settles before terminal finish',
      () => _expectFocusSettlesBeforeTerminalFinish(transition),
    );
    test(
      'failed focus ${transition.name} is superseded by process background',
      () => _expectFailedFocusSupersededByBackground(transition),
    );
    test(
      'failed focus ${transition.name} is superseded across gate off and re-enable',
      () => _expectFailedFocusSupersededByGateBoundary(transition),
    );
    testWidgets(
      'real shell failed focus ${transition.name} retries exact unchanged intent',
      (tester) => _expectShellFocusRetryUsesExactIntent(tester, transition),
    );
    testWidgets(
      'real shell failed focus ${transition.name} settles across gate re-enable',
      (tester) => _expectShellFailedFocusSettlesAcrossGate(tester, transition),
    );
    testWidgets(
      'real shell failed focus evidence ${transition.name} content supersedes before fresh retry',
      (tester) => _expectShellContentSupersedesFailedEntry(tester, transition),
    );
    testWidgets(
      'real shell failed focus evidence ${transition.name} IME survives passive emergency-off',
      (tester) =>
          _expectShellImeSupersedesBeforeEmergencyOff(tester, transition),
    );
    test(
      'failed focus evidence ${transition.name} emergency-off stays passive until interaction',
      () => _expectEmergencyOffWaitsForInteraction(transition),
    );
  }

  testWidgets(
    'initial paused or hidden mount reconciles without a lifecycle event',
    (tester) async {
      for (final initialState in <AppLifecycleState>[
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
      ]) {
        final fixture = await _fixture();
        await fixture.controller.start(fixture.startCommand);

        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              lifecycleStateReader: () => initialState,
              nowUtc: () => fixture.now.add(const Duration(seconds: 5)),
              builder: (_) => const Text('lesson body'),
            ),
          ),
        );
        await tester.pump();

        expect(fixture.controller.state.status, LessonSessionStatus.paused);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('initial foreground mount leaves an active lesson active', (
    tester,
  ) async {
    final fixture = await _fixture();
    await fixture.controller.start(fixture.startCommand);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          lifecycleStateReader: () => AppLifecycleState.resumed,
          builder: (_) => const Text('lesson body'),
        ),
      ),
    );
    await tester.pump();

    expect(fixture.controller.state.status, LessonSessionStatus.active);
  });

  testWidgets(
    'foreground during a queued lifecycle pause resumes after the pause',
    (tester) async {
      final fixture = await _fixture(blockRecord: true);
      await fixture.controller.start(fixture.startCommand);
      final transitions = <LessonSessionStatus>[];
      var lastStatus = fixture.controller.state.status;
      fixture.controller.addListener(() {
        final status = fixture.controller.state.status;
        if (status != lastStatus) {
          transitions.add(status);
          lastStatus = status;
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonShell(
            controller: fixture.controller,
            nowUtc: () => fixture.now.add(const Duration(seconds: 5)),
            builder: (_) => const Text('lesson body'),
          ),
        ),
      );
      final submit = fixture.controller.submit(fixture.submission());
      await fixture.repository.recordStarted.future;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(fixture.controller.state.status, LessonSessionStatus.active);
      fixture.repository.releaseRecord();
      await submit;
      await tester.pumpAndSettle();

      expect(fixture.controller.state.status, LessonSessionStatus.active);
      expect(transitions, <LessonSessionStatus>[
        LessonSessionStatus.paused,
        LessonSessionStatus.active,
      ]);
    },
  );

  testWidgets(
    'terminal conflict does not self-reschedule lifecycle reconciliation',
    (tester) async {
      final fixture = await _fixture(blockFinish: true);
      await fixture.controller.start(fixture.startCommand);
      final transitions = <LessonSessionStatus>[];
      var lastStatus = fixture.controller.state.status;
      fixture.controller.addListener(() {
        final status = fixture.controller.state.status;
        if (status != lastStatus) {
          transitions.add(status);
          lastStatus = status;
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonShell(
            controller: fixture.controller,
            nowUtc: () => fixture.now.add(const Duration(seconds: 5)),
            builder: (_) => const Text('lesson body'),
          ),
        ),
      );
      final completion = fixture.controller.complete(
        fixture.now.add(const Duration(seconds: 6)),
      );
      await fixture.repository.finishStarted.future;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      fixture.repository.releaseFinish();
      await completion;
      await tester.pump();

      expect(fixture.controller.state.status, LessonSessionStatus.completed);
      expect(fixture.repository.finishCalls, 1);
      expect(transitions, <LessonSessionStatus>[LessonSessionStatus.completed]);
    },
  );

  testWidgets('failed completion stays fenced across lifecycle changes', (
    tester,
  ) async {
    final fixture = await _fixture(blockFinish: true, failFinish: true);
    await fixture.controller.start(fixture.startCommand);
    final transitions = <LessonSessionStatus>[];
    var lastStatus = fixture.controller.state.status;
    fixture.controller.addListener(() {
      final status = fixture.controller.state.status;
      if (status != lastStatus) {
        transitions.add(status);
        lastStatus = status;
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          nowUtc: () => fixture.now.add(const Duration(seconds: 5)),
          builder: (_) => const Text('lesson body'),
        ),
      ),
    );
    final completion = fixture.controller.complete(
      fixture.now.add(const Duration(seconds: 6)),
    );
    final completionExpectation = expectLater(completion, throwsStateError);
    await fixture.repository.finishStarted.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    fixture.repository.releaseFinish();
    await completionExpectation;
    await tester.pump();
    final statusAfterFailure = fixture.controller.state.status;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fixture.controller.hintState, isNull);
    expect(statusAfterFailure, LessonSessionStatus.active);
    expect(fixture.controller.state.status, LessonSessionStatus.active);
    expect(fixture.controller.terminalMutationInFlight, isTrue);
    expect(fixture.repository.finishCalls, 1);
    expect(transitions, isEmpty);
  });

  testWidgets('failed abandon signals one deferred background pause', (
    tester,
  ) async {
    final fixture = await _fixture(blockAbandon: true, failAbandon: true);
    await fixture.controller.start(fixture.startCommand);
    final transitions = <LessonSessionStatus>[];
    var lastStatus = fixture.controller.state.status;
    fixture.controller.addListener(() {
      final status = fixture.controller.state.status;
      if (status != lastStatus) {
        transitions.add(status);
        lastStatus = status;
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          nowUtc: () => fixture.now.add(const Duration(seconds: 5)),
          builder: (_) => const Text('lesson body'),
        ),
      ),
    );
    final abandon = fixture.controller.abandon(
      fixture.now.add(const Duration(seconds: 6)),
    );
    final abandonExpectation = expectLater(abandon, throwsStateError);
    await fixture.repository.abandonStarted.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    fixture.repository.releaseAbandon();
    await abandonExpectation;
    await tester.pump();
    final statusAfterFailure = fixture.controller.state.status;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fixture.controller.hintState, isNull);
    expect(statusAfterFailure, LessonSessionStatus.paused);
    expect(fixture.controller.state.status, LessonSessionStatus.active);
    expect(fixture.repository.scopedAbandonCalls, 1);
    expect(transitions, <LessonSessionStatus>[
      LessonSessionStatus.paused,
      LessonSessionStatus.active,
    ]);
  });

  testWidgets(
    'failed completion retains lifecycle pause ownership for foreground retry',
    (tester) async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      final transitions = <LessonSessionStatus>[];
      var lastStatus = fixture.controller.state.status;
      fixture.controller.addListener(() {
        final status = fixture.controller.state.status;
        if (status != lastStatus) {
          transitions.add(status);
          lastStatus = status;
        }
      });
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
      final completion = fixture.controller.complete(
        fixture.now.add(const Duration(seconds: 6)),
      );
      final completionExpectation = expectLater(completion, throwsStateError);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await completionExpectation;
      await tester.pump();

      expect(fixture.controller.state.status, LessonSessionStatus.active);
      expect(fixture.repository.finishCalls, 0);
      expect(transitions, <LessonSessionStatus>[
        LessonSessionStatus.paused,
        LessonSessionStatus.active,
      ]);
    },
  );

  testWidgets(
    'failed abandon retains lifecycle pause ownership for foreground retry',
    (tester) async {
      final fixture = await _fixture(blockAbandon: true, failAbandon: true);
      await fixture.controller.start(fixture.startCommand);
      final transitions = <LessonSessionStatus>[];
      var lastStatus = fixture.controller.state.status;
      fixture.controller.addListener(() {
        final status = fixture.controller.state.status;
        if (status != lastStatus) {
          transitions.add(status);
          lastStatus = status;
        }
      });
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
      final abandon = fixture.controller.abandon(
        fixture.now.add(const Duration(seconds: 6)),
      );
      final abandonExpectation = expectLater(abandon, throwsStateError);
      await fixture.repository.abandonStarted.future;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      fixture.repository.releaseAbandon();
      await abandonExpectation;
      await tester.pump();

      expect(fixture.controller.state.status, LessonSessionStatus.active);
      expect(fixture.repository.scopedAbandonCalls, 1);
      expect(transitions, <LessonSessionStatus>[
        LessonSessionStatus.paused,
        LessonSessionStatus.active,
      ]);
    },
  );

  testWidgets(
    'background intent survives controller replacement and stale completion',
    (tester) async {
      final first = await _fixture(blockRecord: true);
      final replacement = await _fixture();
      await first.controller.start(first.startCommand);
      await replacement.controller.start(replacement.startCommand);
      final replacementTransitions = <LessonSessionStatus>[];
      var replacementStatus = replacement.controller.state.status;
      replacement.controller.addListener(() {
        final status = replacement.controller.state.status;
        if (status != replacementStatus) {
          replacementTransitions.add(status);
          replacementStatus = status;
        }
      });
      UnifiedLessonShell shell(UnifiedLessonController controller) =>
          UnifiedLessonShell(
            controller: controller,
            nowUtc: () => first.now.add(const Duration(seconds: 5)),
            builder: (_) => const Text('lesson body'),
          );
      await tester.pumpWidget(MaterialApp(home: shell(first.controller)));
      final submit = first.controller.submit(first.submission());
      await first.repository.recordStarted.future;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpWidget(MaterialApp(home: shell(replacement.controller)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final replacementWhileBackgrounded = replacement.controller.state.status;

      first.repository.releaseRecord();
      await submit;
      await tester.pump();
      final firstAfterStaleCompletion = first.controller.state.status;
      final replacementAfterStaleCompletion =
          replacement.controller.state.status;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final replacementAfterForeground = replacement.controller.state.status;

      expect(replacementWhileBackgrounded, LessonSessionStatus.paused);
      expect(firstAfterStaleCompletion, LessonSessionStatus.paused);
      expect(replacementAfterStaleCompletion, LessonSessionStatus.paused);
      expect(replacementAfterForeground, LessonSessionStatus.active);
      expect(replacementTransitions, <LessonSessionStatus>[
        LessonSessionStatus.paused,
        LessonSessionStatus.active,
      ]);
    },
  );

  testWidgets(
    'shell controller replacement clears registered ephemeral state',
    (tester) async {
      final first = await _fixture();
      final replacement = await _fixture();
      final scratchpad = HandwritingScratchpadController()
        ..beginStroke(const Offset(1, 1))
        ..endStroke();
      UnifiedLessonShell shell(UnifiedLessonController controller) =>
          UnifiedLessonShell(
            controller: controller,
            builder: (_) =>
                Material(child: HandwritingScratchpad(controller: scratchpad)),
          );

      await tester.pumpWidget(MaterialApp(home: shell(first.controller)));
      await tester.pumpWidget(MaterialApp(home: shell(replacement.controller)));
      await tester.pump();

      expect(scratchpad.strokeCount, 0);
    },
  );

  testWidgets(
    'controllerless-to-controlled shell transition clears scratchpad state',
    (tester) async {
      final fixture = await _fixture();
      final scratchpad = HandwritingScratchpadController()
        ..beginStroke(const Offset(1, 1))
        ..endStroke();
      UnifiedLessonShell shell(UnifiedLessonController? controller) =>
          UnifiedLessonShell(
            controller: controller,
            builder: (_) =>
                Material(child: HandwritingScratchpad(controller: scratchpad)),
          );

      await tester.pumpWidget(MaterialApp(home: shell(null)));
      await tester.enterText(find.byType(TextField), 'station');
      await tester.pumpWidget(MaterialApp(home: shell(fixture.controller)));
      await tester.pump();

      expect(scratchpad.strokeCount, 0);
      expect(find.text('station'), findsNothing);
      expect(find.byType(HandwritingScratchpad), findsOneWidget);
    },
  );

  testWidgets(
    'controlled-to-controllerless shell transition clears scratchpad state',
    (tester) async {
      final fixture = await _fixture();
      final scratchpad = HandwritingScratchpadController()
        ..beginStroke(const Offset(1, 1))
        ..endStroke();
      UnifiedLessonShell shell(UnifiedLessonController? controller) =>
          UnifiedLessonShell(
            controller: controller,
            builder: (_) =>
                Material(child: HandwritingScratchpad(controller: scratchpad)),
          );

      await tester.pumpWidget(MaterialApp(home: shell(fixture.controller)));
      await tester.enterText(find.byType(TextField), 'station');
      await tester.pumpWidget(MaterialApp(home: shell(null)));
      await tester.pump();

      expect(scratchpad.strokeCount, 0);
      expect(find.text('station'), findsNothing);
      expect(find.byType(HandwritingScratchpad), findsOneWidget);
    },
  );

  testWidgets('terminal lesson state clears registered ephemeral state', (
    tester,
  ) async {
    final fixture = await _fixture();
    await fixture.controller.start(fixture.startCommand);
    final scratchpad = HandwritingScratchpadController()
      ..beginStroke(const Offset(1, 1))
      ..endStroke();

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          builder: (_) =>
              Material(child: HandwritingScratchpad(controller: scratchpad)),
        ),
      ),
    );
    await fixture.controller.abandon(
      fixture.now.add(const Duration(seconds: 1)),
    );
    await tester.pump();

    expect(scratchpad.strokeCount, 0);
  });

  testWidgets('route retirement clears registered ephemeral state', (
    tester,
  ) async {
    final fixture = await _fixture();
    final route = UnifiedLessonRouteLifecycle(
      fixture.controller,
      fixture.learning,
      () => fixture.now,
    );
    final scratchpad = HandwritingScratchpadController()
      ..beginStroke(const Offset(1, 1))
      ..endStroke();

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          routeLifecycle: route,
          builder: (_) =>
              Material(child: HandwritingScratchpad(controller: scratchpad)),
        ),
      ),
    );
    await route.retire();
    await tester.pump();

    expect(scratchpad.strokeCount, 0);
  });

  testWidgets('emergency-off clears registered ephemeral state', (
    tester,
  ) async {
    final fixture = await _fixture();
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    final scratchpad = HandwritingScratchpadController()
      ..beginStroke(const Offset(1, 1))
      ..endStroke();

    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _bookmarkDependencies(
          fixture.database,
          features: features,
          learning: fixture.learning,
        ),
        child: MaterialApp(
          home: UnifiedLessonModeHost(
            adapter: fixture.adapter,
            createController: (_) => fixture.controller,
            feature: Feature.quiz,
            featureRegistry: features,
            learning: fixture.learning,
            nowUtc: () => fixture.now,
            builder: (_) =>
                Material(child: HandwritingScratchpad(controller: scratchpad)),
          ),
        ),
      ),
    );
    expect(find.byType(HandwritingScratchpad), findsOneWidget);
    features.emergencyOff(Feature.quiz);
    await tester.pumpAndSettle();

    expect(find.byType(HandwritingScratchpad), findsNothing);
    expect(scratchpad.strokeCount, 0);
  });

  testWidgets('shell presents one panel for one committed answer result', (
    tester,
  ) async {
    final fixture = await _fixture();
    await fixture.controller.start(fixture.startCommand);
    await fixture.controller.submit(fixture.submission(isCorrect: false));

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          builder: (_) => const Text('lesson body'),
        ),
      ),
    );

    expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
    expect(find.text('Not quite'), findsOneWidget);
    expect(find.text('Correct answer: บทเรียน'), findsOneWidget);
    expect(find.text('Save for review'), findsNothing);
  });

  testWidgets(
    'production lesson shell save is idempotent and does not mutate weakness',
    (tester) async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      await fixture.controller.submit(
        fixture.submission(
          bookmarkIdentity: ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: fixture.wordId,
            revision: 1,
          ),
        ),
      );
      final repository = DriftLearnerIntentRepository(
        fixture.database,
        owners: fixture.owners,
        nowUtc: () => fixture.now,
      );
      var nextId = 0;
      final bookmark = LearnerIntentUseCases(
        repository: repository,
        generateId: () => 'lesson-save-${++nextId}',
        nowUtc: () => fixture.now,
      ).bookmark;
      final weaknessCountBefore = await fixture.database
          .select(fixture.database.srsStates)
          .get()
          .then((rows) => rows.length);

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _bookmarkDependencies(
            fixture.database,
            learnerIntents: repository,
            bookmarkLearningItem: bookmark,
          ),
          child: MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              builder: (_) => const Text('lesson body'),
            ),
          ),
        ),
      );

      expect(find.text('Save for review'), findsOneWidget);
      await tester.tap(find.text('Save for review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save for review'));
      await tester.pumpAndSettle();

      final saved = await fixture.database
          .select(fixture.database.savedLearningItems)
          .get();
      final outbox = await (fixture.database.select(
        fixture.database.outboxOperations,
      )..where((row) => row.entityType.equals('savedLearningItem'))).get();
      final weaknessCountAfter = await fixture.database
          .select(fixture.database.srsStates)
          .get()
          .then((rows) => rows.length);
      expect(saved, hasLength(1));
      expect(saved.single.contentType, ContentType.lexicalMetadata.name);
      expect(saved.single.contentId, fixture.wordId);
      expect(saved.single.contentRevision, 1);
      expect(outbox, hasLength(1));
      expect(weaknessCountAfter, weaknessCountBefore);
    },
  );

  testWidgets(
    'production lesson feedback report is single-flight and isolated from learning',
    (tester) async {
      final fixture = await _fixture();
      await fixture.controller.start(fixture.startCommand);
      await fixture.controller.submit(
        fixture.submission(
          bookmarkIdentity: ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: fixture.wordId,
            revision: 1,
          ),
        ),
      );
      final owner = await fixture.owners.getOrCreateActiveOwner();
      await DriftResearchConsentRepository(fixture.database).decide(
        ownerId: owner.id,
        version: 1,
        accepted: true,
        decidedAtUtc: fixture.now.subtract(const Duration(minutes: 1)),
      );
      final repository = DriftContentQualityReportRepository(
        fixture.database,
        owners: fixture.owners,
        consentRegistry: DriftConsentRegistry(fixture.database),
        uploadPolicy: const ContentReportUploadPolicy.v1(
          deployedRulesRevision: contentQualityReportV1RulesRevision,
          consentVersion: 1,
        ),
      );
      var nextId = 0;
      final report = ContentReportUseCases(
        repository: repository,
        generateId: () => 'lesson-report-${++nextId}',
        nowUtc: () => fixture.now,
      ).report;
      final before = (
        content: await fixture.database
            .select(fixture.database.vocabularyWords)
            .get(),
        attempts: await fixture.database
            .select(fixture.database.answerAttempts)
            .get(),
        weakness: await fixture.database
            .select(fixture.database.srsStates)
            .get(),
      );

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _bookmarkDependencies(
            fixture.database,
            contentQualityReports: repository,
            reportContent: report,
          ),
          child: MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              builder: (_) => const Text('lesson body'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Report content'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Answer problem'));
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.tap(find.text('Submit report'), warnIfMissed: false);
      await tester.pumpAndSettle();

      final reports = await fixture.database
          .select(fixture.database.contentQualityReports)
          .get();
      final outbox = await (fixture.database.select(
        fixture.database.outboxOperations,
      )..where((row) => row.entityType.equals('contentQualityReport'))).get();
      expect(reports, hasLength(1));
      expect(reports.single.contentId, fixture.wordId);
      expect(reports.single.contentRevision, 1);
      expect(outbox, hasLength(1));
      expect(
        await fixture.database.select(fixture.database.vocabularyWords).get(),
        before.content,
      );
      expect(
        await fixture.database.select(fixture.database.answerAttempts).get(),
        before.attempts,
      );
      expect(
        await fixture.database.select(fixture.database.srsStates).get(),
        before.weakness,
      );
    },
  );

  test(
    'one-argument production factory composes isolated typed hint use cases',
    () async {
      final fixture = await _fixture();
      UnifiedLessonController factory(LessonModeAdapter adapter) =>
          UnifiedLessonController(learning: fixture.learning, adapter: adapter);
      final UnifiedLessonControllerFactory productionFactory = factory;
      final first = productionFactory(_HintAdapter());
      final second = productionFactory(_HintAdapter());
      await first.start(fixture.startCommand);
      await second.start(fixture.startCommand);

      first.revealNextHint();

      expect(first.hintState!.hintLevel, 1);
      expect(second.hintState!.hintLevel, 0);
    },
  );

  testWidgets(
    'shell invokes one typed hint transition without asking the adapter to classify',
    (tester) async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(policy: adapter.hintPolicy);
      final fixture = await _fixture(adapter: adapter, hints: hints);
      await fixture.controller.start(fixture.startCommand);

      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedLessonShell(
            controller: fixture.controller,
            builder: (_) => const Text('lesson body'),
          ),
        ),
      );
      await tester.tap(find.text('Show strategy'));
      await tester.pump();

      expect(find.byType(HintPanel), findsOneWidget);
      expect(find.text('Look for the familiar word family.'), findsOneWidget);
      expect(hints.state.hintLevel, 1);
      expect(adapter.classifyCalls, 0);
    },
  );

  testWidgets('shell disables hints while accepted evidence is uncommitted', (
    tester,
  ) async {
    final adapter = _HintAdapter();
    final hints = HintUseCases(policy: adapter.hintPolicy);
    final fixture = await _fixture(
      adapter: adapter,
      hints: hints,
      blockRecord: true,
    );
    await fixture.controller.start(fixture.startCommand);
    fixture.controller.revealNextHint();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedLessonShell(
          controller: fixture.controller,
          builder: (_) => const Text('lesson body'),
        ),
      ),
    );

    final submit = fixture.controller.submit(
      fixture.submission(
        sourceEvidenceId: 'blocked-shell-response',
        evidenceClass: EvidenceClass.independentRecall,
      ),
    );
    await fixture.repository.recordStarted.future;
    await tester.pump();

    final blockedButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Reveal context'),
    );
    expect(blockedButton.onPressed, isNull);
    expect(fixture.controller.canRevealHint, isFalse);

    fixture.repository.releaseRecord();
    await submit;
    await tester.pump();
    expect(fixture.controller.canRevealHint, isTrue);
    expect(find.text('Show strategy'), findsOneWidget);
  });

  test(
    'hint availability listeners cannot overtake an accepted submit',
    () async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(policy: adapter.hintPolicy);
      final fixture = await _fixture(adapter: adapter, hints: hints);
      await fixture.controller.start(fixture.startCommand);
      late Future<void> pause;
      var pauseQueued = false;
      fixture.controller.addListener(() {
        if (!pauseQueued && !fixture.controller.canRevealHint) {
          pauseQueued = true;
          pause = fixture.controller.pause(
            fixture.now.add(const Duration(seconds: 1)),
          );
        }
      });

      final result = await fixture.controller.submit(fixture.submission());
      await pause;

      expect(result.inserted, isTrue);
      expect(fixture.repository.recordCalls, 1);
      expect(fixture.controller.state.status, LessonSessionStatus.paused);
    },
  );

  test(
    'controller replaces caller hint claims with actual shell-owned usage',
    () async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(policy: adapter.hintPolicy);
      final fixture = await _fixture(adapter: adapter, hints: hints);
      await fixture.controller.start(fixture.startCommand);

      await fixture.controller.submit(
        fixture.submission(
          evidenceClass: EvidenceClass.independentRecall,
          declaredHintLevel: 2,
        ),
      );

      expect(
        fixture.repository.lastRecordCommand!.evidenceContext.evidenceClass,
        EvidenceClass.independentRecall,
      );
      expect(
        fixture.repository.lastRecordCommand!.evidenceContext.hintLevel,
        0,
      );
    },
  );

  test(
    'committed evidence resets assistance before the next response',
    () async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(policy: adapter.hintPolicy);
      final fixture = await _fixture(adapter: adapter, hints: hints);
      await fixture.controller.start(fixture.startCommand);
      fixture.controller.revealNextHint();

      await fixture.controller.submit(
        fixture.submission(
          sourceEvidenceId: 'assisted-response',
          evidenceClass: EvidenceClass.independentRecall,
        ),
      );
      await fixture.controller.submit(
        fixture.submission(
          sourceEvidenceId: 'next-unassisted-response',
          evidenceClass: EvidenceClass.independentRecall,
        ),
      );

      expect(
        fixture.repository.recordCommands.map(
          (command) => command.evidenceContext.evidenceClass,
        ),
        <EvidenceClass>[
          EvidenceClass.guidedPractice,
          EvidenceClass.independentRecall,
        ],
      );
      expect(
        fixture.repository.recordCommands.map(
          (command) => command.evidenceContext.hintLevel,
        ),
        <int>[1, 0],
      );
      expect(hints.state.hintLevel, 0);
    },
  );

  test(
    'a different response cannot inherit hints while accepted evidence is uncommitted',
    () async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(policy: adapter.hintPolicy);
      final fixture = await _fixture(
        adapter: adapter,
        hints: hints,
        blockRecord: true,
      );
      await fixture.controller.start(fixture.startCommand);
      fixture.controller.revealNextHint();

      final first = fixture.controller.submit(
        fixture.submission(
          sourceEvidenceId: 'blocked-assisted-response',
          evidenceClass: EvidenceClass.independentRecall,
        ),
      );
      await fixture.repository.recordStarted.future;
      final competing = fixture.controller.submit(
        fixture.submission(
          sourceEvidenceId: 'competing-response',
          evidenceClass: EvidenceClass.independentRecall,
        ),
      );
      final competingExpectation = expectLater(competing, throwsStateError);

      fixture.repository.releaseRecord();
      await first;
      await competingExpectation;

      expect(fixture.repository.recordCalls, 1);
      expect(adapter.classifyCalls, 1);
      expect(hints.state.hintLevel, 0);
    },
  );

  test(
    'lost-ACK retry keeps the accepted hint snapshot and rejects changed same-ID semantics',
    () async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(policy: adapter.hintPolicy);
      final fixture = await _fixture(
        adapter: adapter,
        hints: hints,
        failAfterFirstRecord: true,
      );
      await fixture.controller.start(fixture.startCommand);
      fixture.controller.revealNextHint();
      final submission = fixture.submission(
        sourceEvidenceId: 'hint-lost-ack',
        evidenceClass: EvidenceClass.independentRecall,
      );

      await expectLater(
        fixture.controller.submit(submission),
        throwsStateError,
      );
      expect(fixture.controller.revealNextHint, throwsStateError);
      final replay = await fixture.controller.submit(submission);

      expect(replay.inserted, isFalse);
      expect(adapter.classifyCalls, 1);
      expect(fixture.repository.recordCalls, 1);
      expect(
        fixture.repository.lastRecordCommand!.evidenceContext.evidenceClass,
        EvidenceClass.guidedPractice,
      );
      expect(
        fixture.repository.lastRecordCommand!.evidenceContext.hintLevel,
        1,
      );
      await expectLater(
        fixture.controller.submit(
          fixture.submission(
            sourceEvidenceId: 'hint-lost-ack',
            isCorrect: false,
            evidenceClass: EvidenceClass.independentRecall,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'unknown accepted hint state records conservative guided evidence',
    () async {
      final adapter = _HintAdapter();
      final hints = HintUseCases(
        policy: adapter.hintPolicy,
        initialState: const HintState.unknown(),
      );
      final fixture = await _fixture(adapter: adapter, hints: hints);
      await fixture.controller.start(fixture.startCommand);

      await fixture.controller.submit(
        fixture.submission(evidenceClass: EvidenceClass.independentRecall),
      );

      expect(
        fixture.repository.lastRecordCommand!.evidenceContext.evidenceClass,
        EvidenceClass.guidedPractice,
      );
      expect(
        fixture.repository.lastRecordCommand!.evidenceContext.hintLevel,
        2,
      );
    },
  );

  testWidgets(
    'every registered adapter delivers one committed result to one panel without duplicate evidence',
    (tester) async {
      for (final registration
          in buildLegacyLessonModeRegistry().registrations) {
        final fixture = await _fixture(adapter: registration.adapter);
        await fixture.controller.start(fixture.startCommand);
        final submission = fixture.submissionForAdapter(
          registration.adapter,
          sourceEvidenceId: 'adapter-${registration.mode.id}',
        );

        final first = await fixture.controller.submit(submission);
        final duplicate = await fixture.controller.submit(submission);
        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              builder: (_) => const Text('lesson body'),
            ),
          ),
        );

        expect(first.isCorrect, isTrue);
        expect(duplicate, same(first));
        expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
        expect(fixture.repository.recordCalls, 1);
      }
    },
  );

  testWidgets(
    'every registered adapter reuses one committed result and panel after a lost ACK',
    (tester) async {
      for (final registration
          in buildLegacyLessonModeRegistry().registrations) {
        final fixture = await _fixture(
          adapter: registration.adapter,
          failAfterFirstRecord: true,
        );
        await fixture.controller.start(fixture.startCommand);
        final submission = fixture.submissionForAdapter(
          registration.adapter,
          sourceEvidenceId: 'adapter-lost-ack-${registration.mode.id}',
        );

        await expectLater(
          fixture.controller.submit(submission),
          throwsStateError,
        );
        final replay = await fixture.controller.submit(submission);
        final duplicate = await fixture.controller.submit(submission);
        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedLessonShell(
              controller: fixture.controller,
              builder: (_) => const Text('lesson body'),
            ),
          ),
        );

        expect(replay.inserted, isFalse);
        expect(duplicate, same(replay));
        expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
        expect(fixture.repository.recordCalls, 1);
      }
    },
  );
}

AppDependencies _bookmarkDependencies(
  AppDatabase database, {
  FeatureRegistry features = const BuildFeatureRegistry.fieldDefaults(),
  LearningUseCases? learning,
  LearnerIntentRepository? learnerIntents,
  BookmarkLearningItemAction? bookmarkLearningItem,
  ContentQualityReportRepository? contentQualityReports,
  ReportContentAction? reportContent,
}) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSession(),
    features: features,
    learning: learning,
    currentActivityEvidence: learning == null
        ? null
        : CurrentActivityEvidenceAdapter(learning: learning),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    learnerIntents: learnerIntents,
    bookmarkLearningItem: bookmarkLearningItem,
    contentQualityReports: contentQualityReports,
    reportContent: reportContent,
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'lesson-save');
}

final class _Fixture {
  const _Fixture({
    required this.database,
    required this.owners,
    required this.repository,
    required this.learning,
    required this.adapter,
    required this.controller,
    required this.startCommand,
    required this.now,
    required this.wordId,
  });

  final AppDatabase database;
  final DriftLocalOwnerRepository owners;
  final _CountingRepository repository;
  final LearningUseCases learning;
  final LessonModeAdapter adapter;
  final UnifiedLessonController controller;
  final LessonStartCommand startCommand;
  final DateTime now;
  final String wordId;

  LessonSubmission submission({
    String sourceEvidenceId = 'evidence-1',
    bool isCorrect = true,
    String canonicalCorrectAnswer = 'บทเรียน',
    ContentIdentity? bookmarkIdentity,
    EvidenceClass evidenceClass = EvidenceClass.recognition,
    int declaredHintLevel = 0,
    String promptMode = 'meaningChoice',
    String? providerProvenance,
    String skillId = 'legacy-meaning-quiz',
    String contentRevision = 'legacy-unknown',
  }) => LessonSubmission(
    response: LessonResponse(
      sourceEvidenceId: sourceEvidenceId,
      occurredAtUtc: now.add(const Duration(milliseconds: 400)),
      sessionId: startCommand.sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: 400,
      attemptNumber: 1,
      feedbackContext: AnswerFeedbackContext(
        canonicalCorrectAnswer: canonicalCorrectAnswer,
        bookmarkIdentity: bookmarkIdentity,
      ),
      providerProvenance: providerProvenance,
    ),
    support: LessonSupport(
      evidenceContext: EvidenceContext.legacyCompatibility(
        evidenceClass: evidenceClass,
        skillId: skillId,
        hintLevel: declaredHintLevel,
        contentRevision: contentRevision,
        engagementAllowed: true,
      ),
    ),
  );

  LessonSubmission submissionForAdapter(
    LessonModeAdapter adapter, {
    required String sourceEvidenceId,
  }) {
    if (adapter is! TypedRecallModeAdapter) {
      return submission(sourceEvidenceId: sourceEvidenceId);
    }
    return submission(
      sourceEvidenceId: sourceEvidenceId,
      promptMode: 'typedRecall',
      providerProvenance:
          'typed-recall:$typedRecallNormalizationRevisionV1:meaning:exact',
      skillId: 'typed-recall',
      contentRevision:
          'lexical-typed-recall:$wordId@1:'
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      evidenceClass: EvidenceClass.independentRecall,
    );
  }
}

Future<_Fixture> _fixture({
  LessonModeAdapter? adapter,
  HintUseCases? hints,
  bool failAfterFirstRecord = false,
  bool blockRecord = false,
  bool blockFinish = false,
  bool failFinish = false,
  bool blockAbandon = false,
  bool failAbandon = false,
  ActiveLearningTimeController? activeLearningTime,
  FocusTimerController? focusTimer,
  Feature? focusTimerFeature,
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
    failFinish: failFinish,
    blockAbandon: blockAbandon,
    failAbandon: failAbandon,
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
  final modeAdapter = adapter ?? _Adapter();
  final controller = UnifiedLessonController(
    learning: learning,
    adapter: modeAdapter,
    hints: hints,
    activeLearningTime: activeLearningTime,
    focusTimer: focusTimer,
    focusTimerFeature: focusTimerFeature,
  );
  return _Fixture(
    database: database,
    owners: owners,
    repository: repository,
    learning: learning,
    adapter: modeAdapter,
    controller: controller,
    startCommand: LessonStartCommand(
      mode: modeAdapter.mode,
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

final class _ActiveEffortAdapter
    implements TrustworthyActiveEffortLessonModeAdapter {
  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      LessonItem(id: 'active-item-${cursor.index}');
}

final class _FocusAdapter implements FocusTimerSupportingLessonModeAdapter {
  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      LessonItem(id: 'focus-item-${cursor.index}');
}

ActiveLearningTimeController _activeTimeController(
  LearningTimeRepository repository, {
  required int Function() monotonicMicros,
}) => ActiveLearningTimeController(
  repository: repository,
  monotonicMicros: monotonicMicros,
  nowUtc: () => DateTime.utc(2026, 8, 24, 9),
  timezoneContext: (_) => const LearningTimeZoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
);

enum _FocusEntryTransition { start, resume }

final class _MutableMonotonicClock {
  int micros = 0;

  int call() => micros;

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
  }
}

final class _FocusLifecycleRaceFixture {
  const _FocusLifecycleRaceFixture({
    required this.fixture,
    required this.timeRepository,
    required this.activeTime,
    required this.focusTimer,
    required this.clock,
  });

  final _Fixture fixture;
  final _MemoryLearningTimeRepository timeRepository;
  final ActiveLearningTimeController activeTime;
  final FocusTimerController focusTimer;
  final _MutableMonotonicClock clock;

  DateTime get now => fixture.now.add(Duration(microseconds: clock.micros));

  Future<void> beginTransition(_FocusEntryTransition transition) =>
      switch (transition) {
        _FocusEntryTransition.start => fixture.controller.startFocusTimer(now),
        _FocusEntryTransition.resume => fixture.controller.resumeFocusTimer(
          now,
        ),
      };

  Future<void> beginBlockedTransition(_FocusEntryTransition transition) {
    timeRepository.blockNextAppend();
    return beginTransition(transition);
  }
}

Future<_FocusLifecycleRaceFixture> _focusLifecycleRaceFixture(
  _FocusEntryTransition transition,
) async {
  final timeRepository = _MemoryLearningTimeRepository();
  final clock = _MutableMonotonicClock();
  final activeTime = _activeTimeController(
    timeRepository,
    monotonicMicros: clock.call,
  );
  final focusTimer = FocusTimerController(timeAuthority: activeTime);
  final fixture = await _fixture(
    adapter: _FocusAdapter(),
    activeLearningTime: activeTime,
    focusTimer: focusTimer,
    focusTimerFeature: Feature.quiz,
  );
  await fixture.controller.start(fixture.startCommand);
  switch (transition) {
    case _FocusEntryTransition.start:
      clock.advance(const Duration(seconds: 1));
      break;
    case _FocusEntryTransition.resume:
      await fixture.controller.startFocusTimer(fixture.now);
      clock.advance(const Duration(seconds: 1));
      await fixture.controller.pauseFocusTimer(
        fixture.now.add(const Duration(seconds: 1)),
      );
      clock.advance(const Duration(seconds: 1));
      break;
  }
  return _FocusLifecycleRaceFixture(
    fixture: fixture,
    timeRepository: timeRepository,
    activeTime: activeTime,
    focusTimer: focusTimer,
    clock: clock,
  );
}

Future<void> _expectFocusSettlesBeforeBackground(
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final focusAction = race.beginBlockedTransition(transition);
  await race.timeRepository.blockedAppendStarted;

  race.clock.advance(const Duration(seconds: 1));
  final background = race.fixture.controller.pause(
    race.now,
    processBackground: true,
  );
  expect(race.timeRepository.maximumConcurrentAppends, 1);

  race.timeRepository.releaseBlockedAppend();
  await focusAction;
  await background;

  expect(race.fixture.controller.state.status, LessonSessionStatus.paused);
  expect(race.focusTimer.snapshot.status, FocusTimerStatus.paused);
  expect(
    race.focusTimer.snapshot.pauseReason,
    FocusTimerPauseReason.processBackground,
  );
  expect(race.activeTime.state, ActiveLearningTimeState.paused);
  expect(
    race.activeTime.captureSource,
    LearningTimeCaptureSource.automaticLesson,
  );
  expect(race.timeRepository.maximumConcurrentAppends, 1);
  race.fixture.controller.dispose();
}

Future<void> _expectFocusSettlesBeforeEmergencyOff(
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final focusAction = race.beginBlockedTransition(transition);
  await race.timeRepository.blockedAppendStarted;

  race.clock.advance(const Duration(seconds: 1));
  final emergencyOff = race.fixture.controller.disableFocusTimer(race.now);
  expect(race.timeRepository.maximumConcurrentAppends, 1);

  race.timeRepository.releaseBlockedAppend();
  await focusAction;
  await emergencyOff;

  expect(race.fixture.controller.state.status, LessonSessionStatus.active);
  expect(race.focusTimer.snapshot.status, FocusTimerStatus.paused);
  expect(
    race.focusTimer.snapshot.pauseReason,
    FocusTimerPauseReason.featureDisabled,
  );
  expect(race.activeTime.state, ActiveLearningTimeState.active);
  expect(
    race.activeTime.captureSource,
    LearningTimeCaptureSource.automaticLesson,
  );
  expect(race.timeRepository.maximumConcurrentAppends, 1);
  await expectLater(
    race.fixture.controller.resumeFocusTimer(race.now),
    throwsStateError,
  );
  expect(race.focusTimer.snapshot.status, FocusTimerStatus.paused);
  race.fixture.controller.dispose();
}

Future<void> _expectFocusSettlesBeforeTerminalFinish(
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final focusAction = race.beginBlockedTransition(transition);
  await race.timeRepository.blockedAppendStarted;

  race.clock.advance(const Duration(seconds: 1));
  final completion = race.fixture.controller.complete(race.now);
  expect(race.timeRepository.maximumConcurrentAppends, 1);

  race.timeRepository.releaseBlockedAppend();
  await focusAction;
  await completion;

  expect(race.fixture.controller.state.status, LessonSessionStatus.completed);
  expect(race.focusTimer.snapshot.status, FocusTimerStatus.finished);
  expect(race.activeTime.state, ActiveLearningTimeState.finished);
  expect(
    race.activeTime.captureSource,
    LearningTimeCaptureSource.automaticLesson,
  );
  expect(race.timeRepository.maximumConcurrentAppends, 1);
  race.fixture.controller.dispose();
}

Future<void> _expectFailedFocusSupersededByBackground(
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  race.timeRepository.failNextAppend = true;

  await expectLater(race.beginTransition(transition), throwsStateError);
  final frozenAutomaticAttempt = race.timeRepository.attempts.last;
  expect(
    frozenAutomaticAttempt.captureSource,
    LearningTimeCaptureSource.automaticLesson,
  );

  race.clock.advance(const Duration(seconds: 1));
  await race.fixture.controller.pause(race.now, processBackground: true);

  expect(race.fixture.controller.state.status, LessonSessionStatus.paused);
  expect(race.activeTime.state, ActiveLearningTimeState.paused);
  expect(
    race.timeRepository.attempts.where(
      (segment) => identical(segment, frozenAutomaticAttempt),
    ),
    hasLength(2),
  );
  expect(
    race.timeRepository.segments.where(
      (segment) => identical(segment, frozenAutomaticAttempt),
    ),
    hasLength(1),
  );

  race.clock.advance(const Duration(hours: 1));
  await race.fixture.controller.resume(race.now);
  race.clock.advance(const Duration(seconds: 1));
  final freshEntryAtUtc = race.now;
  await race.beginTransition(transition);
  expect(race.focusTimer.snapshot.lastTransitionAtUtc, freshEntryAtUtc);
  race.clock.advance(const Duration(seconds: 2));
  await race.fixture.controller.finishFocusTimer(race.now);

  _expectOnlyFreshFocusEffort(race, transition);
  expect(race.timeRepository.maximumConcurrentAppends, 1);
  expect(
    race.timeRepository.segments.every(
      (segment) => segment.activeDuration < const Duration(hours: 1),
    ),
    isTrue,
  );
  race.fixture.controller.dispose();
}

Future<void> _expectFailedFocusSupersededByGateBoundary(
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  race.timeRepository.failNextAppend = true;

  await expectLater(race.beginTransition(transition), throwsStateError);
  final frozenAutomaticAttempt = race.timeRepository.attempts.last;
  expect(
    frozenAutomaticAttempt.captureSource,
    LearningTimeCaptureSource.automaticLesson,
  );

  race.clock.advance(const Duration(seconds: 1));
  await race.fixture.controller.disableFocusTimer(race.now);

  expect(
    race.timeRepository.attempts.where(
      (segment) => identical(segment, frozenAutomaticAttempt),
    ),
    hasLength(2),
  );
  expect(
    race.timeRepository.segments.where(
      (segment) => identical(segment, frozenAutomaticAttempt),
    ),
    hasLength(1),
  );
  await expectLater(race.beginTransition(transition), throwsStateError);

  race.clock.advance(const Duration(hours: 1));
  race.fixture.controller.setFocusTimerGateEnabled(true);
  await race.fixture.controller.recordActiveLearningInteraction(race.now);
  race.clock.advance(const Duration(seconds: 1));
  final freshEntryAtUtc = race.now;
  await race.beginTransition(transition);
  expect(race.focusTimer.snapshot.lastTransitionAtUtc, freshEntryAtUtc);
  race.clock.advance(const Duration(seconds: 2));
  await race.fixture.controller.finishFocusTimer(race.now);

  _expectOnlyFreshFocusEffort(race, transition);
  expect(race.timeRepository.maximumConcurrentAppends, 1);
  race.fixture.controller.dispose();
}

void _expectOnlyFreshFocusEffort(
  _FocusLifecycleRaceFixture race,
  _FocusEntryTransition transition,
) {
  final focusDurations = race.timeRepository.segments
      .where(
        (segment) =>
            segment.captureSource == LearningTimeCaptureSource.focusTimer,
      )
      .map((segment) => segment.activeDuration);
  expect(
    focusDurations,
    transition == _FocusEntryTransition.start
        ? <Duration>[const Duration(seconds: 2)]
        : <Duration>[const Duration(seconds: 1), const Duration(seconds: 2)],
  );
  expect(
    race.focusTimer.snapshot.activeDuration,
    transition == _FocusEntryTransition.start
        ? const Duration(seconds: 2)
        : const Duration(seconds: 3),
  );
}

Future<void> _expectShellFocusRetryUsesExactIntent(
  WidgetTester tester,
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final registry = RuntimeFeatureRegistry(
    const BuildFeatureRegistry.allEnabled(),
  );
  addTearDown(registry.dispose);
  await _pumpFocusRaceShell(tester, race, registry);
  try {
    race.timeRepository.failNextAppend = true;
    final acceptedAtUtc = race.now;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('focus-timer/error')),
      findsOneWidget,
    );
    final frozenAutomaticAttempt = race.timeRepository.attempts.last;
    race.clock.advance(const Duration(seconds: 1));

    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();

    expect(race.focusTimer.snapshot.status, FocusTimerStatus.running);
    expect(race.focusTimer.snapshot.lastTransitionAtUtc, acceptedAtUtc);
    expect(
      race.timeRepository.attempts.where(
        (segment) => identical(segment, frozenAutomaticAttempt),
      ),
      hasLength(2),
    );

    race.clock.advance(const Duration(minutes: 4, seconds: 59));
    await tester.tap(
      find.byKey(const ValueKey<String>('lesson-body/interaction')),
    );
    await tester.pumpAndSettle();
    race.clock.advance(const Duration(minutes: 2));
    await tester.tap(find.byKey(const ValueKey<String>('focus-timer/finish')));
    await tester.pumpAndSettle();

    expect(race.focusTimer.snapshot.status, FocusTimerStatus.finished);
    expect(
      race.focusTimer.snapshot.activeDuration,
      transition == _FocusEntryTransition.start
          ? const Duration(minutes: 7)
          : const Duration(minutes: 7, seconds: 1),
    );
    expect(race.timeRepository.maximumConcurrentAppends, 1);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    race.fixture.controller.dispose();
  }
}

Future<void> _expectShellFailedFocusSettlesAcrossGate(
  WidgetTester tester,
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final registry = RuntimeFeatureRegistry(
    const BuildFeatureRegistry.allEnabled(),
  );
  addTearDown(registry.dispose);
  await _pumpFocusRaceShell(tester, race, registry);
  try {
    race.timeRepository.failNextAppend = true;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();
    final frozenAutomaticAttempt = race.timeRepository.attempts.last;

    race.clock.advance(const Duration(seconds: 1));
    registry.emergencyOff(Feature.quiz);
    await tester.pumpAndSettle();

    expect(find.byType(FocusTimerWidget), findsNothing);
    expect(
      race.timeRepository.attempts.where(
        (segment) => identical(segment, frozenAutomaticAttempt),
      ),
      hasLength(2),
    );
    expect(
      race.activeTime.captureSource,
      LearningTimeCaptureSource.automaticLesson,
    );

    race.clock.advance(const Duration(hours: 1));
    registry.setOverride(Feature.quiz, FeatureState.enabled);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('lesson-body/interaction')),
    );
    await tester.pumpAndSettle();
    race.clock.advance(const Duration(seconds: 1));
    final freshEntryAtUtc = race.now;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();

    expect(race.focusTimer.snapshot.status, FocusTimerStatus.running);
    expect(race.focusTimer.snapshot.lastTransitionAtUtc, freshEntryAtUtc);
    race.clock.advance(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey<String>('focus-timer/finish')));
    await tester.pumpAndSettle();
    _expectOnlyFreshFocusEffort(race, transition);
    expect(race.timeRepository.maximumConcurrentAppends, 1);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    race.fixture.controller.dispose();
  }
}

Future<void> _expectShellContentSupersedesFailedEntry(
  WidgetTester tester,
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final registry = RuntimeFeatureRegistry(
    const BuildFeatureRegistry.allEnabled(),
  );
  addTearDown(registry.dispose);
  await _pumpFocusRaceShell(tester, race, registry);
  try {
    race.timeRepository.failNextAppend = true;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();
    final frozenAutomaticAttempt = race.timeRepository.attempts.last;

    race.clock.advance(const Duration(hours: 1));
    await tester.tap(
      find.byKey(const ValueKey<String>('lesson-body/interaction')),
    );
    await tester.pumpAndSettle();

    expect(race.activeTime.state, ActiveLearningTimeState.active);
    expect(
      race.activeTime.captureSource,
      LearningTimeCaptureSource.automaticLesson,
    );
    expect(
      race.timeRepository.attempts.where(
        (segment) => identical(segment, frozenAutomaticAttempt),
      ),
      hasLength(2),
    );

    race.clock.advance(const Duration(seconds: 2));
    final freshEntryAtUtc = race.now;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();
    expect(race.focusTimer.snapshot.status, FocusTimerStatus.running);
    expect(race.focusTimer.snapshot.lastTransitionAtUtc, freshEntryAtUtc);

    race.clock.advance(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey<String>('focus-timer/finish')));
    await tester.pumpAndSettle();

    _expectAllCaptureSegments(
      race,
      transition,
      automaticAfterSettlement: const Duration(seconds: 2),
    );
    expect(race.timeRepository.maximumConcurrentAppends, 1);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    race.fixture.controller.dispose();
  }
}

Future<void> _expectShellImeSupersedesBeforeEmergencyOff(
  WidgetTester tester,
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  final registry = RuntimeFeatureRegistry(
    const BuildFeatureRegistry.allEnabled(),
  );
  addTearDown(registry.dispose);
  await _pumpFocusRaceShell(tester, race, registry);
  try {
    race.timeRepository.failNextAppend = true;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();

    race.clock.advance(const Duration(hours: 1));
    await tester.enterText(
      find.byKey(const ValueKey<String>('lesson-body/ime')),
      'learner evidence',
    );
    await tester.pumpAndSettle();
    expect(race.activeTime.state, ActiveLearningTimeState.active);

    race.clock.advance(const Duration(seconds: 2));
    registry.emergencyOff(Feature.quiz);
    await tester.pumpAndSettle();
    expect(race.activeTime.state, ActiveLearningTimeState.active);
    expect(find.byType(FocusTimerWidget), findsNothing);

    race.clock.advance(const Duration(seconds: 2));
    registry.setOverride(Feature.quiz, FeatureState.enabled);
    await tester.pumpAndSettle();
    final freshEntryAtUtc = race.now;
    await tester.tap(find.byKey(_focusEntryKey(transition)));
    await tester.pumpAndSettle();
    expect(race.focusTimer.snapshot.lastTransitionAtUtc, freshEntryAtUtc);

    race.clock.advance(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey<String>('focus-timer/finish')));
    await tester.pumpAndSettle();

    _expectAllCaptureSegments(
      race,
      transition,
      automaticAfterSettlement: const Duration(seconds: 4),
    );
    expect(race.timeRepository.maximumConcurrentAppends, 1);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    race.fixture.controller.dispose();
  }
}

Future<void> _expectEmergencyOffWaitsForInteraction(
  _FocusEntryTransition transition,
) async {
  final race = await _focusLifecycleRaceFixture(transition);
  race.timeRepository.failNextAppend = true;
  await expectLater(race.beginTransition(transition), throwsStateError);
  final frozenAutomaticAttempt = race.timeRepository.attempts.last;

  race.clock.advance(const Duration(hours: 1));
  await race.fixture.controller.disableFocusTimer(race.now);

  expect(race.activeTime.state, ActiveLearningTimeState.paused);
  expect(
    race.activeTime.captureSource,
    LearningTimeCaptureSource.automaticLesson,
  );
  expect(
    race.timeRepository.attempts.where(
      (segment) => identical(segment, frozenAutomaticAttempt),
    ),
    hasLength(2),
  );
  _expectSettledEntrySegmentsOnly(race, transition);

  race.clock.advance(const Duration(hours: 1));
  await race.fixture.controller.recordActiveLearningInteraction(race.now);
  expect(race.activeTime.state, ActiveLearningTimeState.active);
  _expectSettledEntrySegmentsOnly(race, transition);

  race.clock.advance(const Duration(seconds: 2));
  race.fixture.controller.setFocusTimerGateEnabled(true);
  final freshEntryAtUtc = race.now;
  await race.beginTransition(transition);
  expect(race.focusTimer.snapshot.lastTransitionAtUtc, freshEntryAtUtc);
  race.clock.advance(const Duration(seconds: 3));
  await race.fixture.controller.finishFocusTimer(race.now);

  _expectAllCaptureSegments(
    race,
    transition,
    automaticAfterSettlement: const Duration(seconds: 2),
  );
  expect(race.timeRepository.maximumConcurrentAppends, 1);
  race.fixture.controller.dispose();
}

void _expectSettledEntrySegmentsOnly(
  _FocusLifecycleRaceFixture race,
  _FocusEntryTransition transition,
) {
  final expected = transition == _FocusEntryTransition.start
      ? <(LearningTimeCaptureSource, Duration)>[
          (
            LearningTimeCaptureSource.automaticLesson,
            const Duration(seconds: 1),
          ),
        ]
      : <(LearningTimeCaptureSource, Duration)>[
          (LearningTimeCaptureSource.focusTimer, const Duration(seconds: 1)),
          (
            LearningTimeCaptureSource.automaticLesson,
            const Duration(seconds: 1),
          ),
        ];
  expect(_captureSegments(race), expected);
}

void _expectAllCaptureSegments(
  _FocusLifecycleRaceFixture race,
  _FocusEntryTransition transition, {
  required Duration automaticAfterSettlement,
}) {
  final expected = <(LearningTimeCaptureSource, Duration)>[
    if (transition == _FocusEntryTransition.resume)
      (LearningTimeCaptureSource.focusTimer, const Duration(seconds: 1)),
    (LearningTimeCaptureSource.automaticLesson, const Duration(seconds: 1)),
    (LearningTimeCaptureSource.automaticLesson, automaticAfterSettlement),
    (LearningTimeCaptureSource.focusTimer, const Duration(seconds: 3)),
  ];
  expect(_captureSegments(race), expected);
  expect(
    race.timeRepository.segments.any(
      (segment) => segment.activeDuration >= const Duration(hours: 1),
    ),
    isFalse,
  );
}

List<(LearningTimeCaptureSource, Duration)> _captureSegments(
  _FocusLifecycleRaceFixture race,
) => race.timeRepository.segments
    .map((segment) => (segment.captureSource, segment.activeDuration))
    .toList(growable: false);

Future<void> _pumpFocusRaceShell(
  WidgetTester tester,
  _FocusLifecycleRaceFixture race,
  RuntimeFeatureRegistry registry,
) => tester.pumpWidget(
  AppDependenciesScope(
    dependencies: _bookmarkDependencies(
      race.fixture.database,
      features: registry,
    ),
    child: MaterialApp(
      home: UnifiedLessonShell(
        controller: race.fixture.controller,
        nowUtc: () => race.now,
        lifecycleStateReader: () => AppLifecycleState.resumed,
        builder: (context) => Material(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('lesson-body/interaction'),
                  onPressed: () {},
                  child: const Text('Lesson interaction'),
                ),
                TextField(
                  key: const ValueKey<String>('lesson-body/ime'),
                  onChanged: (_) => UnifiedLessonSessionLifecycleScope.maybeOf(
                    context,
                  )?.recordInteraction(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

ValueKey<String> _focusEntryKey(_FocusEntryTransition transition) =>
    ValueKey<String>(
      transition == _FocusEntryTransition.start
          ? 'focus-timer/start'
          : 'focus-timer/resume',
    );

final class _MemoryLearningTimeRepository implements LearningTimeRepository {
  final segments = <LearningTimeSegment>[];
  final attempts = <LearningTimeSegment>[];
  bool failActiveDuration = false;
  bool failNextAppend = false;
  bool loseNextAppendAcknowledgement = false;
  bool _blockNextAppend = false;
  Completer<void>? _blockedAppendStarted;
  Completer<void>? _blockedAppendRelease;
  int _concurrentAppends = 0;
  int maximumConcurrentAppends = 0;

  Future<void> get blockedAppendStarted {
    final started = _blockedAppendStarted;
    if (started == null) {
      throw StateError('no append was prepared for blocking');
    }
    return started.future;
  }

  void blockNextAppend() {
    if (_blockNextAppend ||
        (_blockedAppendRelease != null &&
            !_blockedAppendRelease!.isCompleted)) {
      throw StateError('an append is already blocked');
    }
    _blockNextAppend = true;
    _blockedAppendStarted = Completer<void>();
    _blockedAppendRelease = Completer<void>();
  }

  void releaseBlockedAppend() {
    final release = _blockedAppendRelease;
    if (release == null || release.isCompleted) {
      throw StateError('no append is blocked');
    }
    release.complete();
  }

  @override
  Future<void> append(LearningTimeSegment segment) async {
    attempts.add(segment);
    _concurrentAppends += 1;
    if (_concurrentAppends > maximumConcurrentAppends) {
      maximumConcurrentAppends = _concurrentAppends;
    }
    try {
      if (_blockNextAppend) {
        _blockNextAppend = false;
        _blockedAppendStarted!.complete();
        await _blockedAppendRelease!.future;
      }
      if (failNextAppend) {
        failNextAppend = false;
        throw StateError('injected time append failure');
      }
      final existing = segments.where(
        (candidate) => candidate.id == segment.id,
      );
      if (existing.isNotEmpty) {
        if (existing.single != segment) {
          throw StateError('time replay mismatch');
        }
        return;
      }
      segments.add(segment);
      if (loseNextAppendAcknowledgement) {
        loseNextAppendAcknowledgement = false;
        throw StateError('injected post-write time acknowledgement loss');
      }
    } finally {
      _concurrentAppends -= 1;
    }
  }

  @override
  Future<Duration> activeDuration(String sessionId) async {
    if (failActiveDuration) {
      failActiveDuration = false;
      throw StateError('injected time start failure');
    }
    return Duration(
      milliseconds: segments
          .where((segment) => segment.sessionId == sessionId)
          .fold<int>(
            0,
            (sum, segment) => sum + segment.activeDuration.inMilliseconds,
          ),
    );
  }
}

final class _HintAdapter implements HintSupportingLessonModeAdapter {
  int classifyCalls = 0;

  @override
  HintPolicy get hintPolicy => HintPolicy.staged(
    strategy: 'Look for the familiar word family.',
    context: 'The sentence is about rail travel.',
  );

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    classifyCalls += 1;
    return support.evidenceContext;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      LessonItem(id: 'hint-item-${cursor.index}');
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
    required this.failFinish,
    required this.blockAbandon,
    required this.failAbandon,
  });

  final DriftLearningRepository delegate;
  final bool failAfterFirstRecord;
  final bool blockRecord;
  final bool blockFinish;
  final bool failFinish;
  final bool blockAbandon;
  final bool failAbandon;
  final Completer<void> recordStarted = Completer<void>();
  final Completer<void> finishStarted = Completer<void>();
  final Completer<void> abandonStarted = Completer<void>();
  final Completer<void> _recordRelease = Completer<void>();
  final Completer<void> _finishRelease = Completer<void>();
  final Completer<void> _abandonRelease = Completer<void>();
  int recordCalls = 0;
  int replayCalls = 0;
  int finishCalls = 0;
  int scopedAbandonCalls = 0;
  int bulkAbandonCalls = 0;
  RecordAnswerCommand? lastRecordCommand;
  final List<RecordAnswerCommand> recordCommands = <RecordAnswerCommand>[];
  bool _lostAckSent = false;
  bool failNextFinish = false;
  bool loseNextFinishAcknowledgement = false;

  void releaseRecord() {
    if (!_recordRelease.isCompleted) _recordRelease.complete();
  }

  void releaseFinish() {
    if (!_finishRelease.isCompleted) _finishRelease.complete();
  }

  void releaseAbandon() {
    if (!_abandonRelease.isCompleted) _abandonRelease.complete();
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
    lastRecordCommand = command;
    recordCommands.add(command);
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
    if (failNextFinish) {
      failNextFinish = false;
      throw StateError('injected finish failure');
    }
    if (failFinish) throw StateError('finish failed');
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    if (loseNextFinishAcknowledgement) {
      loseNextFinishAcknowledgement = false;
      throw StateError('injected post-write close acknowledgement loss');
    }
    return result;
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
  }) async {
    scopedAbandonCalls += 1;
    if (!abandonStarted.isCompleted) abandonStarted.complete();
    if (blockAbandon) await _abandonRelease.future;
    if (failAbandon) throw StateError('abandon failed');
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
