import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature.dart';
import '../domain/lesson_mode.dart';
import 'definition_quiz_mode_adapter.dart';
import 'cloze_mode_adapter.dart';
import 'flashcard_mode_adapter.dart';
import 'legacy_lesson_mode_adapters.dart';
import 'meaning_quiz_mode_adapter.dart';
import 'matching_mode_adapter.dart';

enum LessonModeDeliveryState { implementedOff, enabled }

final class LessonModeRegistration {
  const LessonModeRegistration({
    required this.adapter,
    required this.feature,
    required this.productionEntryId,
    required this.routeName,
    this.deliveryState = LessonModeDeliveryState.enabled,
  });

  final LessonModeAdapter adapter;
  LessonMode get mode => adapter.mode;
  final Feature feature;
  final String productionEntryId;
  final String routeName;
  final LessonModeDeliveryState deliveryState;

  bool get isDeliverable => deliveryState == LessonModeDeliveryState.enabled;
}

final class LessonModeRegistry {
  LessonModeRegistry(Iterable<LessonModeRegistration> registrations)
    : _registrations = Map<LessonMode, LessonModeRegistration>.unmodifiable(
        _index(registrations),
      );

  final Map<LessonMode, LessonModeRegistration> _registrations;

  Iterable<LessonModeRegistration> get registrations => _registrations.values;

  LessonModeRegistration? find(LessonMode mode) => _registrations[mode];

  /// Resolves only invokable delivery. Raw [find] remains available to
  /// architecture/readiness checks without making implemented-off code a
  /// learner-facing route.
  LessonModeRegistration? resolve(LessonMode mode) {
    final registration = find(mode);
    return registration?.isDeliverable == true ? registration : null;
  }

  static Map<LessonMode, LessonModeRegistration> _index(
    Iterable<LessonModeRegistration> registrations,
  ) {
    final indexed = <LessonMode, LessonModeRegistration>{};
    final productionEntryFeatures = <String, Feature>{};
    final routeNames = <String>{};
    for (final registration in registrations) {
      if (registration.productionEntryId.trim().isEmpty) {
        throw ArgumentError.value(
          registration.productionEntryId,
          'productionEntryId',
          'must not be blank',
        );
      }
      if (registration.routeName.trim().isEmpty) {
        throw ArgumentError.value(
          registration.routeName,
          'routeName',
          'must not be blank',
        );
      }
      final existingFeature =
          productionEntryFeatures[registration.productionEntryId];
      if (existingFeature != null && existingFeature != registration.feature) {
        throw ArgumentError.value(
          registration.productionEntryId,
          'registrations',
          'production entry cannot be shared across runtime features',
        );
      }
      productionEntryFeatures[registration.productionEntryId] =
          registration.feature;
      if (!routeNames.add(registration.routeName)) {
        throw ArgumentError.value(
          registration.routeName,
          'registrations',
          'duplicate route name',
        );
      }
      if (indexed.containsKey(registration.mode)) {
        throw ArgumentError.value(
          registration.mode,
          'registrations',
          'duplicate lesson mode adapter',
        );
      }
      indexed[registration.mode] = registration;
    }
    return indexed;
  }
}

/// Production registry. Each migrated mode replaces the legacy adapter at the
/// same typed entry and route, so there is never a competing delivery path.
LessonModeRegistry buildLessonModeRegistry({
  LessonModeDeliveryState matchingDeliveryState =
      LessonModeDeliveryState.implementedOff,
}) {
  LessonModeRegistration registration({
    required LessonModeAdapter adapter,
    required Feature feature,
    required String routeName,
    LessonModeDeliveryState deliveryState = LessonModeDeliveryState.enabled,
  }) => LessonModeRegistration(
    adapter: adapter,
    feature: feature,
    productionEntryId: productionFeatureContract[feature]!.productionEntryId,
    routeName: routeName,
    deliveryState: deliveryState,
  );

  return LessonModeRegistry(<LessonModeRegistration>[
    registration(
      adapter: const LegacyLessonModeAdapter(LessonMode.associativeReading),
      feature: Feature.reading,
      routeName: 'learning/associative-reading',
    ),
    registration(
      adapter: const MeaningQuizModeAdapter(),
      feature: Feature.quiz,
      routeName: 'learning/quiz',
    ),
    registration(
      adapter: const DefinitionQuizModeAdapter(),
      feature: Feature.quiz,
      routeName: 'learning/definition-quiz',
    ),
    registration(
      adapter: const ClozeModeAdapter(),
      feature: Feature.quiz,
      routeName: 'learning/cloze',
    ),
    registration(
      adapter: const MatchingModeAdapter(),
      feature: Feature.quiz,
      routeName: 'learning/matching',
      deliveryState: matchingDeliveryState,
    ),
    registration(
      adapter: const FlashcardModeAdapter(),
      feature: Feature.srs,
      routeName: 'learning/srs',
    ),
  ]);
}
