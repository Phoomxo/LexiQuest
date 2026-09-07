import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../../../support/inert_research_dependencies.dart';
import '../../../support/test_quest_use_cases.dart';
import 'pair_matching_evidence_contract_test.dart'
    show PairHarness, PairFaultRepository;
import 'pair_matching_source_composer_test.dart' as lexical;

void main() {
  for (final version in [1, 2, 3, 4, 5]) {
    test(
      'Release A restores exact legacy schema $version through old reader',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        await _abandonFixturePair(h);
        final learning = _realLearning(h);
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final registry = buildLessonModeRegistry();
        final adapter =
            registry.find(LessonMode.matching)!.adapter as MatchingModeAdapter;
        expect(registry.resolve(LessonMode.matching), isNull);
        final original = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'synthetic-category',
          itemCount: 4,
        );
        final rows = await _checkpoints(h, original.session.id);
        expect(rows, hasLength(1));
        final row = rows.single;
        final payload = _json(row.payloadJson);
        final state = (payload['state'] as Map).cast<String, Object?>();
        expect(
          state['schemaVersion'],
          5,
          reason: 'default writer stays legacy',
        );
        state['schemaVersion'] = version;
        if (version < 5) state.remove('timingKind');
        if (version < 4) state.remove('summaryPresented');
        if (version < 3) {
          state.remove('timeoutAnchorUtc');
          state.remove('timeoutDurationMs');
        }
        if (version < 2) {
          state.remove('timeoutDeadlineUtc');
          payload['schemaVersion'] = 1;
          payload.remove('terminalAtUtc');
          payload.remove('terminalAcknowledged');
        }
        payload['state'] = state;
        final historicalBytes = jsonEncode(payload);
        await (h.db.update(
          h.db.eventsV2,
        )..where((r) => r.eventId.equals(row.eventId))).write(
          EventsV2Companion(
            payloadJson: Value(historicalBytes),
            eventVersion: Value(version == 1 ? 1 : row.eventVersion),
          ),
        );
        final restored = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'synthetic-category',
          itemCount: 4,
          timeLimit: const Duration(minutes: 20),
        );
        expect(restored.session.id, original.session.id);
        expect(
          restored.session.questions.map((q) => q.word.id),
          original.session.questions.map((q) => q.word.id),
        );
        expect(
          restored.timeoutDeadlineUtc,
          original.session.startedAtUtc!.add(const Duration(minutes: 2)),
        );
        expect(restored.attemptNumber, 0);
        expect(restored.matchedWordIds, isEmpty);
        final after = await _checkpoints(h, original.session.id);
        expect(
          after.first.payloadJson,
          historicalBytes,
          reason:
              'legacy upgrade appends; it never overwrites historical bytes',
        );
        expect(after, hasLength(version == 5 ? 1 : 2));
        expect(
          (_json(after.last.payloadJson)['state'] as Map)['schemaVersion'],
          5,
        );
        expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
      },
    );
  }

  for (final codec in [1, 2, 3, 4]) {
    test(
      'current reader restores progressed codec $codec with no elapsed backfill',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final c = await h.restore();
        await h.tap(c, 'synthetic-0', PairTileSide.prompt);
        await h.tap(c, 'synthetic-0', PairTileSide.target);
        await h.tap(c, 'synthetic-1', PairTileSide.prompt);
        await c.flush();
        final expectedEngine = jsonEncode(c.state.toJson());
        c.dispose();
        final rows = await _checkpoints(h, h.operation.plan.learningSessionId);
        for (final row in rows.skip(1)) {
          final payload = _json(row.payloadJson);
          final state = (payload['state'] as Map).cast<String, Object?>();
          final decoded = PairMatchingCheckpointCodec.decode(state);
          state['codecVersion'] = codec;
          if (codec < 3) {
            state.remove('timer');
            state.remove('roundSeed');
            state.remove('terminal');
          } else if (codec == 3) {
            (state['timer'] as Map).remove('interactiveElapsedMs');
          }
          if (codec == 1) {
            final compact = state['engine'] as Map;
            state['engine'] = {
              ...decoded.engine.toJson(),
              'attempts': compact['attempts'],
              'pending': compact['pending'],
            };
            state['startOperation'] = h.operation.stableSerialization;
          }
          payload['state'] = state;
          await (h.db.update(
            h.db.eventsV2,
          )..where((r) => r.eventId.equals(row.eventId))).write(
            EventsV2Companion(payloadJson: Value(jsonEncode(payload))),
          );
        }
        final historicalBytes = await _durableBytes(h);
        final restored = await const MatchingModeAdapter().preparePairSession(
          operation: h.operation,
          learning: h.learning,
          evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
          activeOwnerId: () => h.owner,
        );
        expect(jsonEncode(restored.state.toJson()), expectedEngine);
        expect(restored.timer.interactiveElapsedMs, isNull);
        expect(await _durableBytes(h), historicalBytes);
        await h.tap(restored, 'synthetic-1', PairTileSide.target);
        expect(restored.state.attempts, hasLength(2));
        expect(restored.timer.interactiveElapsedMs, isNull);
        final latest = (await _checkpoints(
          h,
          h.operation.plan.learningSessionId,
        )).last;
        final latestState = (_json(latest.payloadJson)['state'] as Map)
            .cast<String, Object?>();
        expect(latestState['codecVersion'], 4);
        expect(
          PairMatchingCheckpointCodec.decode(
            latestState,
          ).timer!.interactiveElapsedMs,
          isNull,
        );
        restored.dispose();
      },
    );
  }

  test(
    'strict schema6 and measured codec4 retain separate start and elapsed identities',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final rows = await _checkpoints(h, h.operation.plan.learningSessionId);
      expect(rows, hasLength(2));
      final initial = (_json(rows.first.payloadJson)['state'] as Map)
          .cast<String, Object?>();
      expect(initial['schemaVersion'], 6);
      expect(initial.containsKey('codecVersion'), false);
      expect(
        jsonEncode(initial),
        jsonEncode(h.operation.initialCheckpoint.state),
      );
      expect(PairMatchingCheckpointCodec.decode(initial).timer, isNull);
      final before = await _durableBytes(h);
      final restored = await h.restore();
      expect(restored.timer.interactiveElapsedMs, 0);
      expect(
        restored.operation.stableSerialization,
        h.operation.stableSerialization,
      );
      expect(await _durableBytes(h), before);
      restored.dispose();
    },
  );

  for (final state in ['initial', 'pending', 'terminal']) {
    test(
      'old reader rejects actual schema6 $state without replacing saved state',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final c = await h.restore();
        if (state == 'pending') {
          await h.tap(c, 'synthetic-0', PairTileSide.prompt);
          h.repository.answerFault = true;
          await expectLater(
            h.tap(c, 'synthetic-0', PairTileSide.target),
            throwsStateError,
          );
          expect(c.state.pending, isNotNull);
        } else if (state == 'terminal') {
          for (var i = 0; i < 4; i++) {
            await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
            await h.tap(c, 'synthetic-$i', PairTileSide.target);
          }
          await c.finish();
          await c.markSummaryPresented();
        }
        c.dispose();
        final before = await _durableBytes(h);
        final learning = _realLearning(h);
        await expectLater(
          const MatchingModeAdapter().prepareSession(
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'reason',
              contains('schema'),
            ),
          ),
        );
        expect(await _durableBytes(h), before);
        final current = await h.restore();
        expect(current.state.pending != null, state == 'pending');
        expect(current.summaryPresented, state == 'terminal');
        current.dispose();
      },
    );
  }

  for (final corruption in [
    'activity7',
    'codec5',
    'unknownKey',
    'legacyDisguisedAs6',
  ]) {
    test(
      'current reader rejects $corruption without rewriting the checkpoint',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final row = (await _checkpoints(
          h,
          h.operation.plan.learningSessionId,
        )).last;
        final payload = _json(row.payloadJson);
        final state = (payload['state'] as Map).cast<String, Object?>();
        switch (corruption) {
          case 'activity7':
            state['schemaVersion'] = 7;
          case 'codec5':
            state['codecVersion'] = 5;
          case 'unknownKey':
            state['legacyStars'] = 3;
          case 'legacyDisguisedAs6':
            state.clear();
            state.addAll({
              'schemaVersion': 6,
              'pairs': [],
              'pendingEvidence': null,
              'pendingCloseAtUtc': null,
              'timeoutRequested': false,
            });
        }
        payload['state'] = state;
        await (h.db.update(h.db.eventsV2)
              ..where((r) => r.eventId.equals(row.eventId)))
            .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));
        final before = await _durableBytes(h);
        await expectLater(
          h.restore(),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
        expect(await _durableBytes(h), before);
      },
    );
  }

  test(
    'internal Pair writer requires explicit capability while unrelated Quiz records normally',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await _abandonFixturePair(h);
      final operation = _nextOperation(h);
      final allowlist = _allowlist(h);
      final disabled = PairMatchingAtomicStartAdapter(
        repository: h.real,
        capability: InternalPairMatchingCapability(allowlist: allowlist),
      );
      final before = await _durableBytes(h);
      await expectLater(
        disabled.startMeasured(operation),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('unavailable'),
          ),
        ),
      );
      expect(await _durableBytes(h), before);

      final learning = _realLearning(h);
      final registration = buildLessonModeRegistry().resolve(
        LessonMode.meaningQuiz,
      )!;
      final quiz = await learning.startQuiz(
        categoryId: 'synthetic-category',
        limit: 2,
      );
      final review = (registration.adapter as MeaningQuizModeAdapter)
          .createReview(
            session: quiz,
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
          );
      await review.answer(
        option: review.currentQuestion.correctOption,
        responseTimeMs: 25,
      );
      expect(
        (await h.db.select(h.db.answerAttempts).get()).single.sessionId,
        quiz.id,
      );
      review.dispose();
      await h.real.abandonSession(
        ownerId: h.owner,
        sessionId: quiz.id,
        abandonedAtUtc: h.learning.nowUtc(),
      );
      await PairMatchingAtomicStartAdapter(
        repository: h.real,
        capability: InternalPairMatchingCapability(
          allowlist: allowlist,
          isEnabled: () => true,
        ),
      ).startMeasured(operation);
      final admitted = await h.real.read(
        ownerId: h.owner,
        sessionId: operation.plan.learningSessionId,
      );
      expect(admitted.snapshot!.timer!.interactiveElapsedMs, 0);
      final admittedBytes = await _durableBytes(h);
      await disabled.startMeasured(operation);
      expect(
        await _durableBytes(h),
        admittedBytes,
        reason: 'gate-off exact accepted-operation retry remains idempotent',
      );
    },
  );

  test(
    'attempts writer1 fails closed preserving outbox; explicit writer2 claims the same Pair answer',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      c.dispose();
      final attempt = (await h.db.select(h.db.answerAttempts).get()).single;
      expect(
        _json(attempt.evidenceContextJson)['classificationSource'],
        'declared',
      );
      const uid = 'pm8-synthetic-compatibility-uid';
      await (h.db.update(h.db.localOwners)..where((r) => r.id.equals(h.owner)))
          .write(const LocalOwnersCompanion(firebaseUid: Value(uid)));
      final gate = DriftOwnerOperationGate(h.db);
      const token = 'pm8-synthetic-owner-gate';
      final now = h.learning.nowUtc();
      expect(
        await gate.tryAcquire(
          token: token,
          nowUtc: now,
          leaseDuration: const Duration(minutes: 2),
        ),
        true,
      );
      try {
        final before = await _durableBytes(h);
        await expectLater(
          DriftSyncStore(h.db).claimPending(
            ownerId: h.owner,
            firebaseUid: uid,
            limit: 50,
            leaseToken: 'pm8-old-writer',
            ownerGateToken: token,
            leaseDuration: const Duration(minutes: 1),
            nowUtc: now,
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
        expect(
          await _durableBytes(h),
          before,
          reason:
              'a failed claim must not delete or downgrade ordinary outbox work',
        );
        final claims =
            await DriftSyncStore(
              h.db,
              payloadRollout: const SyncPayloadRollout.answerAttemptV2(),
            ).claimPending(
              ownerId: h.owner,
              firebaseUid: uid,
              limit: 50,
              leaseToken: 'pm8-compatible-writer',
              ownerGateToken: token,
              leaseDuration: const Duration(minutes: 1),
              nowUtc: now,
            );
        final answer = claims.singleWhere(
          (claim) => claim.mutation.collection == SyncCollection.attempts,
        );
        expect(answer.mutation.entityId, attempt.id);
        expect(answer.mutation.payloadVersion, 2);
        expect(
          answer.mutation.payload['sessionId'],
          h.operation.plan.learningSessionId,
        );
        expect(
          (await h.db.select(h.db.answerAttempts).get()).single.toJson(),
          attempt.toJson(),
        );
      } finally {
        await gate.release(token: token);
      }
    },
  );

  for (final stage in ['answer', 'close']) {
    testWidgets(
      'actual Quiz gate disposal retains accepted $stage and direct reopen completes with starts off',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final features = RuntimeFeatureRegistry(
          BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(features.dispose);
        final repository = _HeldCompatibilityRepository(h.real, stage);
        var enabled = true;
        final runtime = _runtime(h, repository, features, () => enabled);
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: _dependencies(h, runtime, features),
            child: MaterialApp(
              home: ProductionFeatureGate(
                feature: Feature.quiz,
                registry: features,
                builder: (_) => PairMatchingExperienceHost.recover(
                  runtime: runtime,
                  operation: h.operation,
                  onExit: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (stage == 'close') {
          for (var i = 0; i < 3; i++) {
            await _tap(tester, 'prompt', i);
            await _tap(tester, 'target', i);
          }
        }
        final last = stage == 'answer' ? 0 : 3;
        await _tap(tester, 'prompt', last);
        repository.arm();
        await tester.tap(
          find.byKey(ValueKey('pair-tile:target:synthetic-$last')),
        );
        for (var i = 0; i < 30 && !repository.entered!.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(repository.entered!.isCompleted, true);
        final accepted = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        final acceptedEvidence = stage == 'answer'
            ? accepted.snapshot!.frozenEvidence!['sourceEvidenceId']
            : accepted.snapshot!.evidenceIds.last;
        final acceptedClose = accepted.snapshot!.terminal?.atUtc;
        enabled = false;
        features.emergencyOff(Feature.quiz);
        await tester.pump();
        expect(find.byType(PairMatchingExperienceHost), findsNothing);
        expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        repository.release!.complete();
        await tester.pumpAndSettle();
        final retained = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(retained.snapshot!.evidenceIds, contains(acceptedEvidence));
        if (stage == 'close') {
          expect(retained.snapshot!.terminal!.atUtc, acceptedClose);
        }
        expect(
          await h.db.select(h.db.answerAttempts).get(),
          hasLength(stage == 'answer' ? 1 : 4),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost.recover(
              runtime: runtime,
              operation: h.operation,
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (stage == 'answer') {
          for (var i = 1; i < 4; i++) {
            await _tap(tester, 'prompt', i);
            await _tap(tester, 'target', i);
          }
        }
        expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
        final terminal = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(terminal.snapshot!.terminal!.presented, true);
        expect(terminal.snapshot!.evidenceIds.toSet(), hasLength(4));
        expect(terminal.snapshot!.evidenceIds, contains(acceptedEvidence));
        expect(await h.db.select(h.db.learningSessions).get(), hasLength(1));
        expect(await h.db.select(h.db.answerAttempts).get(), hasLength(4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}

Map<String, Object?> _json(String value) =>
    (jsonDecode(value) as Map).cast<String, Object?>();

Future<List<EventsV2Data>> _checkpoints(PairHarness h, String sessionId) async {
  final rows =
      (await (h.db.select(
            h.db.eventsV2,
          )..where((r) => r.aggregateId.equals(sessionId))).get())
          .where((r) => r.eventType == 'LearningActivityCheckpoint')
          .toList();
  rows.sort(
    (a, b) => (_json(a.payloadJson)['revision'] as int).compareTo(
      _json(b.payloadJson)['revision'] as int,
    ),
  );
  return rows;
}

Future<String> _durableBytes(PairHarness h) async => jsonEncode({
  'sessions': (await h.db.select(h.db.learningSessions).get())
      .map((r) => r.toJson())
      .toList(),
  'events': (await h.db.select(h.db.eventsV2).get())
      .map((r) => r.toJson())
      .toList(),
  'answers': (await h.db.select(h.db.answerAttempts).get())
      .map((r) => r.toJson())
      .toList(),
  'outbox': (await h.db.select(h.db.outboxOperations).get())
      .map((r) => r.toJson())
      .toList(),
});

LearningUseCases _realLearning(PairHarness h) => LearningUseCases(
  owners: h.learning.owners,
  repository: h.real,
  generateId: h.learning.generateId,
  nowUtc: h.learning.nowUtc,
  buildInfo: h.learning.buildInfo,
);

Future<void> _abandonFixturePair(PairHarness h) async {
  await h.real.abandonSession(
    ownerId: h.owner,
    sessionId: h.operation.plan.learningSessionId,
    abandonedAtUtc: h.learning.nowUtc(),
  );
}

PairCuratedAllowlist _allowlist(PairHarness h) => PairCuratedAllowlist(
  version: h.operation.plan.allowlistVersion,
  items: h.operation.plan.orderedLexicalItems,
);

PairMatchingStartOperation _nextOperation(PairHarness h) {
  final launch = PairMatchingLaunchIntent(
    ownerId: h.owner,
    sourceSurface: PairSourceSurface.learn,
    sourceSnapshotRef: 'synthetic-snapshot',
    operationId: 'pm8-explicit-next',
    createdAtUtc: h.learning.nowUtc(),
    requestedDensity: PairDensity.compact4,
  );
  final plan =
      (lexical.compose(
                h.operation.plan.orderedLexicalItems.toList(),
                launch: launch,
              )
              as PairPlanReady)
          .plan;
  return PairMatchingStartOperation(
    plan: plan,
    launchOperationId: launch.operationId,
    appVersion: 'synthetic',
    buildId: 'synthetic',
  );
}

// Reuse the real SQL fault fixture and forward the host's pinned/configuration
// interfaces. The only behavior added is a barrier for parent-gate disposal.
final class _HeldCompatibilityRepository extends PairFaultRepository
    implements
        PinnedLearningContentRepository,
        SessionConfiguredLearningRepository,
        LearningSessionLifecycleRepository {
  _HeldCompatibilityRepository(super.delegate, this.stage);
  final String stage;
  Completer<void>? entered, release;
  void arm() {
    entered = Completer<void>();
    release = Completer<void>();
  }

  Future<void> _hold(String value) async {
    if (stage != value || entered == null || entered!.isCompleted) return;
    entered!.complete();
    await release!.future;
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    await _hold('answer');
    return super.recordAnswer(command);
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    await _hold('close');
    return super.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<LearningSessionSummary?> getActiveSession({required String ownerId}) =>
      delegate.getActiveSession(ownerId: ownerId);
  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) => delegate.loadSessionConfigurationState(
    ownerId: ownerId,
    sessionId: sessionId,
  );
  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) => delegate.addSessionConfigurationActiveEffort(
    ownerId: ownerId,
    sessionId: sessionId,
    configurationIdentity: configurationIdentity,
    delta: delta,
  );
  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) => delegate.abandonSession(
    ownerId: ownerId,
    sessionId: sessionId,
    abandonedAtUtc: abandonedAtUtc,
  );
  @override
  Future<List<QuizWord>> listPinnedQuizWords({
    required String ownerId,
    required List<String> wordIds,
  }) => delegate.listPinnedQuizWords(ownerId: ownerId, wordIds: wordIds);
  @override
  Future<List<QuizWord>> listExactPinnedQuizWords({
    required String ownerId,
    required List<PinnedQuizContent> content,
  }) => delegate.listExactPinnedQuizWords(ownerId: ownerId, content: content);
}

PairMatchingExperienceRuntime _runtime(
  PairHarness h,
  _HeldCompatibilityRepository repository,
  FeatureRegistry features,
  bool Function() enabled,
) {
  final learning = LearningUseCases(
    owners: h.learning.owners,
    repository: repository,
    generateId: h.learning.generateId,
    nowUtc: h.learning.nowUtc,
    buildInfo: h.learning.buildInfo,
  );
  final allowlist = _allowlist(h);
  return PairMatchingExperienceRuntime(
    database: h.db,
    learning: learning,
    currentActivityEvidence: CurrentActivityEvidenceAdapter(learning: learning),
    registry: buildLessonModeRegistry(
      internalPairMatching: true,
      matchingDeliveryState: LessonModeDeliveryState.enabled,
    ),
    createController: (adapter) => UnifiedLessonController(
      learning: learning,
      adapter: adapter,
      sessionPurposeReader: h.real,
    ),
    composer: PairMatchingSourceComposer(allowlist: allowlist),
    start: PairMatchingAtomicStartAdapter(
      repository: h.real,
      capability: InternalPairMatchingCapability(
        allowlist: allowlist,
        isEnabled: enabled,
      ),
    ),
    features: features,
    canStart: enabled,
    monotonicMicros: () => 0,
  );
}

AppDependencies _dependencies(
  PairHarness h,
  PairMatchingExperienceRuntime runtime,
  FeatureRegistry features,
) {
  final research = InertResearchDependencies(h.db);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _Guest(),
    quest: testQuestUseCases(),
    features: features,
    learning: runtime.learning,
    currentActivityEvidence: runtime.currentActivityEvidence,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
  );
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'pm8-synthetic-compatibility');
}

Future<void> _tap(WidgetTester tester, String side, int index) async {
  final tile = find.byKey(ValueKey('pair-tile:$side:synthetic-$index'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}
