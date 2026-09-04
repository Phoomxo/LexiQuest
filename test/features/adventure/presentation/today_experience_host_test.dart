import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_presentation_preferences.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/presentation/today_experience_host.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_view.dart';

void main() {
  testWidgets('Standard escape is visible and usable while Today is loading', (
    tester,
  ) async {
    final pending = Completer<TodayHubSnapshot>();
    final loader = _PendingLoader(pending.future);
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.pump();

    expect(find.byType(TodayHubLoading), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adventure-standard-switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<TodayExperiencePresentation>>(
            find.byKey(const ValueKey('adventure-standard-switch')),
          )
          .onSelectionChanged,
      isNotNull,
    );

    await tester.tap(find.text('มาตรฐาน'));
    await tester.pump();
    expect(
      tester
          .widget<SegmentedButton<TodayExperiencePresentation>>(
            find.byKey(const ValueKey('adventure-standard-switch')),
          )
          .selected,
      <TodayExperiencePresentation>{TodayExperiencePresentation.standard},
    );

    pending.complete(_today());
    await tester.pumpAndSettle();
    expect(find.byType(TodayHubView), findsOneWidget);
    expect(loader.calls, 1);
  });

  testWidgets('Standard escape recovers from Adventure load failure', (
    tester,
  ) async {
    final loader = _Loader(_today());
    final savedChoices = <TodayExperiencePresentation>[];
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _FailingJourney(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        activePermits: _Permits(_permit()),
        presentationPreferences: _CallbackPreferenceWriter(
          (_, choice) async => savedChoices.add(choice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TodayHubLoadFailure), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adventure-standard-switch')),
      findsOneWidget,
    );

    await tester.tap(find.text('มาตรฐาน'));
    await tester.pumpAndSettle();

    expect(find.byType(TodayHubView), findsOneWidget);
    expect(loader.calls, 1);
    expect(savedChoices, isEmpty);
  });

  testWidgets('Standard escape stays usable in the unavailable state', (
    tester,
  ) async {
    final loader = _Loader(_today(ownerId: 'owner:other'));
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'กิจกรรมแบบผจญภัยยังไม่พร้อม รายการเรียนเดิมของคุณไม่เปลี่ยนแปลง',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('adventure-standard-switch')),
      findsOneWidget,
    );

    await tester.tap(find.text('มาตรฐาน'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SegmentedButton<TodayExperiencePresentation>>(
            find.byKey(const ValueKey('adventure-standard-switch')),
          )
          .selected,
      <TodayExperiencePresentation>{TodayExperiencePresentation.standard},
    );
    expect(loader.calls, 1);
  });

  testWidgets(
    'active Adventure permit escapes to Standard without reopening or saving',
    (tester) async {
      final today = _today();
      final loader = _Loader(today);
      final journey = _Journey();
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      final app = _app(
        loader: loader,
        journey: journey,
        createId: () {
          const id = '11111111-1111-4111-8111-111111111111';
          ids.add(id);
          return id;
        },
        activePermits: _Permits(_permit()),
        presentationPreferences: _CallbackPreferenceWriter(
          (_, choice) async => savedChoices.add(choice),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adventure-hub')), findsOneWidget);

      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(
        tester.widget<TodayHubView>(find.byType(TodayHubView)).snapshot,
        same(today),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(loader.calls, 1);
      expect(ids, hasLength(1));
      expect(journey.today, same(today));
      expect(savedChoices, isEmpty);
    },
  );

  testWidgets(
    'Standard escape during unresolved permit read never saves protocol preference',
    (tester) async {
      final permits = _PendingPermits();
      final loader = _Loader(_today());
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: _Journey(),
          createId: () {
            const id = '11111111-1111-4111-8111-111111111111';
            ids.add(id);
            return id;
          },
          activePermits: permits,
          presentationPreferences: _CallbackPreferenceWriter(
            (_, choice) async => savedChoices.add(choice),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TodayHubLoading), findsOneWidget);
      await tester.tap(find.text('มาตรฐาน'));
      await tester.pump();
      expect(savedChoices, isEmpty);

      permits.complete(_permit());
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubView), findsOneWidget);
      expect(savedChoices, isEmpty);
      expect(loader.calls, 1);
      expect(ids, hasLength(1));
    },
  );

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
          presentationPreferences: _CallbackPreferenceWriter(
            (_, choice) async => savedChoices.add(choice),
          ),
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

  testWidgets('rapid switches serialize saves and persist the last selection', (
    tester,
  ) async {
    final saver = _ControlledPreferenceSaver();
    await tester.pumpWidget(
      _app(
        loader: _Loader(_today()),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: saver,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('มาตรฐาน'));
    await tester.pump();

    expect(saver.started, <TodayExperiencePresentation>[
      TodayExperiencePresentation.adventure,
    ]);
    saver.completeNext();
    await tester.pump();
    expect(saver.started, <TodayExperiencePresentation>[
      TodayExperiencePresentation.adventure,
      TodayExperiencePresentation.standard,
    ]);
    saver.completeNext();
    await tester.pumpAndSettle();

    expect(saver.completed.last, TodayExperiencePresentation.standard);
    expect(find.byType(TodayHubView), findsOneWidget);
  });

  testWidgets('save failure is visible and retry recovers it', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        loader: _Loader(_today()),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: _CallbackPreferenceWriter((_, _) async {
          calls += 1;
          if (calls == 1) throw StateError('disk unavailable');
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsOneWidget,
    );

    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsNothing,
    );
  });

  testWidgets('owner change fences an old pending presentation save', (
    tester,
  ) async {
    final oldSave = Completer<void>();
    final calls = <String>[];
    final writer = _CallbackPreferenceWriter((ownerId, presentation) {
      calls.add('$ownerId/${presentation.name}');
      return ownerId == 'owner:one' ? oldSave.future : Future<void>.value();
    });
    var owner = 'owner:one';

    await tester.pumpWidget(
      _app(
        ownerId: owner,
        loader: _Loader(_today(ownerId: owner)),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ผจญภัย'));
    await tester.pump();

    owner = 'owner:two';
    await tester.pumpWidget(
      _app(
        ownerId: owner,
        loader: _Loader(_today(ownerId: owner)),
        journey: _Journey(),
        createId: () => '22222222-2222-4222-8222-222222222222',
        presentationPreferences: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();

    expect(calls, <String>['owner:one/adventure', 'owner:two/adventure']);
    oldSave.completeError(StateError('stale owner failure'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsNothing,
    );
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
    final account = _rewardAccount();
    await tester.pumpWidget(
      _app(
        loader: _Loader(today),
        journey: _Journey(mission: mission),
        createId: () => '11111111-1111-4111-8111-111111111111',
        rewardAccounts: _RewardAccounts(account),
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
    expect(captured?.rewardOwnership, same(account));
    expect(
      captured?.entryDecision.destination,
      AdventureEntryDestination.adventure,
    );
  });

  testWidgets(
    'Adventure hub reads ownership and renders mission-ready reaction',
    (tester) async {
      final today = _today();
      final mission = AdventureMissionRef(
        missionId: 'mission:ready',
        ownerId: today.ownerId,
        nodeId: 'today-mission',
        kind: AdventureMissionKind.recommendation,
        sourceId: 'word:one',
        content: const [],
        reasonCode: 'due',
        sourceEvaluatedAtUtc: today.evaluatedAtUtc,
      );
      final rewards = _RewardAccounts(
        _rewardAccount(
          equippedBySlot: const <String, String>{'headgear': 'headgear_ipa'},
        ),
      );
      await tester.pumpWidget(
        _app(
          loader: _Loader(today),
          journey: _Journey(mission: mission),
          createId: () => '11111111-1111-4111-8111-111111111111',
          rewardAccounts: rewards,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ผจญภัย'));
      await tester.pumpAndSettle();

      expect(rewards.calls, 1);
      expect(rewards.ownerIds, <String>[today.ownerId]);
      expect(find.text('ภารกิจพร้อมแล้ว เริ่มเมื่อคุณพร้อมนะ'), findsOneWidget);
      expect(find.text('หมวก IPA'), findsOneWidget);
    },
  );
}

Widget _app({
  String ownerId = 'owner:one',
  required TodayHubSnapshotLoader loader,
  required AdventureJourneyReader journey,
  required String Function() createId,
  Future<void> Function(AdventureMissionLaunchContext)? onStartMission,
  AdventurePresentationPreferenceWriter? presentationPreferences,
  RewardAccountReader? rewardAccounts,
  ActivePresentationPermitReader activePermits =
      const NoActivePresentationPermitReader(),
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
      activePermits: activePermits,
      todayHub: loader,
      catalog: catalog,
      journey: journey,
      rewardAccounts: rewardAccounts ?? _RewardAccounts(_rewardAccount()),
      createEntryAttemptId: createId,
      nowUtc: () => _now,
      actions: _Actions(),
      features: const BuildFeatureRegistry.allEnabled(),
      assessmentAvailable: false,
      presentationPreferences: presentationPreferences,
      onStartMission: onStartMission ?? (_) async {},
    ),
  );
}

final class _RewardAccounts implements RewardAccountReader {
  _RewardAccounts(this.account);

  final RewardAccount account;
  int calls = 0;
  final List<String> ownerIds = <String>[];

  @override
  Future<RewardAccount> loadForOwner(String ownerId) async {
    calls += 1;
    ownerIds.add(ownerId);
    return account;
  }
}

RewardAccount _rewardAccount({
  Map<String, String> equippedBySlot = const <String, String>{},
}) => RewardAccount(
  coinBalance: 0,
  catalogVersion: RewardCatalog.version,
  ownedItemIds: equippedBySlot.values.toSet(),
  equippedBySlot: equippedBySlot,
  transactionCount: 0,
);

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
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() {
    calls += 1;
    return pending;
  }
}

final class _Permits implements ActivePresentationPermitReader {
  _Permits(this.permit);

  final ActivePresentationPermit? permit;

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async => permit;
}

final class _PendingPermits implements ActivePresentationPermitReader {
  final Completer<ActivePresentationPermit?> _pending =
      Completer<ActivePresentationPermit?>();

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) => _pending.future;

  void complete(ActivePresentationPermit? permit) => _pending.complete(permit);
}

final class _ControlledPreferenceSaver
    implements AdventurePresentationPreferenceWriter {
  final List<TodayExperiencePresentation> started =
      <TodayExperiencePresentation>[];
  final List<TodayExperiencePresentation> completed =
      <TodayExperiencePresentation>[];
  final List<Completer<void>> _pending = <Completer<void>>[];

  @override
  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  ) async {
    started.add(presentation);
    final gate = Completer<void>();
    _pending.add(gate);
    await gate.future;
    completed.add(presentation);
  }

  void completeNext() => _pending.removeAt(0).complete();
}

final class _CallbackPreferenceWriter
    implements AdventurePresentationPreferenceWriter {
  const _CallbackPreferenceWriter(this.callback);

  final Future<void> Function(
    String ownerId,
    TodayExperiencePresentation presentation,
  )
  callback;

  @override
  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  ) => callback(ownerId, presentation);
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

final class _FailingJourney implements AdventureJourneyReader {
  @override
  Future<AdventureJourneySnapshot> compose(
    AdventureJourneyRequest request,
  ) async => throw StateError('Adventure projection unavailable');
}

ActivePresentationPermit _permit() => ActivePresentationPermit(
  permitId: 'permit:one',
  ownerId: 'owner:one',
  assignedPresentation: TodayExperiencePresentation.adventure,
  protocolId: 'protocol:one',
  protocolVersion: '1.0.0',
  assignmentId: 'assignment:one',
  expiresAtUtc: _now.add(const Duration(days: 1)),
);

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
