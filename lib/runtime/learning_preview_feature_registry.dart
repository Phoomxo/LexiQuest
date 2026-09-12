import 'registries/feature_registry.dart';

/// Local preview changes only ordinary Today visibility. Runtime overrides are
/// applied outside this base registry and remain authoritative.
final class LearningPreviewFeatureRegistry implements FeatureRegistry {
  const LearningPreviewFeatureRegistry(this.base);

  final FeatureRegistry base;

  @override
  FeatureState stateOf(Feature feature) {
    final state = base.stateOf(feature);
    return feature == Feature.dailyContinuity && state == FeatureState.hidden
        ? FeatureState.enabled
        : state;
  }

  @override
  bool isEnabled(Feature feature) => switch (stateOf(feature)) {
    FeatureState.enabled || FeatureState.limited => true,
    _ => false,
  };

  @override
  bool isVisible(Feature feature) => isEnabled(feature);
}
