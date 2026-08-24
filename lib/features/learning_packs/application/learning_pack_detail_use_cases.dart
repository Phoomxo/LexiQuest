import '../../learning/application/definition_quiz_mode_adapter.dart';
import '../../learning/application/cloze_mode_adapter.dart';
import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../progress/application/progress_use_cases.dart';
import '../../progress/domain/progress_models.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../domain/learning_pack_detail.dart';
import '../domain/learning_pack_repository.dart';

/// Read-only composition for a pinned pack revision. Content remains owned by
/// [LearningPackRepository], and progress remains the canonical projection.
typedef ProductionDependencyReadiness = bool Function(Feature feature);
typedef PinnedPackVocabularyReader =
    Future<List<VocabularyWord>> Function(Iterable<String> wordIds);

final class LearningPackDetailUseCases {
  const LearningPackDetailUseCases({
    required this.packs,
    required this.progress,
    required this.lessonModes,
    required this.features,
    required this.hasComposedDependency,
    this.readPinnedVocabulary,
  });

  final LearningPackRepository packs;
  final ProgressUseCases progress;
  final LessonModeRegistry? lessonModes;
  final FeatureRegistry? features;
  final ProductionDependencyReadiness hasComposedDependency;
  final PinnedPackVocabularyReader? readPinnedVocabulary;

  Future<LearningPackDetailView> loadVersion(
    String packId,
    int revision,
  ) async {
    final detail = await packs.getVersion(packId, revision);
    final snapshot = await progress.load();
    return LearningPackDetailView(
      detail: detail,
      progress: snapshot,
      activities: await _activities(detail),
    );
  }

  Future<List<LearningPackActivity>> _activities(
    LearningPackDetail detail,
  ) async {
    final activities = <LearningPackActivity>[];
    for (final mode in LessonMode.values) {
      final registration = lessonModes?.find(mode);
      final availability = await _isAvailable(registration, detail)
          ? LearningPackActivityAvailability.available
          : LearningPackActivityAvailability.unavailable;
      activities.add(
        LearningPackActivity(mode: mode, availability: availability),
      );
    }
    activities.sort((left, right) => left.mode.id.compareTo(right.mode.id));
    return List<LearningPackActivity>.unmodifiable(activities);
  }

  Future<bool> _isAvailable(
    LessonModeRegistration? registration,
    LearningPackDetail detail,
  ) async {
    if (registration == null || !hasComposedDependency(registration.feature)) {
      return false;
    }
    final delivery = productionFeatureContract[registration.feature];
    final productionReady =
        features?.isEnabled(registration.feature) == true &&
        delivery != null &&
        delivery.feature == registration.feature &&
        delivery.durable &&
        delivery.productionEntryId.trim().isNotEmpty &&
        delivery.dependencyId.trim().isNotEmpty &&
        registration.productionEntryId == delivery.productionEntryId;
    if (!productionReady) return false;
    if (registration.mode != LessonMode.definitionQuiz &&
        registration.mode != LessonMode.cloze) {
      return true;
    }
    final adapter = registration.adapter;
    final reader = readPinnedVocabulary;
    if (reader == null ||
        (adapter is! DefinitionQuizModeAdapter &&
            adapter is! ClozeModeAdapter)) {
      return false;
    }
    try {
      final words = await reader(detail.vocabularyWordIds);
      final requestedIds = detail.vocabularyWordIds.toSet();
      final returnedIds = words.map((word) => word.id).toSet();
      if (words.length != requestedIds.length ||
          returnedIds.length != requestedIds.length ||
          !returnedIds.containsAll(requestedIds)) {
        return false;
      }
      return switch (registration.mode) {
        LessonMode.definitionQuiz when adapter is DefinitionQuizModeAdapter =>
          adapter.hasDeliverableReviewedDefinition(words),
        LessonMode.cloze when adapter is ClozeModeAdapter =>
          adapter.hasDeliverableReviewedExample(words),
        _ => false,
      };
    } on Object {
      return false;
    }
  }
}

final class LearningPackDetailView {
  const LearningPackDetailView({
    required this.detail,
    required this.progress,
    required this.activities,
  });

  final LearningPackDetail detail;
  final ProgressSnapshot progress;
  final List<LearningPackActivity> activities;
}
