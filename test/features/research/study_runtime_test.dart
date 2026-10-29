import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/study_runtime_harness.dart';

Matcher studyDenied([ResearchCaptureReason? reason]) => throwsA(
  reason == null
      ? isA<ResearchCaptureDenied>()
      : isA<ResearchCaptureDenied>().having(
          (error) => error.reason,
          'reason',
          reason,
        ),
);

final class _MutationProbe {
  _MutationProbe(StudyRuntimeFixture fixture, StudyReadQueries queries) {
    queries.afterSelect = (executor, statement) {
      if (statement.contains('committed-study-notifier')) {
        transactionQueries.add(executor is drift.TransactionExecutor);
      }
    };
    fixture.onLocalMutation = () {
      calls++;
      pending.add(
        fixture.database
            .customSelect(
              'SELECT id FROM learning_sessions /* committed-study-notifier */',
            )
            .get()
            .then<void>(
              (rows) {
                sessionCounts.add(rows.length);
              },
              onError: (Object error, StackTrace stack) {
                errors.add(error);
              },
            ),
      );
    };
  }

  int calls = 0;
  final transactionQueries = <bool>[];
  final sessionCounts = <int>[];
  final errors = <Object>[];
  final pending = <Future<void>>[];
  Future<void> drain() async {
    await Future.wait(pending);
  }
}

void main() {
  late StudyRuntimeFixture fixture;
  var fixtureClosed = false;
  setUp(() => fixtureClosed = false);
  tearDown(() async {
    if (!fixtureClosed) await fixture.database.close();
  });

  test(
    'Study start notifies only committed rows outside the inherited transaction',
    () async {
      final queries = StudyReadQueries();
      fixture = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
      );
      final ready = await fixture.ready();
      final probe = _MutationProbe(fixture, queries);
      final accepted = await fixture.runtime.startIndex(
        fixture.ownerId,
        ready.opportunity!.id,
        stillVisible: () => true,
      );
      await probe.drain();
      expect(probe.calls, 1);
      expect(probe.transactionQueries, [false]);
      expect(probe.sessionCounts, [1]);
      expect(probe.errors, isEmpty);
      final before = await fixture.researchRows();
      await fixture.runtime.startIndex(
        fixture.ownerId,
        ready.opportunity!.id,
        stillVisible: () => true,
      );
      await probe.drain();
      expect(probe.calls, 1);
      expect(await fixture.researchRows(), before);
      expect(
        (await fixture.runtime.load(fixture.ownerId)).index!.sessionId,
        accepted.sessionId,
      );
    },
  );

  for (final denial in ['visibility', 'authority']) {
    test(
      'final $denial rollback emits zero mutation notifications or business rows',
      () async {
        final queries = StudyReadQueries();
        fixture = await StudyRuntimeFixture.open(
          database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
        );
        final ready = await fixture.ready();
        final before = await fixture.researchRows();
        final probe = _MutationProbe(fixture, queries);
        var changed = false;
        var visible = true;
        fixture.participation.states.onRead = (_) async {
          if (!changed &&
              (await fixture.rows('learning_sessions')).isNotEmpty) {
            changed = true;
            if (denial == 'visibility') {
              visible = false;
            } else {
              fixture.participation.states.revoked = true;
            }
          }
        };
        await expectLater(
          fixture.runtime.startIndex(
            fixture.ownerId,
            ready.opportunity!.id,
            stillVisible: () => visible,
          ),
          studyDenied(),
        );
        await probe.drain();
        expect(changed, isTrue);
        expect(probe.calls, 0);
        expect(probe.transactionQueries, isEmpty);
        expect(probe.errors, isEmpty);
        expect(await fixture.researchRows(), before);
      },
    );
  }

  test(
    'completion repair notifies zero ordinary mutations and retains original ordinary facts',
    () async {
      final queries = StudyReadQueries();
      fixture = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
      );
      final first = await fixture.start();
      await fixture.database.customStatement(
        "CREATE TRIGGER deny_notify_completion BEFORE INSERT ON events_v2 WHEN NEW.event_type = '$measurementMissionCompletedEventType' BEGIN SELECT RAISE(ABORT, 'synthetic unavailable'); END",
      );
      final finished = await fixture.finish(first);
      final ordinary = {
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'srs_states',
          'achievement_unlocks',
          'outbox_operations',
          'reward_transactions',
          'points_ledger_entries',
        ])
          table: await fixture.rows(table),
      };
      await fixture.database.customStatement(
        'DROP TRIGGER deny_notify_completion',
      );
      final probe = _MutationProbe(fixture, queries);
      final resumed = await fixture.runtime.resumeIndex(fixture.ownerId);
      await probe.drain();
      expect(resumed.endedAtUtc, finished.endedAtUtc);
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.post,
      );
      expect(probe.calls, 0);
      expect(probe.transactionQueries, isEmpty);
      expect(probe.errors, isEmpty);
      for (final table in ordinary.keys) {
        expect(await fixture.rows(table), ordinary[table]);
      }
      expect(await fixture.rows('events_v2'), hasLength(3));
    },
  );

  for (final change in ['expiry', 'revocation']) {
    test(
      'late $change after Presented repository validation rolls back all new exposure facts',
      () async {
        fixture = await StudyRuntimeFixture.open();
        await fixture.baseline();
        final opened = await fixture.runtime.openPresentation(
          fixture.ownerId,
          entryAttemptId: studyEntryId,
        );
        final before = await fixture.researchRows();
        var repositoryValidated = false;
        var changed = false;
        fixture.participation.states.onRead = (_) async {
          if (repositoryValidated && !changed) {
            changed = true;
            if (change == 'expiry') {
              fixture.participation.clock.now =
                  fixture.participation.current.expiresAtUtc;
            } else {
              fixture.participation.states.revoked = true;
            }
          }
        };
        await expectLater(
          fixture.runtime.recordPresented(
            fixture.ownerId,
            opened.opportunity!.id,
            stillVisible: () {
              repositoryValidated = true;
              return true;
            },
          ),
          studyDenied(),
        );
        expect(repositoryValidated, isTrue);
        expect(changed, isTrue);
        expect(await fixture.researchRows(), before);
      },
    );
  }

  test(
    'Presented replay cannot acknowledge an unavailable incomplete completion snapshot',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final first = await fixture.start();
      await fixture.database.customStatement(
        "CREATE TRIGGER deny_ack_completion BEFORE INSERT ON events_v2 WHEN NEW.event_type = '$measurementMissionCompletedEventType' BEGIN SELECT RAISE(ABORT, 'synthetic unavailable'); END",
      );
      await fixture.finish(first);
      final unavailable = await fixture.runtime.load(fixture.ownerId);
      expect(unavailable.phase, StudyPhase.unavailable);
      expect(unavailable.reason, ResearchCaptureReason.incomplete);
      final before = await fixture.researchRows();
      await expectLater(
        fixture.runtime.recordPresented(
          fixture.ownerId,
          unavailable.opportunity!.id,
          stillVisible: () => true,
        ),
        studyDenied(ResearchCaptureReason.incomplete),
      );
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'synchronous composition performs no IO and uses the one canonical writer',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final before = await fixture.researchRows();
      final calls = fixture.participation.operations.calls;
      final getters = fixture.learningGetterCalls;
      final composed = fixture.newRuntime();
      expect(fixture.learningGetterCalls, getters);
      expect(fixture.participation.operations.calls, calls);
      expect(await fixture.researchRows(), before);
      expect(identical(fixture.runtime.learning, fixture.learning), isTrue);
      expect(
        identical(fixture.runtime.lifecycleObserver.database, fixture.database),
        isTrue,
      );
      expect(() => composed.learning, throwsStateError);
    },
  );

  test(
    'eligible availability is read-only even when SQL mutations are forbidden',
    () async {
      final queries = StudyReadQueries();
      fixture = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
      );
      final before = await fixture.researchRows();
      queries.rejectWrites = true;
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.baseline);
      expect(view.run, isNull);
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'active index availability parses exact stored plan without SQL writes',
    () async {
      final queries = StudyReadQueries();
      fixture = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
      );
      final first = await fixture.start();
      final before = await fixture.researchRows();
      queries.rejectWrites = true;
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.activeIndex);
      expect(
        view.index!.plan.stableSerialization,
        first.plan.stableSerialization,
      );
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'disabled runtime never consults authority or creates study rows',
    () async {
      fixture = await StudyRuntimeFixture.open(enabled: false);
      final calls = fixture.participation.operations.calls;
      final before = await fixture.researchRows();
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      expect(fixture.participation.operations.calls, calls);
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'available signed source document is not silently imported or admitted',
    () async {
      fixture = await StudyRuntimeFixture.open(admitted: false);
      final before = await fixture.researchRows();
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      await expectLater(fixture.runtime.begin(fixture.ownerId), studyDenied());
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'missing owner availability never creates a replacement guest',
    () async {
      fixture = await StudyRuntimeFixture.open(admitted: false);
      await fixture.database.customStatement('DELETE FROM vocabulary_words');
      await fixture.database.customStatement(
        'DELETE FROM vocabulary_categories',
      );
      await fixture.database.customStatement('DELETE FROM research_consents');
      await fixture.database.customStatement('DELETE FROM local_owners');
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      expect(await fixture.rows('local_owners'), isEmpty);
    },
  );

  test(
    'nonparticipants retain ordinary configured learning and zero research artifacts',
    () async {
      fixture = await StudyRuntimeFixture.open(admitted: false);
      final beforeOperations = fixture.participation.operations.calls;
      final launch = await fixture.learning.prepareConfiguredQuiz(
        configuration: fixture.catalog.configuration,
        expectedOwnerId: fixture.ownerId,
      );
      final ordinary = await fixture.learning.startConfiguredQuiz(launch);
      await fixture.finish(ordinary);
      expect(await fixture.rows('motivation_measurement_runs'), isEmpty);
      expect(await fixture.rows('motivation_responses'), isEmpty);
      expect(await fixture.rows('measurement_opportunities'), isEmpty);
      expect(await fixture.rows('events_v2'), isEmpty);
      expect(await fixture.rows('research_participation_permits'), isEmpty);
      expect(await fixture.rows('experiment_assignments'), isEmpty);
      expect(fixture.participation.operations.calls, beforeOperations);
      expect(await fixture.rows('answer_attempts'), hasLength(1));
      expect(await fixture.rows('srs_states'), hasLength(1));
      expect(await fixture.rows('outbox_operations'), hasLength(3));
    },
  );

  test('begin retry retains exact run identity and original time', () async {
    fixture = await StudyRuntimeFixture.open();
    final first = await fixture.runtime.begin(fixture.ownerId);
    final before = await fixture.rows('motivation_measurement_runs');
    fixture.participation.clock.now = participationStart.add(
      const Duration(seconds: 10),
    );
    final replay = await fixture.runtime.begin(fixture.ownerId);
    expect(replay.run!.id, first.run!.id);
    expect(replay.run!.startedAtUtc, participationStart);
    expect(await fixture.rows('motivation_measurement_runs'), before);
    expect(await fixture.rows('measurement_opportunities'), isEmpty);
    expect(await fixture.rows('events_v2'), isEmpty);
  });

  test(
    'incomplete baseline cannot open an opportunity or start an index',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.runtime.begin(fixture.ownerId);
      await expectLater(
        fixture.runtime.openPresentation(
          fixture.ownerId,
          entryAttemptId: studyEntryId,
        ),
        studyDenied(ResearchCaptureReason.incomplete),
      );
      expect(await fixture.rows('measurement_opportunities'), isEmpty);
      expect(await fixture.rows('learning_sessions'), isEmpty);
    },
  );

  for (final treatment in TodayExperiencePresentation.values) {
    test(
      '${treatment.name} keeps its fixed signed treatment through actual mission completion',
      () async {
        fixture = await StudyRuntimeFixture.open(treatment: treatment);
        final first = await fixture.start();
        expect(first.activityType, 'sourcePractice');
        expect(first.plan.mode, 'meaning-quiz');
        expect(first.plan.id, isNot(first.sessionId));
        final finished = await fixture.finish(first);
        final post = await fixture.runtime.load(fixture.ownerId);
        expect(post.phase, StudyPhase.post);
        expect(post.index!.sessionId, first.sessionId);
        expect(post.index!.endedAtUtc, finished.endedAtUtc);
        expect(post.opportunity!.assignedTreatment, treatment);
        expect(post.opportunity!.effectivePresentation, treatment);
        for (final event in await fixture.rows('events_v2')) {
          final payload = jsonDecode(event['payload_json']! as String) as Map;
          expect(payload['assignedTreatment'], treatment.wireName);
          expect(payload['effectivePresentation'], treatment.wireName);
          if (event['event_type'] == measurementMissionStartedEventType) {
            expect(payload['planId'], first.plan.id);
            expect(payload['mode'], first.plan.mode);
          }
        }
        await fixture.runtime
            .measurementsFor(fixture.ownerId)
            .record(
              MotivationResponse(
                ownerId: fixture.ownerId,
                runId: post.run!.id,
                itemId: 'synthetic-post',
                responseCode: 'low',
              ),
            );
        expect(
          (await fixture.runtime.load(fixture.ownerId)).phase,
          StudyPhase.completed,
        );
        expect(await fixture.rows('events_v2'), hasLength(3));
        expect(await fixture.rows('answer_attempts'), hasLength(1));
        expect(await fixture.rows('srs_states'), hasLength(1));
        expect(await fixture.rows('achievement_unlocks'), hasLength(2));
        expect(await fixture.rows('reward_transactions'), isEmpty);
        final outbox = await fixture.rows('outbox_operations');
        expect(outbox.map((r) => r['entity_type']).toSet(), {
          'attempt',
          'srsState',
          'achievementUnlock',
        });
        expect(outbox, hasLength(3));
      },
    );
  }

  test(
    'missing supplied Adventure dependency is unavailable without substituting Standard',
    () async {
      fixture = await StudyRuntimeFixture.open(
        treatment: TodayExperiencePresentation.adventure,
        presentations: {TodayExperiencePresentation.standard},
      );
      final before = await fixture.researchRows();
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.unavailable);
      expect(view.reason, ResearchCaptureReason.invalidInput);
      await expectLater(fixture.runtime.begin(fixture.ownerId), studyDenied());
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'one unpresented opening resumes only its exact entry identity',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.baseline();
      final first = await fixture.runtime.openPresentation(
        fixture.ownerId,
        entryAttemptId: studyEntryId,
      );
      fixture.restartRuntime();
      final replay = await fixture.runtime.openPresentation(
        fixture.ownerId,
        entryAttemptId: studyEntryId,
      );
      expect(replay.opportunity!.id, first.opportunity!.id);
      expect(replay.opportunity!.openedAtUtc, first.opportunity!.openedAtUtc);
      await expectLater(
        fixture.runtime.openPresentation(
          fixture.ownerId,
          entryAttemptId: otherStudyEntryId,
        ),
        studyDenied(ResearchCaptureReason.identityConflict),
      );
      expect(await fixture.rows('measurement_opportunities'), hasLength(1));
      expect(await fixture.rows('events_v2'), isEmpty);
    },
  );

  test(
    'two unpresented openings fail closed instead of choosing the latest',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.baseline();
      final first = await fixture.runtime.openPresentation(
        fixture.ownerId,
        entryAttemptId: studyEntryId,
      );
      final measurements =
          fixture.runtime.measurementsFor(fixture.ownerId)
              as DriftMotivationMeasurementRepository;
      await DriftMeasurementOpportunityRepository(
        fixture.database,
        measurements: measurements,
        timing: measurements.timing as DriftMotivationMeasurementTimingReader,
      ).open(
        ownerId: fixture.ownerId,
        measurementRunId: first.run!.id,
        entryAttemptId: otherStudyEntryId,
        effectivePresentation: TodayExperiencePresentation.standard,
      );
      final before = await fixture.researchRows();
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.unavailable);
      expect(view.reason, ResearchCaptureReason.identityConflict);
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'Presented lost ACK replay keeps exact facts and no extra rows',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final first = await fixture.ready();
      final before = await fixture.researchRows();
      fixture.participation.clock.now = participationStart.add(
        const Duration(minutes: 2),
      );
      final replay = await fixture.runtime.recordPresented(
        fixture.ownerId,
        first.opportunity!.id,
        stillVisible: () => true,
      );
      expect(
        replay.opportunity!.presentation!.occurredAtUtc,
        first.opportunity!.presentation!.occurredAtUtc,
      );
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'hidden binding after real Ed await rolls back Presented and opportunity projection',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.baseline();
      final opened = await fixture.runtime.openPresentation(
        fixture.ownerId,
        entryAttemptId: studyEntryId,
      );
      final before = await fixture.researchRows();
      final reached = Completer<void>();
      final release = Completer<void>();
      var paused = false;
      var visible = true;
      fixture.participation.states.onRead = (_) async {
        if (!paused && (await fixture.rows('events_v2')).isNotEmpty) {
          paused = true;
          reached.complete();
          await release.future;
        }
      };
      final pending = fixture.runtime.recordPresented(
        fixture.ownerId,
        opened.opportunity!.id,
        stillVisible: () => visible,
      );
      final rejected = expectLater(
        pending,
        studyDenied(ResearchCaptureReason.sessionUnavailable),
      );
      await reached.future;
      visible = false;
      release.complete();
      await rejected;
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'hidden Study start after signed recheck leaves no accepted session or Mission',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final ready = await fixture.ready();
      fixture.participation.clock.now = participationStart.add(
        const Duration(minutes: 2),
      );
      final before = await fixture.researchRows();
      final reached = Completer<void>();
      final release = Completer<void>();
      var paused = false;
      var visible = true;
      fixture.participation.states.onRead = (_) async {
        if (!paused && (await fixture.rows('learning_sessions')).isNotEmpty) {
          paused = true;
          reached.complete();
          await release.future;
        }
      };
      final pending = fixture.runtime.startIndex(
        fixture.ownerId,
        ready.opportunity!.id,
        stillVisible: () => visible,
      );
      final rejected = expectLater(pending, studyDenied());
      await reached.future;
      visible = false;
      release.complete();
      await rejected;
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'read-only load rejects owner replacement during real signed authority await',
    () async {
      fixture = await StudyRuntimeFixture.open();
      var changed = false;
      fixture.participation.states.onRead = (_) async {
        if (!changed) {
          changed = true;
          await fixture.switchOwner();
        }
      };
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.unavailable);
      expect(await fixture.rows('motivation_measurement_runs'), isEmpty);
      expect(await fixture.rows('measurement_opportunities'), isEmpty);
    },
  );

  test(
    'active owner B never receives owner A authority pins or session',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.start();
      await fixture.switchOwner();
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      expect(
        (await fixture.runtime.load('owner-b')).phase,
        StudyPhase.unavailable,
      );
      final repository =
          fixture.runtime.measurementsFor('owner-b')
              as DriftMotivationMeasurementRepository;
      expect(
        repository
            .participation
            .assignments
            .authorizer
            .requirements
            .assignmentId,
        experimentAssignmentId(
          ownerId: 'owner-b',
          experimentId: 'synthetic-experiment',
          experimentVersion: 2,
        ),
      );
      expect(await fixture.rows('learning_sessions'), hasLength(1));
    },
  );

  test(
    'restart and repeated start resume the first exact plan and index',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final first = await fixture.start();
      final before = await fixture.researchRows();
      fixture.restartRuntime();
      final view = await fixture.runtime.load(fixture.ownerId);
      final resumed = await fixture.runtime.resumeIndex(fixture.ownerId);
      final retried = await fixture.runtime.startIndex(
        fixture.ownerId,
        view.opportunity!.id,
        stillVisible: () => true,
      );
      expect(resumed.sessionId, first.sessionId);
      expect(resumed.startedAtUtc, first.startedAtUtc);
      expect(resumed.plan.stableSerialization, first.plan.stableSerialization);
      expect(retried.sessionId, first.sessionId);
      expect(await fixture.researchRows(), before);
    },
  );

  test('concurrent launch retry accepts one first persisted plan', () async {
    fixture = await StudyRuntimeFixture.open();
    final ready = await fixture.ready();
    fixture.participation.clock.now = participationStart.add(
      const Duration(minutes: 2),
    );
    final results = await Future.wait([
      fixture.runtime.startIndex(
        fixture.ownerId,
        ready.opportunity!.id,
        stillVisible: () => true,
      ),
      fixture.runtime.startIndex(
        fixture.ownerId,
        ready.opportunity!.id,
        stillVisible: () => true,
      ),
    ]);
    expect(results.first.sessionId, results.last.sessionId);
    expect(
      results.first.plan.stableSerialization,
      results.last.plan.stableSerialization,
    );
    expect(await fixture.rows('learning_sessions'), hasLength(1));
    expect(await fixture.rows('events_v2'), hasLength(2));
  });

  for (final activity in ['quiz', 'shadowing']) {
    test(
      'legacy $activity first acceptance leaves a gap and no later replacement',
      () async {
        fixture = await StudyRuntimeFixture.open();
        final ready = await fixture.ready();
        await fixture.repository.startSession(
          LearningSessionDraft(
            id: 'legacy-first',
            ownerId: fixture.ownerId,
            activityType: activity,
            startedAtUtc: participationStart.add(const Duration(minutes: 2)),
            appVersion: fixture.learning.buildInfo.version,
            buildId: fixture.learning.buildInfo.buildId,
          ),
        );
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 3),
        );
        final before = await fixture.researchRows();
        expect(
          (await fixture.runtime.load(fixture.ownerId)).phase,
          StudyPhase.unavailable,
        );
        await expectLater(
          fixture.runtime.startIndex(
            fixture.ownerId,
            ready.opportunity!.id,
            stillVisible: () => true,
          ),
          studyDenied(),
        );
        expect(await fixture.researchRows(), before);
        expect(await fixture.rows('learning_sessions'), hasLength(1));
        expect(await fixture.rows('events_v2'), hasLength(1));
      },
    );
  }

  test(
    'abandoned first configured index stays stopped and is never replaced',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final first = await fixture.start();
      await fixture.learning.abandonQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: fixture.ownerId,
        expectedRevision: first.checkpointRevision,
      );
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.stopped);
      expect(view.index!.sessionId, first.sessionId);
      await expectLater(
        fixture.runtime.startIndex(
          fixture.ownerId,
          view.opportunity!.id,
          stillVisible: () => true,
        ),
        studyDenied(),
      );
      await expectLater(
        fixture.runtime.resumeIndex(fixture.ownerId),
        studyDenied(),
      );
      expect(await fixture.rows('learning_sessions'), hasLength(1));
    },
  );

  test(
    'changed original content makes active index unavailable without a new deck',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final first = await fixture.start();
      await fixture.database.customStatement(
        'UPDATE vocabulary_words SET local_revision = local_revision + 1, meaning = ? WHERE id = ?',
        ['changed', studyWordId],
      );
      final before = await fixture.rows('learning_sessions');
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      await expectLater(
        fixture.runtime.resumeIndex(fixture.ownerId),
        throwsA(anything),
      );
      expect(await fixture.rows('learning_sessions'), before);
      expect(before.single['id'], first.sessionId);
    },
  );

  test(
    'missing MissionStarted is unavailable and completion retry never fabricates it',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.finish(await fixture.start());
      await fixture.database.customStatement(
        'DELETE FROM events_v2 WHERE event_type = ?',
        [measurementMissionStartedEventType],
      );
      final before = await fixture.researchRows();
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      await expectLater(
        fixture.runtime.resumeIndex(fixture.ownerId),
        studyDenied(),
      );
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'explicit completion repair reuses original end and never duplicates ordinary effects',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final first = await fixture.start();
      await fixture.database.customStatement(
        "CREATE TRIGGER deny_study_completion BEFORE INSERT ON events_v2 WHEN NEW.event_type = '$measurementMissionCompletedEventType' BEGIN SELECT RAISE(ABORT, 'synthetic completion capture unavailable'); END",
      );
      final finished = await fixture.finish(first);
      final ordinary = {
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'srs_states',
          'achievement_unlocks',
          'outbox_operations',
          'reward_transactions',
        ])
          table: await fixture.rows(table),
      };
      final pending = await fixture.runtime.load(fixture.ownerId);
      expect(pending.phase, StudyPhase.unavailable);
      expect(pending.reason, ResearchCaptureReason.incomplete);
      await fixture.database.customStatement(
        'DROP TRIGGER deny_study_completion',
      );
      fixture.participation.clock.now = participationStart.add(
        const Duration(minutes: 4),
      );
      fixture.restartRuntime();
      final repaired = await fixture.runtime.resumeIndex(fixture.ownerId);
      expect(repaired.endedAtUtc, finished.endedAtUtc);
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.post,
      );
      for (final table in ordinary.keys) {
        expect(await fixture.rows(table), ordinary[table]);
      }
      expect(await fixture.rows('events_v2'), hasLength(3));
    },
  );

  for (final delta in [Duration.zero, const Duration(milliseconds: 1)]) {
    test(
      'baseline24h first-invalid boundary $delta preserves original answers',
      () async {
        fixture = await StudyRuntimeFixture.open(longLived: true);
        await fixture.baseline();
        fixture.participation.clock.now = participationStart
            .add(const Duration(hours: 24))
            .add(delta);
        final before = await fixture.rows('motivation_responses');
        final view = await fixture.runtime.load(fixture.ownerId);
        expect(
          view.phase,
          delta == Duration.zero ? StudyPhase.ready : StudyPhase.stopped,
        );
        if (delta == Duration.zero) {
          expect(
            view.promptExpiresAtUtc,
            participationStart.add(const Duration(hours: 24, milliseconds: 1)),
          );
        }
        expect(await fixture.rows('motivation_responses'), before);
      },
    );
  }

  for (final delta in [Duration.zero, const Duration(milliseconds: 1)]) {
    test(
      'post30m first-invalid boundary $delta uses original canonical completion',
      () async {
        fixture = await StudyRuntimeFixture.open(longLived: true);
        final finished = await fixture.finish(await fixture.start());
        fixture.participation.clock.now = finished.endedAtUtc!
            .add(const Duration(minutes: 30))
            .add(delta);
        final view = await fixture.runtime.load(fixture.ownerId);
        expect(
          view.phase,
          delta == Duration.zero ? StudyPhase.post : StudyPhase.stopped,
        );
        expect(view.index!.endedAtUtc, finished.endedAtUtc);
        if (delta == Duration.zero) {
          expect(
            view.promptExpiresAtUtc,
            finished.endedAtUtc!.add(
              const Duration(minutes: 30, milliseconds: 1),
            ),
          );
        }
      },
    );
  }

  test(
    'suppression deadline is bounded by actual Ed expiry before P256 or trusted freshness',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final expiry = participationStart.add(const Duration(seconds: 20));
      fixture.participation.operations.current = participationOperation(
        expiresAtUtc: expiry,
      );
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.evaluatedAtUtc, participationStart);
      expect(view.promptExpiresAtUtc, expiry);
      fixture.participation.clock.now = expiry;
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
    },
  );

  for (final invalid in [
    'Ed signature',
    'P256 current document',
    'receipt',
    'trusted time',
    'withdrawal',
  ]) {
    test('$invalid fails closed without any availability writes', () async {
      fixture = await StudyRuntimeFixture.open();
      switch (invalid) {
        case 'Ed signature':
          fixture.participation.operations.current = participationOperation(
            corruptSignature: true,
          );
        case 'P256 current document':
          fixture.participation.use(
            participationPermit(corruptSignature: true),
          );
        case 'receipt':
          fixture.participation.receipts.inactive.add(
            ResearchReceiptKind.consent,
          );
        case 'trusted time':
          fixture.participation.clock.stale = true;
        case 'withdrawal':
          await fixture.participation.withdraw();
      }
      final before = await fixture.researchRows();
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
      expect(await fixture.researchRows(), before);
    });
  }

  test(
    'study consent is bound to its version and does not withdraw version1',
    () async {
      fixture = await StudyRuntimeFixture.open();
      await fixture.participation.consent.decide(
        ownerId: fixture.ownerId,
        version: 1,
        accepted: true,
        decidedAtUtc: participationStart,
      );
      expect(fixture.runtime.consent.version, 4);
      expect(
        await fixture.runtime.consent.withdraw(
          expectedOwnerId: fixture.ownerId,
          expectedVersion: 1,
        ),
        isFalse,
      );
      expect(
        await fixture.runtime.consent.withdraw(
          expectedOwnerId: fixture.ownerId,
          expectedVersion: 4,
        ),
        isTrue,
      );
      expect(
        (await fixture.participation.consent.load(
          ownerId: fixture.ownerId,
          version: 1,
        )).accepted,
        isTrue,
      );
      expect(
        (await fixture.runtime.load(fixture.ownerId)).phase,
        StudyPhase.unavailable,
      );
    },
  );

  test(
    'persistent deletion intent blocks availability and Study start before business writes',
    () async {
      fixture = await StudyRuntimeFixture.open();
      final ready = await fixture.ready();
      await fixture.participation.ownerWrites.beginDeletion(
        ownerId: fixture.ownerId,
        firebaseUid: 'uid-a',
        idempotencyKey: 'synthetic-study-deletion',
      );
      final before = await fixture.researchRows();
      final view = await fixture.runtime.load(fixture.ownerId);
      expect(view.phase, StudyPhase.unavailable);
      expect(view.reason, ResearchCaptureReason.ownerConflict);
      await expectLater(
        fixture.runtime.startIndex(
          fixture.ownerId,
          ready.opportunity!.id,
          stillVisible: () => true,
        ),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(await fixture.researchRows(), before);
    },
  );

  test(
    'file-backed process reopen resumes the exact first session and saved plan',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-study-runtime-',
      );
      addTearDown(() async {
        if (!fixtureClosed) {
          await fixture.database.close();
          fixtureClosed = true;
        }
        await directory.delete(recursive: true);
      });
      final file = File(
        '${directory.path}${Platform.pathSeparator}study.sqlite',
      );
      fixture = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase(file)),
      );
      final first = await fixture.start();
      final before = await fixture.researchRows();
      await fixture.database.close();
      fixture = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase(file)),
        seed: false,
      );
      fixture.participation.clock.now = participationStart.add(
        const Duration(minutes: 3),
      );
      final resumed = await fixture.runtime.resumeIndex(fixture.ownerId);
      expect(resumed.sessionId, first.sessionId);
      expect(resumed.plan.id, first.plan.id);
      expect(resumed.plan.stableSerialization, first.plan.stableSerialization);
      expect(resumed.startedAtUtc, first.startedAtUtc);
      expect(await fixture.researchRows(), before);
    },
  );
}
