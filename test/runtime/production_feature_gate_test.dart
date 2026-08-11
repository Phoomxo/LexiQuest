import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

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
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry({Feature.reading: FeatureState.enabled}),
    );
    addTearDown(registry.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionFeatureGate(
          feature: Feature.reading,
          registry: registry,
          builder: (_) {
            builds += 1;
            return const Text('reading content');
          },
        ),
      ),
    );

    expect(find.text('reading content'), findsOneWidget);
    expect(builds, 1);

    registry.emergencyOff(Feature.reading);
    await tester.pump();

    expect(find.text('reading content'), findsNothing);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(unavailable.state, FeatureState.emergencyOff);
    expect(builds, 1, reason: 'disabled rebuild must stay lazy');
  });
}
