import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/presentation/today_experience_host.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_view.dart';

void main() {
  testWidgets(
    'loads Today once and reuses the exact snapshot and UUID across switches',
    (tester) async {
      final today = _today();
      final loader = _Loader(today);
      final journey = _Journey();
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: journey,
          createId: () {
            const id = '11111111-1111-4111-8111-111111111111';
            ids.add(id);
            return id;
          },
          onPresentationPreferenceChanged: (choice) async {
            savedChoices.add(choice);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(find.byType(TodayHubView), findsOneWidget);
      await tester.tap(find.text('ผจญภัย'));
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(ids, hasLength(1));
      expect(identical(journey.today, today), isTrue);
      expect(find.byKey(const ValueKey('adventure-hub')), findsOneWidget);

      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(savedChoices, <TodayExperiencePresentation>[
        TodayExperiencePresentation.adventure,
        TodayExperiencePresentation.standard,
      ]);
    },
  );

  testWidgets('explicit refresh creates a new UUID and reloads Today', (
    tester,
  ) async {
    final loader = _Loader(_today());
    var idNumber = 0;
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () {
          idNumber += 1;
          return idNumber == 1
              ? '11111111-1111-4111-8111-111111111111'
              : '22222222-2222-4222-8222-222222222222';
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
    await tester.pumpAndSettle();
    expect(idNumber, 2);
    expect(loader.calls, 2);
  });

  testWidgets('stale owner result is discarded without rendering a snapshot', (
    tester,
  ) async {
    final pending = Completer<TodayHubSnapshot>();
    final loader = _PendingLoader(pending.future);
    await tester.pumpWidget(
      _app(
        ownerId: 'owner:one',
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      _app(
        ownerId: 'owner:two',
        loader: loader,
        journey: _Journey(),
        createId: () => '22222222-2222-4222-8222-222222222222',
      ),
    );
    pending.complete(_today(ownerId: 'owner:one'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayHubView), findsNothing);
  });

  testWidgets('mission launch keeps the exact Today and entry decision', (
    tester,
  ) async {
    final today = _today();
    final mission = AdventureMissionRef(
      missionId: 'mission:one',
      ownerId: today.ownerId,
      nodeId: 'today-mission',
      kind: AdventureMissionKind.recommendation,
      sourceId: 'word:one',
      content: const [],
      reasonCode: 'due',
      sourceEvaluatedAtUtc: today.evaluatedAtUtc,
    );
    AdventureMissionLaunchContext? captured;
    await tester.pumpWidget(
      _app(
        loader: _Loader(today),
        journey: _Journey(mission: mission),
        createId: () => '11111111-1111-4111-8111-111111111111',
        onStartMission: (launch) async => captured = launch,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure-start-mission')));
    await tester.pumpAndSettle();

    expect(captured?.mission, same(mission));
    expect(captured?.today, same(today));
    expect(
      captured?.entryDecision.destination,
      AdventureEntryDestination.adventure,
    );
  });
}

Widget _app({
  String ownerId = 'owner:one',
  required TodayHubSnapshotLoader loader,
  required AdventureJourneyReader journey,
  required String Function() createId,
  Future<void> Function(AdventureMissionLaunchContext)? onStartMission,
  AdventurePresentationPreferenceSaver? onPresentationPreferenceChanged,
}) {
  final catalog = PackagedAdventureWorldCatalog.forLocale('th');
  final entry = AdventureEntryUseCases(
    rollout: AdventureRolloutGate(
      features: const BuildFeatureRegistry.allEnabled(),
      requiredDependenciesReady: () => true,
      catalogReadiness: () => AdventureCatalogReadiness.ready,
    ),
    catalog: catalog,
    todayHubIdentity: loader,
    learningIdentity: Object(),
  );
  return MaterialApp(
    home: TodayExperienceHost(
      ownerId: ownerId,
      entry: entry,
      activePermits: const NoActivePresentationPermitReader(),
      todayHub: loader,
      catalog: catalog,
      journey: journey,
      createEntryAttemptId: createId,
      nowUtc: () => _now,
      actions: _Actions(),
      features: const BuildFeatureRegistry.allEnabled(),
      assessmentAvailable: false,
      onPresentationPreferenceChanged: onPresentationPreferenceChanged,
      onStartMission: onStartMission ?? (_) async {},
    ),
  );
}

final _now = DateTime.utc(2026, 9, 4, 8);

TodayHubSnapshot _today({String ownerId = 'owner:one'}) => TodayHubSnapshot(
  ownerId: ownerId,
  evaluatedAtUtc: _now,
  sectionOrder: const <TodayHubSectionKind>[TodayHubSectionKind.recommendation],
  resumableSession: null,
  assignedAssessment: null,
  reviewWork: const <TodayHubReviewWorkItem>[],
  recommendation: TodayHubRecommendation(
    result: RecommendationPanelResult.unavailable(
      ownerId: ownerId,
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
  dependencyStates: <TodayHubDependency, TodayHubDependencyState>{
    for (final dependency in TodayHubDependency.values)
      dependency: TodayHubDependencyState.ready,
  },
);

final class _Loader implements TodayHubSnapshotLoader {
  _Loader(this.snapshot);
  final TodayHubSnapshot snapshot;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    return snapshot;
  }
}

final class _PendingLoader implements TodayHubSnapshotLoader {
  _PendingLoader(this.pending);
  final Future<TodayHubSnapshot> pending;

  @override
  Future<TodayHubSnapshot> load() => pending;
}

final class _Journey implements AdventureJourneyReader {
  _Journey({this.mission});

  final AdventureMissionRef? mission;
  TodayHubSnapshot? today;

  @override
  Future<AdventureJourneySnapshot> compose(
    AdventureJourneyRequest request,
  ) async {
    today = request.today;
    return AdventureJourneySnapshot(
      ownerId: request.ownerId,
      evaluatedAtUtc: request.evaluatedAtUtc,
      sourceEvaluatedAtUtc: request.today.evaluatedAtUtc,
      catalogId: request.catalog.catalogId,
      catalogVersion: request.catalog.catalogVersion,
      catalogSchemaVersion: request.catalog.schemaVersion,
      freshness: AdventureSnapshotFreshness.current,
      dependencyStates:
          <AdventureJourneyAuthority, AdventureJourneyDependencyState>{
            for (final authority in AdventureJourneyAuthority.values)
              authority: AdventureJourneyDependencyState.ready,
          },
      nodes: const [],
      primaryMission: mission,
      inputFingerprintSha256: 'a' * 64,
    );
  }
}

final class _Actions implements TodayHubActionDelegate {
  @override
  Future<void> openHistory() async {}
  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {}
  @override
  Future<void> resume(LearningSessionSummary session) async {}
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) async {}
  @override
  Future<void> startRecommendation(
    TodayHubRecommendation recommendation,
  ) async {}
}
