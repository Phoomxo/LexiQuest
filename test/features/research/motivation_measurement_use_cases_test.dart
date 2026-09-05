import 'dart:async';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/research/application/motivation_measurement_use_cases.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import '../../support/motivation_research_fixture.dart';

void main() {
  late MotivationResearchFixture f;
  late MotivationMeasurementUseCases service;
  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize();
    service = MotivationMeasurementUseCases(
      database: f.database,
      measurements: f.measurements,
      opportunities: DriftMeasurementOpportunityRepository(
        f.database,
        measurements: f.measurements,
        nowUtc: () => f.now,
      ),
    );
  });
  tearDown(() => f.database.close());
  test(
    'read-only owner fences do not retrigger the learning observer',
    () async {
      var notifications = 0;
      final first = Completer<void>();
      final subscription = service.watch('owner:a').listen((_) {
        notifications++;
        if (!first.isCompleted) first.complete();
      });
      addTearDown(subscription.cancel);
      await first.future;
      await service.prepare(ownerId: 'owner:a', permitId: 'permit:a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications, 1);
    },
  );
  Future<String> opening(TodayExperiencePresentation p) async {
    final run = (await service.prepare(
      ownerId: 'owner:a',
      permitId: 'permit:a',
    ))!;
    await f.measurements.record(
      MotivationResponse(
        ownerId: 'owner:a',
        runId: run.id,
        itemId: 'baseline',
        responseCode: 'high',
      ),
    );
    final o = (await service.open(
      ownerId: 'owner:a',
      runId: run.id,
      entryAttemptId: '11111111-1111-4111-8111-111111111111',
      presentation: p,
    ))!;
    await service.opportunities.recordPresented('owner:a', o.id);
    return run.id;
  }

  Future<void> accepted(String id, {DateTime? start}) async {
    final c = SessionConfiguration.validated(
      schemaVersion: 1,
      policyVersion: sessionConfigurationPolicyVersion,
      ownerId: 'owner:a',
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
            ownerId: 'owner:a',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: (start ?? f.now).millisecondsSinceEpoch,
            appVersion: '1',
            buildId: 'test',
            sessionConfigurationIdentity: Value(c.contentIdentity),
            sessionConfigurationJson: Value(c.stableSerialization),
          ),
        );
  }

  test('missing permit is no-op; no rows, events or outbox created', () async {
    expect(
      await service.prepare(ownerId: 'owner:a', permitId: 'missing'),
      isNull,
    );
    await service.reconcile('owner:a');
    expect(
      await f.database.select(f.database.motivationMeasurementRuns).get(),
      isEmpty,
    );
    expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
    expect(await f.database.select(f.database.outboxOperations).get(), isEmpty);
  });
  test(
    'incomplete baseline retains opportunity but cannot record exposure',
    () async {
      final run = (await service.prepare(
        ownerId: 'owner:a',
        permitId: 'permit:a',
      ))!;
      final o = await service.open(
        ownerId: 'owner:a',
        runId: run.id,
        entryAttemptId: '11111111-1111-4111-8111-111111111111',
        presentation: TodayExperiencePresentation.standard,
      );
      expect(o, isNotNull);
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
      await expectLater(
        service.opportunities.recordPresented('owner:a', o!.id),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
    },
  );
  for (final p in TodayExperiencePresentation.values) {
    test(
      '${p.name} reconciles accepted canonical session and completion identically',
      () async {
        final runId = await opening(p);
        await accepted('session:one');
        await service.reconcile('owner:a');
        await service.reconcile('owner:a');
        var ops = await f.database
            .select(f.database.measurementOpportunities)
            .get();
        expect(ops.single.learningSessionId, 'session:one');
        expect(ops.single.startedEventId, isNotNull);
        f.now = f.now.add(const Duration(minutes: 1));
        await f.database.customStatement(
          "UPDATE learning_sessions SET state='completed',ended_at_utc_ms=? WHERE id='session:one'",
          [f.now.millisecondsSinceEpoch],
        );
        await service.reconcile('owner:a');
        await service.reconcile('owner:a');
        ops = await f.database
            .select(f.database.measurementOpportunities)
            .get();
        expect(ops.single.completedEventId, isNotNull);
        expect(
          (await f.measurements.load('owner:a', runId))!.indexCompletionAtUtc,
          f.now,
        );
        expect(
          await f.database.select(f.database.eventsV2).get(),
          hasLength(3),
        );
        expect(
          await f.database.select(f.database.answerAttempts).get(),
          isEmpty,
        );
        expect(
          await f.database.select(f.database.rewardTransactions).get(),
          isEmpty,
        );
      },
    );
  }
  test(
    'restart reconstructs linkage without accepting pre-exposure session',
    () async {
      await accepted(
        'session:old',
        start: f.now.subtract(const Duration(minutes: 1)),
      );
      await opening(TodayExperiencePresentation.adventure);
      await accepted('session:new');
      final restored = MotivationMeasurementUseCases(
        database: f.database,
        measurements: f.measurements,
        opportunities: service.opportunities,
      );
      await restored.reconcile('owner:a');
      expect(
        (await f.database.select(f.database.measurementOpportunities).get())
            .single
            .learningSessionId,
        'session:new',
      );
    },
  );
  test(
    'withdrawn authority suppresses linkage without changing canonical session',
    () async {
      await opening(TodayExperiencePresentation.standard);
      await accepted('session:one');
      f.authority.receiptsActive = false;
      await service.reconcile('owner:a');
      expect(
        (await f.database.select(f.database.measurementOpportunities).get())
            .single
            .learningSessionId,
        isNull,
      );
      expect(
        (await f.database.select(f.database.learningSessions).get())
            .single
            .state,
        'active',
      );
      expect(await f.database.select(f.database.eventsV2).get(), hasLength(1));
    },
  );
}
