import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature.dart';
import '../domain/evidence_context.dart';
import '../domain/hint_policy.dart';
import '../domain/lesson_mode.dart';
import 'definition_quiz_mode_adapter.dart';
import 'cloze_mode_adapter.dart';
import 'flashcard_mode_adapter.dart';
import 'meaning_quiz_mode_adapter.dart';
import 'matching_mode_adapter.dart';
import 'typed_recall_mode_adapter.dart';
import 'handwriting_self_check_adapter.dart';

enum LessonModeDeliveryState { implementedOff, enabled }

class LessonModeRegistration {
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

final class TypedRecallCapabilityRegistration extends LessonModeRegistration {
  const TypedRecallCapabilityRegistration({
    required TypedRecallModeAdapter adapter,
    required super.feature,
    required super.productionEntryId,
    required super.routeName,
    super.deliveryState = LessonModeDeliveryState.enabled,
  }) : super(adapter: adapter);

  @override
  TypedRecallModeAdapter get adapter => super.adapter as TypedRecallModeAdapter;
}

final class LessonModeRegistry {
  LessonModeRegistry(
    Iterable<LessonModeRegistration> registrations, {
    TypedRecallCapabilityRegistration? typedRecall,
  }) : _registrations = Map<LessonMode, LessonModeRegistration>.unmodifiable(
         _index(<LessonModeRegistration>[...registrations, ?typedRecall]),
       ) {
    final capability = this.typedRecall;
    if (capability != null &&
        (capability.feature != Feature.quiz ||
            capability.productionEntryId !=
                productionFeatureContract[Feature.quiz]!.productionEntryId ||
            capability.routeName != 'learning/typed-recall')) {
      throw ArgumentError.value(
        capability,
        'typedRecall',
        'typed recall must use the quiz catalog authority',
      );
    }
  }

  final Map<LessonMode, LessonModeRegistration> _registrations;

  TypedRecallCapabilityRegistration? get typedRecall {
    final registration = _registrations[LessonMode.typedRecall];
    return registration is TypedRecallCapabilityRegistration
        ? registration
        : null;
  }

  Iterable<LessonModeRegistration> get registrations => _registrations.values;

  LessonModeRegistration? find(LessonMode mode) => _registrations[mode];

  /// Resolves only invokable delivery. Raw [find] remains available to
  /// architecture/readiness checks without making implemented-off code a
  /// learner-facing route.
  LessonModeRegistration? resolve(LessonMode mode) {
    final registration = find(mode);
    return registration?.isDeliverable == true ? registration : null;
  }

  TypedRecallCapabilityRegistration? resolveTypedRecall() =>
      typedRecall?.isDeliverable == true ? typedRecall : null;

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
  LessonModeDeliveryState handwritingDeliveryState =
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

  return LessonModeRegistry(
    <LessonModeRegistration>[
      registration(
        adapter: const _AssociativeReadingModeAdapter(),
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
      registration(
        adapter: const HandwritingSelfCheckAdapter(),
        feature: Feature.quiz,
        routeName: 'learning/handwriting-scratchpad',
        deliveryState: handwritingDeliveryState,
      ),
    ],
    typedRecall: TypedRecallCapabilityRegistration(
      adapter: const TypedRecallModeAdapter(),
      feature: Feature.quiz,
      productionEntryId:
          productionFeatureContract[Feature.quiz]!.productionEntryId,
      routeName: 'learning/typed-recall',
    ),
  );
}

final class _AssociativeReadingModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        HintSupportingLessonModeAdapter {
  const _AssociativeReadingModeAdapter();

  @override
  LessonMode get mode => LessonMode.associativeReading;

  @override
  HintPolicy get hintPolicy => const TypedRecallModeAdapter().hintPolicy;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    if (context.evidenceClass == EvidenceClass.recreational) {
      throw StateError(
        'Associative reading cannot record recreational lesson evidence.',
      );
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('Associative reading owns staged item selection.'),
  );
}
