import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature.dart';
import '../domain/evidence_context.dart';
import '../domain/lesson_mode.dart';
import 'lesson_mode_registry.dart';
import 'typed_recall_mode_adapter.dart';

final class LegacyLessonModeAdapter
    implements FocusTimerSupportingLessonModeAdapter {
  const LegacyLessonModeAdapter(this.mode);

  @override
  final LessonMode mode;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    if (context.evidenceClass == EvidenceClass.recreational) {
      throw StateError(
        'Recreational evidence cannot use an active-effort lesson adapter.',
      );
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('Legacy mode ${mode.id} owns item selection until migration.'),
  );
}

LessonModeRegistry buildLegacyLessonModeRegistry() {
  LessonModeRegistration registration(
    LessonMode mode,
    Feature feature,
    String routeName,
  ) {
    return LessonModeRegistration(
      adapter: LegacyLessonModeAdapter(mode),
      feature: feature,
      productionEntryId: productionFeatureContract[feature]!.productionEntryId,
      routeName: routeName,
    );
  }

  return LessonModeRegistry(
    <LessonModeRegistration>[
      registration(
        LessonMode.associativeReading,
        Feature.reading,
        'learning/associative-reading',
      ),
      registration(LessonMode.meaningQuiz, Feature.quiz, 'learning/quiz'),
      registration(LessonMode.flashcard, Feature.srs, 'learning/srs'),
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
