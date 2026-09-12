import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_unavailable_session.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_session_purpose.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/features/review/application/pair_review_deferral.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/data/drift_learning_history_reader.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import '../../../support/inert_research_dependencies.dart';
import '../../../support/test_quest_use_cases.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'pair_matching_evidence_contract_test.dart'
    show PairHarness, PairFaultRepository;
import 'pair_timeout_recovery_test.dart' show timedPlan, clocked;

final class _ComposedRollout implements EvidencePolicyRolloutModeProvider {
  final owners = <String>[];
  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) async {
    owners.add(ownerId);
    return EvidencePolicyRolloutMode.legacy;
  }
}

final class _ComposedResearch implements CurrentActivityResearchStateProvider {
  final calls = <({String owner, CurrentActivityInput input, DateTime time})>[];
  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) {
    calls.add((owner: ownerId, input: input, time: occurredAtUtc));
    return const BaselineCurrentActivityResearchStateProvider().resolveActivity(
      ownerId: ownerId,
      input: input,
      occurredAtUtc: occurredAtUtc,
      rolloutMode: rolloutMode,
    );
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) => const BaselineCurrentActivityResearchStateProvider().resolve(
    ownerId: ownerId,
    evidenceContext: evidenceContext,
    occurredAtUtc: occurredAtUtc,
  );
}

final class _HeldHostRepository extends PairFaultRepository
    implements
        PinnedLearningContentRepository,
        SessionConfiguredLearningRepository,
        LearningSessionLifecycleRepository {
  _HeldHostRepository(super.delegate);
  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) async {
    if (failConfigurationLoadOnce) {
      failConfigurationLoadOnce = false;
      throw StateError('synthetic configuration read unavailable');
    }
    return delegate.loadSessionConfigurationState(
      ownerId: ownerId,
      sessionId: sessionId,
    );
  }

  bool failConfigurationLoadOnce = false;
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
  }) async {
    abandonTimes.add(abandonedAtUtc);
    final fault = abandonFault;
    abandonFault = null;
    if (fault == false) throw StateError('synthetic abandon before commit');
    final result = await delegate.abandonSession(
      ownerId: ownerId,
      sessionId: sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
    if (fault == true) throw StateError('synthetic abandon lost ack');
    return result;
  }

  bool? abandonFault;
  final closeTimes = <DateTime>[];
  final abandonTimes = <DateTime>[];
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
  Completer<void>? entered, release;
  String heldStage = 'answer';
  Future<void> _hold(String stage) async {
    if (heldStage != stage) return;
    if (entered?.isCompleted == false) entered!.complete();
    await release?.future;
  }

  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    await _hold('capture');
    await super.appendActivityCheckpoint(
      ownerId: ownerId,
      checkpoint: checkpoint,
    );
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    await _hold('close');
    closeTimes.add(endedAtUtc);
    return super.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    await _hold('answer');
    return super.recordAnswer(command);
  }
}

final class _FailResultRead implements PairMatchingSessionPurposeReader {
  _FailResultRead(this.delegate);
  final PairMatchingSessionPurposeReader delegate;
  bool failed = false;
  @override
  Future<PairMatchingSessionPurpose> read({
    required String ownerId,
    required String sessionId,
  }) async {
    final result = await delegate.read(ownerId: ownerId, sessionId: sessionId);
    if (!failed && result.snapshot?.terminal?.acknowledged == true) {
      failed = true;
      throw StateError('synthetic authenticated result read unavailable');
    }
    return result;
  }
}

final class _Protocols implements SessionConfigurationProtocolProvider {
  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => const SessionConfigurationProtocolLimits.standard();
}

final class _GenericHistoryLauncher implements LearningHistorySessionLauncher {
  int calls = 0;
  @override
  Object get authorityIdentity => this;
  @override
  Future<void> start(LessonStartCommand command) async {
    calls++;
  }
}

final class _ShortProtocols implements SessionConfigurationProtocolProvider {
  const _ShortProtocols({this.seconds = 60});
  final int seconds;
  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => SessionConfigurationProtocolLimits(
    schemaVersion: 1,
    protocolId: 'synthetic-short',
    protocolVersion: '1',
    minimumItemCount: 1,
    maximumItemCount: 20,
    maximumHintBudget: 2,
    minimumTimedSeconds: 60,
    maximumTimedSeconds: seconds,
    allowsUntimedAlternative: true,
    maximumUntimedActiveEffortSeconds: seconds,
  );
}

final class _HostVoice implements VoiceProvider {
  final requests = <VoiceRequest>[];
  bool fail = false, failStop = false;
  Completer<void>? playback;
  Completer<void>? stopEntered, stopRelease;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    if (fail) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.synthesis,
        message: 'synthetic local voice unavailable',
      );
    }
    final completion = playback;
    if (completion != null) return _HostCompletionResult(completion.future);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    if (stopEntered?.isCompleted == false) stopEntered!.complete();
    await stopRelease?.future;
    if (failStop) {
      throw StateError('synthetic stop acknowledgement unavailable');
    }
  }
}

final class _HostCompletionResult extends VoicePlaybackResult {
  const _HostCompletionResult(Future<void> completion)
    : super(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
        playbackCompleted: completion,
      );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-pair-host');
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
    guestSessionService: _GuestSession(),
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

PairMatchingExperienceRuntime _runtime(
  PairHarness h, {
  int Function()? clock,
  _HeldHostRepository? repository,
  bool Function()? canStart,
  SessionConfigurationProtocolProvider? protocols,
  VoiceUseCases? voice,
  PairMatchingSessionPurposeReader? resultReader,
  CurrentActivityEvidenceAdapter Function(LearningUseCases)? evidenceBuilder,
}) {
  final repo = repository ?? _HeldHostRepository(h.real);
  final learning = LearningUseCases(
    owners: h.learning.owners,
    repository: repo,
    generateId: h.learning.generateId,
    nowUtc: h.learning.nowUtc,
    buildInfo: h.learning.buildInfo,
  );
  final allowlist = PairCuratedAllowlist(
    version: h.operation.plan.allowlistVersion,
    items: h.operation.plan.orderedLexicalItems,
  );
  return PairMatchingExperienceRuntime(
    database: h.db,
    resultReader: resultReader,
    learning: learning,
    currentActivityEvidence:
        evidenceBuilder?.call(learning) ??
        CurrentActivityEvidenceAdapter(learning: learning),
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
    protocols: protocols,
    voice: voice,
    reviewDeferral: PairReviewDeferral(h.db),
    start: PairMatchingAtomicStartAdapter(
      repository: h.real,
      capability: InternalPairMatchingCapability(
        allowlist: allowlist,
        isEnabled: canStart,
      ),
    ),
    canStart: canStart,
    monotonicMicros: clock,
  );
}

void main() {
  for (final interruption in ['dispose', 'owner']) {
    testWidgets(
      'R15 feedback rejects duplicate input and cleans up on $interruption',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost.recover(
              runtime: _runtime(h),
              operation: h.operation,
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(
          const ValueKey('pair-tile:target:synthetic-0'),
        );
        await tester.ensureVisible(target);
        final stalePress = tester.widget<OutlinedButton>(target).onPressed!;
        await tester.tap(target);
        for (
          var tick = 0;
          tick < 30 && find.text('Correct').evaluate().isEmpty;
          tick++
        ) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(find.text('Correct'), findsNWidgets(2));
        stalePress();
        await tester.pump(const Duration(milliseconds: 1));
        if (interruption == 'dispose') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          await h.db.customStatement('UPDATE local_owners SET is_active = 0');
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.text('Correct'), findsNothing);
        expect((await h.db.select(h.db.answerAttempts).get()), hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'R15 final pair is durable before presentation reduced=$reduced',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final runtime = _runtime(h);
        Widget app() => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: PairMatchingExperienceHost.recover(
            runtime: runtime,
            operation: h.operation,
            onExit: () {},
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        Future<void> waitForInput(Finder tile) async {
          for (var tick = 0; tick < 40; tick++) {
            await tester.pump(const Duration(milliseconds: 1));
            if (tester.widget<OutlinedButton>(tile).onPressed != null) return;
          }
          fail('Pair input did not become available within the bounded wait');
        }
        for (var i = 0; i < 4; i++) {
          final prompt = find.byKey(ValueKey('pair-tile:prompt:synthetic-$i'));
          await waitForInput(prompt);
          await tester.ensureVisible(prompt);
          await tester.tap(prompt);
          final target = find.byKey(ValueKey('pair-tile:target:synthetic-$i'));
          await waitForInput(target);
          await tester.ensureVisible(target);
          await tester.tap(target);
          if (i == 3) {
            for (var tick = 0; tick < 40; tick++) {
              await tester.pump(const Duration(milliseconds: 1));
              final saved = await h.real.read(
                ownerId: h.owner,
                sessionId: h.operation.plan.learningSessionId,
              );
              if (saved.snapshot?.terminal?.acknowledged == true) break;
            }
          }
        }
        final durable = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(durable.snapshot!.terminal!.acknowledged, true);
        expect(durable.snapshot!.evidenceIds, hasLength(4));
        await tester.pump(const Duration(milliseconds: 1));
        if (!reduced) {
          expect(find.byKey(const ValueKey('pair-result')), findsNothing);
          expect(
            durable.snapshot!.terminal!.presented,
            false,
            reason:
                'the summary is not presented while final feedback is visible',
          );
          expect(
            find.byKey(const ValueKey('pair-feedback:prompt:synthetic-3')),
            findsOneWidget,
          );
          expect(
            find.text('Correct').evaluate().length,
            greaterThanOrEqualTo(4),
            reason: 'overlapping pairs keep separate feedback episodes',
          );
          await tester.pump(const Duration(milliseconds: 600));
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'pair-result-heading',
        );
        final attempts = (await h.db.select(h.db.answerAttempts).get()).length;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
        expect(find.text('Correct'), findsNothing);
        expect((await h.db.select(h.db.answerAttempts).get()).length, attempts);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets('R15 accepted pair remains readable before its slots disappear', (
    tester,
  ) async {
    final h = PairHarness();
    addTearDown(h.db.close);
    await h.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: PairMatchingExperienceHost.recover(
          runtime: _runtime(h),
          operation: h.operation,
          onExit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
    );
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('pair-tile:target:synthetic-0'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    for (var i = 0; i < 30 && find.text('Correct').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.text('Correct'), findsNWidgets(2));
    final saved = await h.real.loadExactActivityRecovery(
      ownerId: h.owner,
      sessionId: h.operation.plan.learningSessionId,
      activityType: 'matching',
    );
    expect(saved!.attempts.length, 1);
    await tester.pump(const Duration(milliseconds: 449));
    expect(find.text('Correct'), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 151));
    expect(find.text('Correct'), findsNothing);
    expect(
      find.byKey(const ValueKey('pair-placeholder:prompt:synthetic-0')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  test(
    'Pair composition rejects a different learning authority before use',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final foreign = CurrentActivityEvidenceAdapter(learning: h.learning);
      expect(
        () => _runtime(h, evidenceBuilder: (_) => foreign),
        throwsArgumentError,
      );
      final runtime = _runtime(h);
      expect(
        () => PairMatchingUnavailableSession(
          operation: h.operation,
          learning: runtime.learning,
          currentActivityEvidence: foreign,
          requireOwner: runtime.requireOwner,
        ),
        throwsArgumentError,
      );
    },
  );

  testWidgets(
    'Pair host records with the composed providers and evidence identity',
    (tester) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final rollout = _ComposedRollout();
      final research = _ComposedResearch();
      final occurredAt = h.learning.nowUtc().add(const Duration(seconds: 1));
      final runtime = _runtime(
        h,
        evidenceBuilder: (learning) => CurrentActivityEvidenceAdapter(
          learning: learning,
          rolloutModeProvider: rollout,
          researchStateProvider: research,
          generateId: () => 'synthetic-composed-evidence',
          nowUtc: () => occurredAt,
        ),
      );
      expect(
        identical(
          _dependencies(
            h,
            runtime,
            const BuildFeatureRegistry({}),
          ).currentActivityEvidence,
          runtime.currentActivityEvidence,
        ),
        isTrue,
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
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('pair-tile:target:synthetic-0'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      final recovery = await h.real.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      expect(
        recovery!.attempts.single.id,
        'attempt:synthetic-composed-evidence',
      );
      expect(rollout.owners, [h.owner]);
      expect(research.calls, [
        (
          owner: h.owner,
          input: CurrentActivityInput.matchingPair,
          time: occurredAt,
        ),
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test(
    'Pair normal close rejects overflow before a hidden Pair marker',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      const sessionId = 'synthetic-generic-overflow';
      await h.db.customStatement(
        'UPDATE learning_sessions SET id=? WHERE id=?',
        [sessionId, h.operation.plan.learningSessionId],
      );
      await h.db.customStatement(
        'UPDATE events_v2 SET aggregate_id=? WHERE aggregate_id=?',
        [sessionId, h.operation.plan.learningSessionId],
      );
      final original =
          (await h.db.customSelect('SELECT * FROM events_v2').getSingle()).data;
      for (var i = 0; i < 65; i++) {
        final payload =
            jsonDecode(original['payload_json'] as String)
                as Map<String, dynamic>;
        payload['sessionId'] = sessionId;
        payload['state'] = <String, Object?>{'identity': 'accepted'};
        final candidate = <String, Object?>{
          ...original,
          'event_id': '000-generic-${i.toString().padLeft(3, '0')}',
          'idempotency_key': '000-generic-${i.toString().padLeft(3, '0')}',
          'payload_json': jsonEncode(payload),
        };
        await h.db.customStatement(
          'INSERT INTO events_v2 (${candidate.keys.join(',')}) VALUES (${List.filled(candidate.length, '?').join(',')})',
          candidate.values.toList(),
        );
      }
      final query = PairMatchingSessionPurpose.checkpointQuery(
        h.owner,
        sessionId,
      );
      final window = await h.db
          .customSelect(
            query.sql,
            variables: [for (final arg in query.args) Variable(arg as String)],
          )
          .get();
      expect(window, hasLength(65));
      expect(
        window.every(
          (r) =>
              ((jsonDecode(r.data['payload_json'] as String) as Map)['state']
                  as Map)['schemaVersion'] !=
              6,
        ),
        true,
      );
      expect(await h.db.select(h.db.eventsV2).get(), hasLength(66));
      final before = await h.db.select(h.db.learningSessions).getSingle();
      await expectLater(
        h.real.finishSession(
          ownerId: h.owner,
          sessionId: sessionId,
          endedAtUtc: h.learning.nowUtc(),
        ),
        throwsStateError,
      );
      expect(await h.db.select(h.db.learningSessions).getSingle(), before);
      expect(await h.db.select(h.db.achievementUnlocks).get(), isEmpty);
    },
  );
  for (final corruption in [
    'missing',
    'generic',
    'legacyMarker',
    'nonReservedId',
  ]) {
    test('Pair normal close cannot downgrade authority $corruption', () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: corruption == 'nonReservedId');
      var sessionId = h.operation.plan.learningSessionId;
      if (corruption == 'missing') {
        await h.db.customStatement(
          'DELETE FROM events_v2 WHERE aggregate_id=?',
          [sessionId],
        );
      } else if (corruption == 'nonReservedId') {
        const renamed = 'synthetic-generic-close';
        await h.db.customStatement(
          'UPDATE learning_sessions SET id=? WHERE id=?',
          [renamed, sessionId],
        );
        await h.db.customStatement(
          'UPDATE events_v2 SET aggregate_id=? WHERE aggregate_id=?',
          [renamed, sessionId],
        );
        final latest = (await h.db.select(h.db.eventsV2).get()).singleWhere(
          (r) => (jsonDecode(r.payloadJson) as Map)['revision'] == 2,
        );
        final payload = jsonDecode(latest.payloadJson) as Map<String, dynamic>;
        payload['state'] = <String, Object?>{'identity': 'accepted'};
        await h.db.customStatement(
          'UPDATE events_v2 SET payload_json=? WHERE event_id=?',
          [jsonEncode(payload), latest.eventId],
        );
        sessionId = renamed;
      } else {
        final rows = await h.db.select(h.db.eventsV2).get();
        for (final row in rows.where((r) => r.aggregateId == sessionId)) {
          final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
          payload['state'] = corruption == 'generic'
              ? <String, Object?>{'identity': 'accepted'}
              : <String, Object?>{'schemaVersion': 5};
          await h.db.customStatement(
            'UPDATE events_v2 SET payload_json=? WHERE event_id=?',
            [jsonEncode(payload), row.eventId],
          );
        }
      }
      final before = await h.db.select(h.db.learningSessions).getSingle();
      await expectLater(
        h.real.finishSession(
          ownerId: h.owner,
          sessionId: sessionId,
          endedAtUtc: h.learning.nowUtc(),
        ),
        throwsStateError,
      );
      expect(await h.db.select(h.db.learningSessions).getSingle(), before);
      expect(await h.db.select(h.db.achievementUnlocks).get(), isEmpty);
    });
  }
  test(
    'normal Pair close rejects incomplete accepted board without mutation',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final before = await h.db.select(h.db.learningSessions).getSingle();
      await expectLater(
        h.real.finishSession(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          endedAtUtc: h.learning.nowUtc(),
        ),
        throwsStateError,
      );
      expect(await h.db.select(h.db.learningSessions).getSingle(), before);
      expect(await h.db.select(h.db.achievementUnlocks).get(), isEmpty);
    },
  );
  for (final ending in ['natural', 'routeStop', 'takeover', 'failedStop']) {
    testWidgets(
      'Pair narration counts no listening time before actual end $ending',
      (tester) async {
        var micros = 0;
        final h = PairHarness(pinnedPlan: timedPlan());
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final provider = _HostVoice()..playback = Completer<void>();
        final voice = VoiceUseCases(
          provider: provider,
          disposeProvider: () async {},
        );
        addTearDown(voice.dispose);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [appRouteObserver],
            home: PairMatchingExperienceHost.recover(
              runtime: _runtime(h, clock: () => micros, voice: voice),
              operation: h.operation,
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        micros = 1000000;
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.pumpAndSettle();
        final pronounce = find.byKey(
          const ValueKey('pair-pronounce:prompt:synthetic-0'),
        );
        await tester.ensureVisible(pronounce);
        await tester.tap(pronounce);
        await tester.pumpAndSettle();
        expect(provider.requests, hasLength(1));
        micros = 9000000;
        await tester.pump(const Duration(milliseconds: 300));
        final during = tester
            .widget<PairBoardView>(find.byType(PairBoardView))
            .model;
        expect(during.timer.reasons, contains(PairPauseReason.narration));
        expect(during.timer.interactiveElapsedMs, 1000);
        expect(during.timer.remainingActiveMs, 59000);
        if (ending == 'natural') {
          provider.playback!.complete();
        } else {
          provider.stopEntered = Completer<void>();
          provider.stopRelease = Completer<void>();
          provider.failStop = ending == 'failedStop';
          if (ending == 'routeStop' || ending == 'failedStop') {
            unawaited(
              navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Text('synthetic voice cover')),
                ),
              ),
            );
          } else {
            voice.acquireSession();
          }
          for (var i = 0; i < 40 && !provider.stopEntered!.isCompleted; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(provider.stopEntered!.isCompleted, true);
          final stopping = tester
              .widget<PairBoardView>(
                find.byType(PairBoardView, skipOffstage: false),
              )
              .model;
          expect(stopping.timer.reasons, contains(PairPauseReason.narration));
          provider.stopRelease!.complete();
          await tester.pumpAndSettle();
          provider.playback!
              .complete(); // late old end cannot resume a covered route
          if (ending == 'routeStop' || ending == 'failedStop') {
            navigator.currentState!.pop();
          }
        }
        await tester.pumpAndSettle();
        micros = 10000000;
        await tester.pump(const Duration(milliseconds: 300));
        if (ending == 'failedStop') {
          final blockedBoard = tester.widget<PairBoardView>(
            find.byType(PairBoardView),
          );
          final uncertain = blockedBoard.model.timer;
          expect(uncertain.reasons, contains(PairPauseReason.narration));
          expect(uncertain.interactiveElapsedMs, 1000);
          expect(blockedBoard.model.busy, true);
          blockedBoard.onSelectTile(
            const PairTile(PairTileSide.target, 'synthetic-0'),
          );
          await tester.pumpAndSettle();
          expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
          provider.failStop = false;
          final retryStop = find.byKey(const ValueKey('pair-retry-audio-stop'));
          await tester.ensureVisible(retryStop);
          await tester.tap(retryStop);
          await tester.pumpAndSettle();
          micros = 11000000;
          await tester.pump(const Duration(milliseconds: 300));
        }
        final after = tester
            .widget<PairBoardView>(find.byType(PairBoardView))
            .model
            .timer;
        expect(after.reasons, isNot(contains(PairPauseReason.narration)));
        expect(after.interactiveElapsedMs, 2000);
        expect(after.remainingActiveMs, 58000);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final ownerChange in ['logout', 'switch', 'insideClose']) {
    testWidgets('queued normal Pair close rejects owner change $ownerChange', (
      tester,
    ) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final repository = _HeldHostRepository(h.real)..heldStage = 'close';
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h, repository: repository),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')));
        await tester.pumpAndSettle();
        if (i == 3) {
          repository.entered = Completer<void>();
          repository.release = Completer<void>();
        }
        await tester.tap(find.byKey(ValueKey('pair-tile:target:synthetic-$i')));
        if (i < 3) await tester.pumpAndSettle();
      }
      for (var i = 0; i < 40 && !repository.entered!.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(repository.entered!.isCompleted, true);
      if (ownerChange == 'insideClose') {
        await h.db.customStatement(
          "CREATE TRIGGER pm8_close_owner AFTER UPDATE OF state ON learning_sessions WHEN NEW.state='completed' BEGIN UPDATE local_owners SET is_active=0 WHERE id=NEW.owner_id; END",
        );
      } else {
        await h.db.customStatement('UPDATE local_owners SET is_active=0');
        if (ownerChange == 'switch') {
          await h.db.customStatement(
            "INSERT INTO local_owners (id,is_active,created_at_utc_ms) VALUES ('synthetic-other-active',1,1)",
          );
        }
      }
      Future<String> durable() async => jsonEncode({
        for (final table in [
          'learning_sessions',
          'events_v2',
          'answer_attempts',
          'achievement_unlocks',
          'outbox_operations',
          'local_owners',
        ])
          table:
              (await h.db
                      .customSelect('SELECT * FROM $table ORDER BY rowid')
                      .get())
                  .map((r) => r.data)
                  .toList(),
      });
      final before = await durable();
      repository.release!.complete();
      await tester.pumpAndSettle();
      expect(await durable(), before);
      expect(find.byKey(const ValueKey('pair-result')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(await durable(), before);
    });
  }
  testWidgets(
    'covered and returned during accepted write resumes visible Pair clocks',
    (tester) async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final repository = _HeldHostRepository(h.real);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [appRouteObserver],
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h, clock: () => micros, repository: repository),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      micros = 1000000;
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
      );
      await tester.pumpAndSettle();
      repository.entered = Completer<void>();
      repository.release = Completer<void>();
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
      );
      for (var i = 0; i < 40 && !repository.entered!.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(repository.entered!.isCompleted, true);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('synthetic cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      micros = 9000000;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<PairBoardView>(find.byType(PairBoardView)).model.busy,
        true,
      );
      repository.release!.complete();
      await tester.pumpAndSettle();
      final resumed = tester
          .widget<PairBoardView>(find.byType(PairBoardView))
          .model
          .timer;
      expect(
        resumed.reasons,
        isNot(contains(PairPauseReason.boardUnavailable)),
      );
      micros = 10000000;
      await tester.pump(const Duration(milliseconds: 300));
      final advanced = tester
          .widget<PairBoardView>(find.byType(PairBoardView))
          .model
          .timer;
      expect(advanced.interactiveElapsedMs, 2000);
      expect(advanced.elapsedActiveMs, 2000);
      expect(advanced.remainingActiveMs, 58000);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final fault in ['closeBefore', 'closeAfter', 'resultRead']) {
    testWidgets('same host retries exact canonical completion fault=$fault', (
      tester,
    ) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final repo = _HeldHostRepository(h.real)
        ..closeFault = fault != 'resultRead'
        ..afterWrite = fault == 'closeAfter';
      final runtime = _runtime(
        h,
        repository: repo,
        resultReader: fault == 'resultRead' ? _FailResultRead(h.real) : null,
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
      final controller = tester
          .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
          .controller;
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('pair-tile:target:synthetic-$i')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('pair-result')), findsNothing);
      final before = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(before.snapshot!.terminal!.presented, false);
      expect(find.byKey(const ValueKey('pair-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pair-retry')));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester
              .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
              .controller,
          controller,
        ),
        true,
      );
      expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
      final after = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(after.snapshot!.terminal!.presented, true);
      expect(repo.closeTimes.toSet(), hasLength(1));
      expect(
        repo.checkpoints.where((p) => p.terminalAtUtc != null),
        hasLength(3),
      );
      expect(await h.db.select(h.db.answerAttempts).get(), hasLength(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    'restored timed capacity stays actionable without postframe exception',
    (tester) async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      while (!c.timer.reasons.contains(PairPauseReason.capacity)) {
        micros += 1000;
        final lease = c.pause(PairPauseReason.modal);
        await c.flush();
        try {
          c.releasePause(lease);
        } on StateError {
          expect(c.timer.reasons, contains(PairPauseReason.capacity));
        }
      }
      c.dispose();
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h, clock: () => micros),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final continueAction = find.byKey(
        const ValueKey('pair-timer-action-continueUntimed'),
      );
      expect(continueAction, findsOneWidget);
      await tester.tap(continueAction);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-board-regular')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final action in ['reveal', 'timer']) {
    testWidgets(
      'actual parent gate preserves pending $action checkpoint without synthesizing an answer',
      (tester) async {
        var micros = 0;
        final h = PairHarness(
          pinnedPlan: action == 'timer' ? timedPlan() : null,
        );
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        if (action == 'timer') {
          final c = await clocked(h, () => micros);
          c.resumeInteraction();
          micros = 60000000;
          await c.expire();
          c.dispose();
        }
        final repository = _HeldHostRepository(h.real)..heldStage = 'capture';
        final runtime = _runtime(
          h,
          repository: repository,
          clock: () => micros,
        );
        final features = RuntimeFeatureRegistry(
          BuildFeatureRegistry.allEnabled(),
        );
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
        if (action == 'reveal') {
          await tester.tap(
            find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
          );
          await tester.pumpAndSettle();
        }
        repository.entered = Completer<void>();
        repository.release = Completer<void>();
        final trigger = find.byKey(
          ValueKey(
            action == 'timer'
                ? 'pair-timer-action-continueUntimed'
                : 'pair-reveal:synthetic-0',
          ),
        );
        await tester.ensureVisible(trigger);
        await tester.tap(trigger);
        for (var i = 0; i < 30 && !repository.entered!.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(repository.entered!.isCompleted, true);
        features.emergencyOff(Feature.quiz);
        await tester.pump();
        expect(find.byType(PairMatchingExperienceHost), findsNothing);
        repository.release!.complete();
        await tester.pumpAndSettle();
        final retained = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(retained.snapshot!.engine.attempts, isEmpty);
        if (action == 'reveal') {
          expect(
            retained.snapshot!.engine.supportedWordIds,
            contains('synthetic-0'),
          );
        } else {
          expect(retained.snapshot!.timer!.mode.name, 'continuedUntimed');
        }
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
        if (action == 'reveal') {
          final confirm = find.byKey(
            const ValueKey('pair-confirm-guided:synthetic-0'),
          );
          await tester.ensureVisible(confirm);
          await tester.tap(confirm);
          await tester.pumpAndSettle();
        }
        for (var i = action == 'reveal' ? 1 : 0; i < 4; i++) {
          for (final side in ['prompt', 'target']) {
            final tile = find.byKey(ValueKey('pair-tile:$side:synthetic-$i'));
            await tester.ensureVisible(tile);
            await tester.tap(tile);
            await tester.pumpAndSettle();
          }
        }
        final finished = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(finished.snapshot!.terminal!.presented, true);
        expect(finished.snapshot!.evidenceIds.toSet(), hasLength(4));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'actual background pause flush excludes hidden duration and resumes same Pair clock',
    (tester) async {
      var micros = 0;
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h, clock: () => micros),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      micros = 1000000;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      final paused = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(paused.snapshot!.timer!.interactiveElapsedMs, 1000);
      micros = 9000000;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      micros = 10000000;
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('pair-tile:target:synthetic-$i')));
        await tester.pumpAndSettle();
      }
      final finished = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(finished.snapshot!.timer!.interactiveElapsedMs, 2000);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final presented = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(presented.snapshot!.terminal!.presented, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final lateFailure in [false, true]) {
    testWidgets(
      'presentation replacement keeps owning host and selected Pair across decoration failure late=$lateFailure',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final runtime = _runtime(h);
        final decoration = ValueNotifier<PairBoardDecoration?>(null);
        addTearDown(decoration.dispose);
        ValueChanged<PairDecorationFailure>? fail;
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<PairBoardDecoration?>(
              valueListenable: decoration,
              builder: (_, decorate, _) => PairMatchingExperienceHost.recover(
                runtime: runtime,
                operation: h.operation,
                decoration: decorate,
                onExit: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final original = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller;
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.pumpAndSettle();
        final before = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          activityType: 'matching',
        );
        decoration.value = (context, model, board, reportFailure) {
          if (!lateFailure) {
            throw StateError('synthetic decoration unavailable');
          }
          fail = reportFailure;
          return ColoredBox(
            key: const ValueKey('synthetic-decoration'),
            color: Colors.transparent,
            child: board,
          );
        };
        await tester.pumpAndSettle();
        if (lateFailure) {
          fail!(PairDecorationFailure.unavailable);
          await tester.pump();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('synthetic-decoration')),
            findsNothing,
          );
        }
        expect(
          identical(
            original,
            tester
                .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
                .controller,
          ),
          true,
        );
        final after = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          activityType: 'matching',
        );
        expect(after!.checkpoint!.revision, before!.checkpoint!.revision);
        expect(after.attempts, isEmpty);
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
        );
        await tester.pumpAndSettle();
        expect((await h.db.select(h.db.answerAttempts).get()), hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'actual canonical History explicit Pair replay opens a fresh measured owning host',
    (tester) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final old = await h.restore();
      for (var i = 0; i < 4; i++) {
        await h.tap(old, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(old, 'synthetic-$i', PairTileSide.target);
      }
      await old.finish();
      await old.markSummaryPresented();
      final runtime = _runtime(h, canStart: () => true);
      final launcher = _GenericHistoryLauncher();
      final useCases = LearningHistoryUseCases(
        owners: h.learning.owners,
        reader: DriftLearningHistoryReader(
          h.db,
          learningTime: DriftLearningTimeRepository(
            h.db,
            owners: h.learning.owners,
          ),
          nowUtc: h.learning.nowUtc,
        ),
        sessionLauncher: launcher,
        pairReader: runtime.reader,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => LearningHistoryScreen(
              useCases: useCases,
              generateReplayOperationId: () => 'synthetic-history-replay',
              onPairReplay: (source, operationId) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PairMatchingExperienceHost.practiceReplay(
                      runtime: runtime,
                      source: source,
                      launchOperationId: operationId,
                      onExit: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final replay = find.byKey(
        ValueKey('pair-replay-history-${h.operation.plan.learningSessionId}'),
      );
      await tester.ensureVisible(replay);
      await tester.tap(replay);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-board-regular')), findsOneWidget);
      final controller = tester
          .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
          .controller!;
      expect(controller.state.status, LessonSessionStatus.active);
      expect(
        controller.state.sessionId,
        isNot(h.operation.plan.learningSessionId),
      );
      final canonical = await h.real.read(
        ownerId: h.owner,
        sessionId: controller.state.sessionId!,
      );
      expect(
        canonical.snapshot!.engine.plan.sessionPurpose,
        PairSessionPurpose.practiceReplay,
      );
      expect(
        canonical.snapshot!.engine.plan.sourceSessionId,
        h.operation.plan.learningSessionId,
      );
      expect(canonical.snapshot!.timer!.interactiveElapsedMs, 0);
      expect(launcher.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'actual wrong repair guided confirmation and Review preserve canonical evidence',
    (tester) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      List<ReviewQueueItem>? handedOff;
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h),
            operation: h.operation,
            onExit: () {},
            onReview: (rows) => handedOff = rows,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> pair(int prompt, int target) async {
        await tester.ensureVisible(
          find.byKey(ValueKey('pair-tile:prompt:synthetic-$prompt')),
        );
        await tester.tap(
          find.byKey(ValueKey('pair-tile:prompt:synthetic-$prompt')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(ValueKey('pair-tile:target:synthetic-$target')),
        );
        await tester.tap(
          find.byKey(ValueKey('pair-tile:target:synthetic-$target')),
        );
        await tester.pumpAndSettle();
      }

      await pair(0, 1);
      expect(find.byKey(const ValueKey('pair-feedback:wrong')), findsOneWidget);
      await pair(1, 1);
      await pair(2, 2);
      await pair(0, 3);
      final before = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(
        before.snapshot!.engine.supportAtRevision['synthetic-0'],
        isNotNull,
      );
      final answerCount = (await h.db.select(h.db.answerAttempts).get()).length;
      await tester.pump(const Duration(seconds: 1));
      expect(
        (await h.db.select(h.db.answerAttempts).get()).length,
        answerCount,
      );
      final confirm = find.byKey(
        const ValueKey('pair-confirm-guided:synthetic-0'),
      );
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        (await h.db.select(h.db.answerAttempts).get()).length,
        answerCount + 1,
      );
      await pair(3, 3);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
      final answersBeforeReview = await h.db.select(h.db.answerAttempts).get();
      final eventsBeforeReview = await h.db.select(h.db.eventsV2).get();
      await tester.ensureVisible(find.text('Review next'));
      await tester.tap(find.text('Review next'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && handedOff == null; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(handedOff, isNotEmpty);
      expect(
        handedOff!.every((item) => item.identity.id == 'synthetic-0'),
        true,
      );
      expect(
        (await h.db.select(h.db.answerAttempts).get()).length,
        answersBeforeReview.length,
      );
      expect(
        (await h.db.select(h.db.eventsV2).get()).length,
        eventsBeforeReview.length,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'actual result Replay owns fresh canonical controller and measured duration with zero learning side effects',
    (tester) async {
      var micros = 0;
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final runtime = _runtime(h, clock: () => micros, canStart: () => true);
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
      final firstController = tester
          .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
          .controller;
      Future<void> answerSet() async {
        for (var i = 0; i < 4; i++) {
          await tester.ensureVisible(
            find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')),
          );
          await tester.tap(
            find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(ValueKey('pair-tile:target:synthetic-$i')),
          );
          await tester.tap(
            find.byKey(ValueKey('pair-tile:target:synthetic-$i')),
          );
          await tester.pumpAndSettle();
        }
      }

      micros = 2000000;
      await answerSet();
      final normal = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(normal.snapshot!.timer!.interactiveElapsedMs, 2000);
      const tables = [
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
      Future<String> effects() async => jsonEncode({
        for (final table in tables)
          table: [
            for (final row
                in await h.db
                    .customSelect('SELECT * FROM $table ORDER BY 1')
                    .get())
              row.data,
          ],
      });
      final before = await effects();
      await tester.ensureVisible(find.text('Practice Replay'));
      await tester.tap(find.text('Practice Replay'));
      await tester.pumpAndSettle();
      final secondController = tester
          .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
          .controller;
      expect(identical(firstController, secondController), false);
      final replaySession = await h.real.getActiveSession(ownerId: h.owner);
      expect(replaySession!.id, isNot(h.operation.plan.learningSessionId));
      micros = 5000000;
      await answerSet();
      final replay = await h.real.read(
        ownerId: h.owner,
        sessionId: replaySession.id,
      );
      expect(
        replay.snapshot!.engine.plan.sessionPurpose,
        PairSessionPurpose.practiceReplay,
      );
      expect(
        replay.snapshot!.engine.plan.sourceSessionId,
        h.operation.plan.learningSessionId,
      );
      expect(replay.snapshot!.timer!.interactiveElapsedMs, 3000);
      expect(replay.snapshot!.terminal!.presented, true);
      expect(await effects(), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'near-capacity timeout host opens without receipt then Continue and audio fallback still finish',
    (tester) async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      for (var i = 0; i < 3; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      for (var i = 0; i < 38; i++) {
        micros += 1000;
        await c.flush();
      }
      micros += 60000000;
      await c.expire();
      expect(c.timerAvailability.restart.available, false);
      expect(c.timerAvailability.continueUntimed.available, true);
      c.dispose();
      final before = await h.real.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      final provider = _HostVoice()..fail = true;
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h, clock: () => micros, voice: voice),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final opened = await h.real.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      expect(opened!.checkpoint!.revision, before!.checkpoint!.revision);
      expect(find.text('Show strategy'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('pair-timer-action-continueUntimed')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-3')),
      );
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-3')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('pair-pronounce:prompt:synthetic-3')),
      );
      await tester.tap(
        find.byKey(const ValueKey('pair-pronounce:prompt:synthetic-3')),
      );
      await tester.pumpAndSettle();
      expect(provider.requests, hasLength(1));
      expect(
        find.textContaining('Continue using the visible text'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pair-tile:target:synthetic-3')),
      );
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:target:synthetic-3')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
      final result = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(result.snapshot!.terminal!.presented, true);
      expect(result.snapshot!.evidenceIds.toSet(), hasLength(4));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final capCase in <({bool? fault, bool finish, bool continued})>[
    (fault: null, finish: false, continued: false),
    (fault: false, finish: false, continued: false),
    (fault: true, finish: false, continued: false),
    (fault: null, finish: true, continued: false),
    (fault: null, finish: false, continued: true),
  ]) {
    final abandonFault = capCase.fault;
    testWidgets(
      'configured cap ends incomplete OFF Pair truthfully without completion receipt fault=$abandonFault finish=${capCase.finish} continued=${capCase.continued}',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final old = await h.restore();
        for (var i = 0; i < 4; i++) {
          await h.tap(old, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(old, 'synthetic-$i', PairTileSide.target);
        }
        await old.finish();
        final repository = _HeldHostRepository(h.real)
          ..abandonFault = abandonFault;
        var micros = 0;
        final limitSeconds = capCase.continued ? 120 : 60;
        final runtime = _runtime(
          h,
          repository: repository,
          clock: () => micros,
          canStart: () => true,
          protocols: _ShortProtocols(seconds: limitSeconds),
        );
        final launch = PairMatchingLaunchIntent(
          ownerId: h.owner,
          sourceSurface: PairSourceSurface.learn,
          sourceSnapshotRef: 'synthetic-cap-source',
          operationId: 'synthetic-cap-start',
          createdAtUtc: h.learning.nowUtc(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost(
              runtime: runtime,
              launch: launch,
              source: PairSourceSnapshot.learn(
                ownerId: h.owner,
                reference: launch.sourceSnapshotRef,
                items: h.operation.plan.orderedLexicalItems,
              ),
              preferences: PairDensityPreferences(
                ownerId: h.owner,
                learnerPreference: PairDensity.compact4,
              ),
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('pair-configured-limit')),
          findsOneWidget,
        );
        expect(find.textContaining('60'), findsWidgets);
        if (capCase.continued) {
          await tester.tap(find.byKey(const ValueKey('pair-timer-seconds60')));
        }
        await tester.tap(find.byKey(const ValueKey('pair-start')));
        await tester.pumpAndSettle();
        final started = await h.real.getActiveSession(ownerId: h.owner);
        await tester.ensureVisible(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
        );
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
        );
        await tester.pumpAndSettle();
        if (capCase.finish) {
          for (var i = 1; i < 3; i++) {
            await tester.ensureVisible(
              find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')),
            );
            await tester.tap(
              find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(ValueKey('pair-tile:target:synthetic-$i')),
            );
            await tester.tap(
              find.byKey(ValueKey('pair-tile:target:synthetic-$i')),
            );
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('pair-tile:prompt:synthetic-3')),
          );
          await tester.tap(
            find.byKey(const ValueKey('pair-tile:prompt:synthetic-3')),
          );
          await tester.pumpAndSettle();
          repository.entered = Completer<void>();
          repository.release = Completer<void>();
          await tester.ensureVisible(
            find.byKey(const ValueKey('pair-tile:target:synthetic-3')),
          );
          await tester.tap(
            find.byKey(const ValueKey('pair-tile:target:synthetic-3')),
          );
          for (var i = 0; i < 30 && !repository.entered!.isCompleted; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(repository.entered!.isCompleted, true);
        }
        if (capCase.continued) {
          micros = 61000000;
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('pair-timer-action-continueUntimed')),
          );
          await tester.pumpAndSettle();
          final continued = await h.real.read(
            ownerId: h.owner,
            sessionId: started!.id,
          );
          expect(continued.snapshot!.timer!.mode.name, 'continuedUntimed');
        }
        await tester.pump(Duration(seconds: limitSeconds + 1));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 250));
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;
        expect(
          controller.configurationLimitReached,
          true,
          reason:
              'status=${controller.state.status} effort=${controller.configurationActiveEffort}',
        );
        if (capCase.finish) {
          repository.release!.complete();
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
          final result = await h.real.read(
            ownerId: h.owner,
            sessionId: started!.id,
          );
          expect(result.snapshot!.terminal!.presented, true);
          expect(result.snapshot!.evidenceIds.toSet(), hasLength(4));
          expect(repository.abandonTimes, isEmpty);
          expect(
            controller.configurationActiveEffort,
            lessThanOrEqualTo(const Duration(seconds: 60)),
          );
          final receipts =
              await (h.db.select(h.db.eventsV2)..where(
                    (r) =>
                        r.eventType.equals('LearningActivityCheckpoint') &
                        r.aggregateId.equals(started.id),
                  ))
                  .get();
          expect(
            receipts.where(
              (r) =>
                  (jsonDecode(r.payloadJson) as Map)['terminalAtUtc'] != null,
            ),
            hasLength(3),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          return;
        }
        final end = find.byKey(const ValueKey('pair-end-at-limit'));
        expect(end, findsOneWidget);
        await tester.tap(end);
        await tester.pumpAndSettle();
        if (abandonFault != null) {
          expect(
            find.byKey(const ValueKey('pair-incomplete-ended')),
            findsNothing,
          );
          await tester.pump(const Duration(seconds: 2));
          await tester.tap(end);
          await tester.pumpAndSettle();
          expect(repository.abandonTimes, hasLength(2));
          expect(repository.abandonTimes.toSet(), hasLength(1));
        }
        expect(
          find.byKey(const ValueKey('pair-incomplete-ended')),
          findsOneWidget,
        );
        expect(await h.real.getActiveSession(ownerId: h.owner), isNull);
        final recovered = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: started!.id,
          activityType: 'matching',
        );
        expect(recovered!.session.state, 'abandoned');
        expect(recovered.attempts, hasLength(1));
        final purpose = await h.real.read(
          ownerId: h.owner,
          sessionId: started.id,
        );
        expect(purpose.snapshot!.terminal, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost.recover(
              runtime: runtime,
              operation: PairMatchingStartOperation.fromStableSerialization(
                purpose.snapshot!.startOperation,
              ),
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('pair-incomplete-ended')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('pair-board-regular')), findsNothing);
        expect(await h.real.getActiveSession(ownerId: h.owner), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'real Pair route pronunciation is learner initiated local-only with opaque metadata',
    (tester) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final provider = _HostVoice();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h, voice: voice),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.requests, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
      );
      await tester.pumpAndSettle();
      expect(provider.requests, isEmpty);
      final button = find.byKey(
        const ValueKey('pair-pronounce:prompt:synthetic-0'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(provider.requests, hasLength(1));
      final request = provider.requests.single;
      expect(request.localOnly, true);
      expect(request.contentId, isNot(contains('synthetic-0')));
      expect(request.contentType, 'pairPronunciation');
      final snapshot = await h.real.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      expect(snapshot!.attempts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'real host keeps selected identity across focused resize and records one target activation',
    (tester) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: _runtime(h),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
      );
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(320, 900));
      await tester.pumpAndSettle();
      final before = await h.real.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      expect(before!.attempts, isEmpty);
      expect(find.byKey(const ValueKey('pair-board-focused')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
      );
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
      );
      await tester.pumpAndSettle();
      final after = await h.real.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      expect(after!.attempts, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final heldStage in ['capture', 'answer', 'close']) {
    testWidgets(
      'parent ProductionFeatureGate disposes pending Pair then recovery-only reopen closes exactly once stage=$heldStage',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final repository = _HeldHostRepository(h.real)..heldStage = heldStage;
        final runtime = _runtime(h, repository: repository);
        final features = RuntimeFeatureRegistry(
          BuildFeatureRegistry.allEnabled(),
        );
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
        final lastIndex = heldStage == 'close' ? 3 : 0;
        for (var i = 0; i < lastIndex; i++) {
          await tester.tap(
            find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('pair-tile:target:synthetic-$i')),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(ValueKey('pair-tile:prompt:synthetic-$lastIndex')),
        );
        await tester.pumpAndSettle();
        repository.entered = Completer<void>();
        repository.release = Completer<void>();
        await tester.tap(
          find.byKey(ValueKey('pair-tile:target:synthetic-$lastIndex')),
        );
        for (var i = 0; i < 30 && !repository.entered!.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(repository.entered!.isCompleted, true);
        features.emergencyOff(Feature.quiz);
        await tester.pump();
        expect(find.byType(PairMatchingExperienceHost), findsNothing);
        expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        repository.release!.complete();
        await tester.pumpAndSettle();
        final pending = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          activityType: 'matching',
        );
        expect(
          pending!.session.state,
          heldStage == 'close' ? 'completed' : 'active',
        );
        expect(pending.attempts, hasLength(lastIndex + 1));
        expect(runtime.newStartsAllowed, false);
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
        for (var i = lastIndex + 1; i < 4; i++) {
          await tester.tap(
            find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('pair-tile:target:synthetic-$i')),
          );
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
        final finished = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(finished.snapshot!.terminal!.presented, true);
        expect(finished.snapshot!.evidenceIds.toSet(), hasLength(4));
        final receipts =
            await (h.db.select(h.db.eventsV2)..where(
                  (r) =>
                      r.eventType.equals('LearningActivityCheckpoint') &
                      r.aggregateId.equals(h.operation.plan.learningSessionId),
                ))
                .get();
        expect(
          receipts.where(
            (r) => (jsonDecode(r.payloadJson) as Map)['terminalAtUtc'] != null,
          ),
          hasLength(3),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final direction in PairDirection.values) {
    testWidgets(
      'real setup pins configuration before fresh shell in $direction',
      (tester) async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final old = await h.restore();
        for (var i = 0; i < 4; i++) {
          await h.tap(old, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(old, 'synthetic-$i', PairTileSide.target);
        }
        await old.finish();
        final repository = _HeldHostRepository(h.real)
          ..failConfigurationLoadOnce = true;
        final runtime = _runtime(
          h,
          repository: repository,
          canStart: () => true,
          protocols: _Protocols(),
        );
        final launch = PairMatchingLaunchIntent(
          ownerId: h.owner,
          sourceSurface: PairSourceSurface.learn,
          sourceSnapshotRef: 'synthetic-new-source',
          operationId: 'synthetic-new-${direction.name}',
          createdAtUtc: h.learning.nowUtc(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost(
              runtime: runtime,
              launch: launch,
              source: PairSourceSnapshot.learn(
                ownerId: h.owner,
                reference: launch.sourceSnapshotRef,
                items: h.operation.plan.orderedLexicalItems,
              ),
              preferences: PairDensityPreferences(
                ownerId: h.owner,
                learnerPreference: PairDensity.compact4,
              ),
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('pair-timer-off')))
              .selected,
          true,
        );
        await tester.tap(
          find.byKey(ValueKey('pair-direction-${direction.name}')),
        );
        await tester.tap(find.byKey(const ValueKey('pair-start')));
        await tester.pumpAndSettle();
        final acceptedBeforeRetry = await h.real.getActiveSession(
          ownerId: h.owner,
        );
        expect(find.byKey(const ValueKey('pair-board-regular')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('pair-retry-attachment')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('pair-board-regular')),
          findsOneWidget,
        );
        final controller = tester
            .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
            .controller!;
        expect(controller.state.sessionId, isNotNull);
        expect(controller.state.status.name, 'active');
        final active = await h.real.getActiveSession(ownerId: h.owner);
        expect(active!.id, acceptedBeforeRetry!.id);
        expect(
          active.sessionConfiguration!.direction,
          direction == PairDirection.enToTh
              ? SessionDirection.forward
              : SessionDirection.reverse,
        );
        expect(active.sessionConfiguration!.itemCount, 4);
        final purpose = await h.real.read(
          ownerId: h.owner,
          sessionId: active.id,
        );
        expect(purpose.snapshot!.timer!.interactiveElapsedMs, 0);
        expect(purpose.snapshot!.timer!.mode.name, 'off');
        await tester.ensureVisible(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
        );
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
        );
        await tester.pumpAndSettle();
        final recorded = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: active.id,
          activityType: 'matching',
        );
        expect(recorded!.attempts, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'real recovered host matches typed tiles and renders authenticated elapsed result',
    (tester) async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final repository = _HeldHostRepository(h.real);
      final learning = LearningUseCases(
        owners: h.learning.owners,
        repository: repository,
        generateId: h.learning.generateId,
        nowUtc: h.learning.nowUtc,
        buildInfo: h.learning.buildInfo,
      );
      final allowlist = PairCuratedAllowlist(
        version: h.operation.plan.allowlistVersion,
        items: h.operation.plan.orderedLexicalItems,
      );
      var micros = 0;
      final runtime = PairMatchingExperienceRuntime(
        database: h.db,
        learning: learning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
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
          capability: InternalPairMatchingCapability(allowlist: allowlist),
        ),
        monotonicMicros: () => micros,
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
      micros = 2000000;
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(ValueKey('pair-tile:prompt:synthetic-$i')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('pair-tile:target:synthetic-$i')));
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
      final result = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(result.snapshot!.terminal!.presented, true);
      expect(result.snapshot!.timer!.interactiveElapsedMs, 2000);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  test(
    'exact Pair route reservation drains accepted answer before retirement and preserves recovery',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final repository = _HeldHostRepository(h.real);
      final learning = LearningUseCases(
        owners: h.learning.owners,
        repository: repository,
        generateId: h.learning.generateId,
        nowUtc: h.learning.nowUtc,
        buildInfo: h.learning.buildInfo,
      );
      final controller = UnifiedLessonController(
        learning: learning,
        adapter: const MatchingModeAdapter.internalPair(),
        sessionPurposeReader: h.real,
      );
      addTearDown(controller.dispose);
      final route = UnifiedLessonRouteLifecycle(
        controller,
        learning,
        learning.nowUtc,
      );
      final c = await PairMatchingSessionCoordinator.restore(
        operation: h.operation,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        activeOwnerId: () => h.owner,
        acceptsOperation: () => route.acceptsPairContinuation,
        runAdmittedOperation: route.runAcceptedOperation<void>,
        runRecoveryOperation: route.runRecoveryOperation<void>,
        completeSession: route.completeRecovery,
        ownClose: route.ownRecoveryClose,
      );
      route.reservePairSession(c);
      final recovered = await learning.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      await route.initializeSession(
        learning.reconstructPinnedQuizSession(
          session: recovered!.session,
          content: [
            for (final item in h.operation.plan.orderedLexicalItems)
              ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: item.wordId,
                revision: item.contentRevision,
              ),
          ],
          contentChecksumsSha256: {
            for (final item in h.operation.plan.orderedLexicalItems)
              item.wordId: item.checksum,
          },
        ),
      );
      c.resumeInteraction();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      repository.entered = Completer<void>();
      repository.release = Completer<void>();
      final answer = h.tap(c, 'synthetic-0', PairTileSide.target);
      await repository.entered!.future;
      var retired = false;
      final retirement = route.retire().then((_) => retired = true);
      await Future<void>.delayed(Duration.zero);
      expect(retired, false);
      expect(route.acceptsOperations, false);
      repository.release!.complete();
      await answer;
      await retirement;
      final after = await learning.loadExactActivityRecovery(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      expect(after!.session.state, 'active');
      expect(after.attempts, hasLength(1));
      await expectLater(
        route.runRecoveryOperation<void>(() async {}),
        throwsStateError,
      );
    },
  );
}
