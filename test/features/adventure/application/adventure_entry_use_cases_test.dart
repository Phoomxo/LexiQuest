import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  final now = DateTime.utc(2026, 9, 4, 10);

  final blockedCases =
      <
        ({
          String id,
          FeatureState state,
          bool dependenciesReady,
          AdventureAvailability availability,
        })
      >[
        (
          id: 'ENT-001 hidden',
          state: FeatureState.hidden,
          dependenciesReady: true,
          availability: AdventureAvailability.hidden,
        ),
        (
          id: 'ENT-002 disabled',
          state: FeatureState.disabled,
          dependenciesReady: true,
          availability: AdventureAvailability.disabled,
        ),
        (
          id: 'ENT-003 missing dependency',
          state: FeatureState.enabled,
          dependenciesReady: false,
          availability: AdventureAvailability.missingDependency,
        ),
        (
          id: 'ENT-006 unknown registry state',
          state: FeatureState.hidden,
          dependenciesReady: true,
          availability: AdventureAvailability.hidden,
        ),
        (
          id: 'ENT-007 emergency off',
          state: FeatureState.emergencyOff,
          dependenciesReady: true,
          availability: AdventureAvailability.emergencyOff,
        ),
        (
          id: 'ENT-013 stale direct route',
          state: FeatureState.disabled,
          dependenciesReady: true,
          availability: AdventureAvailability.disabled,
        ),
      ];

  for (final item in blockedCases) {
    test(
      '${item.id} returns Learn without permit, preference or Today reads',
      () async {
        final permits = _Permits(_permit(now));
        final preferences = _Preferences(TodayExperiencePresentation.adventure);
        final today = _TodayLoader(_snapshot('owner-001', now));
        final useCases = _useCases(
          state: item.state,
          dependenciesReady: item.dependenciesReady,
          permits: permits,
          preferences: preferences,
        );
        final host = AdventureEntryHost(
          entry: useCases,
          activePermits: permits,
          todayHub: today,
          createEntryAttemptId: () => _uuid,
        );

        final result = await host.open(
          ownerId: 'owner-001',
          occurredAtUtc: now,
        );

        expect(result?.decision.destination, AdventureEntryDestination.learn);
        expect(result?.decision.availability, item.availability);
        expect(result?.today, isNull);
        expect(permits.calls, 0);
        expect(preferences.calls, 0);
        expect(today.calls, 0);
      },
    );
  }

  test(
    'ENT-004 enabled Adventure choice opens one canonical Today snapshot',
    () async {
      final today = _TodayLoader(_snapshot('owner-001', now));
      final useCases = _useCases();
      final host = _host(useCases, today: today);

      final result = await host.open(
        ownerId: 'owner-001',
        occurredAtUtc: now,
        sessionChoice: TodayExperiencePresentation.adventure,
      );

      expect(result?.decision.destination, AdventureEntryDestination.adventure);
      expect(result?.decision.treatment, 'adventure');
      expect(result?.today, same(today.snapshot));
      expect(today.calls, 1);
    },
  );

  test('ENT-005 explicit Standard choice does not become Adventure', () async {
    final result = await _host(_useCases()).open(
      ownerId: 'owner-001',
      occurredAtUtc: now,
      sessionChoice: TodayExperiencePresentation.standard,
    );

    expect(
      result?.decision.destination,
      AdventureEntryDestination.standardToday,
    );
    expect(
      result?.decision.fallbackReason,
      AdventureFallbackReason.learnerChoseStandard,
    );
  });

  test(
    'ENT-008/009 emergency off blocks new starts but preserves accepted close',
    () {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry({
          Feature.adventureMotivation: FeatureState.enabled,
        }),
      );
      addTearDown(registry.dispose);
      final gate = AdventureRolloutGate(
        features: registry,
        requiredDependenciesReady: () => true,
        catalogReadiness: () => AdventureCatalogReadiness.ready,
      );

      expect(gate.canStartNewMission, isTrue);
      registry.emergencyOff(Feature.adventureMotivation);
      expect(gate.canStartNewMission, isFalse);
      expect(gate.canCloseAcceptedSession, isTrue);
    },
  );

  test(
    'ENT-010 active permit takes precedence without mutating preference',
    () async {
      final preferences = _Preferences(TodayExperiencePresentation.standard);
      final permit = _permit(now);
      final result =
          await _host(_useCases(preferences: preferences), permit: permit).open(
            ownerId: 'owner-001',
            occurredAtUtc: now,
            sessionChoice: TodayExperiencePresentation.standard,
          );

      expect(result?.decision.destination, AdventureEntryDestination.adventure);
      expect(result?.decision.permitId, permit.permitId);
      expect(result?.decision.assignmentId, permit.assignmentId);
      expect(preferences.calls, 0);
    },
  );

  test(
    'ENT-011 nonparticipant product mode has no research write boundary',
    () async {
      final result = await _host(_useCases()).open(
        ownerId: 'owner-001',
        occurredAtUtc: now,
        sessionChoice: TodayExperiencePresentation.adventure,
      );

      expect(result?.decision.destination, AdventureEntryDestination.adventure);
      expect(result?.decision.permitId, isNull);
      expect(result?.decision.assignmentId, isNull);
    },
  );

  test('ENT-012 stale owner async resolution is discarded', () async {
    final permits = _ControllablePermits();
    final useCases = _useCases(permits: permits);
    final host = AdventureEntryHost(
      entry: useCases,
      activePermits: permits,
      todayHub: _TodayLoader(_snapshot('owner-002', now)),
      createEntryAttemptId: () => _uuid,
    );

    final stale = host.open(ownerId: 'owner-001', occurredAtUtc: now);
    final current = host.open(ownerId: 'owner-002', occurredAtUtc: now);
    permits.complete(null);

    expect(await stale, isNull);
    expect((await current)?.decision.entryAttemptId, _uuid);
  });

  test(
    'ENT-014 rebuild retry and switch reuse one UUID and Today load',
    () async {
      var ids = 0;
      final today = _TodayLoader(_snapshot('owner-001', now));
      final host = AdventureEntryHost(
        entry: _useCases(),
        activePermits: _Permits(null),
        todayHub: today,
        createEntryAttemptId: () {
          ids += 1;
          return _uuid;
        },
      );

      final first = await host.open(ownerId: 'owner-001', occurredAtUtc: now);
      final retry = await host.open(ownerId: 'owner-001', occurredAtUtc: now);
      final switched = await host.open(
        ownerId: 'owner-001',
        occurredAtUtc: now,
        sessionChoice: TodayExperiencePresentation.adventure,
      );

      expect(ids, 1);
      expect(today.calls, 1);
      expect(retry?.decision.entryAttemptId, first?.decision.entryAttemptId);
      expect(switched?.today, same(first?.today));
    },
  );

  test(
    'ENT-015 invalid permit falls through choice then preference then Standard',
    () async {
      final expired = _permit(
        now,
      ).copyWith(expiresAtUtc: now.subtract(const Duration(minutes: 1)));
      final choice = await _host(_useCases(), permit: expired).open(
        ownerId: 'owner-001',
        occurredAtUtc: now,
        sessionChoice: TodayExperiencePresentation.adventure,
      );
      expect(choice?.decision.destination, AdventureEntryDestination.adventure);

      final preference = await _host(
        _useCases(
          preferences: _Preferences(TodayExperiencePresentation.adventure),
        ),
        permit: expired,
      ).open(ownerId: 'owner-001', occurredAtUtc: now);
      expect(
        preference?.decision.destination,
        AdventureEntryDestination.adventure,
      );

      final standard = await _host(
        _useCases(),
        permit: expired,
      ).open(ownerId: 'owner-001', occurredAtUtc: now);
      expect(
        standard?.decision.destination,
        AdventureEntryDestination.standardToday,
      );
      expect(
        standard?.decision.fallbackReason,
        AdventureFallbackReason.assignmentUnavailable,
      );
    },
  );

  test(
    'post-authorization catalog failure uses Standard and keeps version pins',
    () async {
      final result =
          await _host(
            _useCases(catalogReadiness: AdventureCatalogReadiness.invalid),
          ).open(
            ownerId: 'owner-001',
            occurredAtUtc: now,
            sessionChoice: TodayExperiencePresentation.adventure,
          );

      expect(
        result?.decision.destination,
        AdventureEntryDestination.standardToday,
      );
      expect(
        result?.decision.availability,
        AdventureAvailability.invalidCatalog,
      );
      expect(
        result?.decision.fallbackReason,
        AdventureFallbackReason.catalogUnavailable,
      );
      expect(
        result?.decision.catalogId,
        PackagedAdventureWorldCatalog.catalogId,
      );
      expect(
        result?.decision.catalogVersion,
        PackagedAdventureWorldCatalog.catalogVersion,
      );
      expect(result?.decision.catalogSchemaVersion, 1);
      expect(result?.today, isNotNull);
    },
  );

  test(
    'production entry resolver records destination and fallback codes',
    () async {
      final diagnostics = AdventureDiagnostics();
      final result =
          await _host(
            _useCases(
              catalogReadiness: AdventureCatalogReadiness.contentUnavailable,
              diagnostics: diagnostics,
            ),
          ).open(
            ownerId: 'owner-001',
            occurredAtUtc: now,
            sessionChoice: TodayExperiencePresentation.adventure,
          );

      expect(
        result?.decision.destination,
        AdventureEntryDestination.standardToday,
      );
      expect(
        diagnostics.snapshot().counters,
        <AdventureDiagnosticReasonCode, int>{
          AdventureDiagnosticReasonCode.entryStandard: 1,
          AdventureDiagnosticReasonCode.entryFallbackContentUnavailable: 1,
        },
      );
    },
  );

  test('Product Entry source has no raw consent or measurement dependency', () {
    final source = File(
      'lib/features/adventure/application/adventure_entry_use_cases.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ConsentRegistry')));
    expect(source, isNot(contains('ResearchConsent')));
    expect(source, isNot(contains('consentReceiptId')));
    expect(source, isNot(contains('guardianPermissionReceiptRef')));
    expect(source, isNot(contains('learnerAssentReceiptRef')));
    expect(source, isNot(contains('measurement')));
    expect(source, contains('ActivePresentationPermitReader'));
  });
}

AdventureEntryUseCases _useCases({
  FeatureState state = FeatureState.enabled,
  bool dependenciesReady = true,
  AdventureCatalogReadiness catalogReadiness = AdventureCatalogReadiness.ready,
  ActivePresentationPermitReader? permits,
  AdventurePresentationPreferenceReader? preferences,
  AdventureDiagnostics? diagnostics,
}) {
  final registry = BuildFeatureRegistry(<Feature, FeatureState>{
    Feature.adventureMotivation: state,
  });
  return AdventureEntryUseCases(
    rollout: AdventureRolloutGate(
      features: registry,
      requiredDependenciesReady: () => dependenciesReady,
      catalogReadiness: () => catalogReadiness,
    ),
    catalog: PackagedAdventureWorldCatalog.forLocale('th'),
    todayHubIdentity: _identityToday,
    learningIdentity: _identityLearning,
    preferences: preferences,
    diagnostics: diagnostics,
  );
}

AdventureEntryHost _host(
  AdventureEntryUseCases useCases, {
  TodayHubSnapshotLoader? today,
  ActivePresentationPermit? permit,
}) => AdventureEntryHost(
  entry: useCases,
  activePermits: _Permits(permit),
  todayHub: today ?? _TodayLoader(_snapshot('owner-001', _now)),
  createEntryAttemptId: () => _uuid,
);

ActivePresentationPermit _permit(DateTime now) => ActivePresentationPermit(
  permitId: 'permit-001',
  ownerId: 'owner-001',
  assignedPresentation: TodayExperiencePresentation.adventure,
  protocolId: 'amm-pilot',
  protocolVersion: '1.0.0',
  assignmentId: 'assignment-001',
  expiresAtUtc: now.add(const Duration(days: 1)),
);

TodayHubSnapshot _snapshot(String ownerId, DateTime now) => TodayHubSnapshot(
  ownerId: ownerId,
  evaluatedAtUtc: now,
  sectionOrder: const <TodayHubSectionKind>[],
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

final class _TodayLoader implements TodayHubSnapshotLoader {
  _TodayLoader(this.snapshot);
  final TodayHubSnapshot snapshot;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    return snapshot;
  }
}

final class _Permits implements ActivePresentationPermitReader {
  _Permits(this.permit);
  final ActivePresentationPermit? permit;
  int calls = 0;

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    calls += 1;
    return permit;
  }
}

final class _ControllablePermits implements ActivePresentationPermitReader {
  final Completer<ActivePresentationPermit?> _completer =
      Completer<ActivePresentationPermit?>();

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) => _completer.future;

  void complete(ActivePresentationPermit? permit) =>
      _completer.complete(permit);
}

final class _Preferences implements AdventurePresentationPreferenceReader {
  _Preferences(this.value);
  final TodayExperiencePresentation? value;
  int calls = 0;

  @override
  Future<TodayExperiencePresentation?> readForOwner(String ownerId) async {
    calls += 1;
    return value;
  }
}

const _uuid = '018f1f90-7b2d-4d58-8d7d-6d97039ad003';
final _now = DateTime.utc(2026, 9, 4, 10);
final Object _identityToday = Object();
final Object _identityLearning = Object();
