import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets('disabled features never construct the lazy enabled subtree', (
    tester,
  ) async {
    var builds = 0;
    const registry = BuildFeatureRegistry({
      Feature.vocabulary: FeatureState.disabled,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionFeatureGate(
          feature: Feature.vocabulary,
          registry: registry,
          builder: (_) {
            builds += 1;
            return const Text('enabled content');
          },
        ),
      ),
    );

    expect(builds, 0);
    expect(find.text('enabled content'), findsNothing);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(unavailable.feature, Feature.vocabulary);
    expect(
      unavailable.reason,
      ProductionFeatureUnavailableReason.unavailableState,
    );
    expect(unavailable.state, FeatureState.disabled);
  });

  testWidgets('missing dependency scope fails closed without building', (
    tester,
  ) async {
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionFeatureGate(
          feature: Feature.quiz,
          builder: (_) {
            builds += 1;
            return const Text('quiz content');
          },
        ),
      ),
    );

    expect(builds, 0);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(
      unavailable.reason,
      ProductionFeatureUnavailableReason.missingRegistry,
    );
    expect(unavailable.state, isNull);
  });

  testWidgets('enabled content switches live to unavailable on emergency-off', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry({Feature.questV2: FeatureState.enabled}),
    );
    addTearDown(registry.dispose);
    var builds = 0;

    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, registry),
        child: MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.questV2,
            registry: registry,
            builder: (_) {
              builds += 1;
              return const Text('quest content');
            },
          ),
        ),
      ),
    );

    expect(find.text('quest content'), findsOneWidget);
    expect(builds, 1);

    registry.emergencyOff(Feature.questV2);
    await tester.pump();

    expect(find.text('quest content'), findsNothing);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(unavailable.state, FeatureState.emergencyOff);
    expect(builds, 1, reason: 'disabled rebuild must stay lazy');
  });
}

AppDependencies _dependencies(AppDatabase database, FeatureRegistry features) {
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
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'production-feature-gate');
}
