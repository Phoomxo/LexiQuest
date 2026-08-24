import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature.dart';
import '../domain/evidence_context.dart';
import '../domain/lesson_mode.dart';
import 'lesson_mode_registry.dart';

final class LegacyLessonModeAdapter implements LessonModeAdapter {
  const LegacyLessonModeAdapter(this.mode);

  @override
  final LessonMode mode;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

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

  return LessonModeRegistry(<LessonModeRegistration>[
    registration(
      LessonMode.associativeReading,
      Feature.reading,
      'learning/associative-reading',
    ),
    registration(LessonMode.meaningQuiz, Feature.quiz, 'learning/quiz'),
    registration(LessonMode.flashcard, Feature.srs, 'learning/srs'),
  ]);
}
