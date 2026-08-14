/// V2 Feature Registry — build-time feature flags.
///
/// This is the successor to [FieldFeatureRegistry].  The two coexist during
/// Phase -1 / Phase 0 migration; screens should prefer this interface for new
/// code.  [FieldFeatureRegistry] remains for screens that have not yet been
/// migrated.
library;

export 'feature.dart';

import 'package:flutter/foundation.dart';
import 'feature.dart';

/// Read-only contract for querying [Feature] availability.
abstract interface class FeatureRegistry {
  /// Returns the [FeatureState] for [feature].
  FeatureState stateOf(Feature feature);

  /// Convenience: returns `true` when the feature should be shown in the UI
  /// (i.e. its state is not [FeatureState.hidden], [FeatureState.disabled], or
  /// [FeatureState.emergencyOff]). Direct/stale routes use the shared typed
  /// unavailable experience instead of rebuilding a hidden entry surface.
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
        Feature.shadowRewardV2: FeatureState.hidden,
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

  /// Features explicitly configured by this build registry.
  ///
  /// Production defaults enumerate the entire [Feature] domain so adding a
  /// feature cannot silently inherit a fail-open state.
  Iterable<Feature> get configuredFeatures => _states.keys;

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
