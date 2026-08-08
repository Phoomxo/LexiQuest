import 'package:flutter/foundation.dart';

import 'field_feature.dart';
import 'registries/feature_registry.dart';

abstract interface class FieldFeatureRegistry {
  FieldFeatureState stateOf(FieldFeature feature);

  bool isVisible(FieldFeature feature);
}

final class BuildFieldFeatureRegistry implements FieldFeatureRegistry {
  const BuildFieldFeatureRegistry(this._states);

  const BuildFieldFeatureRegistry.fieldDefaults()
    : _states = const {
        FieldFeature.vocabulary: FieldFeatureState.enabled,
        FieldFeature.quiz: FieldFeatureState.enabled,
        FieldFeature.srs: FieldFeatureState.enabled,
        FieldFeature.reading: FieldFeatureState.enabled,
        FieldFeature.mastery: FieldFeatureState.enabled,
        FieldFeature.weakness: FieldFeatureState.enabled,
        FieldFeature.ghostDuel: FieldFeatureState.enabled,
        FieldFeature.achievements: FieldFeatureState.enabled,
        FieldFeature.shop: FieldFeatureState.enabled,
        FieldFeature.objectScanner: FieldFeatureState.limited,
        FieldFeature.speechPractice: FieldFeatureState.limited,
        FieldFeature.aiTutor: FieldFeatureState.limited,
        FieldFeature.export: FieldFeatureState.enabled,
      };

  const BuildFieldFeatureRegistry.allEnabled()
    : _states = const {
        FieldFeature.vocabulary: FieldFeatureState.enabled,
        FieldFeature.quiz: FieldFeatureState.enabled,
        FieldFeature.srs: FieldFeatureState.enabled,
        FieldFeature.reading: FieldFeatureState.enabled,
        FieldFeature.mastery: FieldFeatureState.enabled,
        FieldFeature.weakness: FieldFeatureState.enabled,
        FieldFeature.ghostDuel: FieldFeatureState.enabled,
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

/// Keeps legacy navigation on the same effective feature state as V2 code.
final class FeatureRegistryFieldAdapter extends ChangeNotifier
    implements FieldFeatureRegistry {
  FeatureRegistryFieldAdapter(this._features) {
    final source = _features;
    if (source is Listenable) {
      final listenable = source as Listenable;
      _source = listenable;
      listenable.addListener(_relayChange);
    }
  }

  final FeatureRegistry _features;
  Listenable? _source;

  void _relayChange() => notifyListeners();

  @override
  void dispose() {
    _source?.removeListener(_relayChange);
    _source = null;
    super.dispose();
  }

  @override
  FieldFeatureState stateOf(FieldFeature feature) {
    return switch (_features.stateOf(_map(feature))) {
      FeatureState.enabled => FieldFeatureState.enabled,
      FeatureState.limited => FieldFeatureState.limited,
      FeatureState.hidden ||
      FeatureState.disabled ||
      FeatureState.emergencyOff => FieldFeatureState.hidden,
    };
  }

  @override
  bool isVisible(FieldFeature feature) =>
      stateOf(feature) != FieldFeatureState.hidden;

  static Feature _map(FieldFeature feature) => switch (feature) {
    FieldFeature.vocabulary => Feature.vocabulary,
    FieldFeature.quiz => Feature.quiz,
    FieldFeature.srs => Feature.srs,
    FieldFeature.reading => Feature.reading,
    FieldFeature.mastery => Feature.mastery,
    FieldFeature.weakness => Feature.weakness,
    FieldFeature.ghostDuel => Feature.ghostDuel,
    FieldFeature.achievements => Feature.achievements,
    FieldFeature.shop => Feature.shop,
    FieldFeature.objectScanner => Feature.objectScanner,
    FieldFeature.speechPractice => Feature.speechPractice,
    FieldFeature.aiTutor => Feature.aiTutor,
    FieldFeature.export => Feature.export,
  };
}
