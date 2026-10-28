import '../../../runtime/registries/feature_registry.dart';
import '../domain/adventure_entry.dart';

enum AdventureCatalogReadiness { ready, invalid, contentUnavailable }

final class AdventureRolloutGate {
  const AdventureRolloutGate({
    required this.features,
    required this.requiredDependenciesReady,
    required this.catalogReadiness,
  });

  final FeatureRegistry features;
  final bool Function() requiredDependenciesReady;
  final AdventureCatalogReadiness Function() catalogReadiness;

  AdventureAvailability get availability {
    final state = features.stateOf(Feature.adventureMotivation);
    if (state == FeatureState.emergencyOff) {
      return AdventureAvailability.emergencyOff;
    }
    if (state == FeatureState.hidden) return AdventureAvailability.hidden;
    if (state == FeatureState.disabled) return AdventureAvailability.disabled;
    if (state != FeatureState.enabled && state != FeatureState.limited) {
      return AdventureAvailability.hidden;
    }
    if (!requiredDependenciesReady()) {
      return AdventureAvailability.missingDependency;
    }
    return switch (catalogReadiness()) {
      AdventureCatalogReadiness.ready => AdventureAvailability.available,
      AdventureCatalogReadiness.invalid => AdventureAvailability.invalidCatalog,
      AdventureCatalogReadiness.contentUnavailable =>
        AdventureAvailability.contentUnavailable,
    };
  }

  bool get isHostAuthorized => switch (availability) {
    AdventureAvailability.available ||
    AdventureAvailability.invalidCatalog ||
    AdventureAvailability.contentUnavailable => true,
    _ => false,
  };

  bool get canStartNewMission =>
      availability == AdventureAvailability.available;

  bool get canCloseAcceptedSession => true;
}
