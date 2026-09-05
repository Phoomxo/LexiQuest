import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent;
import 'dart:convert';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/application/quest_catalog_provider.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_practice_replay.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_star_policy.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/history/data/drift_learning_history_reader.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/features/time_tracking/application/focus_timer_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/focus_timer.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  for (final mutation in [
    'deleted',
    'reported',
    'revision',
    'owner',
    'source-missing',
  ]) {
    test('new replay atomically revalidates source and content: $mutation', () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final source = h.operation;
      final c = await h.restore();
      await h.finishBounded(c);
      await c.finish();
      final replay = PairPracticeReplay(
        reader: DriftPairMatchingSessionPurposeReader(h.db),
        start: PairMatchingAtomicStartAdapter(
          repository: h.real,
          capability: InternalPairMatchingCapability(
            allowlist: PairCuratedAllowlist(
              version: source.plan.allowlistVersion,
              items: source.plan.orderedLexicalItems,
            ),
            isEnabled: () => true,
          ),
        ),
      );
      final operation = await replay.prepare(
        ownerId: h.owner,
        sourceSessionId: source.plan.learningSessionId,
        launchOperationId: 'synthetic-revalidation',
        createdAtUtc: DateTime.utc(2026, 9, 5, 0, 2),
        appVersion: 'synthetic',
        buildId: 'synthetic',
      );
      if (mutation == 'deleted') {
        await h.db.customStatement(
          "UPDATE vocabulary_words SET is_deleted=1 WHERE id='synthetic-0'",
        );
      }
      if (mutation == 'reported') {
        await h.db.customStatement(
          "INSERT INTO content_quality_reports (id,owner_id,content_type,content_id,content_revision,reason_code,submitted_at_utc_ms) VALUES ('synthetic-report',?,'lexicalMetadata','synthetic-0',1,'incorrectMeaning',1)",
          [h.owner],
        );
      }
      if (mutation == 'revision') {
        await h.db.customStatement(
          "UPDATE vocabulary_words SET content_revision=content_revision+1 WHERE id='synthetic-0'",
        );
      }
      if (mutation == 'owner') {
        await h.db.customStatement(
          'UPDATE local_owners SET is_active=0 WHERE id=?',
          [h.owner],
        );
      }
      if (mutation == 'source-missing') {
        await h.db.customStatement(
          "DELETE FROM events_v2 WHERE event_type='LearningActivityCheckpoint'",
        );
      }
      await expectLater(replay.start.start(operation), throwsStateError);
      expect(await h.db.select(h.db.learningSessions).get(), hasLength(1));
    });
  }
  for (final wrong in [false, true]) {
    test(
      'identical normal and replay ledger retains descriptive stars: wrong=$wrong',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final source = h.operation;
        Future<void> schedule(PairMatchingSessionCoordinator c) async {
          if (wrong) {
            await h.tap(c, 'synthetic-0', PairTileSide.prompt);
            await h.tap(c, 'synthetic-1', PairTileSide.target);
          }
          for (final i in wrong ? [1, 2, 0, 3] : [0, 1, 2, 3]) {
            await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
            await h.tap(c, 'synthetic-$i', PairTileSide.target);
          }
          await c.finish();
        }

        await schedule(await h.restore());
        final reader = DriftPairMatchingSessionPurposeReader(h.db);
        final normal = (await reader.read(
          ownerId: h.owner,
          sessionId: source.plan.learningSessionId,
        )).snapshot!;
        final replay = PairPracticeReplay(
          reader: reader,
          start: PairMatchingAtomicStartAdapter(
            repository: h.real,
            capability: InternalPairMatchingCapability(
              allowlist: PairCuratedAllowlist(
                version: source.plan.allowlistVersion,
                items: source.plan.orderedLexicalItems,
              ),
              isEnabled: () => true,
            ),
          ),
        );
        h.operation = await replay.prepare(
          ownerId: h.owner,
          sourceSessionId: source.plan.learningSessionId,
          launchOperationId: 'synthetic-parity',
          createdAtUtc: DateTime.utc(2026, 9, 5, 0, 2),
          appVersion: 'synthetic',
          buildId: 'synthetic',
        );
        await replay.start.start(h.operation);
        await schedule(await h.restore());
        final repeated = (await reader.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        )).snapshot!;
        final a = PairStarPolicy.project(
              normal.engine,
              terminalAcknowledged: true,
            ),
            b = PairStarPolicy.project(
              repeated.engine,
              terminalAcknowledged: true,
            );
        expect(
          [b.matched, b.independent, b.assisted, b.stars],
          [a.matched, a.independent, a.assisted, a.stars],
        );
        expect(b.stars, wrong ? 2 : 3);
        expect(
          (await h.db.select(h.db.answerAttempts).get())
              .where((a) => a.sessionId == h.operation.plan.learningSessionId)
              .every((a) => a.evidenceClass == 'recreational'),
          true,
        );
      },
    );
  }
  testWidgets(
    'actual replay shell zero-tap pointer keyboard semantics background and close preserve time',
    (tester) async {
      final h = PairHarness();
      late UnifiedLessonController host;
      late ActiveLearningTimeController time;
      late FocusTimerController focus;
      var micros = 0;
      var interactions = 0;
      final now = DateTime.utc(2026, 9, 5, 0, 2);
      await tester.runAsync(() async {
        await h.initialize();
        final source = h.operation;
        final coordinator = await h.restore();
        await h.finishBounded(coordinator);
        await coordinator.finish();
        final replay = PairPracticeReplay(
          reader: DriftPairMatchingSessionPurposeReader(h.db),
          start: PairMatchingAtomicStartAdapter(
            repository: h.real,
            capability: InternalPairMatchingCapability(
              allowlist: PairCuratedAllowlist(
                version: source.plan.allowlistVersion,
                items: source.plan.orderedLexicalItems,
              ),
              isEnabled: () => true,
            ),
          ),
        );
        h.operation = await replay.prepare(
          ownerId: h.owner,
          sourceSessionId: source.plan.learningSessionId,
          launchOperationId: 'synthetic-shell-replay',
          createdAtUtc: now,
          appVersion: 'synthetic',
          buildId: 'synthetic',
        );
        await replay.start.start(h.operation);
        time = ActiveLearningTimeController(
          repository: DriftLearningTimeRepository(
            h.db,
            owners: h.learning.owners,
          ),
          monotonicMicros: () => micros,
          nowUtc: () => now,
          timezoneContext: (_) => const LearningTimeZoneContext(
            timezoneId: 'UTC',
            utcOffsetMinutes: 0,
          ),
        );
        focus = FocusTimerController(timeAuthority: time);
        host = UnifiedLessonController(
          learning: h.learning,
          adapter: const MatchingModeAdapter(),
          activeLearningTime: time,
          focusTimer: focus,
          focusTimerFeature: Feature.quiz,
          sessionPurposeReader: DriftPairMatchingSessionPurposeReader(h.db),
        );
        await host.start(
          LessonStartCommand(
            mode: LessonMode.matching,
            sessionId: h.operation.plan.learningSessionId,
            ownerId: h.owner,
            startedAtUtc: now,
            itemCount: 4,
          ),
        );
      });
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedLessonShell(
              controller: host,
              nowUtc: () => now,
              lifecycleStateReader: () => AppLifecycleState.resumed,
              builder: (_) => Center(
                child: TextButton(
                  key: const Key('synthetic-action'),
                  autofocus: true,
                  onPressed: () {
                    interactions++;
                    host.noteActiveLearningInteraction(now);
                  },
                  child: const Text('Synthetic action'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(time.state, ActiveLearningTimeState.inactive);
      micros += 1000000;
      await tester.tap(find.byKey(const Key('synthetic-action')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final node = tester.getSemantics(
        find.byKey(const Key('synthetic-action')),
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(interactions, 3);
      await tester.runAsync(() async {
        await host.startFocusTimer(now);
        await host.pause(now, processBackground: true);
        await host.resume(now);
        expect(time.state, ActiveLearningTimeState.inactive);
        expect(focus.snapshot.sessionId, isNull);
        expect(focus.snapshot.activeDuration, Duration.zero);
        expect(await h.db.select(h.db.learningTimeSegments).get(), isEmpty);
        final restored = await h.restore();
        await h.finishBounded(restored);
        await restored.finish();
        expect(await h.db.select(h.db.learningTimeSegments).get(), isEmpty);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      host.dispose();
      await tester.runAsync(h.db.close);
    },
  );
  test(
    'new exact replay commits recreational answers and preserves authority rows',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final original = h.operation;
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-1', PairTileSide.target);
      for (final i in [1, 2, 0, 3]) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      await c.finish();
      await h.db.customStatement(
        "INSERT INTO srs_states (id,owner_id,word_id,interval_days,repetitions,due_at_utc_ms,algorithm_version) VALUES ('synthetic-srs',?,'synthetic-0',14,4,1,1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO points_ledger_entries (id,owner_id,idempotency_key,entry_type,amount,occurred_at_utc_ms) VALUES ('synthetic-xp',?,'synthetic-xp','quizCorrect',25,1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO reward_transactions (id,owner_id,idempotency_key,transaction_type,amount,catalog_version,occurred_at_utc_ms) VALUES ('synthetic-coins',?,'synthetic-coins','grant',25,1,1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO owned_reward_items (id,owner_id,item_id,catalog_version,acquired_by_transaction_id,acquired_at_utc_ms) VALUES ('synthetic-owned',?,'synthetic-item',1,'synthetic-coins',1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO equipped_reward_items (id,owner_id,slot,item_id,equipped_at_utc_ms) VALUES ('synthetic-equipped',?,'avatar','synthetic-item',1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO streak_states (owner_id,current_streak_days,longest_streak_days,updated_at_utc_ms) VALUES (?,2,2,1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO learning_day_log (id,owner_id,learning_day,first_session_at_utc_ms) VALUES ('synthetic-day',?,'2026-09-04',1)",
        [h.owner],
      );
      await h.db.customStatement(
        "INSERT INTO achievement_unlocks (id,owner_id,achievement_id,definition_version,source_event_id,unlocked_at_utc_ms) VALUES ('synthetic-achievement',?,'synthetic-historical',1,'synthetic-historical-event',1)",
        [h.owner],
      );
      await h.real.projections.rebuildAchievements(h.owner);
      var questId = 0;
      final quest = QuestUseCases(
        repository: DriftQuestRepository(h.db),
        owners: h.learning.owners,
        generateId: () => 'synthetic-quest-${++questId}',
        nowUtc: () => DateTime.utc(2026, 9, 5),
        timezoneId: 'UTC',
      );
      await quest.startQuest(QuestCatalogProvider.dailyCorrectAnswers);
      final sinkCalls = <String>[];
      final reconciler = LearningSideEffectReconciler(
        h.db,
        questSink: (e) async {
          sinkCalls.add(e.eventId);
          final p = await quest.projectEvent(e, QuestCatalogProvider.allQuests);
          final payload = quest.projectionPayload(
            p,
            QuestCatalogProvider.allQuests,
          );
          return p.eligible
              ? LearningProjectionResult.applied(payload: payload)
              : LearningProjectionResult.notApplicable(payload: payload);
        },
        streakSink: (e) async {
          sinkCalls.add(e.eventId);
          return const LearningProjectionResult.notApplicable();
        },
        coinsSink: (e, _) async {
          sinkCalls.add(e.eventId);
          return const LearningProjectionResult.notApplicable();
        },
        rewardSink: (e, p) async {
          sinkCalls.add(e.eventId);
          return await quest.reconcileReward(e, p)
              ? const LearningProjectionResult.applied()
              : const LearningProjectionResult.notApplicable();
        },
      );
      await reconciler.reconcileOwner(h.owner);
      final store = DriftLearningEventStore(h.db);
      for (final projection in ['coins', 'quest', 'streak', 'reward']) {
        expect(
          await store.listPendingProjectionEvents(
            ownerId: h.owner,
            projection: projection,
            appliedVersion: LearningSideEffectReconciler.appliedVersion,
            limit: 100,
          ),
          isEmpty,
          reason: 'normal baseline must be fully drained',
        );
      }
      sinkCalls.clear();
      expect(await h.db.select(h.db.questInstances).get(), isNotEmpty);
      expect(await h.db.select(h.db.questObjectiveProgress).get(), isNotEmpty);
      final tables = [
        'srs_states',
        'points_ledger_entries',
        'achievement_unlocks',
        'reward_transactions',
        'owned_reward_items',
        'equipped_reward_items',
        'quest_instances',
        'quest_objective_progress',
        'streak_states',
        'learning_day_log',
        'learning_time_segments',
        'session_configurations',
        'assessment_runs',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
      ];
      Future<Map<String, Object?>> snapshot() async => {
        for (final table in tables)
          table: [
            for (final row
                in await h.db
                    .customSelect('SELECT * FROM $table ORDER BY 1')
                    .get())
              row.data,
          ],
      };
      final before = await snapshot();
      Future<Object> progress() async {
        final p = await DriftProgressQueries(
          h.db,
        ).load(ownerId: h.owner, nowUtc: DateTime.utc(2026, 9, 5));
        return [
          p.sampleSize,
          p.correctCount,
          p.wrongCount,
          p.accuracy,
          p.totalXp,
          p.completedSessions,
          p.streakDays,
          p.dueReviewCount,
          p.masteredWordCount,
          p.achievementCount,
          p.gameLevel,
          p.averageResponseTimeMs,
          p.latestEvidenceAtUtc,
          [
            for (final w in p.weaknesses)
              [
                w.wordId,
                w.sampleSize,
                w.incorrectCount,
                w.errorRate,
                w.dueAtUtc,
              ],
          ],
          [
            for (final s in p.skills) [s.key, s.sampleSize, s.accuracy],
          ],
        ];
      }

      final progressBefore = await progress();
      final replay = PairPracticeReplay(
        reader: DriftPairMatchingSessionPurposeReader(h.db),
        start: PairMatchingAtomicStartAdapter(
          repository: h.real,
          capability: InternalPairMatchingCapability(
            allowlist: PairCuratedAllowlist(
              version: original.plan.allowlistVersion,
              items: original.plan.orderedLexicalItems,
            ),
            isEnabled: () => true,
          ),
        ),
      );
      final operation = await replay.prepare(
        ownerId: h.owner,
        sourceSessionId: original.plan.learningSessionId,
        launchOperationId: 'synthetic-replay',
        createdAtUtc: DateTime.utc(2026, 9, 5, 0, 1),
        appVersion: 'synthetic',
        buildId: 'synthetic',
      );
      await replay.start.start(operation);
      expect(operation.plan.sourceSessionId, original.plan.learningSessionId);
      expect(operation.plan.sessionPurpose, PairSessionPurpose.practiceReplay);
      expect(operation.plan.shuffleSeed, isNot(original.plan.shuffleSeed));
      h.operation = operation;
      var micros = 0;
      final time = ActiveLearningTimeController(
        repository: DriftLearningTimeRepository(
          h.db,
          owners: h.learning.owners,
        ),
        monotonicMicros: () => micros,
        nowUtc: () => DateTime.utc(2026, 9, 5, 0, 2),
        timezoneContext: (_) => const LearningTimeZoneContext(
          timezoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
      );
      final focus = FocusTimerController(timeAuthority: time);
      final host = UnifiedLessonController(
        learning: h.learning,
        adapter: const MatchingModeAdapter(),
        activeLearningTime: time,
        focusTimer: focus,
        focusTimerFeature: Feature.quiz,
        sessionPurposeReader: DriftPairMatchingSessionPurposeReader(h.db),
      );
      addTearDown(host.dispose);
      await host.start(
        LessonStartCommand(
          mode: LessonMode.matching,
          sessionId: operation.plan.learningSessionId,
          ownerId: h.owner,
          startedAtUtc: operation.plan.createdAtUtc,
          itemCount: 4,
        ),
      );
      expect(
        time.state,
        ActiveLearningTimeState.inactive,
        reason: 'zero-tap replay admission must not open time',
      );
      micros += 1000000;
      await host.recordActiveLearningInteraction(
        DateTime.utc(2026, 9, 5, 0, 2),
      );
      await host.startFocusTimer(DateTime.utc(2026, 9, 5, 0, 2));
      expect(focus.snapshot.status, FocusTimerStatus.notStarted);
      expect(focus.snapshot.sessionId, isNull);
      expect(focus.snapshot.activeDuration, Duration.zero);
      expect(await snapshot(), before);
      final replayCoordinator = await h.restore();
      await h.finishBounded(replayCoordinator);
      await replayCoordinator.finish();
      await reconciler.reconcileOwner(h.owner);
      expect(
        sinkCalls,
        isEmpty,
        reason: 'replay must be rejected before invoking any external sink',
      );
      for (final projection in ['coins', 'quest', 'streak', 'reward']) {
        expect(
          await store.listPendingProjectionEvents(
            ownerId: h.owner,
            projection: projection,
            appliedVersion: LearningSideEffectReconciler.appliedVersion,
            limit: 100,
          ),
          isEmpty,
        );
      }
      expect(await snapshot(), before);
      expect(await progress(), progressBefore);
      final attempts = (await h.db.select(h.db.answerAttempts).get())
          .where((a) => a.sessionId == operation.plan.learningSessionId)
          .toList();
      expect(attempts, isNotEmpty);
      expect(
        attempts.every(
          (a) => a.evidenceClass == EvidenceClass.recreational.name,
        ),
        true,
      );
      final replayCommands = h.repository.commands
          .where((c) => c.sessionId == operation.plan.learningSessionId)
          .toList();
      expect(replayCommands, hasLength(attempts.length));
      for (final command in replayCommands) {
        final event = (await h.db.select(h.db.eventsV2).get()).singleWhere(
          (e) => e.eventId == 'learning-event:${command.id}',
        );
        expect(
          jsonDecode(event.consentContextJson),
          LearningEventContext.noResearch(
            command.evidenceContext,
          ).consentContext.toJson(),
        );
        expect(event.experimentContextJson, isNull);
        expect(
          command.evidenceContext.toJson(),
          EvidenceContext.forNewEvidence(
            evidenceClass: EvidenceClass.recreational,
            skillId: 'matching-recognition',
            hintLevel: 0,
            contentRevision: command.evidenceContext.contentRevision,
            rolloutMode: EvidencePolicyRolloutMode.legacy,
            engagementAllowed: false,
          ).toJson(),
        );
      }
      final captured = CurrentActivityEvidenceAdapter(learning: h.learning)
          .capturePracticeReplayMatching(
            plan: operation.plan,
            wordId: 'synthetic-0',
            isCorrect: true,
            responseTimeMs: 25,
            attemptNumber: 10,
            contentRevision:
                replayCommands.first.evidenceContext.contentRevision,
          );
      final frozen = await captured.freezeForRecovery();
      final altered = {
        ...frozen.toJson(),
        'eventContext': {
          ...frozen.eventContext.toJson(),
          'consentContext': {
            ...frozen.eventContext.consentContext.toJson(),
            'aiConsentGranted': true,
          },
        },
      };
      expect(
        () => CurrentActivityEvidenceAdapter(learning: h.learning)
            .restorePracticeReplayMatching(
              FrozenPendingCurrentActivityEvidence.fromJson(altered),
              plan: operation.plan,
            ),
        throwsStateError,
      );
      final replayEventIds = attempts
          .map((a) => 'learning-event:${a.id}')
          .toSet();
      final receipts = (await h.db.select(h.db.eventsV2).get())
          .where(
            (e) =>
                replayEventIds.contains(e.aggregateId) &&
                e.aggregateType == 'LearningProjection',
          )
          .toList();
      expect(receipts, hasLength(attempts.length * 4));
      expect(
        receipts.every(
          (e) =>
              e.eventType == 'LearningProjectionSkipped' &&
              (jsonDecode(e.payloadJson) as Map)['outcome'] == 'notApplicable',
        ),
        true,
      );
      await replay.start.start(operation);
      final recovered = await PairMatchingSessionCoordinator.restore(
        operation: operation,
        learning: h.learning,
        evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
        activeOwnerId: () => h.owner,
      );
      await recovered.finish();
      final history = DriftLearningHistoryReader(
        h.db,
        learningTime: time.repository,
        nowUtc: () => DateTime.utc(2026, 9, 5, 0, 2),
      );
      final normal = await history.list(
        HistoryFilter(ownerId: h.owner, limit: 1, includePracticeReplay: false),
      );
      expect(normal.single.sessionId, original.plan.learningSessionId);
      expect(normal.single.pairSummary!.result.stars, 2);
      final all = await history.list(HistoryFilter(ownerId: h.owner));
      expect(all, hasLength(2));
      expect(
        all.first.pairSummary!.sourceSessionId,
        original.plan.learningSessionId,
      );
      expect(all.first.pairSummary!.purpose, PairSessionPurpose.practiceReplay);
      final overview = await history.pairOverview(ownerId: h.owner);
      expect(overview.latestNormal!.sessionId, original.plan.learningSessionId);
      expect(overview.bestNormal!.result.stars, 2);
      expect(
        overview
            .replaysBySource[original.plan.learningSessionId]!
            .single
            .sessionId,
        operation.plan.learningSessionId,
      );
      h.operation = await replay.prepare(
        ownerId: h.owner,
        sourceSessionId: original.plan.learningSessionId,
        launchOperationId: 'synthetic-better-replay',
        createdAtUtc: DateTime.utc(2026, 9, 5, 0, 3),
        appVersion: 'synthetic',
        buildId: 'synthetic',
      );
      await replay.start.start(h.operation);
      var perfect = await h.restore();
      for (var i = 0; i < 4; i++) {
        await h.tap(perfect, 'synthetic-$i', PairTileSide.prompt);
        if (i == 0) {
          h.repository.answerFault = true;
          h.repository.afterWrite = true;
          await expectLater(
            h.tap(perfect, 'synthetic-$i', PairTileSide.target),
            throwsStateError,
          );
          perfect.dispose();
          perfect = await h.restore();
          await perfect.retryPending();
        } else {
          await h.tap(perfect, 'synthetic-$i', PairTileSide.target);
        }
      }
      h.repository.closeFault = true;
      h.repository.afterWrite = true;
      await expectLater(perfect.finish(), throwsStateError);
      perfect.dispose();
      perfect = await h.restore();
      await perfect.finish();
      expect(
        (await h.db.select(h.db.answerAttempts).get()).where(
          (a) => a.sessionId == h.operation.plan.learningSessionId,
        ),
        hasLength(4),
      );
      await reconciler.reconcileOwner(h.owner);
      expect(sinkCalls, isEmpty);
      final updatedOverview = await history.pairOverview(ownerId: h.owner);
      expect(
        updatedOverview.latestNormal!.sessionId,
        original.plan.learningSessionId,
      );
      expect(updatedOverview.bestNormal!.result.stars, 2);
      expect(
        updatedOverview
            .bestReplayFor(original.plan.learningSessionId)!
            .result
            .stars,
        3,
      );
      expect(
        (await history.list(
          HistoryFilter(
            ownerId: h.owner,
            limit: 1,
            includePracticeReplay: false,
          ),
        )).single.sessionId,
        original.plan.learningSessionId,
      );
      expect(await snapshot(), before);
      expect(
        (await h.db.select(h.db.answerAttempts).get())
            .where((a) => a.sessionId == operation.plan.learningSessionId)
            .length,
        attempts.length,
      );
    },
  );
}
