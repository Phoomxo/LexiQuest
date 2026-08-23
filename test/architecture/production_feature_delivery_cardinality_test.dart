import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/runtime_feature_override_store.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

const _persistedFeatureNames = <String>[
  'vocabulary',
  'quiz',
  'srs',
  'reading',
  'mastery',
  'weakness',
  'ghostDuel',
  'achievements',
  'shop',
  'objectScanner',
  'speechPractice',
  'aiTutor',
  'export',
  'shadowRewardV2',
  'questV2',
  'studyPlanning',
  'researchAssessment',
  'dailyContinuity',
  'offlineContent',
];

const _broadDeliveries =
    <Feature, ({String productionEntryId, String screenClassName})>{
      Feature.studyPlanning: (
        productionEntryId: 'home/study-planning',
        screenClassName: 'StudyPlanningHubScreen',
      ),
      Feature.researchAssessment: (
        productionEntryId: 'research/assessment',
        screenClassName: 'PrePostAssessmentScreen',
      ),
      Feature.dailyContinuity: (
        productionEntryId: 'home/today',
        screenClassName: 'TodayHubScreen',
      ),
      Feature.offlineContent: (
        productionEntryId: 'settings/offline-content',
        screenClassName: 'OfflineContentManagerScreen',
      ),
    };

const _productContractsByBroadFeature = <String, Set<FeatureContractId>>{
  'studyPlanning': {
    FeatureContractId.f01,
    FeatureContractId.f26,
    FeatureContractId.f27,
  },
  'researchAssessment': {FeatureContractId.f28},
  'dailyContinuity': {
    FeatureContractId.f22,
    FeatureContractId.f30,
    FeatureContractId.f37,
    FeatureContractId.f42,
    FeatureContractId.f43,
  },
  'offlineContent': {FeatureContractId.f44},
};

void main() {
  test('runtime feature identities append exactly four broad parents', () {
    expect(
      Feature.values.map((feature) => feature.name).toList(growable: false),
      _persistedFeatureNames,
      reason:
          'Persisted runtime identities are append-only and child fXX actions '
          'must not create additional flags.',
    );
  });

  test('each broad runtime feature owns one exact production delivery', () {
    final deliveriesByName = <String, ProductionFeatureDelivery>{
      for (final entry in productionFeatureContract.entries)
        entry.key.name: entry.value,
    };

    expect(deliveriesByName.keys.toList(), _persistedFeatureNames);
    expect(productionFeatureContract, hasLength(_persistedFeatureNames.length));
    expect(
      productionFeatureContract.keys.toSet(),
      Feature.values.toSet(),
      reason: 'Every runtime feature must have exactly one delivery record.',
    );

    final nonEmptyEntryIds = productionFeatureContract.values
        .map((delivery) => delivery.productionEntryId)
        .where((entryId) => entryId.isNotEmpty)
        .toList(growable: false);
    expect(
      nonEmptyEntryIds.toSet(),
      hasLength(nonEmptyEntryIds.length),
      reason: 'Parent and child actions must never compete for one route.',
    );

    for (final expected in _broadDeliveries.entries) {
      final delivery = productionFeatureContract[expected.key];
      expect(delivery, isNotNull, reason: '${expected.key.name} delivery');
      if (delivery == null) continue;
      expect(delivery.feature, expected.key);
      expect(delivery.productionEntryId, expected.value.productionEntryId);
      expect(delivery.durable, isTrue);
      expect(delivery.dependencyId, isNotEmpty);
      expect(
        nonEmptyEntryIds.where(
          (entryId) => entryId == expected.value.productionEntryId,
        ),
        hasLength(1),
        reason:
            '${expected.key.name} must own its canonical route exactly once.',
      );
    }
  });

  test('delivery declarations pin the four canonical screen targets', () {
    for (final expected in _broadDeliveries.entries) {
      final delivery = productionFeatureContract[expected.key];
      expect(delivery, isNotNull, reason: '${expected.key.name} delivery');
      if (delivery == null) continue;
      expect(delivery.productionEntryId, expected.value.productionEntryId);
      expect(
        delivery.screenClassName,
        expected.value.screenClassName,
        reason:
            '${expected.key.name} must pin ${expected.value.screenClassName} as '
            'its sole canonical delivery target.',
      );
    }
  });

  test(
    'product records reuse broad parents and never auto-enable delivery',
    () {
      const buildDefaults = BuildFeatureRegistry.fieldDefaults();
      final runtime = RuntimeFeatureRegistry(buildDefaults);
      addTearDown(runtime.dispose);

      final mappingsByName = <String, Set<FeatureContractId>>{
        for (final entry in productContractIdsByRuntimeFeature.entries)
          entry.key.name: entry.value,
      };

      for (final expected in _productContractsByBroadFeature.entries) {
        final feature = _featureNamed(expected.key);
        expect(feature, isNotNull, reason: '${expected.key} runtime identity');
        if (feature == null) continue;

        expect(mappingsByName[expected.key], expected.value);
        expect(buildDefaults.configuredFeatures, contains(feature));
        expect(
          runtime.stateOf(feature),
          anyOf(FeatureState.hidden, FeatureState.disabled),
          reason: '${expected.key} must be implemented-off by default.',
        );

        final mappedRecords = allTcasIdeaIntegrationCatalog.records
            .where((record) => expected.value.contains(record.id))
            .toList(growable: false);
        expect(mappedRecords, hasLength(expected.value.length));
        expect(
          mappedRecords.every(
            (record) => record.runtimeFeatures.contains(feature),
          ),
          isTrue,
          reason: 'Child contracts must reuse the broad parent flag.',
        );

        // Catalog reads are metadata-only. They cannot mutate runtime state.
        for (final record in mappedRecords) {
          record.productionEntryIds.toList(growable: false);
        }
        expect(
          runtime.stateOf(feature),
          anyOf(FeatureState.hidden, FeatureState.disabled),
        );
      }
    },
  );

  testWidgets(
    'enabled registry without the composed dependency still fails closed',
    (tester) async {
      var builds = 0;
      const registry = BuildFeatureRegistry({
        Feature.quiz: FeatureState.enabled,
      });
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dependencies = _inertDependenciesWithoutLearning(
        database,
        registry,
      );

      expect(dependencies.learning, isNull);

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: ProductionFeatureGate(
              feature: Feature.quiz,
              registry: registry,
              builder: (_) {
                builds += 1;
                return const Text('must not build without LearningUseCases');
              },
            ),
          ),
        ),
      );

      expect(builds, 0);
      final unavailable = tester.widget<ProductionFeatureUnavailable>(
        find.byType(ProductionFeatureUnavailable),
      );
      expect(
        unavailable.reason,
        ProductionFeatureUnavailableReason.missingDependency,
      );
      expect(
        find.text('must not build without LearningUseCases'),
        findsNothing,
      );
    },
  );

  test(
    'emergency-off leaves the experiment assignment byte-equivalent',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      final controls = RuntimeFeatureControls(
        store: RuntimeFeatureOverrideStore(database),
        registry: registry,
        nowUtc: () => DateTime.utc(2026, 8, 24, 12),
      );
      addTearDown(() async {
        controls.dispose();
        registry.dispose();
        await database.close();
      });

      await database.customInsert(
        'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
        'VALUES (?, ?, ?)',
        variables: const [
          Variable<String>('owner-rollout'),
          Variable<String>('localGuest'),
          Variable<int>(1),
        ],
      );
      final assignments = DriftExperimentAssignmentRepository(database);
      final before = await assignments.assignIfAbsent(
        ownerId: 'owner-rollout',
        experimentId: 'controlled-rollout',
        experimentVersion: 1,
        cohort: 'pilot',
        protocolVersion: 'protocol-1',
        assignedAtUtc: DateTime.utc(2026, 8, 24, 11),
      );
      final beforeRows = await _assignmentAuthorityRows(database);

      await controls.emergencyOff(Feature.aiTutor, source: 'field-operator');

      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(
        await assignments.getAssignment(
          ownerId: before.ownerId,
          experimentId: before.experimentId,
          experimentVersion: before.experimentVersion,
        ),
        before,
      );
      expect(await _assignmentAuthorityRows(database), beforeRows);
    },
  );
}

AppDependencies _inertDependenciesWithoutLearning(
  AppDatabase database,
  FeatureRegistry features,
) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSessionService(),
    quest: testQuestUseCases(),
    features: features,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
  );
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionStarted(uid: 'feature-cardinality');
  }
}

Feature? _featureNamed(String name) {
  for (final feature in Feature.values) {
    if (feature.name == name) return feature;
  }
  return null;
}

Future<List<Map<String, Object?>>> _assignmentAuthorityRows(
  AppDatabase database,
) async {
  final rows = await database
      .customSelect(
        'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
        'protocol_version, assigned_at_utc_ms '
        'FROM experiment_assignments ORDER BY id',
      )
      .get();
  return rows
      .map((row) => Map<String, Object?>.unmodifiable(row.data))
      .toList(growable: false);
}
