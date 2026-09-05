import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_pair_renderer.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

import '../learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairHarness, PairFaultRepository;
import '../learning/pair_matching/pair_matching_source_composer_test.dart'
    show fixture;

void main() {
  for (final density in PairDensity.values) {
    for (final direction in PairDirection.values) {
      for (final preset in PairTimerPreset.values) {
        testWidgets(
          'canonical renderer parity ${density.name} ${direction.name} ${preset.name}',
          (tester) async {
            final standard = await _runScript(
              tester,
              density,
              direction,
              preset,
              adventure: false,
            );
            final adventure = await _runScript(
              tester,
              density,
              direction,
              preset,
              adventure: true,
            );
            expect(
              adventure,
              standard,
              reason:
                  'Only UTC metadata is normalized; deterministic identities, hashes, ordering and cross-row links stay exact.',
            );
          },
        );
      }
    }
  }
  for (final stage in ['answer', 'timeoutChoice', 'closeRetry']) {
    for (final failure in ['adventureOff', 'syncConstruction', 'lateHealth']) {
      testWidgets('same host fallback $failure preserves $stage', (
        tester,
      ) async {
        await _runFallback(tester, stage: stage, failure: failure);
      });
    }
  }
}

Future<void> _runFallback(
  WidgetTester tester, {
  required String stage,
  required String failure,
}) async {
  final f = await _ParityFixture.create(
    PairDensity.compact4,
    PairDirection.enToTh,
    PairTimerPreset.seconds60,
  );
  final constructionFails = ValueNotifier(false);
  final changes = Listenable.merge([f.features, constructionFails]);
  Widget decoration(
    BuildContext context,
    PairBoardModel model,
    Widget board,
    ValueChanged<PairDecorationFailure> reportFailure,
  ) {
    if (constructionFails.value) {
      throw StateError('synthetic construction failure');
    }
    return f.decorate(context, model, board, reportFailure);
  }

  await tester.pumpWidget(
    MaterialApp(
      home: AnimatedBuilder(
        animation: changes,
        builder: (context, child) => PairMatchingExperienceHost.recover(
          runtime: f.runtime,
          operation: f.h.operation,
          onExit: () {},
          decoration: f.features.isEnabled(Feature.adventureMotivation)
              ? decoration
              : null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final hostState = tester.state(find.byType(PairMatchingExperienceHost));
  final controller = tester
      .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
      .controller!;
  PairBoardView board() =>
      tester.widget<PairBoardView>(find.byType(PairBoardView));
  Future<void> select(PairTileSide side, int word, {bool settle = true}) async {
    final view = board();
    expect(view.model.busy, isFalse);
    f.micros += 25000;
    view.onSelectTile(PairTile(side, 'synthetic-$word'));
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> pair(int word) async {
    await select(PairTileSide.prompt, word);
    await select(PairTileSide.target, word);
  }

  Future<void> expire() async {
    f.micros += (board().model.timer.remainingActiveMs + 1) * 1000;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  Future<void> timer(PairTimerAction action, {bool settle = true}) async {
    final button = find.byKey(ValueKey('pair-timer-action-${action.name}'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    if (settle) await tester.pumpAndSettle();
  }

  final entered = Completer<void>();
  final release = Completer<void>();
  if (stage == 'answer') {
    f.repository.beforeAnswer = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    await select(PairTileSide.prompt, 0);
    await select(PairTileSide.target, 0, settle: false);
  } else if (stage == 'timeoutChoice') {
    await expire();
    await timer(PairTimerAction.extend);
    await expire();
    f.repository.holdCheckpoint = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    await timer(PairTimerAction.continueUntimed, settle: false);
  } else {
    for (var word = 0; word < 3; word++) {
      await pair(word);
    }
    f.repository.closeFault = true;
    f.repository.afterWrite = true;
    await pair(3);
    expect(find.byKey(const ValueKey('pair-retry')), findsOneWidget);
  }
  if (stage != 'closeRetry') {
    for (var i = 0; i < 40 && !entered.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      entered.isCompleted,
      isTrue,
      reason: 'Actual canonical write reached the held boundary.',
    );
  }
  final before = await f.h.real.read(
    ownerId: f.h.owner,
    sessionId: f.h.operation.plan.learningSessionId,
  );
  final beforeSnapshot = before.snapshot!.toJson();
  final ids = f.h.nextId;
  switch (failure) {
    case 'adventureOff':
      f.features.emergencyOff(Feature.adventureMotivation);
    case 'syncConstruction':
      constructionFails.value = true;
    case 'lateHealth':
      f.health.reportFailure(PairDecorationFailure.unavailable);
  }
  // Pair/Quiz disables fresh starts, while the preaccepted host remains owned.
  f.features.emergencyOff(Feature.quiz);
  await tester.pump();
  await tester.pump();
  final during = await f.h.real.read(
    ownerId: f.h.owner,
    sessionId: f.h.operation.plan.learningSessionId,
  );
  expect(during.snapshot!.toJson(), beforeSnapshot);
  expect(f.h.nextId, ids);
  expect(
    tester.state(find.byType(PairMatchingExperienceHost)),
    same(hostState),
  );
  expect(
    tester
        .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
        .controller,
    same(controller),
  );
  if (stage != 'closeRetry') {
    release.complete();
    await tester.pumpAndSettle();
    f.repository.beforeAnswer = null;
    f.repository.holdCheckpoint = null;
    await tester.pumpAndSettle();
    expect(find.byType(AdventurePairRenderer), findsNothing);
    if (stage == 'timeoutChoice') {
      expect(board().model.timer.mode, PairTimerMode.continuedUntimed);
      expect(board().model.timer.extensionUsed, isTrue);
    }
    for (var word = stage == 'answer' ? 1 : 0; word < 4; word++) {
      await pair(word);
    }
  } else {
    expect(find.byType(AdventurePairRenderer), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pair-retry')));
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
  final finalState = await f.h.real.read(
    ownerId: f.h.owner,
    sessionId: f.h.operation.plan.learningSessionId,
  );
  expect(finalState.snapshot!.terminal!.presented, isTrue);
  expect(finalState.snapshot!.evidenceIds.toSet(), hasLength(4));
  expect((await f.h.db.select(f.h.db.answerAttempts).get()), hasLength(4));
  final events = await f.h.db.select(f.h.db.eventsV2).get();
  expect(
    events.where(
      (e) =>
          e.eventType == 'LearningActivityCheckpoint' &&
          (jsonDecode(e.payloadJson) as Map)['terminalAtUtc'] != null,
    ),
    hasLength(3),
  );
  expect(f.runtime.newStartsAllowed, isFalse);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  constructionFails.dispose();
  f.health.dispose();
  f.features.dispose();
  await f.h.db.close();
}

Future<Map<String, Object?>> _runScript(
  WidgetTester tester,
  PairDensity density,
  PairDirection direction,
  PairTimerPreset preset, {
  required bool adventure,
}) async {
  final f = await _ParityFixture.create(density, direction, preset);
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: PairMatchingExperienceHost.recover(
          runtime: f.runtime,
          operation: f.h.operation,
          decoration: adventure ? f.decorate : null,
          onExit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
        .controller!;
    expect(controller.state.status, LessonSessionStatus.active);
    expect(
      controller.sessionConfiguration!.contentIdentity,
      f.h.configuration!.contentIdentity,
    );
    final requests = <Map<String, Object?>>[];
    PairBoardView board() =>
        tester.widget<PairBoardView>(find.byType(PairBoardView));
    Future<void> settle() async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> select(PairTileSide side, int index) async {
      final view = board();
      final state = view.model.state;
      expect(view.model.busy, isFalse);
      expect(state.pending, isNull);
      final tile = PairTile(side, 'synthetic-$index');
      requests.add({
        'kind': 'select',
        'round': state.roundOrdinal,
        'revision': state.operationRevision,
        'tile': tile.toJson(),
      });
      f.micros += 25000;
      view.onSelectTile(tile);
      await settle();
    }

    Future<void> pair(int prompt, int target) async {
      await select(PairTileSide.prompt, prompt);
      await select(PairTileSide.target, target);
    }

    Future<void> confirm(int index) async {
      final view = board();
      final state = view.model.state;
      final id = 'synthetic-$index';
      final support = state.supportAtRevision[id]!;
      expect(find.byKey(ValueKey('pair-confirm-guided:$id')), findsOneWidget);
      requests.add({
        'kind': 'confirmGuidedMapping',
        'wordId': id,
        'round': state.roundOrdinal,
        'revision': state.operationRevision,
        'shownSupportRevision': support,
      });
      f.micros += 25000;
      view.onConfirmGuidedMapping(id, support);
      await settle();
    }

    Future<void> expire() async {
      final remaining = board().model.timer.remainingActiveMs;
      f.micros += (remaining + 1) * 1000;
      await tester.pump(const Duration(milliseconds: 250));
      await settle();
      expect(
        find.byKey(const ValueKey('pair-timer-action-continueUntimed')),
        findsOneWidget,
      );
    }

    Future<void> timer(PairTimerAction action) async {
      final saved = await f.h.real.read(
        ownerId: f.h.owner,
        sessionId: f.h.operation.plan.learningSessionId,
      );
      requests.add({
        'kind': 'timerDecision',
        'action': action.name,
        'round': saved.snapshot!.engine.roundOrdinal,
        'revision': saved.snapshot!.engine.operationRevision,
      });
      final button = find.byKey(ValueKey('pair-timer-action-${action.name}'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle();
    }

    if (preset != PairTimerPreset.off) {
      await expire();
      await timer(PairTimerAction.restart);
      expect(board().model.state.roundOrdinal, 1);
      await expire();
      await timer(PairTimerAction.extend);
      expect(board().model.timer.extensionUsed, isTrue);
      await expire();
      await timer(PairTimerAction.continueUntimed);
      expect(board().model.timer.mode, PairTimerMode.continuedUntimed);
    }

    // Every answer travels through the actual mounted board's typed callbacks.
    // A failed ACK is retried by the real host's retry button, not by a reducer.
    f.repository.answerFault = true;
    f.repository.afterWrite = true;
    await pair(0, 1);
    expect(find.byKey(const ValueKey('pair-retry')), findsOneWidget);
    expect((await f.h.db.select(f.h.db.answerAttempts).get()), hasLength(1));
    final frozen = board().model.state.pending!;
    final idsBeforeRetry = f.h.nextId;
    await tester.tap(find.byKey(const ValueKey('pair-retry')));
    await settle();
    expect(f.h.nextId, idsBeforeRetry);
    expect(board().model.state.attempts.single.operationId, frozen.operationId);
    expect((await f.h.db.select(f.h.db.answerAttempts).get()), hasLength(1));
    await pair(1, 1);
    await pair(2, 2);
    // Six pairs require three distinct intervening successes; four require two.
    // Keep word 3 unresolved for the same later explicit reveal in both sizes.
    if (density == PairDensity.standard6) await pair(4, 4);
    expect(
      board().model.state.repairFor('synthetic-0')!.status,
      PairRepairStatus.available,
    );
    await pair(0, 3);
    expect(
      board().model.state.repairFor('synthetic-0')!.status,
      PairRepairStatus.guidedRequired,
    );
    final beforeConfirmation =
        (await f.h.db.select(f.h.db.answerAttempts).get()).length;
    await tester.pump();
    expect(
      (await f.h.db.select(f.h.db.answerAttempts).get()).length,
      beforeConfirmation,
    );
    await confirm(0);
    await select(PairTileSide.prompt, 3);
    final revealView = board();
    requests.add({
      'kind': 'revealMapping',
      'wordId': 'synthetic-3',
      'round': revealView.model.state.roundOrdinal,
      'revision': revealView.model.state.operationRevision,
    });
    revealView.onRevealMapping('synthetic-3');
    await settle();
    final remaining = [3, for (var i = 5; i < density.pairCount; i++) i];
    for (final id in remaining) {
      if (id == remaining.last) {
        f.repository.closeFault = true;
        f.repository.afterWrite = true;
      }
      if (id == 3) {
        await confirm(id);
      } else {
        await pair(id, id);
      }
    }
    expect(find.byKey(const ValueKey('pair-retry')), findsOneWidget);
    final beforeCloseRetry = await f.h.real.read(
      ownerId: f.h.owner,
      sessionId: f.h.operation.plan.learningSessionId,
    );
    expect(beforeCloseRetry.snapshot!.terminal!.acknowledged, isFalse);
    await tester.tap(find.byKey(const ValueKey('pair-retry')));
    await settle();
    expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
    final saved = await f.h.real.read(
      ownerId: f.h.owner,
      sessionId: f.h.operation.plan.learningSessionId,
    );
    final snapshot = saved.snapshot!;
    expect(snapshot.terminal!.presented, isTrue);
    expect(snapshot.engine.attempts, hasLength(density.pairCount + 2));
    expect(snapshot.evidenceIds.toSet(), hasLength(density.pairCount + 2));
    expect(
      snapshot.engine.attempts.map((a) => a.role),
      containsAll([
        PairAttemptRole.firstOpportunity,
        PairAttemptRole.delayedRepair,
        PairAttemptRole.guidedCompletion,
      ]),
    );
    expect(snapshot.engine.supportedWordIds, {'synthetic-0', 'synthetic-3'});
    final history = PairMatchingHistoryProjection(snapshot);
    final events = await f.h.db.select(f.h.db.eventsV2).get();
    final terminalEvents = events.where(
      (e) =>
          e.eventType == 'LearningActivityCheckpoint' &&
          (jsonDecode(e.payloadJson) as Map)['terminalAtUtc'] != null,
    );
    expect(terminalEvents, hasLength(3));
    final transcript = <String, Object?>{
      'requests': requests,
      'durableSnapshot': snapshot.toJson(),
      'answers': (await f.h.db.select(f.h.db.answerAttempts).get())
          .map((r) => r.toJson())
          .toList(),
      'session': (await f.h.db.select(f.h.db.learningSessions).get())
          .map((r) => r.toJson())
          .toList(),
      'events': events.map((r) => r.toJson()).toList(),
      'stars': {
        'matched': history.result.matched,
        'independent': history.result.independent,
        'assisted': history.result.assisted,
        'stars': history.result.stars,
        'policyVersion': history.result.policyVersion,
      },
      'answerCalls': f.repository.commands
          .map(
            (c) => {
              'evidenceId': c.id,
              'sessionId': c.sessionId,
              'wordId': c.wordId,
              'isCorrect': c.isCorrect,
            },
          )
          .toList(),
    };
    return _normalizeUtc(transcript) as Map<String, Object?>;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    f.health.dispose();
    f.features.dispose();
    await f.h.db.close();
  }
}

/// Deterministic fixture IDs mean no ID, hash, role or pin is removed. Only
/// UTC metadata can vary between independent real database runs. JSON fields
/// are decoded recursively so evidence and cross-row references remain visible.
Object? _normalizeUtc(Object? value, [String? key]) {
  if (value == null) return null;
  if (key != null &&
      RegExp(r'(AtUtc|AtUtcMs|_at_utc|_at_utc_ms)$').hasMatch(key)) {
    return '<utc>';
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _normalizeUtc(entry.value, entry.key as String),
    };
  }
  if (value is List) return value.map((item) => _normalizeUtc(item)).toList();
  if (value is String && (value.startsWith('{') || value.startsWith('['))) {
    return _normalizeUtc(jsonDecode(value));
  }
  return value;
}

final class _Protocols implements SessionConfigurationProtocolProvider {
  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => const SessionConfigurationProtocolLimits.standard();
}

final class _ParityFixture {
  _ParityFixture(this.h, this.repository, this.runtime, this.features);
  final PairHarness h;
  final _ParityRepository repository;
  final PairMatchingExperienceRuntime runtime;
  final RuntimeFeatureRegistry features;
  final health = AdventurePairDecorationHealth();
  final diagnostics = AdventureDiagnostics();
  int micros = 0;
  Widget decorate(
    BuildContext context,
    PairBoardModel model,
    Widget board,
    ValueChanged<PairDecorationFailure> reportFailure,
  ) => AdventurePairRenderer(
    model: model,
    standardBoard: board,
    reportFailure: reportFailure,
    diagnostics: diagnostics,
    health: health,
  );

  static Future<_ParityFixture> create(
    PairDensity density,
    PairDirection direction,
    PairTimerPreset preset,
  ) async {
    final registry = buildLessonModeRegistry(
      internalPairMatching: true,
      matchingDeliveryState: LessonModeDeliveryState.enabled,
    );
    const policy = SessionConfigurationPolicy();
    final registration = registry.resolve(LessonMode.matching)!;
    const limits = SessionConfigurationProtocolLimits.standard();
    final configuration = policy.validate(
      draft: policy
          .defaultsFor(registration: registration, limits: limits)
          .copyWith(
            itemCount: density.pairCount,
            timing: const SessionTiming.timed(Duration(minutes: 10)),
            direction: direction == PairDirection.enToTh
                ? SessionDirection.forward
                : SessionDirection.reverse,
          ),
      registration: registration,
      limits: limits,
      ownerId: 'synthetic-owner',
      availablePackIdentities: const [],
    );
    final plan = PairMatchingPlanV1(
      ownerId: 'synthetic-owner',
      orderedLexicalItems: List.generate(density.pairCount, fixture),
      direction: direction,
      density: density,
      shuffleSeed: 42,
      timerPreset: preset,
      allowlistVersion: 'synthetic-v1',
      learningSessionId: pairSessionId(
        'synthetic-owner',
        'synthetic-operation',
      ),
      entryKind: PairSourceSurface.today,
      sourceSnapshotId: 'synthetic-today',
      createdAtUtc: DateTime.utc(2026, 9, 5),
    );
    final h = PairHarness(pinnedPlan: plan, configuration: configuration);
    await h.initialize(measured: true);
    final repository = _ParityRepository(h.real);
    final learning = LearningUseCases(
      owners: h.learning.owners,
      repository: repository,
      generateId: h.learning.generateId,
      nowUtc: h.learning.nowUtc,
      buildInfo: h.learning.buildInfo,
    );
    final allowlist = PairCuratedAllowlist(
      version: plan.allowlistVersion,
      items: plan.orderedLexicalItems,
    );
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    late _ParityFixture result;
    final runtime = PairMatchingExperienceRuntime(
      database: h.db,
      learning: learning,
      registry: registry,
      createController: (adapter) => UnifiedLessonController(
        learning: learning,
        adapter: adapter,
        sessionPurposeReader: h.real,
        configurationMonotonicMicros: () => result.micros,
      ),
      composer: PairMatchingSourceComposer(allowlist: allowlist),
      protocols: _Protocols(),
      start: PairMatchingAtomicStartAdapter(
        repository: h.real,
        capability: InternalPairMatchingCapability(
          allowlist: allowlist,
          isEnabled: () => true,
        ),
      ),
      features: features,
      canStart: () => true,
      monotonicMicros: () => result.micros,
    );
    result = _ParityFixture(h, repository, runtime, features);
    return result;
  }
}

final class _ParityRepository extends PairFaultRepository
    implements
        PinnedLearningContentRepository,
        SessionConfiguredLearningRepository,
        LearningSessionLifecycleRepository {
  _ParityRepository(super.delegate);
  Future<void> Function()? holdCheckpoint;
  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    await holdCheckpoint?.call();
    await super.appendActivityCheckpoint(
      ownerId: ownerId,
      checkpoint: checkpoint,
    );
  }

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
