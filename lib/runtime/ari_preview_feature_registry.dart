import 'registries/feature_registry.dart';

/// Explicit isolated Ari entry only. Runtime emergency overrides still wrap this.
final class AriPreviewFeatureRegistry implements FeatureRegistry {
  const AriPreviewFeatureRegistry(this.base);
  final FeatureRegistry base;

  @override
  FeatureState stateOf(Feature feature) => switch (feature) {
    Feature.studyPlanning || Feature.offlineContent => FeatureState.enabled,
    _ => base.stateOf(feature),
  };

  @override
  bool isEnabled(Feature feature) => switch (stateOf(feature)) {
    FeatureState.enabled || FeatureState.limited => true,
    _ => false,
  };

  @override
  bool isVisible(Feature feature) => isEnabled(feature);
}
