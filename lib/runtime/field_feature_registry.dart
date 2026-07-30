import 'field_feature.dart';

abstract interface class FieldFeatureRegistry {
  FieldFeatureState stateOf(FieldFeature feature);

  bool isVisible(FieldFeature feature);
}

final class BuildFieldFeatureRegistry implements FieldFeatureRegistry {
  const BuildFieldFeatureRegistry(this._states);

  const BuildFieldFeatureRegistry.fieldDefaults()
    : _states = const {FieldFeature.vocabulary: FieldFeatureState.enabled};

  const BuildFieldFeatureRegistry.allEnabled()
    : _states = const {
        FieldFeature.vocabulary: FieldFeatureState.enabled,
        FieldFeature.quiz: FieldFeatureState.enabled,
        FieldFeature.srs: FieldFeatureState.enabled,
        FieldFeature.reading: FieldFeatureState.enabled,
        FieldFeature.mastery: FieldFeatureState.enabled,
        FieldFeature.weakness: FieldFeatureState.enabled,
        FieldFeature.achievements: FieldFeatureState.enabled,
        FieldFeature.shop: FieldFeatureState.enabled,
        FieldFeature.objectScanner: FieldFeatureState.enabled,
        FieldFeature.speechPractice: FieldFeatureState.enabled,
        FieldFeature.aiTutor: FieldFeatureState.enabled,
        FieldFeature.export: FieldFeatureState.enabled,
      };

  final Map<FieldFeature, FieldFeatureState> _states;

  @override
  FieldFeatureState stateOf(FieldFeature feature) =>
      _states[feature] ?? FieldFeatureState.hidden;

  @override
  bool isVisible(FieldFeature feature) =>
      stateOf(feature) != FieldFeatureState.hidden;
}
