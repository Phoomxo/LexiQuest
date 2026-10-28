/// V2 Feature Registry — build-time feature flags.
///
/// This is the successor to [FieldFeatureRegistry].  The two coexist during
/// Phase -1 / Phase 0 migration; screens should prefer this interface for new
/// code.  [FieldFeatureRegistry] remains for screens that have not yet been
/// migrated.
library;

import 'feature.dart';

export 'feature.dart';

/// Read-only contract for querying [Feature] availability.
abstract interface class FeatureRegistry {
  /// Returns the [FeatureState] for [feature].
  FeatureState stateOf(Feature feature);

  /// Convenience: returns `true` when the feature should be shown in the UI
  /// (i.e. its state is [FeatureState.enabled] or [FeatureState.limited]).
  bool isVisible(Feature feature);
}

/// Immutable, build-time [FeatureRegistry] driven by an explicit state map.
///
/// ```dart
/// // Production default
/// const registry = BuildFeatureRegistry.fieldDefaults();
///
/// // Test — all features enabled
/// const registry = BuildFeatureRegistry.allEnabled();
/// ```
final class BuildFeatureRegistry implements FeatureRegistry {
  const BuildFeatureRegistry(this._states);

  const BuildFeatureRegistry.fieldDefaults()
    : _states = const {
        Feature.vocabulary: FeatureState.enabled,
        Feature.quiz: FeatureState.enabled,
        Feature.srs: FeatureState.enabled,
        Feature.reading: FeatureState.enabled,
        Feature.mastery: FeatureState.enabled,
        Feature.weakness: FeatureState.enabled,
        Feature.ghostDuel: FeatureState.enabled,
        Feature.achievements: FeatureState.enabled,
        Feature.shop: FeatureState.enabled,
        Feature.objectScanner: FeatureState.limited,
        Feature.speechPractice: FeatureState.limited,
        Feature.aiTutor: FeatureState.limited,
        Feature.export: FeatureState.enabled,
        Feature.shadowRewardV2: FeatureState.hidden,
        Feature.questV2: FeatureState.limited,
        Feature.studyPlanning: FeatureState.hidden,
        Feature.researchAssessment: FeatureState.hidden,
        Feature.dailyContinuity: FeatureState.hidden,
        Feature.offlineContent: FeatureState.hidden,
        Feature.adventureMotivation: FeatureState.hidden,
      };

  const BuildFeatureRegistry.allEnabled()
    : _states = const {
        Feature.vocabulary: FeatureState.enabled,
        Feature.quiz: FeatureState.enabled,
        Feature.srs: FeatureState.enabled,
        Feature.reading: FeatureState.enabled,
        Feature.mastery: FeatureState.enabled,
        Feature.weakness: FeatureState.enabled,
        Feature.ghostDuel: FeatureState.enabled,
        Feature.achievements: FeatureState.enabled,
        Feature.shop: FeatureState.enabled,
        Feature.objectScanner: FeatureState.enabled,
        Feature.speechPractice: FeatureState.enabled,
        Feature.aiTutor: FeatureState.enabled,
        Feature.export: FeatureState.enabled,
        Feature.shadowRewardV2: FeatureState.enabled,
        Feature.questV2: FeatureState.enabled,
        Feature.studyPlanning: FeatureState.enabled,
        Feature.researchAssessment: FeatureState.enabled,
        Feature.dailyContinuity: FeatureState.enabled,
        Feature.offlineContent: FeatureState.enabled,
        Feature.adventureMotivation: FeatureState.enabled,
      };

  final Map<Feature, FeatureState> _states;

  Iterable<Feature> get configuredFeatures => _states.keys;

  @override
  FeatureState stateOf(Feature feature) =>
      _states[feature] ?? FeatureState.hidden;

  @override
  bool isVisible(Feature feature) {
    final state = stateOf(feature);
    return state == FeatureState.enabled || state == FeatureState.limited;
  }
}

/// Mutable [FeatureRegistry] for tests only.
///
/// Use [enable] / [disable] to override individual features:
/// ```dart
/// final reg = MutableFeatureRegistry();
/// reg.enable(Feature.aiTutor);
/// expect(reg.isVisible(Feature.aiTutor), isTrue);
/// ```
final class MutableFeatureRegistry implements FeatureRegistry {
  final Map<Feature, FeatureState> _overrides = {};

  /// Override [feature] to [FeatureState.enabled].
  // ignore: avoid_unused_element
  void enable(Feature feature) => _overrides[feature] = FeatureState.enabled;

  /// Override [feature] to [FeatureState.hidden].
  // ignore: avoid_unused_element
  void disable(Feature feature) => _overrides[feature] = FeatureState.hidden;

  @override
  FeatureState stateOf(Feature feature) =>
      _overrides[feature] ?? FeatureState.hidden;

  @override
  bool isVisible(Feature feature) {
    final state = stateOf(feature);
    return state == FeatureState.enabled || state == FeatureState.limited;
  }
}
