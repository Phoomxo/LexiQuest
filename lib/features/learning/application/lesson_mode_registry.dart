import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature.dart';
import '../domain/lesson_mode.dart';
import 'flashcard_mode_adapter.dart';
import 'legacy_lesson_mode_adapters.dart';
import 'meaning_quiz_mode_adapter.dart';

final class LessonModeRegistration {
  const LessonModeRegistration({
    required this.adapter,
    required this.feature,
    required this.productionEntryId,
    required this.routeName,
  });

  final LessonModeAdapter adapter;
  LessonMode get mode => adapter.mode;
  final Feature feature;
  final String productionEntryId;
  final String routeName;
}

final class LessonModeRegistry {
  LessonModeRegistry(Iterable<LessonModeRegistration> registrations)
    : _registrations = Map<LessonMode, LessonModeRegistration>.unmodifiable(
        _index(registrations),
      );

  final Map<LessonMode, LessonModeRegistration> _registrations;

  Iterable<LessonModeRegistration> get registrations => _registrations.values;

  LessonModeRegistration? find(LessonMode mode) => _registrations[mode];

  static Map<LessonMode, LessonModeRegistration> _index(
    Iterable<LessonModeRegistration> registrations,
  ) {
    final indexed = <LessonMode, LessonModeRegistration>{};
    final productionEntryIds = <String>{};
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
      if (!productionEntryIds.add(registration.productionEntryId)) {
        throw ArgumentError.value(
          registration.productionEntryId,
          'registrations',
          'duplicate production entry',
        );
      }
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
LessonModeRegistry buildLessonModeRegistry() {
  LessonModeRegistration registration({
    required LessonModeAdapter adapter,
    required Feature feature,
    required String routeName,
  }) => LessonModeRegistration(
    adapter: adapter,
    feature: feature,
    productionEntryId: productionFeatureContract[feature]!.productionEntryId,
    routeName: routeName,
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
      adapter: const FlashcardModeAdapter(),
      feature: Feature.srs,
      routeName: 'learning/srs',
    ),
  ]);
}
