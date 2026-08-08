/// V2 Feature Registry — build-time feature flags.
///
/// This is the successor to [FieldFeatureRegistry].  The two coexist during
/// Phase -1 / Phase 0 migration; screens should prefer this interface for new
/// code.  [FieldFeatureRegistry] remains for screens that have not yet been
/// migrated.
library;

import 'package:flutter/foundation.dart';

/// Feature capabilities exposed to learners in the field.
///
/// Mirrors [FieldFeature] during the transition period; values are kept in
/// sync until [FieldFeatureRegistry] is retired.
enum Feature {
  vocabulary,
  quiz,
  srs,
  reading,
  mastery,
  weakness,
  ghostDuel,
  achievements,
  shop,
  objectScanner,
  speechPractice,
  aiTutor,
  export,

  /// V2 shadow mode — runs the V2 reward pipeline in dry-run mode alongside
  /// production.  Disabled by default; enable in debug builds only.
  shadowRewardV2,

  /// V2 Quest persistence — persists [QuestInstance] to Drift (schema v8).
  /// Default: hidden.  Enable internally to test before public rollout.
  questV2,
}

/// Availability state of a [Feature].
enum FeatureState {
  /// Fully available to the learner.
  enabled,

  /// Available with restrictions (e.g. quota, degraded quality).
  limited,

  /// Not available and not shown in the UI.
  hidden,

  /// Explicitly disabled by a kill switch. UI shows a "feature unavailable"
  /// message rather than hiding the feature entirely.
  disabled,

  /// Emergency shut-off — feature and all its data paths are blocked.
  /// Takes precedence over every other state.
  emergencyOff,
}

/// Read-only contract for querying [Feature] availability.
abstract interface class FeatureRegistry {
  /// Returns the [FeatureState] for [feature].
  FeatureState stateOf(Feature feature);

  /// Convenience: returns `true` when the feature should be shown in the UI
  /// (i.e. its state is not [FeatureState.hidden] or [FeatureState.disabled]
  /// or [FeatureState.emergencyOff]).
  bool isVisible(Feature feature);

  /// Returns `true` when the feature is safe to invoke. Features in
  /// [FeatureState.disabled] or [FeatureState.emergencyOff] are NOT usable.
  bool isEnabled(Feature feature);
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
        // V2 features hidden by default in production builds.
        // shadowRewardV2 and questV2 are opt-in for internal testing.
        // Phase 1: questV2 promoted to limited (internal beta).
        Feature.questV2: FeatureState.limited,
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
      };

  final Map<Feature, FeatureState> _states;

  @override
  FeatureState stateOf(Feature feature) =>
      _states[feature] ?? FeatureState.hidden;

  @override
  bool isVisible(Feature feature) {
    final s = stateOf(feature);
    return s != FeatureState.hidden &&
        s != FeatureState.disabled &&
        s != FeatureState.emergencyOff;
  }

  @override
  bool isEnabled(Feature feature) {
    final s = stateOf(feature);
    return s == FeatureState.enabled || s == FeatureState.limited;
  }
}

/// Runtime kill-switch registry that wraps a [FeatureRegistry] and allows
/// features to be disabled or emergency-shut-off at runtime.
///
/// In production, persisted local overrides are loaded from the
/// `runtime_flags` Drift table and folded into the effective state.
/// `emergencyOff` always wins — it cannot be overridden by the base registry.
final class RuntimeFeatureRegistry extends ChangeNotifier
    implements FeatureRegistry {
  RuntimeFeatureRegistry(this._base, {Map<Feature, FeatureState>? overrides})
    : _overrides = overrides ?? {};

  final FeatureRegistry _base;
  final Map<Feature, FeatureState> _overrides;

  /// Set a runtime override for [feature].
  void setOverride(Feature feature, FeatureState state) {
    if (_overrides[feature] == state) return;
    _overrides[feature] = state;
    notifyListeners();
  }

  /// Clear a runtime override, reverting to the base registry.
  void clearOverride(Feature feature) {
    if (_overrides.remove(feature) != null) notifyListeners();
  }

  /// Emergency-disable a feature immediately.
  void emergencyOff(Feature feature) {
    setOverride(feature, FeatureState.emergencyOff);
  }

  @override
  FeatureState stateOf(Feature feature) {
    final override = _overrides[feature];
    if (override == FeatureState.emergencyOff) return FeatureState.emergencyOff;
    return override ?? _base.stateOf(feature);
  }

  @override
  bool isVisible(Feature feature) {
    final s = stateOf(feature);
    return s != FeatureState.hidden &&
        s != FeatureState.disabled &&
        s != FeatureState.emergencyOff;
  }

  @override
  bool isEnabled(Feature feature) {
    final s = stateOf(feature);
    return s == FeatureState.enabled || s == FeatureState.limited;
  }
}

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
  bool isVisible(Feature feature) => stateOf(feature) != FeatureState.hidden;

  @override
  bool isEnabled(Feature feature) {
    final s = stateOf(feature);
    return s == FeatureState.enabled || s == FeatureState.limited;
  }
}
