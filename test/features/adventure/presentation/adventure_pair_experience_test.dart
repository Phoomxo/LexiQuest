import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show LocalOwnersCompanion;
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_pair_renderer.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_pair_experience.dart';
import 'package:vocab_learning_app/features/adventure/presentation/today_experience_host.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_view.dart';
import '../../learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairHarness;
import '../../../support/inert_research_dependencies.dart';
import '../../../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'same mounted Adventure route clears decoration diagnostics on real owner invalidation',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      addTearDown(f.h.db.close);
      await tester.runAsync(
        () => f.h.real.abandonSession(
          ownerId: f.h.owner,
          sessionId: f.h.operation.plan.learningSessionId,
          abandonedAtUtc: f.h.learning.nowUtc(),
        ),
      );
      final health = AdventurePairDecorationHealth();
      final research = InertResearchDependencies(f.h.db);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: AppDependencies(
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
            features: f.features,
            learning: f.runtime.learning,
            currentActivityEvidence: CurrentActivityEvidenceAdapter(
              learning: f.runtime.learning,
            ),
            experiments: research.experiments,
            consents: research.consents,
            experimentAssignments: research.experimentAssignments,
            assignedLearningEventContext: research.assignedLearningEventContext,
            evidencePolicyRolloutModeProvider:
                research.evidencePolicyRolloutModeProvider,
          ),
          child: MaterialApp(
            home: AdventurePairExperience(
              launchContext: f.context(),
              runtime: f.runtime,
              allowlist: f.allowlist,
              preferences: f.preferences,
              decorationHealth: health,
              onExit: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pair-start')));
      await tester.pumpAndSettle();
      final hostState = tester.state(find.byType(PairMatchingExperienceHost));
      final host = tester.widget<PairMatchingExperienceHost>(
        find.byType(PairMatchingExperienceHost),
      );
      final renderer = tester.widget<AdventurePairRenderer>(
        find.byType(AdventurePairRenderer),
      );
      final board = tester.widget<PairBoardView>(find.byType(PairBoardView));
      renderer.diagnostics.record(AdventureDiagnosticReasonCode.entryAdventure);
      expect(renderer.diagnostics.snapshot().counters, isNotEmpty);
      final ids = f.ids;
      await tester.runAsync(
        () => f.h.db
            .update(f.h.db.localOwners)
            .write(const LocalOwnersCompanion(isActive: Value(false))),
      );
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(PairMatchingExperienceHost)),
        same(hostState),
      );
      expect(
        tester
            .widget<PairMatchingExperienceHost>(
              find.byType(PairMatchingExperienceHost),
            )
            .decoration,
        isNull,
      );
      final inert = host.decoration!(
        tester.element(find.byType(AdventurePairExperience)),
        board.model,
        board,
        (_) => fail('Old owner decoration cannot report'),
      );
      expect(inert, same(board));
      health.reportFailure(PairDecorationFailure.unavailable);
      await tester.pumpAndSettle();
      expect(renderer.diagnostics.snapshot().counters, {
        AdventureDiagnosticReasonCode.entryAdventure: 1,
      });
      expect(f.ids, ids);
      expect(
        (await tester.runAsync(
          () => f.h.db.select(f.h.db.answerAttempts).get(),
        ))!,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      health.dispose();
    },
  );
  testWidgets(
    'both contextual entries retain one launch and exact Today source through rebuild',
    (tester) async {
      for (final adventure in [false, true]) {
        final f = await tester.runAsync(_Fixture.create);
        final fixture = f!;
        final today = fixture.today;
        Widget route() => adventure
            ? AdventurePairExperience(
                launchContext: fixture.context(),
                runtime: fixture.runtime,
                allowlist: fixture.allowlist,
                preferences: fixture.preferences,
                onExit: () {},
              )
            : AdventurePairExperience.standard(
                today: today,
                entryDecision: fixture.decision(false),
                runtime: fixture.runtime,
                allowlist: fixture.allowlist,
                preferences: fixture.preferences,
                onExit: () {},
              );
        await tester.pumpWidget(MaterialApp(home: route()));
        await tester.pumpAndSettle();
        final host = tester.widget<PairMatchingExperienceHost>(
          find.byType(PairMatchingExperienceHost),
        );
        final state = tester.state(find.byType(PairMatchingExperienceHost));
        final count = fixture.ids;
        expect(host.launch!.sourceSurface, PairSourceSurface.today);
        expect(
          host.source!.reference,
          'today:${today.evaluatedAtUtc.millisecondsSinceEpoch}',
        );
        expect(
          host.source!.items.map((i) => i.wordId),
          today.reviewWork.map((i) => i.identity.id),
        );
        expect(host.decoration != null, adventure);
        await tester.pumpWidget(MaterialApp(home: route()));
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(PairMatchingExperienceHost)),
          same(state),
        );
        expect(
          tester
              .widget<PairMatchingExperienceHost>(
                find.byType(PairMatchingExperienceHost),
              )
              .launch,
          same(host.launch),
        );
        expect(fixture.ids, count);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(fixture.h.db.close);
      }
    },
  );

  testWidgets(
    'Adventure off replaces decoration on same Pair host without new identity',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      await tester.pumpWidget(
        MaterialApp(
          home: AdventurePairExperience(
            launchContext: f.context(),
            runtime: f.runtime,
            allowlist: f.allowlist,
            preferences: f.preferences,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(PairMatchingExperienceHost));
      final host = tester.widget<PairMatchingExperienceHost>(
        find.byType(PairMatchingExperienceHost),
      );
      final count = f.ids;
      f.features.emergencyOff(Feature.adventureMotivation);
      await tester.pumpAndSettle();
      final next = tester.widget<PairMatchingExperienceHost>(
        find.byType(PairMatchingExperienceHost),
      );
      expect(next.decoration, isNull);
      expect(next.launch, same(host.launch));
      expect(
        tester.state(find.byType(PairMatchingExperienceHost)),
        same(state),
      );
      expect(f.ids, count);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.h.db.close);
    },
  );

  testWidgets(
    'invalid mission or stale context never allocates launch identity',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      for (final stale in [false, true]) {
        final before = f.ids;
        await tester.pumpWidget(
          MaterialApp(
            home: AdventurePairExperience(
              key: ValueKey(stale),
              launchContext: f.context(incompatible: !stale),
              runtime: f.runtime,
              allowlist: f.allowlist,
              preferences: f.preferences,
              isCurrent: () => !stale,
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PairMatchingExperienceHost), findsNothing);
        expect(
          find.byKey(const ValueKey('adventure-pair-unavailable')),
          findsOneWidget,
        );
        expect(f.ids, before);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.h.db.close);
    },
  );

  testWidgets(
    'entry becoming stale in Pair setup denies fresh canonical admission',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      await tester.runAsync(
        () => f.h.real.abandonSession(
          ownerId: f.h.owner,
          sessionId: f.h.operation.plan.learningSessionId,
          abandonedAtUtc: f.h.learning.nowUtc(),
        ),
      );
      var current = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AdventurePairExperience.standard(
            today: f.today,
            entryDecision: f.decision(false),
            runtime: f.runtime,
            allowlist: f.allowlist,
            preferences: f.preferences,
            isCurrent: () => current,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = (await tester.runAsync(
        () => f.h.db.select(f.h.db.learningSessions).get(),
      ))!.length;
      current = false;
      await tester.tap(find.byKey(const ValueKey('pair-start')));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(
          () => f.h.db.select(f.h.db.learningSessions).get(),
        ))!.length,
        before,
      );
      expect(find.byKey(const ValueKey('pair-start')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.h.db.close);
    },
  );

  test(
    'contextual delegates share double tap guard and reject obsolete callbacks',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.h.db.close);
      final fallback = _Fallback();
      final release = Completer<void>();
      final opened = Completer<void>();
      var navigations = 0;
      var current = true;
      Widget? captured;
      final router = AdventurePairTodayActions(
        runtime: f.runtime,
        allowlist: f.allowlist,
        preferences: f.preferences,
        onExit: () {},
        openExperience: (widget) async {
          navigations++;
          captured = widget;
          opened.complete();
          await release.future;
        },
      );
      TodayHubActionDelegate contextualize() => router.contextualize(
        today: f.today,
        entryDecision: f.decision(false),
        fallback: fallback,
        isCurrent: () => current,
      );
      final first = contextualize();
      final count = f.ids;
      final one = first.openReview(f.today.reviewWork);
      final two = contextualize().openReview(f.today.reviewWork);
      await opened.future;
      expect(navigations, 1);
      expect(captured, isA<AdventurePairExperience>());
      expect(
        f.ids,
        count,
        reason: 'route state, never the factory, allocates identity',
      );
      release.complete();
      await Future.wait([one, two]);
      current = false;
      await first.openReview(f.today.reviewWork);
      expect(navigations, 1);
      expect(fallback.reviews, 0);
      await first.openHistory();
      await first.startRecommendation(f.today.recommendation);
      expect(fallback.history, 1);
      expect(fallback.recommendations.single, same(f.today.recommendation));
    },
  );

  test(
    'review payload mismatch forwards unchanged without creating Pair',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.h.db.close);
      final fallback = _Fallback();
      var navigations = 0;
      final router = AdventurePairTodayActions(
        runtime: f.runtime,
        allowlist: f.allowlist,
        preferences: f.preferences,
        onExit: () {},
        openExperience: (_) async {
          navigations++;
        },
      );
      final delegate = router.contextualize(
        today: f.today,
        entryDecision: f.decision(false),
        fallback: fallback,
        isCurrent: () => true,
      );
      final other = f.today.reviewWork.take(1).toList();
      await delegate.openReview(other);
      expect(fallback.lastReview, same(other));
      expect(navigations, 0);
    },
  );

  test(
    'entry invalidation during async owner lookup prevents navigation and IDs',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.h.db.close);
      var current = true;
      var navigations = 0;
      final router = AdventurePairTodayActions(
        runtime: f.runtime,
        allowlist: f.allowlist,
        preferences: f.preferences,
        onExit: () {},
        openExperience: (_) async {
          navigations++;
        },
      );
      final delegate = router.contextualize(
        today: f.today,
        entryDecision: f.decision(false),
        fallback: _Fallback(),
        isCurrent: () => current,
      );
      final count = f.ids;
      final pending = delegate.openReview(f.today.reviewWork);
      current = false;
      await pending;
      expect(navigations, 0);
      expect(f.ids, count);
    },
  );
}

class _Fixture {
  _Fixture(this.h);
  final PairHarness h;
  final features = RuntimeFeatureRegistry(
    const BuildFeatureRegistry.allEnabled(),
  );
  var ids = 0;
  late PairCuratedAllowlist allowlist;
  late PairMatchingExperienceRuntime runtime;
  late TodayHubSnapshot today;
  PairDensityPreferences get preferences => PairDensityPreferences(
    ownerId: h.owner,
    learnerPreference: PairDensity.compact4,
  );
  static Future<_Fixture> create() async {
    final f = _Fixture(PairHarness());
    await f.h.initialize();
    final h = f.h;
    f.allowlist = PairCuratedAllowlist(
      version: h.operation.plan.allowlistVersion,
      items: h.operation.plan.orderedLexicalItems,
    );
    final learning = LearningUseCases(
      owners: h.learning.owners,
      repository: h.real,
      generateId: () => 'synthetic-route-${++f.ids}',
      nowUtc: h.learning.nowUtc,
      buildInfo: h.learning.buildInfo,
    );
    f.runtime = PairMatchingExperienceRuntime(
      database: h.db,
      learning: learning,
      registry: buildLessonModeRegistry(
        internalPairMatching: true,
        matchingDeliveryState: LessonModeDeliveryState.enabled,
      ),
      createController: (adapter) => UnifiedLessonController(
        learning: learning,
        adapter: adapter,
        sessionPurposeReader: h.real,
      ),
      composer: PairMatchingSourceComposer(allowlist: f.allowlist),
      start: PairMatchingAtomicStartAdapter(
        repository: h.real,
        capability: InternalPairMatchingCapability(
          allowlist: f.allowlist,
          isEnabled: () => true,
        ),
      ),
      canStart: () => true,
      features: f.features,
    );
    f.today = TodayHubSnapshot(
      ownerId: h.owner,
      evaluatedAtUtc: DateTime.utc(2026, 9, 5),
      sectionOrder: const [TodayHubSectionKind.review],
      resumableSession: null,
      assignedAssessment: null,
      reviewWork: f.allowlist.items.map(
        (i) => TodayHubReviewWorkItem(
          item: ReviewQueueItem(
            snapshot: ReviewedLexicalContentSnapshot(
              identity: ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: i.wordId,
                revision: i.contentRevision,
              ),
              categoryId: 'synthetic-category',
              spelling: i.spelling,
              normalizedSpelling: i.spelling,
              meaning: i.meaning,
              normalizedMeaning: i.meaning,
              partOfSpeech: 'noun',
              cefrLevel: null,
              source: 'manual',
              isGlobal: false,
              coreChecksumSha256: i.checksum,
              provenance: ContentProvenance.userAuthored,
              reviewState: ContentReviewState.unreviewed,
              publicationState: ContentPublicationState.private,
              artifact: null,
            ),
            provenance: [
              ReviewReasonProvenance.saved(
                sourceId: 'synthetic-save-${i.wordId}',
                occurredAtUtc: DateTime.utc(2026, 9, 5),
              ),
            ],
          ),
          recommendation: null,
        ),
      ),
      recommendation: TodayHubRecommendation(
        result: RecommendationPanelResult.unavailable(
          ownerId: h.owner,
          reason: RecommendationPanelReason.noEligibleActivity,
          freshness: RecommendationEvidenceFreshness.missing,
          protocolConstraint: RecommendationProtocolConstraint.open,
        ),
        isAuthoritative: false,
        mergedInto: null,
      ),
      goals: const [],
      reminders: const [],
      quests: const [],
      gentleStreak: null,
      dependencyStates: {
        for (final d in TodayHubDependency.values)
          d: TodayHubDependencyState.ready,
      },
    );
    return f;
  }

  AdventureProductEntryDecision decision(bool adventure) =>
      AdventureProductEntryDecision(
        entryAttemptId: 'synthetic-entry',
        availability: AdventureAvailability.available,
        destination: adventure
            ? AdventureEntryDestination.adventure
            : AdventureEntryDestination.standardToday,
        fallbackReason: AdventureFallbackReason.none,
        catalogId: 'synthetic',
        catalogVersion: '1',
        catalogSchemaVersion: 1,
      );
  AdventureMissionLaunchContext context({bool incompatible = false}) =>
      AdventureMissionLaunchContext(
        today: today,
        entryDecision: decision(true),
        rewardOwnership: RewardAccount(
          coinBalance: 0,
          catalogVersion: RewardCatalog.version,
          ownedItemIds: const {},
          equippedBySlot: const {},
          transactionCount: 0,
        ),
        mission: AdventureMissionRef(
          missionId: 'review:synthetic',
          ownerId: h.owner,
          nodeId: 'resume-review',
          kind: incompatible
              ? AdventureMissionKind.recommendation
              : AdventureMissionKind.review,
          sourceId: today.reviewWork.first.identity.id,
          content: today.reviewWork.map((w) => w.identity).toList(),
          reasonCode: 'due_review',
          sourceEvaluatedAtUtc: today.evaluatedAtUtc,
        ),
      );
}

class _Fallback implements TodayHubActionDelegate {
  int reviews = 0, history = 0;
  List<TodayHubReviewWorkItem>? lastReview;
  final recommendations = <TodayHubRecommendation>[];
  @override
  Future<void> openHistory() async {
    history++;
  }

  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {
    reviews++;
    lastReview = work;
  }

  @override
  Future<void> resume(LearningSessionSummary session) async {}
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) async {}
  @override
  Future<void> startRecommendation(
    TodayHubRecommendation recommendation,
  ) async {
    recommendations.add(recommendation);
  }
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-pair-diagnostics');
}
