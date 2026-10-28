import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/motivation_research_fixture.dart';
import '../../support/pair_purpose_fixture.dart';

void main() {
  late MotivationResearchFixture f;
  late DriftMeasurementOpportunityRepository repository;
  late MotivationMeasurementRun run;
  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize();
    run = await f.measurements.start(
      const MotivationMeasurementStart(
        ownerId: 'owner:a',
        permitId: 'permit:a',
      ),
    );
    await f.measurements.record(
      MotivationResponse(
        ownerId: 'owner:a',
        runId: run.id,
        itemId: 'baseline',
        responseCode: 'high',
      ),
    );
    repository = DriftMeasurementOpportunityRepository(
      f.database,
      measurements: f.measurements,
      nowUtc: () => f.now,
    );
  });
  tearDown(() => f.database.close());
  Future<MeasurementOpportunity> open({
    String entry = '11111111-1111-4111-8111-111111111111',
    TodayExperiencePresentation presentation =
        TodayExperiencePresentation.adventure,
  }) => repository.open(
    ownerId: 'owner:a',
    measurementRunId: run.id,
    entryAttemptId: entry,
    effectivePresentation: presentation,
  );
  Future<MeasurementOpportunity> presented() async {
    final o = await open();
    return repository.recordPresented('owner:a', o.id);
  }

  test(
    'direct seeded replay attachment is denied without consuming opportunity',
    () async {
      final o = await presented();
      final id = await seedSyntheticReplayPurpose(
        f.database,
        owner: 'owner:a',
        at: f.now,
      );
      await expectLater(
        repository.attachAcceptedSession(
          ownerId: 'owner:a',
          opportunityId: o.id,
          learningSessionId: id,
          planId: 'plan:synthetic',
          mode: LessonMode.matching,
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(
        (await repository.load('owner:a', o.id))!.learningSessionId,
        isNull,
      );
      await f.database.customStatement(
        'UPDATE measurement_opportunities SET learning_session_id=?,started_event_id=?,completed_event_id=?,closed_at_utc_ms=? WHERE id=?',
        [
          id,
          o.presentedEventId,
          o.presentedEventId,
          f.now.millisecondsSinceEpoch,
          o.id,
        ],
      );
      Future<Object> snapshot() async => {
        for (final table in [
          'measurement_opportunities',
          'motivation_measurement_runs',
          'motivation_responses',
          'events_v2',
          'outbox_operations',
        ])
          table: [
            for (final row
                in await f.database
                    .customSelect('SELECT * FROM $table ORDER BY 1')
                    .get())
              row.data,
          ],
      };
      final before = await snapshot();
      await expectLater(
        repository.attachAcceptedSession(
          ownerId: 'owner:a',
          opportunityId: o.id,
          learningSessionId: id,
          planId: 'plan:synthetic',
          mode: LessonMode.matching,
        ),
        throwsA(
          isA<ResearchCaptureDenied>().having(
            (e) => e.reason,
            'reason',
            ResearchCaptureReason.sessionUnavailable,
          ),
        ),
      );
      await expectLater(
        repository.completeAcceptedSession('owner:a', o.id),
        throwsA(
          isA<ResearchCaptureDenied>().having(
            (e) => e.reason,
            'reason',
            ResearchCaptureReason.sessionUnavailable,
          ),
        ),
      );
      expect(await snapshot(), before);
    },
  );

  Future<void> session(
    String id, {
    String owner = 'owner:a',
    String state = 'active',
    DateTime? start,
    DateTime? end,
  }) async {
    final c = SessionConfiguration.validated(
      schemaVersion: 1,
      policyVersion: sessionConfigurationPolicyVersion,
      ownerId: owner,
      mode: LessonMode.meaningQuiz,
      itemCount: 2,
      direction: SessionDirection.forward,
      difficulty: SessionDifficulty.standard,
      hintBudget: 0,
      timing: const SessionTiming.timed(Duration(minutes: 2)),
      packIdentity: null,
      protocolId: 'standard',
      protocolVersion: '1',
      protocolLimitsIdentity: 'standard',
    );
    await f.database
        .into(f.database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: id,
            ownerId: owner,
            activityType: 'quiz',
            state: state,
            startedAtUtcMs: (start ?? f.now).millisecondsSinceEpoch,
            endedAtUtcMs: Value(end?.millisecondsSinceEpoch),
            appVersion: '1',
            buildId: 'test',
            sessionConfigurationIdentity: Value(c.contentIdentity),
            sessionConfigurationJson: Value(c.stableSerialization),
          ),
        );
  }

  Future<MeasurementOpportunity> attach(MeasurementOpportunity o, String id) =>
      repository.attachAcceptedSession(
        ownerId: 'owner:a',
        opportunityId: o.id,
        learningSessionId: id,
        planId: 'plan:synthetic',
        mode: LessonMode.meaningQuiz,
      );

  test(
    'baseline Skip retains denominator without a treatment exposure',
    () async {
      await f.database.delete(f.database.motivationResponses).go();
      final o = await open();
      await expectLater(
        repository.recordPresented('owner:a', o.id),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      await f.measurements.close(
        MotivationMeasurementClose(
          ownerId: 'owner:a',
          runId: run.id,
          state: MotivationMeasurementRunState.skipped,
        ),
      );
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
      expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
    },
  );

  test('one durable denominator before Presented, replay reuses it', () async {
    final o = await open();
    expect((await open()).id, o.id);
    expect(
      await f.database.select(f.database.measurementOpportunities).get(),
      hasLength(1),
    );
    expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
    final first = await repository.recordPresented('owner:a', o.id);
    f.now = f.now.add(const Duration(seconds: 1));
    final retry = await repository.recordPresented('owner:a', o.id);
    expect(retry.presentedEventId, first.presentedEventId);
    expect(await f.database.select(f.database.eventsV2).get(), hasLength(1));
  });
  test(
    'event delivery failure preserves denominator and retry repairs linkage',
    () async {
      final o = await open();
      await f.database.customStatement(
        "CREATE TRIGGER test_event_failure BEFORE INSERT ON events_v2 BEGIN SELECT RAISE(ABORT,'synthetic storage failure'); END",
      );
      await expectLater(
        repository.recordPresented('owner:a', o.id),
        throwsA(anything),
      );
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
      expect(
        (await repository.load('owner:a', o.id))!.presentedEventId,
        isNull,
      );
      await f.database.customStatement('DROP TRIGGER test_event_failure');
      expect(
        (await repository.recordPresented('owner:a', o.id)).presentedEventId,
        isNotNull,
      );
    },
  );
  test(
    'Standard and Adventure use the same bounded neutral event contract',
    () async {
      for (final p in TodayExperiencePresentation.values) {
        final o = await open(
          entry: p == TodayExperiencePresentation.standard
              ? '22222222-2222-4222-8222-222222222222'
              : '33333333-3333-4333-8333-333333333333',
          presentation: p,
        );
        await repository.recordPresented('owner:a', o.id);
      }
      final events = await f.database.select(f.database.eventsV2).get();
      expect(events, hasLength(2));
      for (final e in events) {
        expect(e.eventType, 'TodayExperiencePresented');
        expect(e.eventVersion, 1);
        expect(e.aggregateType, 'MeasurementOpportunity');
        final p = jsonDecode(e.payloadJson) as Map<String, dynamic>;
        expect(p.keys.toSet(), {
          'assignedTreatment',
          'effectivePresentation',
          'entryAttemptId',
          'catalogVersion',
        });
        expect(p['assignedTreatment'], 'adventure');
      }
    },
  );
  test(
    'switches reserve ordinals atomically; stale retries never add suppression',
    () async {
      var o = await presented();
      for (var i = 1; i <= 12; i++) {
        final revision = o.localRevision;
        final target = i.isOdd
            ? TodayExperiencePresentation.standard
            : TodayExperiencePresentation.adventure;
        final results = await Future.wait([
          repository.changePresentation(
            ownerId: 'owner:a',
            opportunityId: o.id,
            presentation: target,
            expectedRevision: revision,
          ),
          repository.changePresentation(
            ownerId: 'owner:a',
            opportunityId: o.id,
            presentation: target,
            expectedRevision: revision,
          ),
        ]);
        o = results.last;
      }
      expect(o.lastSwitchOrdinal, 10);
      expect(o.suppressedSwitchCount, 2);
      final rows =
          await (f.database.select(f.database.eventsV2)..where(
                (r) => r.eventType.equals('TodayExperiencePresentationChanged'),
              ))
              .get();
      expect(rows, hasLength(10));
      expect(
        rows
            .map((e) => (jsonDecode(e.payloadJson) as Map)['switchOrdinal'])
            .toSet(),
        {for (var i = 1; i <= 10; i++) i},
      );
    },
  );
  test(
    'withdrawn authority denies Presented without adding event/outbox',
    () async {
      final o = await open();
      f.authority.receiptsActive = false;
      await expectLater(
        repository.recordPresented('owner:a', o.id),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );
  test(
    'mission requires existing same-owner canonical session after presentation',
    () async {
      final o = await presented();
      await expectLater(
        attach(o, 'missing'),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      await session('old', start: f.now.subtract(const Duration(minutes: 1)));
      await expectLater(
        attach(o, 'old'),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      await session('session:a');
      final accepted = await attach(o, 'session:a');
      expect(accepted.learningSessionId, 'session:a');
      expect(accepted.startedEventId, isNotNull);
      expect(
        (await attach(o, 'session:a')).startedEventId,
        accepted.startedEventId,
      );
      await session('session:b');
      await expectLater(
        attach(o, 'session:b'),
        throwsA(isA<ResearchCaptureDenied>()),
      );
    },
  );
  test(
    'canonical completion links once and enables bounded post measurement',
    () async {
      final o = await presented();
      await session('session:a');
      await attach(o, 'session:a');
      await expectLater(
        repository.completeAcceptedSession('owner:a', o.id),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      f.now = f.now.add(const Duration(minutes: 2));
      await f.database.customStatement(
        "UPDATE learning_sessions SET state='completed',ended_at_utc_ms=? WHERE id='session:a'",
        [f.now.millisecondsSinceEpoch],
      );
      final completed = await repository.completeAcceptedSession(
        'owner:a',
        o.id,
      );
      expect(completed.completedEventId, isNotNull);
      expect(
        (await repository.completeAcceptedSession(
          'owner:a',
          o.id,
        )).completedEventId,
        completed.completedEventId,
      );
      f.now = f.now.add(const Duration(minutes: 30));
      await f.measurements.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'post',
          responseCode: 'low',
        ),
      );
      final measured = await f.measurements.close(
        MotivationMeasurementClose(
          ownerId: 'owner:a',
          runId: run.id,
          state: MotivationMeasurementRunState.completed,
        ),
      );
      expect(measured.primaryAnalysisEligible, isTrue);
      expect(await f.database.select(f.database.eventsV2).get(), hasLength(3));
    },
  );
  test(
    'first accepted index never changes to a later completed session',
    () async {
      final first = await presented();
      await session('session:first');
      await attach(first, 'session:first');
      f.now = f.now.add(const Duration(minutes: 3));
      final second = await open(entry: '44444444-4444-4444-8444-444444444444');
      await repository.recordPresented('owner:a', second.id);
      await session('session:later');
      await attach(second, 'session:later');
      f.now = f.now.add(const Duration(minutes: 2));
      await f.database.customStatement(
        "UPDATE learning_sessions SET state='completed',ended_at_utc_ms=? WHERE id='session:later'",
        [f.now.millisecondsSinceEpoch],
      );
      await repository.completeAcceptedSession('owner:a', second.id);
      expect(
        (await f.measurements.load('owner:a', run.id))!.indexCompletionAtUtc,
        isNull,
      );
      await expectLater(
        f.measurements.record(
          MotivationResponse(
            ownerId: 'owner:a',
            runId: run.id,
            itemId: 'post',
            responseCode: 'high',
          ),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
    },
  );
  test('opening alone does not establish exposure; Presented does', () async {
    final o = await open();
    expect(
      (await f.measurements.load('owner:a', run.id))!.firstExposureAtUtc,
      isNull,
    );
    f.now = f.now.add(const Duration(minutes: 1));
    await repository.recordPresented('owner:a', o.id);
    expect(
      (await f.measurements.load('owner:a', run.id))!.firstExposureAtUtc,
      f.now,
    );
  });
  test(
    'subsecond exposure survives database reload without extending baseline window',
    () async {
      f.now = f.now.add(const Duration(milliseconds: 999));
      final o = await presented();
      expect(
        (await f.measurements.load('owner:a', run.id))!.firstExposureAtUtc,
        f.now,
      );
      final restored = DriftMeasurementOpportunityRepository(
        f.database,
        measurements: f.measurements,
        nowUtc: () => f.now,
      );
      expect(
        (await restored.recordPresented('owner:a', o.id)).presentedEventId,
        o.presentedEventId,
      );
    },
  );
  test(
    'expired baseline retains denominator but primary analysis is ineligible',
    () async {
      f.now = f.now.add(const Duration(hours: 24, seconds: 1));
      final o = await presented();
      await session('session:a');
      await attach(o, 'session:a');
      f.now = f.now.add(const Duration(minutes: 1));
      await f.database.customStatement(
        "UPDATE learning_sessions SET state='completed',ended_at_utc_ms=? WHERE id='session:a'",
        [f.now.millisecondsSinceEpoch],
      );
      await repository.completeAcceptedSession('owner:a', o.id);
      await f.measurements.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'post',
          responseCode: 'high',
        ),
      );
      final measured = await f.measurements.close(
        MotivationMeasurementClose(
          ownerId: 'owner:a',
          runId: run.id,
          state: MotivationMeasurementRunState.completed,
        ),
      );
      expect(measured.primaryAnalysisEligible, isFalse);
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
    },
  );
  test(
    'post beyond thirty minutes cannot become an observed primary answer',
    () async {
      final o = await presented();
      await session('session:a');
      await attach(o, 'session:a');
      f.now = f.now.add(const Duration(minutes: 1));
      await f.database.customStatement(
        "UPDATE learning_sessions SET state='completed',ended_at_utc_ms=? WHERE id='session:a'",
        [f.now.millisecondsSinceEpoch],
      );
      await repository.completeAcceptedSession('owner:a', o.id);
      f.now = f.now.add(const Duration(minutes: 30, milliseconds: 1));
      await expectLater(
        f.measurements.record(
          MotivationResponse(
            ownerId: 'owner:a',
            runId: run.id,
            itemId: 'post',
            responseCode: 'high',
          ),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
    },
  );
}
